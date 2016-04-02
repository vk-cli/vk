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
            me = usersGet();
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
        void delegate() dg;
    }

    private
        Task[] order;
        Mutex orderAccess;

    this() {
        orderAccess = new Mutex();
        super(&procOrder);
    }

    void addToOrder(void delegate() d) {
        synchronized(orderAccess) {
            order ~= Task(d);
        }
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
        S_SELF_RESOLVE = "s_self_resolve";

    AsyncOrder[string] orders;
    AsyncSingle[string] singles;

    void orderedAsync(string orderkey, void delegate() d) {
        auto so = orderkey in orders;
        if(!so) {
            orders[orderkey] = new AsyncOrder();
            so = orderkey in orders;
        }

        so.addToOrder(d);
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

    __gshared {
        VkApi api;
        vkUser* me;
        AsyncMan a;

        BlockFactory!ClDialog dialogsFactory;
        BlockFactory!ClFriend friendsFactory;
        BlockFactory!ClAudio musicFactory;
    }

    this(string token) {
        a = new AsyncMan();
        api = new VkApi(token);
        baseInit();
        //a.singleAsync(a.S_SELF_RESOLVE, () => accountInit());
        accountInit();
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

        dialogsFactory = ClDialog.makeFactory(api);
        friendsFactory = ClFriend.makeFactory(api);
        musicFactory = ClAudio.makeFactory(api);
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
        //return pb.chatBuffer[peer].data.serverCount;
        return -1;
    }

    int getChatLineCount(int peer) {
        //return pb.chatBuffer[peer].data.linesCount;
        return -1;
    }

    string getLastLongpollMessage() {
        auto last = ps.lastlp;
        ps.lastlp = "";
        return last;
    }

    vkFriend[] getBufferedFriends(int count, int offset) {return [];}

    vkAudio[] getBufferedMusic(int count, int offset) {return [];}

    vkDialog[] getBufferedDialogs(int count, int offset) {
        dialogsFactory.setOffset(offset);
        return dialogsFactory
                .map!(q => q.getBlock())
                .joiner
                .drop(dialogsFactory.getReloffset)
                .take(count)
                .map!(q => q.getObject)
                .array;
    }

    vkMessageLine[] getBufferedChatLines(int count, int offset, int peer, int wrapwidth) {return [];}

    int messagesCounter() {return 0;}

    void asyncSendMessage(int peer, string msg) {}

    void setTypingStatus(int peer) {}

}

// ===== Model =====

abstract class ClObject {}

class Block(T : ClObject) {

    alias downloader = T[] delegate(uint, uint, out ldFuncResult);

    private {
        uint
            ordernum,
            blocksz;
        bool filled;
        T[] block;
        downloader ldfunc;
        factoryData* fdata;
    }

    this(uint ord, uint blocksize, downloader ld, factoryData* fdt, bool filledblk = false) {
        ordernum = ord;
        blocksz = blocksize;
        ldfunc = ld;
        fdata = fdt;
        filled = filledblk;
    }

    T[] getBlock() {
        if(!filled) {
            ldFuncResult res;
            block = ldfunc(blocksz, blocksz*ordernum, res); //todo async
            if(res.success) {
                filled = true;
                fdata.serverCount = res.servercount;
            }
        }
        return block;
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
            offset,
            start,
            iter,
            reloffset,
            blocksz;
        Block!T[uint] blockst;
        downloader ldfunc;
    }

    factoryData data;

    enum bool empty = false;

    this(uint blocksize, downloader ld) {
        assert(blocksize != 0);
        blocksz = blocksize;
        offset = 0;
        rebuildOffsets();
        ldfunc = ld;
        data = factoryData();
    }

    private void rebuildOffsets() {
        reloffset = offset % blocksz;
        start = (offset-reloffset) / blocksz;
        iter = start;
    }

    private Block!T getblk(uint i) {
        bool doneload;
        immutable auto sc = data.serverCount;
        immutable auto ln = blockst.keys.length == 0 ? 0 : sort(blockst.keys).takeOne[0];
        if(sc != -1) {
            if(ln > 1 && ((ln-1)*blocksz)+blockst[ln-1].length >= sc) doneload = true;
            else if (ln == 1 && blockst[ln-1].length >= sc) doneload = true;
            else if (ln == 0 && sc == 0) doneload = true;
        }

        if(doneload && i > ln-1) {
            if(ln == 0) return new Block!T(0, 0, ldfunc, &data, true);
            return blockst[ln-1];
        }

        auto c = i in blockst;
        if(c) return *c;
        else {
            blockst[i] = new Block!T(i, blocksz, ldfunc, &data);
            return blockst[i];
        }
    }

    void setOffset(uint woffset) {
        offset = woffset;
        rebuildOffsets();
    }

    uint getReloffset() {
        return reloffset;
    }

    Block!T front() {
        return getblk(iter);
    }

    void popFront() {
        ++iter;
    }

}

ldFuncResult apiCheck(VkApi api) {
    return ldFuncResult(api.isTokenValid);
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

    static auto makeFactory(VkApi api) {
        return new BlockFactory!clt(defaultBlock, getLoadFunc(api));
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

    static auto makeFactory(VkApi api) {
        return new BlockFactory!clt(defaultBlock, getLoadFunc(api));
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

    static auto makeFactory(VkApi api) {
        return new BlockFactory!clt(defaultBlock, getLoadFunc(api));
    }

    private objt obj;

    this(objt o) {
        obj = o;
    }

    objt getObject() {
        return obj;
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
