module vkapi;

import std.stdio, std.conv, std.string, std.regex, std.algorithm, std.array, std.datetime, core.time;
import std.exception, core.exception;
import std.net.curl, std.uri, std.json;
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
}

struct vkMessage {
    string author_name; // in format 'First Last'
    int author_id;
    int peer_id; // for users: user id, for conversations: 2000000000 + chat id
    int msg_id;
    bool outgoing;
    bool unread;
    bool needName;
    long utime; // unix time
    string time_str; // HH:MM (M = minutes), if >24 hours ago, then DD.mm (m = month)
    string[] body_lines; // Message text, splitted in lines (delimiter = '\n')
    int fwd_depth; // max fwd message deph (-1 if no fwd)
    vkFwdMessage[] fwd; // forwarded messages
}

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
}

enum blockType {
    dialogs,
    music,
    friends
}

struct apiBufferData {
    int serverCount = -1;
    bool forceUpdate = true;
    bool loading = false;
    bool updated = false;

}

struct apiChatBuffer {
    vkMessage[] buffer;
    apiBufferData data;
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
        lbThread = new loadBlockThread(this);
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
            } else {
                auto uid = msg["user_id"].integer.to!int;
                ds.id = uid;
                ds.name = nc.getName(ds.id).strName;
                ds.online = (uid in online) ? online[uid] : false;
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

    vkMessage[] messagesGetHistory(int peer_id, int count = -1, int offset = 0, int start_message_id = -1, bool rev = false) {
        auto ct = Clock.currTime();
        auto params = [ "peer_id": peer_id.to!string ];
        if(count >= 0) params["count"] = count.to!string;
        if(offset != 0) params["offset"] = offset.to!string;
        if(start_message_id > 0) params["start_message_id"] = start_message_id.to!string;
        if(rev) params["rev"] = "1";

        auto resp = vkget("messages.getHistory", params);
        auto items = resp["items"].array;

        int last_fid;
        long last_date;
        vkMessage[] rt;
        foreach(m; items) {
            int fid = m["from_id"].integer.to!int;
            int mid = m["id"].integer.to!int;
            int pid = ("chat_id" in m) ? (m["chat_id"].integer.to!int + convStartId) : m["user_id"].integer.to!int;
            long ut = m["date"].integer.to!long;
            bool outg = (m["out"].integer.to!int == 1);
            bool rstate = (m["read_state"].integer.to!int == 1);
            //bool unr = (outg && !rstate);
            bool unr = !rstate;

            string[] mbody = m["body"].str.split("\n");
            string st = vktime(ct, ut);

            int fwdp = -1;
            vkFwdMessage[] fw;
            if("fwd_messages" in m) {
                auto r = digFwd(m["fwd_messages"].array, ct, 0, 1);
                fwdp = r.md;
                fw = r.fwd;
            }

            auto tdelta = ut - last_date;
            bool neednm = (tdelta > needNameMaxDelta) || (fid != last_fid);
            last_date = ut;

            vkMessage mo = {
                msg_id: mid, author_id: fid, peer_id: pid,
                outgoing: outg, unread: unr, utime: ut,
                author_name: nc.getName(fid).strName,
                time_str: st, body_lines: mbody,
                fwd_depth: fwdp, fwd:fw, needName:neednm
            };
            rt ~= mo;
        }
        return rt;
    }

    // ===== buffers =====


    private T[] getBuffered(T)(int block, int upd, int count, int offset, blockType blocktp, ref apiBufferData bufd, ref T[] buf, out bool retLoading) {
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
            //auto tid = spawn(&asyncLoadBlock, this.exportStruct(), blockType.dialogs, block, cl);
            //pb.dialogsLatCL = cl;
            lbThread.loadBlock(blocktp, block, cl);
        }

        return rt;
    }

    vkFriend[] getBufferedFriends(int count, int offset) {
        const int block = 100;
        const int upd = 50;

        bool outload;
        auto rt = getBuffered!vkFriend(block, upd, count, offset, blockType.friends, pb.friendsData, pb.friendsBuffer, outload);

        immutable vkFriend ld = {
            first_name: getLocal("loading"),
            last_name: ""
        };

        if(outload) rt = [ ld ];
        return rt;
    }

    vkAudio[] getBufferedMusic(int count, int offset) {
        const int block = 100;
        const int upd = 50;

        bool outload;
        auto rt = getBuffered!vkAudio(block, upd, count, offset, blockType.music, pb.audioData, pb.audioBuffer, outload);

        immutable vkAudio ld = {
            artist: getLocal("loading"),
            title: ""
        };

        if(outload) rt = [ ld ];
        return rt;
    }

    vkDialog[] getBufferedDialogs(int count, int offset) {
        const int block = 100;
        const int upd = 50;

        bool outload;
        auto rt = getBuffered!vkDialog(block, upd, count, offset, blockType.dialogs, pb.dialogsData, pb.dialogsBuffer, outload);

        immutable vkDialog ld = {
            name: getLocal("loading")
        };

        if(outload) rt = [ ld ];
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

    int getServerCount(blockType tp) {
        return getData(tp).serverCount;
    }

    bool isScrollAllowed(blockType tp) {
        return !getData(tp).loading;
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

    void triggerNewMessage(JSONValue u) {
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

        vkDialog nd = {
            name: title, lastMessage: msg, lastmid: mid,
            id: peer, online: true,
            unread: (unread && !outbox)
        };

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

        toggleUpdate();
        dbm("nm trigger, outbox: " ~ outbox.to!string ~ ", unread: " ~ unread.to!string ~ ", hasattaches: " ~ hasattaches.to!string ~ ", conv: " ~ conv.to!string ~ ", from: " ~ from.to!string ~ ". title: " ~ title.to!string ~ ", peer: " ~ peer.to!string);
        dbm("db peers: " ~ pb.dialogsBuffer[0..7].map!(q => q.id.to!string).join(", ") );

    }

    void triggerRead(JSONValue u) {
        auto peer = u[1].integer.to!int;
        auto mid = u[2].integer.to!int;

        auto dc = pb.dialogsBuffer.map!(q => q.id == peer).countUntil(true);
        if(dc == -1) return;

        if(pb.dialogsBuffer[dc].lastmid == mid) {
            pb.dialogsBuffer[dc].unread = false;
        }

        toggleUpdate();

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
        auto failed = ("failed" in j ? j["failed"].integer.to!int : -1 );
        auto ts = ("ts" in j ? j["ts"].integer.to!int : -1 );
        if(failed == -1) {
            auto upd = j["updates"].array;
            dbm("new lp: " ~ j.toPrettyString());
            foreach(u; upd) {
                switch(u[0].integer.to!int) {
                    case 4: //new message
                        triggerNewMessage(u);
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
                    case 8:
                        triggerOnline(u);
                        break;
                    case 9:
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

    VKapi api;
    blockType bt;
    int count;
    int offset;

    this(VKapi api) {
        this.api = api;
        //super(&asyncLoadBlock);
        super(&run);
    }

    void loadBlock(blockType bt, int count, int offset) {
        this.bt = bt;
        this.count = count;
        this.offset = offset;
        this.start();
    }

    private void asyncLoadBlock() {
        dbm("asyncLoadBlock start");
        switch (bt) {
            case blockType.dialogs:
                dbm("asyncLoadBlock switched dialogs");
                int sc;
                pb.dialogsBuffer ~= api.messagesGetDialogs(count, offset, sc);
                pb.dialogsData.serverCount = sc;
                pb.dialogsData.updated = true;
                break;
            case blockType.music:
                dbm("asyncLoadBlock switched music");
                int sc;
                pb.audioBuffer ~= api.audioGet(count, offset, sc);
                pb.audioData.serverCount = sc;
                pb.audioData.updated = true;
                break;
            case blockType.friends:
                dbm("asyncLoadBlock switched friends");
                int sc;
                pb.friendsBuffer ~= api.friendsGet(count, offset, sc);
                pb.friendsData.serverCount = sc;
                pb.friendsData.updated = true;
                dbm("friends info bufl: " ~ pb.friendsBuffer.length.to!string ~ ", sc: " ~ sc.to!string ~ ", strctsc: " ~ pb.friendsData.serverCount.to!string);
                break;
            default: break;
        }
        api.toggleUpdate();
        dbm("asyncLoadBlock end");
    }

    private void run() {
        try {
            asyncLoadBlock();
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