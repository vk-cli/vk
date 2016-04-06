module vkapi;

import std.stdio, std.conv, std.string, std.regex, std.array, std.datetime, std.random, core.time;
import std.exception, core.exception;
import std.net.curl, std.uri, std.json;
import std.range, std.algorithm;
import std.parallelism, std.concurrency, core.thread, core.sync.mutex;
import utils, namecache, localization;



// ===== vkapi const =====

const int convStartId = 2000000000;
const int mailStartId = convStartId*-1;
const bool return80mc = true;
const long needNameMaxDelta = 180; //seconds, 3 min

const uint defaultBlock = 100;
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

struct vkAccountInit {
    int id;
    string
        first_name,
        last_name;
    uint
        c_messages,
        sc_dialogs,
        sc_friends,
        sc_audio;
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

struct apiState {
    bool lp80got = true;
    int latestUnreadMsg = 0;
    bool somethingUpdated = false;
    bool chatloading = false;
    string lastlp = "";
    uint countermsg;

    //sendOrderMsg[] order;
    //sentMsg[int] sent; //by rid
}

struct ldFuncResult {
    bool success;
    int servercount = -1;
}

struct factoryData {
    int serverCount = -1;
    bool forceUpdate;
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

struct apiFwdIter {
    vkFwdMessage[] fwd;
    int md;
}

__gshared {
    nameCache nc;
    apiState ps;
    Mutex
        sndMutex,
        pbMutex;
}


class VkApi {

    private const string vkurl = "https://api.vk.com/method/";
    const string vkver = "5.50";
    private string vktoken;
    bool isTokenValid;

    vkUser me;
    vkAccountInit initdata;

    this(string token) {
        vktoken = token;
    }

    void addMeNC() {
        nc.addToCache(me.id, cachedName(me.first_name, me.last_name));
    }

    void resolveMe() {
        isTokenValid = checkToken(vktoken);
    }

    private bool checkToken(string token) {
        if(token.length != 85) return false;
        try{
            initdata = executeAccountInit();
            me = vkUser(initdata.first_name, initdata.last_name, initdata.id);
        } catch (ApiErrorException e) {
            dbm("ApiErrorException: " ~ e.msg);
            return false;
        }
        return true;
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
        string got;

        bool htloop;
        while(!htloop) {
            try{
                got = AsyncMan.httpget(url, tm);
                htloop = true;
            } catch(InternalException e) {
                if(e.ecode == e.E_NETWORKFAIL) {
                    //todo notify networkfail
                    dbm(e.msg ~ " E_NETWORKFAIL");
                } else throw e;
            }
        }


        JSONValue resp;
        try{
            resp = got.parseJSON;
            //dbm("json: " ~ resp.toPrettyString);
        }
        catch(JSONException e) {
            throw new ApiErrorException(resp.toPrettyString(), 0);
        }

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

    vkAccountInit executeAccountInit() {
        string[string] params;
        auto resp = vkget("execute.accountInit", params);
        vkAccountInit rt = {
            id:resp["me"]["id"].integer.to!int,
            first_name:resp["me"]["first_name"].str,
            last_name:resp["me"]["last_name"].str,
            c_messages:resp["counters"]["messages"].integer.to!int,
            sc_dialogs:resp["sc"]["dialogs"].integer.to!int,
            sc_friends:resp["sc"]["friends"].integer.to!int,
            sc_audio:resp["sc"]["audio"].integer.to!int
        };
        return rt;
    }

    vkUser usersGet(int userId = 0, string fields = "", string nameCase = "nom") {
        string[string] params;
        if(userId != 0) params["user_ids"] = userId.to!string;
        if(fields != "") params["fields"] = fields;
        if(nameCase != "nom") params["name_case"] = nameCase;
        auto resp = vkget("users.get", params);

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

            auto mo = vkMessage();
            mo.outgoing = outg; mo.unread = unr; mo.utime = ut;
            mo.author_name = nc.getName(fid).strName;
            mo.time_str = st; mo.body_lines = mbody;
            mo.fwd_depth = fwdp; mo.fwd = fw; mo.needName = true;
            mo.msg_id = mid; mo.author_id = fid; mo.peer_id = pid;

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
}

class AsyncOrder : Thread {
    struct Task {
        int id;
        void delegate() dg;
    }

    private
        Task[] order;
        Mutex orderAccess;

    this() {
        orderAccess = new Mutex();
        super(&procOrder);
    }

    void addToOrder(void delegate() d, int ordid) {
        synchronized(orderAccess) {
            immutable auto has = order.map!(q => q.id).canFind(ordid);
            if(!has) order ~= Task(ordid, d);
        }
    }

    bool hasId(int ordid) {
        return order.map!(q => q.id).canFind(ordid);
    }

    private void procOrder() {
        while(true) {
            if(order.length != 0) {
                for (int i; i < order.length; ++i) {
                    try {
                        order[i].dg();
                    }
                    catch (Exception e) {
                        throw e;
                    }
                }
                synchronized(orderAccess) {
                    order = [];
                }
            }
        }
    }
}

class AsyncSingle : Thread {

    this() {
        super(&func);
    }

    private void delegate() dg;

    void startFunc(void delegate() d) {
        if(!this.isRunning) {
            dg = d;
            this.start();
        }
    }

    private void func() {
        try {
            if(dg) dg();
        }
        catch (Exception e) {
            throw e;
        }
    }

}

class AsyncMan {

    static string httpget(string addr, Duration timeout) {
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
                    return sz;
                };
                client.perform();
                ok = true;
                //dbm("recv content: " ~ content);
            } catch (CurlException e) {
                ++tries;
                dbm("[attempt " ~ (tries.to!string) ~ "] network error: " ~ e.msg);
                if(tries >= connectAttmepts) {
                    throw new InternalException(4, "E_NETWORKFAIL");
                    //notifyHttpFail();
                }
                Thread.sleep( dur!"msecs"(mssleepBeforeAttempt) );
            }
        }
        return content;
    }

    const string
        S_SELF_RESOLVE = "s_self_resolve",
        O_LOADBLOCK = "o_loadblock";

    AsyncOrder[string] orders;
    AsyncSingle[string] singles;

    void orderedAsync(string orderkey, int ordid, void delegate() d) {
        auto so = orderkey in orders;
        if(!so) {
            orders[orderkey] = new AsyncOrder();
            so = orderkey in orders;
        }

        so.addToOrder(d, ordid);
        if(!so.isRunning)
            so.start();
    }

    void singleAsync(string singlekey, void delegate() d) {
        auto ss = singlekey in singles;
        if(!ss) {
            singles[singlekey] = new AsyncSingle();
            ss = singlekey in singles;
        }

        ss.startFunc(d);
    }

    void parallelAsync(void delegate() d) {
        auto s = new AsyncSingle();
        s.startFunc(d);
    }

}

class VkMan {

    alias ChatBlockFactory = BlockFactory!ClMessage;

    __gshared {
        VkApi api;
        vkUser* me;
        AsyncMan a;

        BlockFactory!ClDialog dialogsFactory;
        BlockFactory!ClFriend friendsFactory;
        BlockFactory!ClAudio musicFactory;
        ChatBlockFactory[int] chatFactory; //by peer
    }

    this(string token) {
        a = new AsyncMan();
        api = new VkApi(token);
        baseInit();
        a.singleAsync(a.S_SELF_RESOLVE, () => accountInit());
        //accountInit();
    }

    private void accountInit() {
        nc = new nameCache(api);
        api.resolveMe();
        if(!api.isTokenValid) {
            //todo warn about token
            return;
        }

        api.addMeNC();
        me = &(api.me);

        dialogsFactory = ClDialog.makeFactory(api, a);
        friendsFactory = ClFriend.makeFactory(api, a);
        musicFactory = ClAudio.makeFactory(api, a);

        dialogsFactory.data.serverCount = api.initdata.sc_dialogs;
        friendsFactory.data.serverCount = api.initdata.sc_friends;
        musicFactory.data.serverCount = api.initdata.sc_audio;

        ps.countermsg = api.initdata.c_messages;

        toggleUpdate();
    }

    private void baseInit() {
        sndMutex = new Mutex();
        pbMutex = new Mutex();
        ps = apiState();
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

    private auto getData(blockType tp) {
        switch(tp){
            case blockType.dialogs: return &(dialogsFactory.data);
            case blockType.friends: return &(friendsFactory.data);
            case blockType.music: return &(musicFactory.data);
            default: assert(0);
        }
    }

    void toggleForeceUpdate(blockType tp) {
        getData(tp).forceUpdate = true;
    }

    void toggleChatForceUpdate(int peer) {
        //pb.chatBuffer[peer].data.forceUpdate = true;
    }

    int getServerCount(blockType tp) {
        return getData(tp).serverCount;
    }

    bool isScrollAllowed(blockType tp) {
        return true;
    }

    bool isChatScrollAllowed(int peer) {
        return true;
    }

    int getChatServerCount(int peer) {
        auto c = peer in chatFactory;
        if(c) return c.data.serverCount;
        else return -1;
    }

    int getChatLineCount(int peer, int ww) {
        auto c = peer in chatFactory;
        if(c) return (*c).getServerLineCount(ww);
        else return -1;
    }

    string getLastLongpollMessage() {
        auto last = ps.lastlp;
        ps.lastlp = "";
        return last;
    }

    vkFriend[] getBufferedFriends(int count, int offset) {
        return bufferedGet!vkFriend(friendsFactory, count, offset);
    }

    vkAudio[] getBufferedMusic(int count, int offset) {
        return bufferedGet!vkAudio(musicFactory, count, offset);
    }

    vkDialog[] getBufferedDialogs(int count, int offset) {
        return bufferedGet!vkDialog(dialogsFactory, count, offset);
    }

    vkMessageLine[] getBufferedChatLines(int count, int offset, int peer, int wrapwidth) {
        auto f = peer in chatFactory;
        if(!f) {
            chatFactory[peer] = ClMessage.makeFactory(api, a, peer);
            f = peer in chatFactory;
        }

        f.setOffset(0);
        if(!f.isReady) return [];

        return (*f)
                .map!(q => q.getBlock())
                .joinerBidirectional
                .retro
                .map!(q => q.getLines(wrapwidth))
                .joinerBidirectional
                .dropBack(offset)
                .takeBackArray(count);
    }

    int messagesCounter() {
        return ps.countermsg;
    }

    void asyncSendMessage(int peer, string msg) {}

    void setTypingStatus(int peer) {}

    R[] bufferedGet(R, T)(T factory, int count, int offset) {
        factory.setOffset(offset);
        if(!factory.isReady) return [];
        return factory
                .map!(q => q.getBlock())
                .joiner
                .drop(factory.getReloffset)
                .take(count)
                .map!(q => q.getObject)
                .array;
    }

}

// ===== Model =====

abstract class ClObject {}

class Block(T : ClObject) {

    alias downloader = T[] delegate(uint, uint, out ldFuncResult);
    alias objectType = T;

    private {
        uint
            ordernum,
            blocksz;
        int oid;
        bool filled;
        T[] block;
        downloader ldfunc;
        factoryData* fdata;
        AsyncMan a;
    }

    this(uint ord, uint blocksize, downloader ld, AsyncMan asyncm, factoryData* fdt, int woid, bool filledblk = false) {
        ordernum = ord;
        blocksz = blocksize;
        ldfunc = ld;
        fdata = fdt;
        filled = filledblk;
        oid = woid;
        a = asyncm;
    }

    T[] getBlock() {
        downloadBlock();
        return block;
    }

    void downloadBlock(bool force = false) {
        if(!filled || force) a.orderedAsync(a.O_LOADBLOCK, oid, () {
            ldFuncResult res;
            block = ldfunc(blocksz, blocksz*ordernum, res);
            if(res.success) {
                filled = true;
                fdata.serverCount = res.servercount;
            }
        });
    }

    bool isFilled() {
        return filled;
    }

    uint getBlocksize() {
        return blocksz;
    }

    uint length() {
        return block.length.to!uint;
    }
}

class BlockFactory(T : ClObject) {

    alias downloader = T[] delegate(uint, uint, out ldFuncResult);

    private {
        uint
            clastblk,
            offset,
            start,
            reloffset,
            blocksz;
        int
            oid,
            iter,
            backiter;
        Block!T[uint] blockst;
        downloader ldfunc;
        AsyncMan a;
        bool ffront = true;
    }

    factoryData data;

    this(uint blocksize, int woid, AsyncMan asyncm, downloader ld) {
        assert(blocksize != 0);
        blocksz = blocksize;
        offset = 0;
        rebuildOffsets();
        ldfunc = ld;
        data = factoryData();
        //oid = woid;
        oid = genId();
        a = asyncm;
    }

    private void rebuildOffsets() {
        reloffset = offset % blocksz;
        start = (offset-reloffset) / blocksz;
        iter = start;
        clastblk = getlastblk();
        backiter = clastblk;
    }

    private Block!T getblk(uint i) {
        auto c = i in blockst;
        if(c) return *c;
        else {
            blockst[i] = new Block!T(i, blocksz, ldfunc, a, &data, oid);
            return blockst[i];
        }
    }

    uint objectCount() {
        return blockst.values.map!(q => q.length).sum();
    }

    auto getLoadedBlocks() {
        return blockst.keys.map!(q => q in blockst).filter!(q => q.isFilled);
    }

    bool isReady() {
        auto zeroblk = getblk(0);
        if(!zeroblk.isFilled || data.serverCount == -1) {
            zeroblk.downloadBlock();
            return false;
        }
        if(backiter < 0) {
            return false;
        }
        return true;
    }

    private int getlastblk() {
        auto sc = data.serverCount;
        if(sc == -1) return -1;

        immutable auto lastsz = sc % blocksz;
        auto lastblk = ((sc - lastsz) / blocksz) - 1;
        if(lastsz > 0) ++lastblk;

        return lastblk;
    }

    private void downloadBlock(int i) {
        if(i <= clastblk && i >= 0) getblk(i).downloadBlock();
    }

    bool empty() {
        return iter > backiter;
    }

    void setOffset(uint woffset) {
        offset = woffset;
        rebuildOffsets();
    }

    uint getReloffset() {
        return reloffset;
    }

    Block!T front() {
        auto rtblock = getblk(iter);
        if(iter == 0) {
            downloadBlock(1);
        }
        return rtblock;
    }

    void popFront() {
        ++iter;
        downloadBlock(iter + 1);
    }

    Block!T back() {
        auto rtblock = getblk(backiter);
        if(backiter == clastblk) {
            downloadBlock(clastblk - 1);
        }
        return rtblock;
    }

    void popBack() {
        --backiter;
        downloadBlock(backiter-1);
    }

    Block!T moveBack() {
        return back();
    }

    typeof(this) save() {
        return this;
    }

    // ===== special magic =====

    //pragma(msg, "T: " ~ T.stringof ~ ", equals ClMessage: " ~ is(T == ClMessage).stringof);

    static if (is(T == ClMessage)) {
        private int serverLineCount = -1;

        int getServerLineCount(int ww) {
            if(serverLineCount == -1 && objectCount == data.serverCount) {
                serverLineCount = blockst.values
                                    .map!(q => q.getBlock())
                                    .joiner
                                    .map!(q => q.getLineCount(ww))
                                    .sum.to!int;
            }
            return serverLineCount;
        }

    }

}

ldFuncResult apiCheck(VkApi api) {
    return ldFuncResult(api.isTokenValid);
}

const uint maxuint = 4_294_967_295;
const uint maxint = 2_147_483_647;
const uint ridstart = 1;

int genId() {
    long rnd = uniform(ridstart, maxuint);
    if(rnd > maxint) {
        rnd = -(rnd-maxint);
    }
    dbm("rid: " ~ rnd.to!string);
    return rnd.to!int;
}

// ===== Implement objects =====

class ClDialog : ClObject {

    alias objt = vkDialog;
    alias clt = typeof(this);

    static auto getLoadFunc(VkApi api) {
        return (uint c, uint o, out ldFuncResult r) {
            r = apiCheck(api);
            if(!r.success) return new clt[0];
            return api.messagesGetDialogs(c, o, r.servercount).map!(q => new clt(q)).array;
        };
    }

    static auto makeFactory(VkApi api, AsyncMan a) {
        return new BlockFactory!clt(defaultBlock, 1, a, getLoadFunc(api));
    }

    private objt obj;

    this(objt o) {
        obj = o;
    }

    objt getObject() {
        return obj;
    }
}

class ClFriend : ClObject {

    alias objt = vkFriend;
    alias clt = typeof(this);

    static auto getLoadFunc(VkApi api) {
        return (uint c, uint o, out ldFuncResult r) {
            r = apiCheck(api);
            if(!r.success) return new clt[0];
            return api.friendsGet(c, o, r.servercount).map!(q => new clt(q)).array;
        };
    }

    static auto makeFactory(VkApi api, AsyncMan a) {
        return new BlockFactory!clt(defaultBlock, 2, a, getLoadFunc(api));
    }

    private objt obj;

    this(objt o) {
        obj = o;
    }

    objt getObject() {
        return obj;
    }
}

class ClAudio : ClObject {

    alias objt = vkAudio;
    alias clt = typeof(this);

    static auto getLoadFunc(VkApi api) {
        return (uint c, uint o, out ldFuncResult r) {
            r = apiCheck(api);
            if(!r.success) return new clt[0];
            return api.audioGet(c, o, r.servercount).map!(q => new clt(q)).array;
        };
    }

    static auto makeFactory(VkApi api, AsyncMan a) {
        return new BlockFactory!clt(defaultBlock, 3, a, getLoadFunc(api));
    }

    private objt obj;

    this(objt o) {
        obj = o;
    }

    objt getObject() {
        return obj;
    }
}

class ClMessage : ClObject {

    alias objt = vkMessage;
    alias clt = typeof(this);

    static auto getLoadFunc(VkApi api, int peer) {
        return (uint c, uint o, out ldFuncResult r) {
            r = apiCheck(api);
            if(!r.success) return new clt[0];
            return api.messagesGetHistory(peer, c, o, r.servercount).map!(q => new clt(q)).array;
        };
    }

    static auto makeFactory(VkApi api, AsyncMan a, int peer) {
        return new BlockFactory!clt(defaultBlock, 4, a, getLoadFunc(api, peer));
    }

    private {
        objt obj;
        vkMessageLine[] lines;
        int lastww;
    }

    this(objt o) {
        obj = o;
    }

    objt getObject() {
        return obj;
    }

    ulong getLineCount(int ww) {
        fillLines(ww);
        return lines.length;
    }

    vkMessageLine[] getLines(int ww) {
        fillLines(ww);
        return lines;
    }

    private void fillLines(int ww) {
        if(lines.length == 0 || lastww != ww) {
            lastww = ww;
            lines = convertMessage(obj, ww);
        }
    }

    vkMessageLine lspacing = {
        text: "", isSpacing: true
    };

    const int wwmultiplier = 3;

    private vkMessageLine[] convertMessage(ref vkMessage inp, int ww) {
        immutable bool zombie = inp.isZombie || inp.msg_id < 1;

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

        return rt;
    }

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

            vkMessageLine fwdspc;
            fwdspc.isFwd = true; fwdspc.isSpacing = true;
            fwdspc.fwdDepth = depth;
            rt ~= fwdspc;

            if(fm.fwd.length != 0) {
                rt ~= renderFwd(fm.fwd, depth, ww);
                rt ~= fwdspc;
            }

        }
        return rt;
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

class InternalException : Exception {
    public {

        const int E_NETWORKFAIL = 4;

        string msg;
        int ecode;
        @safe pure nothrow this(int error,
                                string appmsg = "",
                                string file =__FILE__,
                                size_t line = __LINE__,
                                Throwable next = null) {
            msg = "client failed - unresolved internal exception: err" ~ error.to!string ~ " " ~ appmsg;
            ecode = error;
            super(msg, file, line, next);
        }
    }
}

void debugThrow() {
    throw new InternalException(228, "DEBUGPOINT");
}
