module vkapi;

import std.stdio, std.conv, std.string, std.regex, std.array, std.datetime, std.random, core.time;
import std.exception, core.exception;
import std.net.curl, std.uri, std.json;
import std.algorithm, std.range, std.experimental.ndslice;
import std.parallelism, std.concurrency, core.thread, core.sync.mutex;
import utils, namecache, localization;



// ===== vkapi const =====

const int convStartId = 2000000000;
const int mailStartId = convStartId*-1;
const bool return80mc = true;
const long needNameMaxDelta = 180; //seconds, 3 min
const int chatBlock = 100;
const int chatUpd = 50;

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
    bool isZombie;
    int rndid;
    int lineCount = -1;
    int wrap = -1;
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
    string lastlp = "";
    sendOrderMsg[] order;
    sentMsg[int] sent; //by rid
}

struct sendOrderMsg {
    int author;
    int peer;
    int rid;
    string msg;
    int[] fwd = [];
    string[] att = [];
}

struct sentMsg {
    int rid;
    int peer;
    int author;
    sendState state = sendState.pending;
}

enum blockType {
    dialogs,
    music,
    friends,
    chat
}

enum sendState {
    pending,
    failed,
    ok
}

struct apiBufferData {
    int serverCount = -1;
    int linesCount = -1;
    bool forceUpdate = true;
    bool loading = false;
    bool updated = false;

}

struct apiRecentlyUpdated {
    long updated;
    bool checkedout;
}

struct apiLineCache {
    vkMessageLine[] buf;
    int wrap = -1;
}

struct apiChatBuffer {
    vkMessage[] buffer;
    apiBufferData data;
    apiLineCache[int] linebuffer; // by mid
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

__gshared Mutex sndMutex;
__gshared Mutex pbMutex;

loadBlockThread lbThread;
longpollThread lpThread;
sendThread sndThread;
typingThread tpThread;

class VKapi {

// ===== API & networking =====

    private const string vkurl = "https://api.vk.com/method/";
    const string vkver = "5.50";
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
        sndThread = new sendThread(this);
        tpThread = new typingThread(this);

        sndMutex = new Mutex();
        pbMutex = new Mutex();
    }

    apiTransfer exportStruct() {
        return apiTransfer(vktoken, isTokenValid, me);
    }

    const uint maxuint = 4_294_967_295;
    const uint maxint = 2_147_483_647;
    const uint ridstart = 1;
    int genId() {
        long rnd = uniform(ridstart, maxuint);
        if(rnd > maxint) {
            rnd = -(rnd-maxint);
        }
        return rnd.to!int;
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
        if(userIds.length == 0) return [];
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

    void setTypingStatus(int peer) {
        tpThread.setStatus(peer);
    }

    void setActivityStatusImpl(int peer, string type) {
        try{
            vkget("messages.setActivity", [ "peer_id": peer.to!string, "type": type ]);
        } catch (Exception e) {
            dbm("catched at setTypingStatus: " ~ e.msg);
        }
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

            nc.requestId(fid);

            vkFwdMessage mm = {
                author_id: fid,
                utime: ut, time_str: vktime(ct, ut),
                body_lines: j["body"].str.split("\n"),
                fwd: fw
            };
            rt ~= mm;
        }
        return apiFwdIter(rt, cmd);
    }

    private void resolveFwdRecv(ref vkFwdMessage[] inp) {
        foreach(ref m; inp) {
            m.author_name = nc.getName(m.author_id).strName;
            if(m.fwd.length != 0) resolveFwdRecv(m.fwd);
        }
    }

    private void resolveFwdNames(ref vkMessage[] inp) {
        nc.resolveNames();
        inp.map!(q => q.fwd).filter!(q => q.length != 0).each!(q => resolveFwdRecv(q));
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
        resolveFwdNames(rt);
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

    int messagesSend(int pid, string msg, int rndid = 0, int[] fwd = [], string[] attaches = []) {
        if(msg.length == 0 && fwd.length == 0 && attaches.length == 0) return -1;

        auto params = ["peer_id": pid.to!string ];
        if(rndid != 0) params["random_id"] = rndid.to!string;
        if(msg != "") params["message"] = msg;
        if(fwd.length != 0) params["forward_messages"] = fwd.map!(q => q.to!string).join(",");
        if(attaches.length != 0) params["attachment"] = attaches.join(",");

        auto resp = vkget("messages.send", params);
        return resp.integer.to!int;
    }

    // ===== buffers =====


    private T[] getBuffered(T)(int block, int upd, int count, int offset, blockType blocktp, void delegate(int count, int offset) download, ref apiBufferData bufd, ref T[] buf, out bool retLoading) {
        T[] rt;
        bool spawnLoadBlock = false;

        //dbm("getbuffered count: " ~ count.to!string ~ ", offset: " ~ offset.to!string ~ ", blocktp: " ~ blocktp.to!string);

        synchronized(pbMutex) {
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
                if(count >= cl) {
                    count = cl;
                    offset = 0;
                } else {
                    offset = cl - count;
                }
                needln = count + offset;
                dbm("this needln too big for me((, now offset: " ~ offset.to!string ~ ", count: " ~ count.to!string ~ ", sc: " ~ bufd.serverCount.to!string ~ ", needln: " ~ needln.to!string);
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
        }
        return rt;
    }

    vkFriend[] getBufferedFriends(int count, int offset) {
        const int block = 100;
        const int upd = 50;
        if(offset < 0) offset = 0;

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
        if(offset < 0) offset = 0;

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
        if(offset < 0) offset = 0;

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
        const int block = chatBlock;
        const int upd = chatUpd;
        if(offset < 0) offset = 0;

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
            pb.chatBuffer[peer].data.loading = false;
            toggleUpdate();
        }

        if(peer !in pb.chatBuffer) pb.chatBuffer[peer] = apiChatBuffer();

        bool outload;
        auto rt = getBuffered!vkMessage(block, upd, count, offset, blockType.chat, &dw, pb.chatBuffer[peer].data, pb.chatBuffer[peer].buffer, outload);

        if(outload) return defaultrt;

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

    vkMessageLine[] getBufferedChatLines(int count, int offset, int peer, int wrapwidth) {
        dbm("bfcl called, count: " ~ count.to!string ~ ", offset: " ~ offset.to!string);
        if(offset < 0) offset = 0;
        vkMessageLine ld = {
            text: getLocal("loading")
        };

        int needln = count + offset;
        int lnsum;
        int start;
        int stoff;
        int end;

        auto haspeer = peer in pb.chatBuffer;
        bool doneload;
        int loadoffset = 0;
        bool offsetcatched = false;

        if(haspeer) {
            auto cb = &(pb.chatBuffer[peer]);

            if(cb.data.linesCount != -1 && needln > cb.data.linesCount && count < cb.data.linesCount) {
                dbm("bfcl got needln more than linescount, coffset: " ~ offset.to!string ~ ", count: " ~ count.to!string);
                offset = cb.data.linesCount - count;
                needln = offset+count;
            }

            loadoffset = cb.buffer.length.to!int;
            doneload = loadoffset >= cb.data.serverCount;

            int i;
            foreach(m; cb.buffer) {
                immutable auto lc = getMessageLinecount(m, wrapwidth);
                lnsum += lc;
                if(!offsetcatched && lnsum >= offset) {
                    start = i;
                    stoff = lc - (lnsum - offset);
                    offsetcatched = true;
                }
                if(lnsum >= needln) {
                    end = i;
                    break;
                }
                ++i;
            }
        }

        auto updtr = loadoffset - chatUpd;
        if(end > updtr && end < loadoffset) {
            if( (updtr+1) < chatUpd ) updtr = 1;
            getBufferedChat(1, updtr+1, peer); //preload
        }

        if(lnsum < needln) {
            dbm("bfcl not enough lnsum: " ~ lnsum.to!string ~ ", needln: " ~ needln.to!string);
            if(!doneload) {
                getBufferedChat(chatBlock, loadoffset, peer);
                return [ ld ];
            } else {
                if(loadoffset == 0) return [];
                end = loadoffset-1;
            }
        }

        if(doneload) {
            auto dt = &(pb.chatBuffer[peer]);
            if(dt.data.linesCount == -1) {
                dt.data.linesCount = dt.buffer.map!(q => getMessageLinecount(q, wrapwidth)).sum;
            }
        }

        vkMessageLine[] lnbf;
        pb.chatBuffer[peer]
                            .buffer[start..end+1]
                            .retro
                            .map!(q => convertMessage(q, wrapwidth))
                            .each!(q => lnbf ~= q);

        auto lcount = count+stoff;
        bool shortchat = doneload && (lnbf.length <= count);
        return (shortchat) ? lnbf : lnbf[$-lcount..$-stoff];
    }

    vkMessageLine lspacing = {
        text: "", isSpacing: true
    };

    int getMessageLinecount(ref vkMessage inp, int ww) {
        if(inp.lineCount == -1 || inp.wrap == -1 || inp.wrap != ww) return convertMessage(inp, ww).length.to!int;
        else return inp.lineCount;
    }

    void defeatMessageCache(int mid, int peer) {
        pb.chatBuffer[peer].linebuffer.remove(mid);
    }

    vkMessageLine[] convertMessage(ref vkMessage inp, int ww) {
        immutable bool zombie = inp.isZombie || inp.msg_id < 1;
        apiChatBuffer* cb;
        synchronized(pbMutex) {
            cb = &(pb.chatBuffer[inp.peer_id]);
            if(!zombie) {
                auto cached = inp.msg_id in cb.linebuffer;
                if(cached && cached.wrap == ww) {
                    return (*cached).buf;
                }
            }
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
            bool unrfl = inp.unread;
            wstring[] wrapped;
            inp.body_lines.map!(q => q.to!wstring.wordwrap(ww)).each!(q => wrapped ~= q);
            foreach(l; wrapped) {
                vkMessageLine msg = {
                    text: l.to!string,
                    unread: unrfl
                };
                rt ~= msg;
                if(unrfl) unrfl = false;
            }
        } else if (nofwd) rt ~= lspacing;

        if(!nofwd) {
            rt ~= lspacing ~ renderFwd(inp.fwd, 0, ww);
        }

        synchronized(pbMutex) {
            if(!zombie) cb.linebuffer[inp.msg_id] = apiLineCache(rt, ww);
            inp.lineCount = rt.length.to!int;
            inp.wrap = ww;
        }
        return rt;
    }

    const int wwmultiplier = 3;

    private vkMessageLine[] renderFwd(vkFwdMessage[] inp, int depth, int ww) {
        ++depth;
        auto lcww = ww - (depth * wwmultiplier);
        if(lcww <= 0) lcww = 1;

        vkMessageLine[] rt;
        foreach(fm; inp) {
            vkMessageLine name = {
                text: fm.author_name,
                time: fm.time_str,
                isFwd: true, isName: true, fwdDepth: depth
            };
            rt ~= name;
            wstring[] wrapped;
            fm.body_lines.map!(q => q.to!wstring.wordwrap(lcww)).each!(q => wrapped ~= q);
            foreach(l; wrapped) {
                vkMessageLine msg = {
                    text: l.to!string,
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
                rt ~= renderFwd(fm.fwd, depth, ww);
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

    bool isChatScrollAllowed(int peer) {
        return !pb.chatBuffer[peer].data.loading;
    }

    int getChatServerCount(int peer) {
        return pb.chatBuffer[peer].data.serverCount;
    }

    int getChatLineCount(int peer) {
        return pb.chatBuffer[peer].data.linesCount;
    }

    string getLastLongpollMessage() {
        auto last = ps.lastlp;
        ps.lastlp = "";
        return last;
    }

    bool isUpdated(blockType tp) {
        auto data = getData(tp);
        if(data.updated) {
            data.updated = false;
            return true;
        }
        return false;
    }

    // ===== send =====

    const int zombiermtake = 30;

    int findzombie(sentMsg snt) {
        return pb.chatBuffer[snt.peer].buffer.take(zombiermtake)
            .map!(q => q.rndid == snt.rid).countUntil(true).to!int;
    }

    void notifySendState(sentMsg m) {
        switch(m.state) {
            case sendState.failed:
                auto fnd = findzombie(m);
                auto cb = &(pb.chatBuffer[m.peer]);
                if(fnd != -1) cb.buffer[fnd].time_str = getLocal("sendfailed");
                toggleUpdate();
                break;
            default: break;
        }
    }

    void asyncSendMessage(int peer, string msg) {
        dbm("called asyncsendmsg, peer: " ~ peer.to!string ~ ", msg: " ~ msg);

        auto rid = genId();
        auto aid = me.id;
        auto cb = &(pb.chatBuffer[peer]);

        vkMessage zombie = {
            author_name: me.first_name ~ " " ~ me.last_name,
            author_id: aid, isZombie: true,
            body_lines: msg.split("\n"),
            time_str: getLocal("sending"),
            rndid: rid, msg_id: -1, outgoing: true, unread: true,
            peer_id: peer, utime: 1,
            needName: true, nmresolved: true
        };

        cb.buffer = zombie ~ cb.buffer;
        toggleUpdate();

        dbm("sendmsg: zombie created");

        sendOrderMsg ord = {
            author: aid,
            peer: peer, rid: rid, msg: msg
        };
        sentMsg snt = {
            rid: rid, author: aid, peer: peer
        };

        synchronized(sndMutex) {
            ps.sent[rid] = snt;
            ps.order ~= ord;
        }

        dbm("sendmsg: message in order");

        if(!sndThread.isRunning) {
            dbm("sendmsg: start sndthread");
            sndThread.start();
        }
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

    const longpollGimStartId = 1000000000;

    void triggerNewMessage(JSONValue ui, SysTime ct) {
        if(pb.dialogsData.forceUpdate) return;
        auto u = ui.array;

        auto mid = u[1].integer.to!int;
        auto flags = u[2].integer.to!int;
        auto peer = u[3].integer.to!int;
        auto utime = u[4].integer.to!long;
        auto msg = u[6].str.longpollReplaces;
        auto att = u[7];
        int rndid = (u.length > 8) ? u[8].integer.to!int : 0;

        bool outbox = (flags & 2) == 2;
        bool unread = (flags & 1) == 1;
        bool hasattaches = att.object.keys.map!(a => (a == "fwd") || a.matchAll(r"attach.*")).any!"a";

        auto conv = (peer > convStartId);
        bool group = false;

        if(!conv && peer > longpollGimStartId) {
            peer = -(peer - longpollGimStartId);
            group = true;
        }

        auto from = conv ? att["from"].str.to!int : ( outbox ? me.id : peer );
        auto first = (pb.dialogsBuffer[0].id == peer);
        auto old = first ? 0 : pb.dialogsBuffer.map!(q => q.id == peer).countUntil(true);
        auto oldfound = (old != -1);
        auto title = conv ? u[5].str : ( group || oldfound ? nc.getName(peer).strName : "" );
        auto haspeer = (peer in pb.chatBuffer);

        vkDialog nd = {
            name: title, lastMessage: msg, lastmid: mid,
            id: peer, online: true, isChat: conv,
            unread: (unread && !outbox)
        };

        vkMessage nm;

        synchronized(pbMutex) {
            if(!hasattaches) {
                vkMessage lpnm = {
                    author_id: from, peer_id: peer, msg_id: mid,
                    outgoing: outbox, unread: unread,
                    utime: utime, time_str: vktime(ct, utime),
                    author_name: nc.getName(from).strName,
                    body_lines: msg.split("\n"),
                    fwd_depth: -1, needName: true
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
                    if (!conv && !group) {
                        auto peerinfo = usersGet(peer, "online");
                        auto peername = cachedName(peerinfo.first_name, peerinfo.last_name);
                        nc.addToCache(peerinfo.id, peername);
                        nd.name = peername.strName;
                        nd.online = peerinfo.online;
                    }
                    pb.dialogsBuffer = nd ~ pb.dialogsBuffer;
                }

            }

            int sentfnd = -1;

            if(rndid != 0) synchronized(sndMutex) {
                auto snt = rndid in ps.sent;
                if(snt && snt.author == me.id) {
                    dbm("lp nm: approved sent");
                    sentfnd = findzombie(*snt);
                    ps.sent.remove(rndid);
                }
            }

            if(haspeer) {
                auto cb = &(pb.chatBuffer[peer]);
                cb.data.serverCount += 1;
                auto realmsg = cb.buffer.filter!(q => !q.isZombie);
                if(!realmsg.empty) {
                    auto lastm = realmsg.front;
                    nm.needName = !(lastm.author_id == from && (utime-lastm.utime) <= needNameMaxDelta);
                }
                if(sentfnd == -1) cb.buffer = nm ~ cb.buffer;
                else cb.buffer[sentfnd] = nm; //todo delete and add instead of replace
            }

        }

        //if(from != me.id)
        ps.lastlp = title ~ ": " ~ msg;

        toggleUpdate();
        dbm("nm trigger, outbox: " ~ outbox.to!string ~ ", unread: " ~ unread.to!string ~ ", hasattaches: " ~ hasattaches.to!string ~ ", conv: " ~ conv.to!string ~ ", from: " ~ from.to!string ~ ". title: " ~ title.to!string ~ ", peer: " ~ peer.to!string);
        dbm("db peers: " ~ pb.dialogsBuffer[0..7].map!(q => q.id.to!string).join(", ") );

    }

    void triggerRead(JSONValue u) {
        bool inboxrd = (u[0].integer == 6);
        auto peer = u[1].integer.to!int;
        auto mid = u[2].integer.to!int;

        if(peer > longpollGimStartId && peer < convStartId) {
            peer = -(peer-longpollGimStartId);
        }

        auto haspeer = (peer in pb.chatBuffer);
        long mc = -1;
        bool upd = false;

        synchronized(pbMutex) {
            auto dc = (inboxrd) ? pb.dialogsBuffer.map!(q => q.id == peer).countUntil(true) : -1;

            if(haspeer) {
                mc = pb.chatBuffer[peer].buffer.map!(q => q.msg_id == mid).countUntil(true);
            }

            if(dc != -1 && pb.dialogsBuffer[dc].lastmid == mid) {
                pb.dialogsBuffer[dc].unread = false;
                upd = true;
            }


            if(mc != -1) {
                auto cb = &(pb.chatBuffer[peer]);
                foreach(ref m; cb.buffer[mc..$]) {
                    if(m.outgoing != inboxrd) {
                        if(m.unread) {
                            m.unread = false;
                            defeatMessageCache(m.msg_id, peer);
                        } else {
                            break;
                        }
                    }
                }
                upd = true;
            }

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

        bool upd = false;

        synchronized(pbMutex) {
            auto dc = (pb.dialogsData.forceUpdate) ? -1 : pb.dialogsBuffer.map!(q => q.id == uid).countUntil(true);
            auto fc = (pb.friendsData.forceUpdate) ? -1 : pb.friendsBuffer.map!(q => q.id == uid).countUntil(true);

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
        auto mode = (2 + 128).to!string; //attaches + random_id
        bool ok = true;
        dbm("longpoll works");
        while(ok) {
            try {
                if(cts < 1) break;
                string url = "https://" ~ start.server ~ "?act=a_check&key=" ~ start.key ~ "&ts=" ~ cts.to!string ~ "&wait=25&mode=" ~ mode;
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

class sendThread : Thread {

    VKapi api;

    this(VKapi api) {
        this.api = api;
        super(&sendproc);
    }

    private void sendproc() {
        for(int i; i < ps.order.length; ++i) {
            auto msg = ps.order[i];
            try {
                api.messagesSend(msg.peer, msg.msg, msg.rid, msg.fwd, msg.att);
            } catch (Exception e) {
                dbm("catched at sendThread: " ~ e.msg);
                synchronized(sndMutex) {
                    auto snt = msg.rid in ps.sent;
                    if(snt) {
                        dbm("sndThread: new failed state");
                        snt.state = sendState.failed;
                        api.notifySendState(*snt);
                    }
                }
            }
        }
        synchronized(sndMutex) {
            ps.order = [];
            dbm("sndThread: order clear");
        }
    }
}

class typingThread : Thread {
    VKapi api;

    const type = "typing";
    const wait = dur!"msecs"(100);
    const waitmultiplier = 5*10;

    int lastpeer;
    bool updpeer;

    this(VKapi api) {
        this.api = api;
        super(&asyncset);
    }

    void setStatus(int peer) {
        if(lastpeer != peer) {
            updpeer = true;
            lastpeer = peer;
        }
        if(!this.isRunning) this.start();
    }

    private void asyncset() {
        bool loop = true;
        while(loop) {
            api.setActivityStatusImpl(lastpeer, type);
            loop = false;
            updpeer = false;
            for(int i; i < waitmultiplier; ++i) {
                Thread.sleep(wait);
                if(updpeer) {
                    loop = true;
                    break;
                }
            }
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