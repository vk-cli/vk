module vkapi;

import std.stdio, std.conv, std.string, std.regex, std.array, std.datetime, core.time;
import std.exception, core.exception;
import std.net.curl, std.uri, std.json;
import std.algorithm, std.range, std.experimental.ndslice;
import std.parallelism, std.concurrency, core.thread;
import utils, namecache, localization;



// ===== vkapi const =====

const int convStartId = 2000000000;
const int mailStartId = convStartId*-1;
const bool return80mc = true;
const long needNameMaxDelta = 180; //seconds, 3 min

// ===== networking const =====

const int connectAttmepts = 3;
const int mssleepBeforeAttempt = 600;
const int vkgetCurlTimeout = 3;
const int longpollCurlTimeout = 27;
const string timeoutFormat = "seconds";

// ===== API objects =====

struct vkUser {
    string first_name;
    string last_name;
    int id;
    bool online;
}

struct vkDialog {
    string name;
    string lastMessage = "";
    int lastmid;
    int id = -1;
    bool unread = false;
    bool online;
    bool isChat;
}

struct vkMessage {
    string author_name; // in format 'First Last'
    int author_id;
    int peer_id; // for users: user id, for conversations: 2000000000 + chat id
    int msg_id;
    bool outgoing;
    bool unread;
    bool needName;
    bool nmresolved;
    long utime; // unix time
    string time_str; // HH:MM (M = minutes), if >24 hours ago, then DD.mm (m = month)
    string[] body_lines; // Message text, splitted in lines (delimiter = '\n')
    int fwd_depth; // max fwd message deph (-1 if no fwd)
    vkFwdMessage[] fwd; // forwarded messages
    bool isLoading;
    int lineCount = -1;
}

struct vkMessageLine {
    string text;
    string time;
    bool unread;
    bool isName;
    bool isSpacing;
    bool isFwd;
    int fwdDepth;
}

auto emptyVkMessage = vkMessage();

struct vkFwdMessage {
    int author_id;
    string author_name;
    long utime;
    string time_str;
    string[] body_lines;
    vkFwdMessage[] fwd;
}

struct vkCounters {
    int friends = 0;
    int messages = 0;
    int notifications = 0;
    int groups = 0;
}

struct vkFriend {
    string first_name;
    string last_name;
    int id;
    bool online;
}

struct vkAudio {
    int id;
    int owner;
    string artist;
    string title;
    int duration_sec;
    string duration_str; // MM:SS (len 5)
    string url;
}

struct vkGroup {
    int id;
    string name;
}

// ===== longpoll objects =====

struct vkLongpoll {
    string key;
    string server;
    int ts;
}

struct vkNextLp {
    int ts;
    int failed;
}

// === API state and meta =====

struct apiTransfer {
    string token;
    bool tokenvalid;
    vkUser user;
}

struct apiState {
    bool lp80got = true;
    int latestUnreadMsg = 0;
    bool somethingUpdated = false;
    bool chatloading = false;
}

enum blockType {
    dialogs,
    music,
    friends,
    chat
}

struct apiBufferData {
    int serverCount = -1;
    bool forceUpdate = true;
    bool loading = false;
    bool updated = false;

}

struct apiRecentlyUpdated {
    long updated;
    bool checkedout;
}

struct apiChatBuffer {
    vkMessage[] buffer;
    apiBufferData data;
    apiRecentlyUpdated[int] recent; //by mid
    vkMessageLine[][int] linebuffer; // by peer
}

struct apiBuffers {
    vkDialog[] dialogsBuffer;
    apiBufferData dialogsData;

    vkFriend[] friendsBuffer;
    apiBufferData friendsData;

    vkAudio[] audioBuffer;
    apiBufferData audioData;

    apiChatBuffer[int] chatBuffer;
}

struct apiFwdIter {
    vkFwdMessage[] fwd;
    int md;
}

__gshared nameCache nc = nameCache();
__gshared apiState ps = apiState();

__gshared apiBuffers pb = apiBuffers();
loadBlockThread lbThread;
longpollThread lpThread;

class VKapi {

// ===== API & networking =====

    private const string vkurl = "https://api.vk.com/method/";
    const string vkver = "5.45";
    private string vktoken = "";
    bool isTokenValid;
    vkUser me;

    this(string token){
        tokenInit(token);
        nc = nc.createNC(this.exportStruct());
        addMeNC();
    }

    this(apiTransfer st) {
        vktoken = st.token;
        isTokenValid = st.tokenvalid;
        me = st.user;
    }

    void addMeNC() {
        nc.addToCache(me.id, cachedName(me.first_name, me.last_name));
    }

    void tokenInit(string token) {
        vktoken = token;
        isTokenValid = checkToken(token);
        lbThread = new loadBlockThread();
        lpThread = new longpollThread(this);
    }

    apiTransfer exportStruct() {
        return apiTransfer(vktoken, isTokenValid, me);
    }

    bool isSomethingUpdated() {
        if(ps.somethingUpdated){
            ps.somethingUpdated = false;
            return true;
        }
        return false;
    }

    void toggleUpdate() {
        ps.somethingUpdated = true;
    }

    private bool checkToken(string token) {
        if(token.length != 85) return false;
        try{
            me = usersGet();
        } catch (ApiErrorException e) {
            dbm("ApiErrorException: " ~ e.msg);
            return false;
        } catch (BackendException e) {
            dbm("BackendException: " ~ e.msg);
            return false;
        }
        return true;
    }

    string httpget(string addr, Duration timeout) {
        string content = "";
        auto client = HTTP();

        int tries = 0;
        bool ok = false;

        while(!ok){
            try{
                client.method = HTTP.Method.get;
                client.url = addr;

                client.dataTimeout = timeout;
                client.operationTimeout = timeout;
                client.connectTimeout = timeout;

                client.onReceive = (ubyte[] data) {
                    auto sz = data.length;
                    content ~= (cast(immutable(char)*)data)[0..sz];
                    //dbm("recv content: " ~ content);
                    return sz;
                };
                client.perform();
                ok = true;
            } catch (CurlException e) {
                ++tries;
                dbm("[attempt " ~ (tries.to!string) ~ "] network error: " ~ e.msg);
                if(tries >= connectAttmepts) throw new BackendException("not working - connection failed!   attempts: " ~ tries.to!string ~ ", last curl error: " ~ e.msg);
                Thread.sleep( dur!"msecs"(mssleepBeforeAttempt) );
            }
        }
        return content;
    }

    JSONValue vkget(string meth, string[string] params, bool dontRemoveResponse = false) {
        bool rmresp = !dontRemoveResponse;
        auto url = vkurl ~ meth ~ "?"; //so blue
        foreach(key; params.keys) {
            auto val = params[key];
            url ~= key ~ "=" ~ val.encode ~ "&";
        }
        url ~= "v=" ~ vkver ~ "&access_token=";
        dbm("request: " ~ url ~ "***");
        url ~= vktoken;
        auto tm = dur!timeoutFormat(vkgetCurlTimeout);
        JSONValue resp = httpget(url, tm).parseJSON;

        if(resp.type == JSON_TYPE.OBJECT) {
            if("error" in resp){
                try {
                    auto eobj = resp["error"];
                    immutable auto emsg = ("error_text" in eobj) ? eobj["error_text"].str : eobj["error_msg"].str;
                    immutable auto ecode = eobj["error_code"].integer.to!int;
                    throw new ApiErrorException(emsg, ecode);
                } catch (JSONException e) {
                    throw new ApiErrorException(resp.toPrettyString(), 0);
                }

            } else if ("response" !in resp) {
                rmresp = false;
            }
        } else rmresp = false;

        return rmresp ? resp["response"] : resp;
    }

    // ===== API method wrappers =====

    vkUser usersGet(int userId = 0, string fields = "", string nameCase = "nom") {
        string[string] params;
        if(userId != 0) params["user_ids"] = userId.to!string;
        if(fields != "") params["fields"] = fields;
        if(nameCase != "nom") params["name_case"] = nameCase;
        auto resp = vkget("users.get", params);
        //dbm(resp.toPrettyString());

        if(resp.array.length != 1) throw new BackendException("users.get (one user) fail: response array length != 1");
        resp = resp[0];

        vkUser rt = {
            id:resp["id"].integer.to!int,
            first_name:resp["first_name"].str,
            last_name:resp["last_name"].str
        };

        if("online" in resp) rt.online = (resp["online"].integer == 1);

        return rt;
    }

    vkUser[] usersGet(int[] userIds, string fields = "", string nameCase = "nom") {
        string[string] params;
        params["user_ids"] = userIds.map!(i => i.to!string).join(",");
        if(fields != "") params["fields"] = fields;
        if(nameCase != "nom") params["name_case"] = nameCase;
        auto resp = vkget("users.get", params).array;

        vkUser[] rt;
        foreach(t; resp){
            vkUser rti = {
                id:t["id"].integer.to!int,
                first_name:t["first_name"].str,
                last_name:t["last_name"].str
            };
            rt ~= rti;
        }
        return rt;
    }

    vkDialog[] messagesGetDialogs(int count , int offset, out int serverCount) {
        auto exresp = vkget("execute.vkGetDialogs", [ "count": count.to!string, "offset": offset.to!string ]);
        auto resp = exresp["conv"];
        auto dcount = resp["count"].integer.to!int;
        dbm("dialogs count now: " ~ dcount.to!string);
        auto respt = resp["items"].array
                                    .map!(q => q["message"]);

        //name resolving
        int[] rootIds = respt
                        .filter!(q => "user_id" in q)
                        .map!(q => q["user_id"].integer.to!int)
                        .array;
        auto convAcvtives = respt
                        .filter!(q => "chat_active" in q)
                        .map!(q => q["chat_active"]);
        int[] convIds;
        foreach(ca; convAcvtives) {
            //dbm(ca.type.to!string);
            convIds ~= ca.array.map!(a => a.integer.to!int).array;
        }
        nc.requestId(rootIds);
        nc.requestId(convIds);
        nc.resolveNames();

        auto ou = exresp["ou"].array;
        auto os = exresp["os"].array;
        bool[int] online;
        foreach(n; 0..(ou.length)) online[ou[n].integer.to!int] = (os[n].integer == 1);

        vkDialog[] dialogs;
        foreach(msg; respt){
            auto ds = vkDialog();
            if("chat_id" in msg){
                auto ctitle = msg["title"].str;
                auto cid = msg["chat_id"].integer.to!int + convStartId;
                nc.addToCache(cid, cachedName(ctitle, ""));

                ds.id = cid;
                ds.name = ctitle;
                ds.online = true;
                ds.isChat = true;
            } else {
                auto uid = msg["user_id"].integer.to!int;
                ds.id = uid;
                ds.name = nc.getName(ds.id).strName;
                ds.online = (uid in online) ? online[uid] : false;
                ds.isChat = false;
            }
            ds.lastMessage = msg["body"].str;
            ds.lastmid = msg["id"].integer.to!int;
            if(msg["out"].integer == 0 && msg["read_state"].integer == 0) ds.unread = true;
            dialogs ~= ds;
            //dbm(ds.id.to!string ~ " " ~ ds.unread.to!string ~ "   " ~ ds.name ~ " " ~ ds.lastMessage);
            //dbm(ds.formatted);
        }

        serverCount = dcount;
        return dialogs;
    }

    vkCounters accountGetCounters(string filter = "") {
        string ft = (filter == "") ? "friends,messages,groups,notifications" : filter;
        auto resp = vkget("account.getCounters", [ "filter": ft ]);
        vkCounters rt;

        if(resp.type == JSON_TYPE.ARRAY) return rt;

        foreach(c; resp.object.keys) switch (c) {
            case "messages": rt.messages = resp[c].integer.to!int; break;
            case "friends": rt.friends = resp[c].integer.to!int; break;
            case "notifications": rt.notifications = resp[c].integer.to!int; break;
            case "groups": rt.groups = resp[c].integer.to!int; break;
            default: break;
        }
        return rt;
    }

    int messagesCounter() {
        int u = ps.latestUnreadMsg;
        if(ps.lp80got) {
            u = accountGetCounters("messages").messages;
            ps.latestUnreadMsg = u;
            ps.lp80got = false;
        }
        return u;
    }

    vkFriend[] friendsGet(int count, int offset, out int serverCount, int user_id = 0) {
        auto params = [ "fields": "online", "order": "hints"];
        if(user_id != 0) params["user_id"] = user_id.to!string;
        if(count != 0) params["count"] = count.to!string;
        if(offset != 0) params["offset"] = offset.to!string;

        auto resp = vkget("friends.get", params);
        serverCount = resp["count"].integer.to!int;

        vkFriend[] rt;
        foreach(f; resp["items"].array) {
            rt ~= vkFriend(
                f["first_name"].str, f["last_name"].str,
                f["id"].integer.to!int, (f["online"].integer.to!int == 1) ? true : false
            );
        }
        return rt;
    }

    vkAudio[] audioGet(int count, int offset, out int serverCount, int owner_id = 0, int album_id = 0) {
        string[string] params;
        if(owner_id != 0) params["owner_id"] = owner_id.to!string;
        if(album_id != 0) params["album_id"] = album_id.to!string;
        if(count != 0) params["count"] = count.to!string;
        if(offset != 0) params["offset"] = offset.to!string;

        auto resp = vkget("audio.get", params);
        serverCount = resp["count"].integer.to!int;

        vkAudio[] rt;
        foreach(a; resp["items"].array) {
            int ad = a["duration"].integer.to!int;
            auto adm = ad.convert!("seconds", "minutes");
            auto ads = ad - (60*adm);

            vkAudio aud = {
                id: a["id"].integer.to!int, owner: a["owner_id"].integer.to!int,
                artist: a["artist"].str, title: a["title"].str, url: a["url"].str,
                duration_sec: ad, duration_str: (adm.to!string ~ ":" ~ tzr(ads.to!int))
            };
            rt ~= aud;
        }
        return rt;
    }

    vkGroup[] groupsGetById(int[] group_ids) {
        vkGroup[] rt;
        if(group_ids.length == 0) return rt;

        auto gids = group_ids.map!(g => (g * -1).to!string).join(",");
        //dbm("gids: " ~ gids);
        auto params = [ "group_ids": gids ];
        auto resp = vkget("groups.getById", params);

        if(resp.type != JSON_TYPE.ARRAY) return rt;

        foreach(g; resp.array) {
            rt ~= vkGroup(g["id"].integer.to!int * -1, g["name"].str);
        }
        return rt;
    }

    private apiFwdIter digFwd(JSONValue[] fwdp, SysTime ct, int mdp, int cdp) {
        int cmd = (cdp > mdp) ? cdp : mdp;
        vkFwdMessage[] rt;
        foreach(j; fwdp) {
            int fid = j["user_id"].integer.to!int;
            long ut = j["date"].integer.to!long;

            vkFwdMessage[] fw;
            if("fwd_messages" in j) {
                auto r = digFwd(j["fwd_messages"].array, ct, cmd, cdp+1);
                if(r.md > cmd) cmd = r.md;
                fw = r.fwd;
            }

            vkFwdMessage mm = {
                author_id: fid,
                author_name: nc.getName(fid).strName,
                utime: ut, time_str: vktime(ct, ut),
                body_lines: j["body"].str.split("\n"),
                fwd: fw
            };
            rt ~= mm;
        }
        return apiFwdIter(rt, cmd);
    }

    private vkMessage[] parseMessageObjects(JSONValue[] items, SysTime ct) {
        vkMessage[] rt;
        int i = 0;
        foreach(m; items) {
            int fid;
            int mid = m["id"].integer.to!int;
            auto hascid = ("chat_id" in m);
            int uid = m["user_id"].integer.to!int;
            int pid = (hascid) ? (m["chat_id"].integer.to!int + convStartId) : uid;
            long ut = m["date"].integer.to!long;
            bool outg = (m["out"].integer.to!int == 1);
            bool rstate = (m["read_state"].integer.to!int == 1);
            //bool unr = (outg && !rstate);
            bool unr = !rstate;

            if("from_id" in m) {
                fid = m["from_id"].integer.to!int;
            } else {
                if(hascid || !outg) {
                    fid = uid;
                } else {
                    fid = me.id;
                }
            }

            string[] mbody = m["body"].str.split("\n");
            string st = vktime(ct, ut);

            int fwdp = -1;
            vkFwdMessage[] fw;
            if("fwd_messages" in m) {
                auto r = digFwd(m["fwd_messages"].array, ct, 0, 1);
                fwdp = r.md;
                fw = r.fwd;
            }

            vkMessage mo = {
                msg_id: mid, author_id: fid, peer_id: pid,
                outgoing: outg, unread: unr, utime: ut,
                author_name: nc.getName(fid).strName,
                time_str: st, body_lines: mbody,
                fwd_depth: fwdp, fwd:fw, needName: true
            };
            rt ~= mo;
            ++i;
        }
        return rt;
    }

    vkMessage[] messagesGetHistory(int peer_id, int count, int offset, out int servercount, int start_message_id = -1, bool rev = false) {
        auto ct = Clock.currTime();
        auto params = [ "peer_id": peer_id.to!string ];
        if(count >= 0) params["count"] = count.to!string;
        if(offset != 0) params["offset"] = offset.to!string;
        if(start_message_id > 0) params["start_message_id"] = start_message_id.to!string;
        if(rev) params["rev"] = "1";

        auto resp = vkget("messages.getHistory", params);
        auto items = resp["items"].array;

        servercount = resp["count"].integer.to!int;

        return parseMessageObjects(items, ct);
    }

    vkMessage[] messagesGetById(int[] mids) {
        auto ct = Clock.currTime();
        auto params = [ "message_ids": mids.map!(q => q.to!string).join(",") ];
        auto resp = vkget("messages.getById", params);
        auto items = resp["items"].array;

        return parseMessageObjects(items, ct);
    }

    // ===== buffers =====


    private T[] getBuffered(T)(int block, int upd, int count, int offset, blockType blocktp, void delegate(int count, int offset) download, ref apiBufferData bufd, ref T[] buf, out bool retLoading) {
        T[] rt;
        bool spawnLoadBlock = false;

        //dbm("getbuffered count: " ~ count.to!string ~ ", offset: " ~ offset.to!string ~ ", blocktp: " ~ blocktp.to!string);

        if(bufd.forceUpdate){
             buf = new T[0];
             bufd.forceUpdate = false;
             dbm(blocktp.to!string ~ " buffer empty now, fc: " ~ bufd.forceUpdate.to!string);
        }

        immutable int cl = buf.length.to!int;
        int needln = count + offset;

        if (bufd.serverCount == -1 || cl == 0 || (cl < bufd.serverCount && needln >= (cl-upd))) {
            dbm("called UPD at offset " ~ offset.to!string ~ ", with current trigger " ~ (cl-upd).to!string);
            dbm("dbuf info cl: " ~ cl.to!string ~ ", needln: " ~ needln.to!string ~ ", dthread running: " ~ lbThread.isRunning.to!string ~ ", blocktp: " ~ blocktp.to!string);
            spawnLoadBlock = true;
        }

        if(bufd.serverCount != -1 && needln > bufd.serverCount) {
            count = bufd.serverCount - offset;
            needln = count + offset;
            dbm("needln greater than sc, now offset: " ~ offset.to!string ~ ", count: " ~ count.to!string ~ ", needln: " ~ needln.to!string);
        }

        if(needln <= cl) {
            bufd.loading = false;
            retLoading = false;
            rt = slice!T(buf, count, offset);
        } else {
            dbm("catched LOADING state at offset " ~ offset.to!string);
            dbm("dbuf info cl: " ~ cl.to!string ~ ", needln: " ~ needln.to!string ~ ", dthread running: " ~ lbThread.isRunning.to!string ~ ", blocktp: " ~ blocktp.to!string);
            bufd.loading = true;
            retLoading = true;
        }

        if(spawnLoadBlock && !lbThread.isRunning) {
            //lbThread.loadBlock(blocktp, block, cl);
            lbThread.func(download, block, cl);
        }

        return rt;
    }

    vkFriend[] getBufferedFriends(int count, int offset) {
        const int block = 100;
        const int upd = 50;

        immutable vkFriend ld = {
            first_name: getLocal("loading"),
            last_name: ""
        };

        void dw(int c, int off) {
            int sc;
            pb.friendsBuffer ~= friendsGet(c, off, sc);
            pb.friendsData.serverCount = sc;
            pb.friendsData.updated = true;
            toggleUpdate();
        }

        bool outload;
        auto rt = getBuffered!vkFriend(block, upd, count, offset, blockType.friends, &dw, pb.friendsData, pb.friendsBuffer, outload);

        if(outload) rt = [ ld ];
        return rt;
    }

    vkAudio[] getBufferedMusic(int count, int offset) {
        const int block = 100;
        const int upd = 50;

        immutable vkAudio ld = {
            artist: getLocal("loading"),
            title: ""
        };

        void dw(int c, int off) {
            int sc;
            pb.audioBuffer ~= audioGet(c, off, sc);
            pb.audioData.serverCount = sc;
            pb.audioData.updated = true;
            toggleUpdate();
        }

        bool outload;
        auto rt = getBuffered!vkAudio(block, upd, count, offset, blockType.music, &dw, pb.audioData, pb.audioBuffer, outload);

        if(outload) rt = [ ld ];
        return rt;
    }

    vkDialog[] getBufferedDialogs(int count, int offset) {
        const int block = 100;
        const int upd = 50;

        immutable vkDialog ld = {
            name: getLocal("loading")
        };

        void dw(int c, int off) {
            int sc;
            pb.dialogsBuffer ~= messagesGetDialogs(c, off, sc);
            pb.dialogsData.serverCount = sc;
            pb.dialogsData.updated = true;
            toggleUpdate();
        }

        bool outload;
        auto rt = getBuffered!vkDialog(block, upd, count, offset, blockType.dialogs, &dw, pb.dialogsData, pb.dialogsBuffer, outload);

        if(outload) rt = [ ld ];
        return rt;
    }

    vkMessage[] getBufferedChat(int count, int offset, int peer) {
        const int block = 100;
        const int upd = 50;

        vkMessage ld = {
            author_name: getLocal("loading"),
            needName: true, isLoading: true
        };

        vkMessage[] defaultrt = [ ld ];

        void dw(int c, int off) {
            int sc;
            pb.chatBuffer[peer].buffer ~= messagesGetHistory(peer, c, off, sc);
            pb.chatBuffer[peer].data.serverCount = sc;
            pb.chatBuffer[peer].data.updated = true;
            resolveNeedName(peer);
            toggleUpdate();
        }

        if(peer !in pb.chatBuffer) pb.chatBuffer[peer] = apiChatBuffer();

        bool outload;
        auto rt = getBuffered!vkMessage(block, upd, count, offset, blockType.chat, &dw, pb.chatBuffer[peer].data, pb.chatBuffer[peer].buffer, outload);

        if(outload) return defaultrt;

        //auto rvrt = rt.reversed!0;
        //reverse(rvrt);

        return rt;
    }

    private void resolveNeedName(int peer) {
        int lastfid;
        long lastut;
        foreach(ref m; pb.chatBuffer[peer].buffer.retro) {
            bool nm = !(m.author_id == lastfid && (m.utime-lastut) <= needNameMaxDelta);
            m.needName = nm;
            lastfid = m.author_id;
            lastut = m.utime;
        }
    }

    ref vkMessage lastMessage(ref vkMessage[] buf) {
        auto bufl = buf.length;
        if(bufl == 0) return emptyVkMessage;
        return buf[bufl-1];
    }

    vkMessageLine[] getBufferedChatLines(int count, int offset, int peer) {
        const int takeamount = 1;
        vkMessageLine ld = {
            text: getLocal("loading")
        };

        int needln = count + offset;

        auto chat = getBufferedChat(needln, 0, peer);

        if(chat.length == 0 || chat[chat.length-1].isLoading) return [ ld ];

        vkMessageLine[] localbuf;
        auto lazylines = chat.map!(q => convertMessage(q));

        while(localbuf.length < needln) {
            lazylines.take(takeamount).each!(q => localbuf = q ~ localbuf);
            lazylines = lazylines.drop(takeamount);
        }

        return localbuf[$-needln..$-offset];
    }

    vkMessageLine lspacing = {
        text: "", isSpacing: true
    };

    vkMessageLine[] convertMessage(vkMessage inp) {
        //auto ct = Clock.currTime();
        auto cb = &(pb.chatBuffer[inp.peer_id]);
        auto rupd = (inp.msg_id in cb.recent);
        bool bufallowed = true;
        if(rupd) if(!cb.recent[inp.msg_id].checkedout) bufallowed = false;
        if(bufallowed && (inp.msg_id in cb.linebuffer)) {
            return cb.linebuffer[inp.msg_id];
        }
        vkMessageLine[] rt;
        rt ~= lspacing;
        bool nofwd = (inp.fwd_depth == -1);

        if(inp.needName) {
            vkMessageLine name = {
                text: inp.author_name,
                time: inp.time_str,
                isName: true
            };
            rt ~= name;
            rt ~= lspacing;
        }

        if(inp.body_lines.length != 0) {
            foreach(l; inp.body_lines) {
                vkMessageLine msg = {
                    text: l
                };
                rt ~= msg;
            }
        } else if (nofwd) rt ~= lspacing;

        if(!nofwd) {
            rt ~= renderFwd(inp.fwd, 0);
        }

        cb.linebuffer[inp.msg_id] = rt;
        if(rupd) cb.recent[inp.msg_id].checkedout = true;
        return rt;
    }

    private vkMessageLine[] renderFwd(vkFwdMessage[] inp, int depth) {
        ++depth;
        vkMessageLine[] rt;
        foreach(fm; inp) {
            vkMessageLine name = {
                text: fm.author_name,
                time: fm.time_str,
                isFwd: true, isName: true, fwdDepth: depth
            };
            rt ~= name;
            foreach(l; fm.body_lines) {
                vkMessageLine msg = {
                    text: l,
                    isFwd: true, fwdDepth: depth
                };
                rt ~= msg;
            }
            vkMessageLine fwdspc = {
                isFwd: true, isSpacing: true,
                fwdDepth: depth
            };
            rt ~= fwdspc;

            if(fm.fwd.length != 0) {
                rt ~= renderFwd(fm.fwd, depth);
                rt ~= fwdspc;
            }

        }
        return rt;
    }

    private apiBufferData* getData(blockType tp) {
        switch(tp){
            case blockType.dialogs: return &pb.dialogsData;
            case blockType.friends: return &pb.friendsData;
            case blockType.music: return &pb.audioData;
            default: assert(0);
        }
    }

    void toggleForeceUpdate(blockType tp) {
        getData(tp).forceUpdate = true;
    }

    int getServerCount(blockType tp) {
        return getData(tp).serverCount;
    }

    bool isScrollAllowed(blockType tp) {
        return !getData(tp).loading;
    }

    bool isChatScrollAllowed(int peer){
        return !pb.chatBuffer[peer].data.loading;
    }

    bool isUpdated(blockType tp) {
        auto data = getData(tp);
        if(data.updated) {
            data.updated = false;
            return true;
        }
        return false;
    }

    // ===== longpoll =====

    vkLongpoll getLongpollServer() {
        auto resp = vkget("messages.getLongPollServer", [ "use_ssl": "1", "need_pts": "0" ]);
        vkLongpoll rt = {
            server: resp["server"].str,
            key: resp["key"].str,
            ts: resp["ts"].integer.to!int
        };
        return rt;
    }

    void triggerNewMessage(JSONValue u, SysTime ct) {
        if(pb.dialogsData.forceUpdate) return;

        auto mid = u[1].integer.to!int;
        auto flags = u[2].integer.to!int;
        auto peer = u[3].integer.to!int;
        auto utime = u[4].integer.to!long;
        auto msg = u[6].str.longpollReplaces;
        auto att = u[7];

        bool outbox = (flags & 2) == 2;
        bool unread = (flags & 1) == 1;
        bool hasattaches = att.object.keys.map!(a => (a == "fwd") || a.matchAll(r"attach.*")).any!"a";

        auto conv = (peer > convStartId);
        auto from = conv ? att["from"].str.to!int : ( outbox ? me.id : peer );
        auto first = (pb.dialogsBuffer[0].id == peer);
        auto old = first ? 0 : pb.dialogsBuffer.map!(q => q.id == peer).countUntil(true);
        auto oldfound = (old != -1);
        auto title = conv ? u[5].str : ( oldfound ? nc.getName(peer).strName : "" );
        auto haspeer = (peer in pb.chatBuffer);

        vkDialog nd = {
            name: title, lastMessage: msg, lastmid: mid,
            id: peer, online: true, isChat: conv,
            unread: (unread && !outbox)
        };

        vkMessage nm;
        if(!hasattaches) {
            vkMessage lpnm = {
                author_id: from, peer_id: peer, msg_id: mid,
                outgoing: outbox, unread: unread,
                utime: utime, time_str: vktime(ct, utime),
                author_name: nc.getName(from).strName,
                body_lines: msg.split("\n"),
                fwd_depth: -1
            };
            nm = lpnm;
        } else {
            auto gett = messagesGetById([mid]);
            if(gett.length == 1) nm = gett[0];
        }

        if(first) {
            pb.dialogsBuffer[0] = nd;
        } else {

            if(oldfound) {
                if(!conv) nd.online = pb.dialogsBuffer[old].online;
                pb.dialogsBuffer = nd ~ pb.dialogsBuffer[0..old] ~ pb.dialogsBuffer[(old+1)..pb.dialogsBuffer.length];
            } else {
                if (!conv) {
                    auto peerinfo = usersGet(peer, "online");
                    auto peername = cachedName(peerinfo.first_name, peerinfo.last_name);
                    nc.addToCache(peerinfo.id, peername);
                    nd.name = peername.strName;
                    nd.online = peerinfo.online;
                }
                pb.dialogsBuffer = nd ~ pb.dialogsBuffer;
            }

        }


        if(haspeer) {
            auto cb = &(pb.chatBuffer[peer]);
            if(cb.buffer.length != 0) {
                auto lastm = cb.buffer[0];
                nm.needName = !(lastm.author_id == from && (utime-lastm.utime) <= needNameMaxDelta);
                cb.buffer = nm ~ cb.buffer;
            }
        }

        toggleUpdate();
        dbm("nm trigger, outbox: " ~ outbox.to!string ~ ", unread: " ~ unread.to!string ~ ", hasattaches: " ~ hasattaches.to!string ~ ", conv: " ~ conv.to!string ~ ", from: " ~ from.to!string ~ ". title: " ~ title.to!string ~ ", peer: " ~ peer.to!string);
        dbm("db peers: " ~ pb.dialogsBuffer[0..7].map!(q => q.id.to!string).join(", ") );

    }

    void triggerRead(JSONValue u) {
        bool inboxrd = (u[0].integer == 6);
        auto peer = u[1].integer.to!int;
        auto mid = u[2].integer.to!int;

        auto dc = (inboxrd) ? pb.dialogsBuffer.map!(q => q.id == peer).countUntil(true) : -1;
        auto mc = (peer in pb.chatBuffer) ? pb.chatBuffer[peer].buffer.map!(q => q.msg_id == mid).countUntil(true) : -1;
        bool upd = false;

        if(dc != -1 && pb.dialogsBuffer[dc].lastmid == mid) {
            pb.dialogsBuffer[dc].unread = false;
            upd = true;
        }

        if(mc != -1) {
            auto ct = Clock.currStdTime.stdTimeToUnixTime!long;
            auto cb = &(pb.chatBuffer[peer]);
            for(long i = mc; i > -1; --i) {
                if(cb.buffer[i].unread) {
                    cb.buffer[i].unread = false;
                    cb.recent[cb.buffer[i].msg_id] = apiRecentlyUpdated(ct);
                } else {
                    break;
                }
            }
            upd = true;
        }

        if(upd) toggleUpdate();

    }

    void triggerOnline(JSONValue u) {
        auto uid = u[1].integer.to!int * -1;
        auto flags = u[2].integer.to!int;
        auto event = u[0].integer.to!int;
        bool exit = (event == 9);
        if(!exit && event != 8) return;
        dbm("trigger online event: " ~ event.to!string ~ ", uid: " ~ uid.to!string);

        auto dc = (pb.dialogsData.forceUpdate) ? -1 : pb.dialogsBuffer.map!(q => q.id == uid).countUntil(true);
        auto fc = (pb.friendsData.forceUpdate) ? -1 : pb.friendsBuffer.map!(q => q.id == uid).countUntil(true);
        bool upd = false;

        if(dc != -1) {
            pb.dialogsBuffer[dc].online = !exit;
            dbm("trigger online dc");
            upd = true;
        }

        if(fc != -1) {
            pb.friendsBuffer[fc].online = !exit;
            dbm("trigger online fc");
            upd = true;
        }

        if(upd) toggleUpdate();

    }

    vkNextLp parseLongpoll(string resp) {
        JSONValue j = parseJSON(resp);
        vkNextLp rt;
        auto ct = Clock.currTime();
        auto failed = ("failed" in j ? j["failed"].integer.to!int : -1 );
        auto ts = ("ts" in j ? j["ts"].integer.to!int : -1 );
        if(failed == -1) {
            auto upd = j["updates"].array;
            dbm("new lp: " ~ j.toPrettyString());
            foreach(u; upd) {
                switch(u[0].integer.to!int) {
                    case 4: //new message
                        triggerNewMessage(u, ct);
                        break;
                    case 80: //counter update
                        if(return80mc) {
                            ps.latestUnreadMsg = u[1].integer.to!int;
                        } else {
                            ps.lp80got = true;
                        }
                        toggleUpdate();
                        break;
                    case 6: //inbox read
                        triggerRead(u);
                        break;
                    case 7: //outbox read
                        triggerRead(u);
                        break;
                    case 8: //online\offline
                        triggerOnline(u);
                        break;
                    case 9: //online\offline
                        triggerOnline(u);
                        break;
                    default:
                        break;
                }
            }
        }
        rt.ts = ts;
        rt.failed = failed;
        return rt;
    }

    void doLongpoll(vkLongpoll start) {
        auto tm = dur!timeoutFormat(longpollCurlTimeout);
        int cts = start.ts;
        bool ok = true;
        dbm("longpoll works");
        while(ok) {
            try {
                if(cts < 1) break;
                string url = "https://" ~ start.server ~ "?act=a_check&key=" ~ start.key ~ "&ts=" ~ cts.to!string ~ "&wait=25&mode=2";
                auto resp = httpget(url, tm);
                immutable auto next = parseLongpoll(resp);
                if(next.failed == 2 || next.failed == 3) ok = false; //get new server
                cts = next.ts;
            } catch(Exception e) {
                dbm("longpoll exception: " ~ e.msg);
                ok = false;
            }
        }
    }

    void startLongpoll() {
        dbm("longpoll is starting...");
        while(true) {
            try {
                doLongpoll(getLongpollServer());
            } catch (ApiErrorException e) {
                dbm("longpoll ApiErrorException: " ~ e.msg);
            }
            dbm("longpoll is restarting...");
        }
    }

    void asyncLongpoll() {
        lpThread.start();
    }

}

// ===== async =====

class longpollThread : Thread {

    VKapi api;

    this(VKapi api) {
        this.api = api;
        super(&longpoll);
    }

    private void longpoll() {
        api.startLongpoll();
    }

}

class loadBlockThread : Thread {
    int count;
    int offset;

    void delegate(int count, int offset) dg;

    this() {
        super(&run);
    }

    void func(void delegate(int count, int offset) r, int count, int offset) {
        this.count = count;
        this.offset = offset;
        dg = r;
        this.start();
    }

    private void run() {
        try {
            dg(count, offset);
        } catch (Exception e) {
            dbm("Catched at asyncLoadBlock thread: " ~ e.msg);
        }
    }

}

// ===== Exceptions =====

class BackendException : Exception {
    public {
        @safe pure nothrow this(string message,
                                string file =__FILE__,
                                size_t line = __LINE__,
                                Throwable next = null) {
            super(message, file, line, next);
        }
    }
}

class ApiErrorException : Exception {
    public {
        int errorCode;
        @safe pure nothrow this(string message,
                                int error_code,
                                string file =__FILE__,
                                size_t line = __LINE__,
                                Throwable next = null) {
            errorCode = error_code;
            super(message, file, line, next);
        }
    }
}