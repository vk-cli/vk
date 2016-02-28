module vkapi;

import std.stdio, std.conv, std.string, std.algorithm, std.array, std.datetime, core.time;
import std.exception, core.exception;
import std.net.curl, std.uri, std.json;
import std.parallelism, std.concurrency, core.thread;
import utils, namecache, localization;



// ===== vkapi const =====

const int convStartId = 2000000000;
const int mailStartId = convStartId*-1;
const bool return80mc = true;

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
}

struct vkDialog {
    string name;
    string lastMessage = "";
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
    dialogs
}

struct apiBuffers {
    vkDialog[] dialogsBuffer;
    int dialogsCount = -1;
    bool dialogsForceUpdate = false;
    bool dialogsLoading = false;
    bool dialogsUpdated = false;
    loadBlockThread dialogsThread;
    int dialogsLatCL;
}

struct apiFwdIter {
    vkFwdMessage[] fwd;
    int md;
}

__gshared nameCache nc = nameCache();
__gshared apiState ps = apiState();
__gshared apiBuffers pb = apiBuffers();

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
        pb.dialogsThread = new loadBlockThread();
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
                ds.id = msg["chat_id"].integer.to!int;
                ds.name = msg["title"].str;
                ds.online = false;
            } else {
                auto uid = msg["user_id"].integer.to!int;
                ds.id = uid;
                ds.name = nc.getName(ds.id).strName;
                ds.online = (uid in online) ? online[uid] : false;
            }
            ds.lastMessage = msg["body"].str;
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

    vkFriend[] friendsGet(int user_id = 0, int count = 0, int offset = 0) {
        auto params = [ "fields": "online" ];
        if(user_id != 0) params["user_id"] = user_id.to!string;
        if(count != 0) params["count"] = count.to!string;
        if(offset != 0) params["offset"] = offset.to!string;

        auto resp = vkget("friends.get", params);
        //resp.toPrettyString().dbm;
        vkFriend[] rt;
        foreach(f; resp["items"].array) {
            rt ~= vkFriend(
                f["first_name"].str, f["last_name"].str,
                f["id"].integer.to!int, (f["online"].integer.to!int == 1) ? true : false
            );
        }
        return rt;
    }

    vkAudio[] audioGet(int owner_id = 0, int album_id = 0, int count = 0, int offset = 0) {
        string[string] params;
        if(owner_id != 0) params["owner_id"] = owner_id.to!string;
        if(album_id != 0) params["album_id"] = album_id.to!string;
        if(count != 0) params["count"] = count.to!string;
        if(offset != 0) params["offset"] = offset.to!string;

        auto resp = vkget("audio.get", params);
        vkAudio[] rt;
        foreach(a; resp["items"].array) {
            int ad = a["duration"].integer.to!int;
            auto adm = ad.convert!("seconds", "minutes");
            auto ads = ad - (60*adm);
            auto ads_str = (ads < 10 ? "0" : "") ~ ads.to!string;

            vkAudio aud = {
                id: a["id"].integer.to!int, owner: a["owner_id"].integer.to!int,
                artist: a["artist"].str, title: a["title"].str, url: a["url"].str,
                duration_sec: ad, duration_str: (adm.to!string ~ ":" ~ ads_str)
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
        vkMessage[] rt;
        foreach(m; items) {
            int fid = m["from_id"].integer.to!int;
            int mid = m["id"].integer.to!int;
            int pid = ("chat_id" in m) ? (m["chat_id"].integer.to!int + convStartId) : m["user_id"].integer.to!int;
            long ut = m["date"].integer.to!long;
            bool outg = (m["out"].integer.to!int == 1);
            bool rstate = (m["read_state"].integer.to!int == 1);
            bool unr = (outg && !rstate);

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
                fwd_depth: fwdp, fwd:fw
            };
            rt ~= mo;
        }
        return rt;
    }

    // ===== buffers =====



    vkDialog[] getBufferedDialogs(int count, int offset) {
        const int block = 100;
        const int upd = 50;

        vkDialog[] rt;
        bool spawnLoadBlock = false;

        if(pb.dialogsForceUpdate || pb.dialogsBuffer.length < block) pb.dialogsBuffer = new vkDialog[0];

        immutable int cl = (pb.dialogsThread.isRunning) ? pb.dialogsLatCL : pb.dialogsBuffer.length.to!int;
        int needln = count + offset;

        if (pb.dialogsCount == -1 || cl == 0 || (cl < pb.dialogsCount && offset >= (cl-upd))) {
            dbm("called UPD at offset " ~ offset.to!string ~ ", with current trigger " ~ (cl-upd).to!string);
            dbm("dbuf info cl: " ~ cl.to!string ~ ", needln: " ~ needln.to!string ~ ", dthread running: " ~ pb.dialogsThread.isRunning.to!string);
            spawnLoadBlock = true;
        }

        if(pb.dialogsCount != -1 && needln > pb.dialogsCount) {
            offset = pb.dialogsCount - count;
            needln = count + offset;
        }

        if(needln <= cl) {
            pb.dialogsLoading = false;
            rt = slice!vkDialog(pb.dialogsBuffer, count, offset);
        } else {
            dbm("catched LOADING state at offset " ~ offset.to!string);
            pb.dialogsLoading = true;
            immutable vkDialog ld = {
                name: getLocal("loading")
            };

            if((cl - needln) == 1) {
                rt = ( slice!vkDialog(pb.dialogsBuffer, count - 1, offset) ~ ld );
            } else {
                rt = [ ld ];
            }

        }

        if(spawnLoadBlock && !pb.dialogsThread.isRunning) {
            //auto tid = spawn(&asyncLoadBlock, this.exportStruct(), blockType.dialogs, block, cl);
            pb.dialogsLatCL = cl;
            pb.dialogsThread.setParams(this.exportStruct(), blockType.dialogs, block, cl);
            pb.dialogsThread.start();
        }

        return rt;
    }

    bool isScrollAllowed() {
        return !pb.dialogsLoading;
    }

    bool isDialogsUpdated() {
        if(pb.dialogsUpdated) {
            pb.dialogsUpdated = false;
            return true;
        }
        return false;
    }

    int getDialogsCount() {
        return pb.dialogsCount;
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

    vkNextLp parseLongpoll(string resp) {
        JSONValue j = parseJSON(resp);
        vkNextLp rt;
        auto failed = ("failed" in j ? j["failed"].integer.to!int : -1 );
        auto ts = ("ts" in j ? j["ts"].integer.to!int : -1 );
        if(failed == -1) {
            auto upd = j["updates"].array;
            foreach(u; upd) {
                switch(u[0].integer.to!int) {
                    case 4: //new message
                        immutable string mbody = u[6].str.longpollReplaces;
                        dbm("longpoll message: " ~ mbody);
                        //todo toggle update condition
                        break;
                    case 80: //counter update
                        if(return80mc) {
                            ps.latestUnreadMsg = u[1].integer.to!int;
                        } else {
                            ps.lp80got = true;
                        }
                        toggleUpdate();
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
        //auto task = task!(this.startLongpoll)();
        //task.executeInNewThread();
        spawn(&asyncLongpollWrapper, this.exportStruct());
    }

}

// ===== async =====

private void asyncLongpollWrapper(apiTransfer apist) {
    auto api = new VKapi(apist);
    api.startLongpoll();
}

class loadBlockThread : Thread {

    apiTransfer apist;
    blockType bt;
    int count;
    int offset;

    this() {
        super(&asyncLoadBlock);
    }

    void setParams(apiTransfer apist, blockType bt, int count, int offset) {
        this.apist = apist;
        this.bt = bt;
        this.count = count;
        this.offset = offset;
    }

    private void asyncLoadBlock() {
        auto api = new VKapi(apist);
        switch (bt) {
            case blockType.dialogs:
                int sc;
                pb.dialogsBuffer ~= api.messagesGetDialogs(count, offset, sc);
                pb.dialogsCount = sc;
                pb.dialogsUpdated = true;
                break;
            default: break;
        }
        api.toggleUpdate();
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