/*
Copyright 2016 HaCk3D, substanceof

https://github.com/HaCk3Dq
https://github.com/substanceof

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

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
const int longpollGimStartId = 1000000000;
const bool return80mc = true;
const long needNameMaxDelta = 180; //seconds, 3 min
const int typingTimeout = 4;

const uint defaultBlock = 100;
const int chatBlock = 100;
const int chatUpd = 50;

// ===== networking const =====

const int connectionAttempts = 10;
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
    int unreadCount;
    bool unread = false;
    bool outbox;
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
    long rndid;
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
    long last_seen_utime;
    string last_seen_str;
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
    bool somethingUpdated;
    bool chatloading;
    bool showConvNotifies;
    int loadingiter = 0;
    string lastlp = "";
    uint countermsg = -1;
    sentMsg[long] sent; //by rid
    bool[int] unreadCountReview; //by peer
}

struct ldFuncResult {
    bool success;
    int servercount = -1;
}

struct factoryData {
    int serverCount = -1;
    bool forceUpdate;
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
    failed
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


struct vkgetparams {
    bool setloading = true;
    int attempts = connectionAttempts;
    bool thrownf = false;
    bool notifynf = true;
}

class VkApi {

    private const string vkurl = "https://api.vk.com/method/";
    const string vkver = "5.50";
    private string vktoken;
    bool isTokenValid;

    vkUser me;
    vkAccountInit initdata;

    alias nfnotifyfn = void delegate();
    nfnotifyfn connectionProblems;

    this(string token, nfnotifyfn nfnotify) {
        vktoken = token;
        connectionProblems = nfnotify;
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

    JSONValue vkget(string meth, string[string] params, bool dontRemoveResponse = false, vkgetparams gp = vkgetparams()) {
        if(gp.setloading) {
            enterLoading();
        }
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
                got = AsyncMan.httpget(url, tm, gp.attempts);
                htloop = true;
            } catch(NetworkException e) {
                dbm(e.msg);
                if(gp.notifynf) connectionProblems();
                if(gp.thrownf) throw e;

                if(gp.notifynf) {
                    //dbm("vkget waits for api init..");
                    do {
                        Thread.sleep(dur!"msecs"(300));
                    } while(!isTokenValid);
                    //dbm("resume vkget");
                }
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

        if(gp.setloading) leaveLoading();
        return rmresp ? resp["response"] : resp;
    }

    // ===== API method wrappers =====

    vkAccountInit executeAccountInit() {
        string[string] params;
        vkgetparams gp = {notifynf: false};
        auto resp = vkget("execute.accountInit", params, false, gp);
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
        params["fields"] = fields != "" ? fields : "online";
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
        params["fields"] = fields != "" ? fields : "online";
        if(nameCase != "nom") params["name_case"] = nameCase;
        auto resp = vkget("users.get", params).array;

        vkUser[] rt;
        foreach(t; resp){
            vkUser rti = {
                id:t["id"].integer.to!int,
                first_name:t["first_name"].str,
                last_name:t["last_name"].str
            };
            if("online" in t) rti.online = t["online"].integer == 1;
            rt ~= rti;
        }
        return rt;
    }

    void setActivityStatusImpl(int peer, string type) {
        vkgetparams gp = {
            setloading: false,
            attempts: 1,
            thrownf: true,
            notifynf: false
        };
        try{
            vkget("messages.setActivity", [ "peer_id": peer.to!string, "type": type ], false, gp);
        } catch (Exception e) {
            dbm("catched at setTypingStatus: " ~ e.msg);
        }
    }

    void accountSetOnline() {
        vkgetparams gp = {
            setloading: false,
            attempts: 10,
            thrownf: true,
            notifynf: false
        };
        string[string] emptyparam;
        try{
            vkget("account.setOnline ", emptyparam, false, gp);
        } catch (Exception e) {
            dbm("catched at accountSetOnline: " ~ e.msg);
        }
    }

    void accountSetOffline() {
        vkgetparams gp = {
            setloading: false,
            attempts: 10,
            thrownf: false,
            notifynf: false
        };
        try{
            vkget("account.setOffline ", [ "voip": "0" ], false, gp);
        } catch (Exception e) {
            dbm("catched at accountSetOnline: " ~ e.msg);
        }
    }

    vkDialog[] messagesGetDialogs(int count , int offset, out int serverCount) {
        auto exresp = vkget("execute.vkGetDialogs", [ "count": count.to!string, "offset": offset.to!string ]);
        auto resp = exresp["conv"];
        auto dcount = resp["count"].integer.to!int;
        dbm("dialogs count now: " ~ dcount.to!string);
        auto respt_items = resp["items"].array;
        auto respt = respt_items.map!(q => q["message"]);

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
        foreach(ditem; respt_items){
            auto msg = ditem["message"];
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
            if("unread" in ditem) ds.unreadCount = ditem["unread"].integer.to!int;
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
        int u = ps.countermsg;
        if(ps.lp80got) {
            u = accountGetCounters("messages").messages;
            ps.countermsg = u;
            ps.lp80got = false;
        }
        return u;
    }

    vkFriend[] friendsGet(int count, int offset, out int serverCount, int user_id = 0) {
        auto params = [ "fields": "online,last_seen", "order": "hints"];
        if(user_id != 0) params["user_id"] = user_id.to!string;
        if(count != 0) params["count"] = count.to!string;
        if(offset != 0) params["offset"] = offset.to!string;

        auto resp = vkget("friends.get", params);
        serverCount = resp["count"].integer.to!int;

        auto ct = Clock.currTime();
        vkFriend[] rt;

        foreach(f; resp["items"].array) {
            auto last = f["last_seen"]["time"].integer.to!long;
            auto laststr = agotime(ct, last);

            vkFriend friend = {
              first_name: f["first_name"].str,
              last_name: f["last_name"].str,
              id: f["id"].integer.to!int,
              online: ( f["online"].integer.to!int == 1 ? true : false ),
              last_seen_utime: last,  last_seen_str: laststr
            };

            rt ~= friend;
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
            long rid = ("random_id" in m) ? m["random_id"].integer.to!long : 0;
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
            mo.rndid = rid;

            rt ~= mo;
            ++i;
        }
        resolveFwdNames(rt);
        return rt;
    }

    vkMessage[] messagesGetHistory(int peer_id, int count, int offset, out int servercount, out int unreadcount, int start_message_id = -1, bool rev = false) {
        auto ct = Clock.currTime();
        auto params = [ "peer_id": peer_id.to!string ];
        if(count >= 0) params["count"] = count.to!string;
        if(offset != 0) params["offset"] = offset.to!string;
        if(start_message_id > 0) params["start_message_id"] = start_message_id.to!string;
        if(rev) params["rev"] = "1";

        auto resp = vkget("messages.getHistory", params);
        auto items = resp["items"].array;
        auto respuc = "unread" in resp;

        servercount = resp["count"].integer.to!int;
        unreadcount = respuc ? respuc.integer.to!int : 0;

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

    static string httpget(string addr, Duration timeout, uint attempts) {
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
                if(tries >= attempts) {
                    throw new NetworkException("httpget");
                }
                Thread.sleep( dur!"msecs"(mssleepBeforeAttempt) );
            }
        }
        return content;
    }

    const string
        S_SELF_RESOLVE = "s_self_resolve",
        S_ONLINE_STATUS = "s_online_status",
        S_TYPING = "s_typing_",
        O_LOADBLOCK = "o_loadblock",
        O_SENDMSG = "o_sendm";

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

}


class Longpoll : Thread {

    private {
        VkMan man;
        VkApi api;
    }

    this(VkMan vkman) {
        man = vkman;
        api = man.api;
        super(&startSync);
    }

    void startSync() {
        if(!api.isTokenValid) {
            dbm("longpoll is waiting for api init...");
            while(!api.isTokenValid) {
                Thread.sleep(dur!"msecs"(300));
            }
        }
        dbm("longpoll is starting...");
        while(true) {
            try {
                doLongpoll(getLongpollServer());
            }
            catch (InternalException e) {
                if(e.ecode == e.E_LPRESTART) {
                    dbm("Network error in longpoll, lp shutdown");
                    man.asyncAccountInit();
                    return;
                }
                else {
                    dbm("longpoll InternalException: " ~ e.msg);
                }
            }
            catch(Exception e) {
                dbm("longpoll exception: " ~ e.msg);
            }
            dbm("longpoll is restarting...");
        }
    }


    vkLongpoll getLongpollServer() {
        auto resp = api.vkget("messages.getLongPollServer", [ "use_ssl": "1", "need_pts": "1" ]);
        dbm("longpoll server: \n" ~ resp.toPrettyString() ~ "\n");
        vkLongpoll rt = {
            server: resp["server"].str,
            key: resp["key"].str,
            ts: resp["ts"].integer.to!int
        };
        return rt;
    }


    const bool longpollRethrow = true;

    void doLongpoll(vkLongpoll start) {
        auto tm = dur!timeoutFormat(longpollCurlTimeout);
        int cts = start.ts;
        auto mode = (2 + 128).to!string; //attaches + random_id
        bool ok = true;
        dbm("longpoll works");
        while(ok) {
            try {
                if(cts < 1) break;
                string url = "https://" ~ start.server ~ "?act=a_check&key=" ~ start.key ~ "&ts=" ~ cts.to!string
                                                                                            ~ "&wait=25&mode=" ~ mode;
                auto resp = AsyncMan.httpget(url, tm, 0);
                immutable auto next = parseLongpoll(resp);
                if(next.failed == 2 || next.failed == 3) ok = false; //get new server
                cts = next.ts;

            }
            catch(NetworkException e) {
                throw new InternalException(InternalException.E_LPRESTART);
            }
        }
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
                            ps.countermsg = u[1].integer.to!int;
                        } else {
                            ps.lp80got = true;
                        }
                        man.toggleUpdate();
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
        resolveMidOrder();
        rt.ts = ts;
        rt.failed = failed;
        return rt;
    }

    alias processnmFunc = void delegate(vkMessage);

    processnmFunc[int] midResolveOrder;

    void resolveMidOrder() {
        if(midResolveOrder.length == 0) return;
        api.messagesGetById(midResolveOrder.keys)
                    .each!(q => midResolveOrder[q.msg_id](q));
        midResolveOrder.clear();
        man.toggleUpdate();
    }

    void triggerNewMessage(JSONValue ui, SysTime ct) {
        auto u = ui.array;

        auto mid = u[1].integer.to!int;
        auto flags = u[2].integer.to!int;
        auto peer = u[3].integer.to!int;
        auto utime = u[4].integer.to!long;
        auto msg = u[6].str.longpollReplaces;
        auto att = u[7];
        long rndid = (u.length > 8) ? u[8].integer.to!long : 0;

        bool outbox = (flags & 2) == 2;
        bool unread = (flags & 1) == 1;
        bool hasattaches = att.object.keys.map!(a => (a == "fwd") || a.matchAll(r"attach.*")).any!"a";

        auto conv = (peer > convStartId);
        bool group = false;

        if(!conv && peer > longpollGimStartId) {
            peer = -(peer - longpollGimStartId);
            group = true;
        }

        auto from = conv ? att["from"].str.to!int : ( outbox ? api.me.id : peer );

        auto title = conv ? u[5].str : nc.getName(peer).strName;
        auto haspeer = (peer in man.chatFactory);

        if(!haspeer) {
            man.chatFactory[peer] = man.generateBF!ClMessage(ClMessage.getLoadFunc(peer, (u) => man.setUnreads(peer, u)));
            man.chatFactory[peer].data.forceUpdate = true;
        }

        auto cf = man.chatFactory[peer];

        auto processnm = delegate (vkMessage nmsg) {
            dbm("processnm");
            auto rid = nmsg.rndid;
            auto realmsg = cf.getLoadedObjects
                                        .filter!(q => !q.getObject.isZombie)
                                        .takeOne();
            if(!realmsg.empty) {
                auto lastm = realmsg.front.getObject;
                nmsg.needName = !(lastm.author_id == from && (utime-lastm.utime) <= needNameMaxDelta);
            }

            auto sent = rid in ps.sent;
            if(sent) {
                dbm("approved sent nm rid: " ~ rid.to!string);
                cf.removeZombie(rid);
                ps.sent.remove(rid);
            }
            cf.addBack(new ClMessage(nmsg));
            if(!outbox && unread) cf.unreadCount += 1;
        };

        auto df = man.dialogsFactory;

        if(!df.isOverrided(peer)) {
            auto blockdlg = df.getLoadedObjects
                                .filter!(q => q.getPeer == peer)
                                .takeOne;
            auto uc = blockdlg.empty ? 0 : blockdlg.front.getObject.unreadCount;
            df.overrideDialog(new ClDialog(title, peer, uc, cf), ct.toUnixTime);
        }
        else df.overrideBump(peer, ct.toUnixTime);

        if(!hasattaches) {
            vkMessage lpnm = {
                author_id: from, peer_id: peer, msg_id: mid,
                outgoing: outbox, unread: unread, rndid: rndid,
                utime: utime, time_str: vktime(ct, utime),
                author_name: nc.getName(from).strName,
                body_lines: msg.split("\n"),
                fwd_depth: -1, needName: true
            };
            processnm(lpnm);
        } else {
            midResolveOrder[mid] = processnm;
        }

        if(from != api.me.id && ( ps.showConvNotifies ? true : !conv )) ps.lastlp = title ~ ": " ~ msg;
        man.toggleUpdate();
    }

    void triggerRead(JSONValue u) {
        bool inboxrd = (u[0].integer == 6);
        auto peer = u[1].integer.to!int;
        auto mid = u[2].integer.to!int;

        if(peer > longpollGimStartId && peer < convStartId) {
            peer = -(peer-longpollGimStartId);
        }

        dbm("rd trigger peer: " ~ peer.to!string ~ ", mid: " ~ mid.to!string ~ ", inbox: " ~ inboxrd.to!string);

        synchronized(pbMutex) {
            auto ch = peer in man.chatFactory;
            int unreadc;

            if(ch) {
                unreadc = ch.unreadCount;
                auto chl = ch.getLoadedObjects;
                chl
                  .map!(q => q.getObject.msg_id == mid)
                  .countUntil(true);


                while( !chl.empty && ( (chl.front !is null && chl.front.getObject.outgoing != inboxrd) ? chl.front.getObject.unread : true) ) {
                    auto mobj = chl.front.getObject;
                    if(mobj.outgoing != inboxrd) {
                        mobj.unread = false;
                        if(inboxrd) --unreadc;
                        chl.front.invalidateLineCache();
                    }
                    chl.popFront();
                }
                ch.unreadCount = unreadc < 0 ? 0 : unreadc;
            }
            else {
                auto dlone = man.dialogsFactory.getLoadedObjects
                    .map!(q => q.getObject)
                    .filter!(q => q.id == peer)
                    .takeOne();
                auto hasdlone = !dlone.empty;
                if(hasdlone) {
                   if(mid == dlone.front.lastmid) {
                        dlone.front.unreadCount = 0;
                        dlone.front.unread = false;
                   }
                }
            }

        }

        man.toggleUpdate();
    }

    void triggerOnline(JSONValue u) {
        auto uid = u[1].integer.to!int * -1;
        auto flags = u[2].integer.to!int;
        auto event = u[0].integer.to!int;
        bool exit = (event == 9);
        if(!exit && event != 8) return;

        if(exit) nc.setOnline(uid, false);
        else nc.setOnline(uid, true);

        man.toggleUpdate();
    }

}

class OnlineNotifier : Thread {

    private {
        bool enabled = false;
        VkApi api;
        AsyncMan a;
        const int retryMin = 14;
    }

    this(VkApi wapi, AsyncMan wa) {
        api = wapi;
        a = wa;
        super(&onlineRoutine);
    }

    void tryStart() {
        if(!this.isRunning) this.start();
        else dbm("onlineNotifier running already");
    }

    void setOnlineSw(bool sw) {
        enabled = sw;
        if(sw) {
            dbm("starting onlineNotifier...");
            tryStart();
        }
        else {
            a.singleAsync(a.S_ONLINE_STATUS, () => api.accountSetOffline());
            dbm("offline status sent (shed)");
            dbm("sheduled onlineNotifier shutdown");
        }
    }

    private void onlineRoutine() {
        while(true) {
            if(enabled) {
                api.accountSetOnline();
                dbm("online status sent");
                Thread.sleep( dur!"minutes"(retryMin) );
            }
            else {
                dbm("onlineNotifier shutdown");
            }
        }
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

        Longpoll longpollThread;
        OnlineNotifier onlineThread;
    }

    this(string token) {
        a = new AsyncMan();
        api = new VkApi(token, &connectionProblems);
        baseInit();
        asyncAccountInit();
    }

    private void accountInit() {
        api.isTokenValid = false;
        ps.countermsg = -1;
        asyncLongpoll();

        nc = new nameCache(api);
        api.resolveMe();
        if(!api.isTokenValid) {
            //todo warn about token
            return;
        }

        api.addMeNC();
        me = &(api.me);

        dialogsFactory.data.serverCount = api.initdata.sc_dialogs;
        friendsFactory.data.serverCount = api.initdata.sc_friends;
        musicFactory.data.serverCount = api.initdata.sc_audio;

        ps.countermsg = api.initdata.c_messages;

        toggleUpdate();
    }

    private void connectionProblems() {
        //asyncAccountInit();
    }

    void asyncAccountInit() {
        a.singleAsync(a.S_SELF_RESOLVE, () => accountInit());
    }

    BlockFactory!T generateBF(T)(T[] delegate(VkApi, uint, uint, out int) ld, uint dwblock = defaultBlock) {
        return new BlockFactory!T(
            new BlockObjectParameters!T(api, dwblock, a, ld, &notifyBlockDownloadDone));
    }

    private void baseInit() {
        sndMutex = new Mutex();
        pbMutex = new Mutex();
        ps = apiState();

        longpollThread = new Longpoll(this);
        onlineThread = new OnlineNotifier(api, a);

        dialogsFactory = generateBF!ClDialog(ClDialog.getLoadFunc());
        friendsFactory = generateBF!ClFriend(ClFriend.getLoadFunc());
        musicFactory = generateBF!ClAudio(ClAudio.getLoadFunc());
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

    void asyncLongpoll() {
        longpollThread.start();
    }

    void toggleForceUpdate(blockType tp) {
        getData(tp).forceUpdate = true;
        toggleUpdate();
    }

    void toggleChatForceUpdate(int peer) {
        chatFactory[peer].data.forceUpdate = true;
        toggleUpdate();
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

    bool isLoading() {
        return ps.loadingiter != 0;
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

    void notifyBlockDownloadDone() {
        toggleUpdate();
    }

    void sendOnline(bool state) {
        onlineThread.setOnlineSw(state);
    }

    void showConvNotifications(bool state) {
        ps.showConvNotifies = state;
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

    void setUnreads(int peer, int uc) {
        auto cf = peer in chatFactory;
        if(cf) {
            cf.unreadCount = uc;
        }
    }

    vkMessageLine[] getBufferedChatLines(int count, int offset, int peer, int wrapwidth) {
        if(offset < 0) offset = 0;
        auto f = peer in chatFactory;
        if(!f) {
            chatFactory[peer] = generateBF!ClMessage(ClMessage.getLoadFunc(peer, (u) => setUnreads(peer, u)));
            f = peer in chatFactory;
            auto blockdlg = dialogsFactory.getLoadedObjects
                                .filter!(q => q.getPeer == peer)
                                .takeOne;
            auto uc = blockdlg.empty ? 0 : blockdlg.front.getObject.unreadCount;
        }

        /*dbm("bfcl p: " ~ peer.to!string ~ ", o: " ~ offset.to!string ~ ", c: " ~ count.to!string
                                ~ ", sc: " ~ f.getServerLineCount(wrapwidth).to!string ~ " sco: "
                                ~ f.data.serverCount.to!string);*/

        synchronized(pbMutex) {
            if(!f.prepare) return [];
            f.seek(0);

            auto rt = (*f)
                    .filter!(q => q !is null)
                    .inputRetro
                    .map!(q => q.getLines(wrapwidth))
                    .joinerBidirectional
                    .dropBack(offset)
                    .takeBackArray(count);

            return rt;
        }
    }

    int messagesCounter() {
        return ps.countermsg;
    }

    private void sendMessageImpl(int rid, int peer, string msg) {
        auto sentmid = api.messagesSend(peer, msg, rid);
        dbm("message sent mid: " ~ sentmid.to!string ~ " rid: " ~ rid.to!string);
    }

    void asyncSendMessage(int peer, string msg) {
        auto rid = genId();
        auto aid = me.id;
        vkMessage zombie = {
            author_name: me.first_name ~ " " ~ me.last_name,
            author_id: aid, isZombie: true,
            body_lines: msg.split("\n"),
            time_str: getLocal("sending"),
            rndid: rid, msg_id: -1, outgoing: true, unread: true,
            peer_id: peer, utime: 1,
            needName: true, nmresolved: true
        };

        synchronized(pbMutex) {
            auto ch = peer in chatFactory;
            if(ch) {
                ch.addZombie(zombie);
            }
        }

        toggleUpdate();

        synchronized(sndMutex) {
            ps.sent[rid] = sentMsg(rid, peer, aid);
        }

        a.orderedAsync(a.O_SENDMSG, rid, () => sendMessageImpl(rid, peer, msg));
    }

    void setTypingStatus(int peer) {
        auto thrid = a.S_TYPING ~ peer.to!string;
        a.singleAsync(thrid, () {
            api.setActivityStatusImpl(peer, "typing");
            Thread.sleep(dur!"seconds"(typingTimeout));
        });
    }

    R[] bufferedGet(R, T)(T factory, int count, int offset) {
        synchronized(pbMutex) {
            if(!factory.prepare) return [];
            factory.seek(offset);
            return factory
                    .filter!(q => q !is null)
                    .take(count)
                    .map!(q => *(q.getObject))
                    .array;
        }
    }

}

// ===== Model =====

abstract class ClObject(T) {

    private {
        private T obj;
    }

    bool ignored = false;

    this(T o) {
        obj = o;
    }

    T* getObject() {
        return &obj;
    }

}

class Block(T) {

    alias objectType = T;
    alias paramsType = BlockObjectParameters!T;

    private {
        uint
            ordernum,
            blocksz;
        int oid;
        bool filled;
        factoryData* fdata;
        paramsType params;
        AsyncMan a;
    }

    T[] block;

    this(uint ord, paramsType objparams, factoryData* fdt, int woid, bool filledblk = false) {
        params = objparams;
        a = params.asyncMan;
        blocksz = params.blockSize;
        ordernum = ord;
        fdata = fdt;
        filled = filledblk;
        oid = woid;
    }

    T[] getBlock() {
        downloadBlock();
        return block;
    }

    void downloadBlock(bool force = false) {
        if(!filled || force) a.orderedAsync(a.O_LOADBLOCK, oid, () {
            ldFuncResult res;
            block = params.downloadBlock(blocksz, blocksz*ordernum, res);
            if(res.success) {
                filled = true;
                fdata.serverCount = res.servercount;
                params.downloadNotify();
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

    void addBack(T obj) {
        block = obj ~ block;
    }

    void addFront(T obj) {
        block ~= obj;
    }
}

class BlockObjectParameters(O) {

    alias downloader = O[] delegate(VkApi, uint, uint, out int);
    alias loadnotify = void delegate();

    downloader loadFunc;
    loadnotify loadNotifyFunc;
    AsyncMan asyncMan;
    uint blockSize;

    private {
        VkApi api;
    }

    this(VkApi vkapi, uint blocksize, AsyncMan asyncm, downloader ld, loadnotify ldn) {
        assert(blocksize != 0);
        loadFunc = ld;
        loadNotifyFunc = ldn;
        asyncMan = asyncm;
        blockSize = blocksize;
        api = vkapi;
    }

    O[] downloadBlock(uint c, uint o, out ldFuncResult r) {
        r = apiCheck(api);
        if(!r.success) return new O[0];
        return loadFunc(api, c, o, r.servercount);
    }

    void downloadNotify() {
        loadNotifyFunc();
    }

}

class BlockFactory(T) {

    alias paramsType = BlockObjectParameters!T;

    private {
        uint
            blocksz;
        int
            oid,
            iter,
            backiter = -1;
        Block!T[uint] blockst;
        Block!T backBlock;
    }

    factoryData data;
    paramsType params;

    this(paramsType objectParams) {
        params = objectParams;
        blocksz = params.blockSize;
        iter = 0;
        data = factoryData();
        oid = genId();
        initBackBlock();
    }

    private void initBackBlock() {
        backBlock = new Block!T(-1, params, &data, oid, true);
    }

    uint objectCount() {
        return blockst.values.map!(q => q.length).sum();
    }

    auto getLoadedObjects() {
        auto ldblocks = blockst.keys
            .map!(q => q in blockst)
            .filter!(q => q.isFilled)
            .map!(q => q.getBlock)
            .joiner;

        auto ldback = backBlock.getBlock;

        return chain(ldback, ldblocks);
    }

    private Block!T getblk(int i) {
        auto c = i in blockst;
        if(c) return *c;
        else {
            blockst[i] = new Block!T(i, params, &data, oid);
            return blockst[i];
        }
    }

    private T getBlockObject(int off) {
        auto bk = backBlock.getBlock();
        if(off < bk.length) {
            auto bkobj = bk[off];
            if(bkobj.ignored) return null;
            return bkobj;
        }
        off -= bk.length;

        auto rel = off % blocksz;
        auto n = (off - rel) / blocksz;
        auto nblk = getblk(n);

        if(!nblk.isFilled) {
            nblk.downloadBlock();
            return null;
        }
        if(rel >= nblk.length) return null;

        getblk(n+1).downloadBlock(); //preload
        auto relobj = nblk.getBlock[rel];

        if(relobj.ignored) return null;

        static if(is(T == ClDialog)) {
            if(isOverrided(relobj.getObject.id)) return null;
        }

        return relobj;
    }

    void seek(int off) {
        iter = off;
        backiter = data.serverCount;
    }

    void addBack(T addobj) {
        backBlock.addBack(addobj);
        data.serverCount += 1;
    }

    bool prepare() {
        if(data.serverCount != -1){
            if(backiter == -1) backiter = data.serverCount + backBlock.length;
            return true;
        }
        getblk(0).downloadBlock();
        return false;
    }

    bool empty() {
        return iter >= backiter;
    }

    T front() {
        if(data.forceUpdate) {
            data.forceUpdate = false;
            data.serverCount = -1;
            initBackBlock();
            blockst.clear();
            prepare();
            return null;
        }
        return getBlockObject(iter);
    }

    void popFront() {
        ++iter;
    }

    typeof(this) save() {
        return this;
    }

    // ===== special magic =====

    //pragma(msg, "T: " ~ T.stringof ~ ", equals ClMessage: " ~ is(T == ClMessage).stringof);

    static if (is(T == ClMessage)) {
        private int serverLineCount = -1;
        int unreadCount = -1;

        int getServerLineCount(int ww) {
            if(serverLineCount == -1 && objectCount == data.serverCount) {
                serverLineCount = blockst.values
                                    .map!(q => q.getBlock())
                                    .joiner
                                    .map!(q => q.getLineCount(ww))
                                    .sum.to!int + 1;
            }
            return serverLineCount;
        }

        void addZombie(vkMessage z) {
            //auto rid = z.rndid;
            auto clz = new ClMessage(z);
            //zombies[rid] = clz;
            addBack(clz);
        }

        void removeZombie(long rid) {
            backBlock
                .getBlock
                .filter!(q => q.getObject.rndid == rid)
                .takeOne
                .each!(q => q.ignored = true);
        }

    }


    static if(is(T == ClDialog)) {
        struct DialogOverrider {
            long utime;
            ClDialog dialog;
        }

        private DialogOverrider[int] store; //by peer

        void overrideDialog(ClDialog dlg, long ut) {
            store[dlg.getPeer] = DialogOverrider(ut, dlg);
            backBlock.block = getOverrided().array;
        }

        void overrideBump(int peer, long ut) {
            auto b = peer in store;
            if(b) {
                b.utime = ut;
            }
        }

        bool isOverrided(int peer) {
            auto ptr = peer in store;
            return ptr !is null;
        }

        auto getOverridedByPeer(int peer) {
            return peer in store;
        }

        auto getOverrided() {
            return store.values
                            .sort!((a, b) => a.utime > b.utime)
                            .map!(q => q.dialog);
        }

        auto getOverridedUnsorted() {
            return store.values
                            .map!(q => q.dialog);
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

void enterLoading() {
    ++ps.loadingiter;
    gltoggleUpdate();
}

void leaveLoading() {
    --ps.loadingiter;
    if(ps.loadingiter < 0) ps.loadingiter = 0;
    gltoggleUpdate();
}

void gltoggleUpdate() {
    ps.somethingUpdated = true;
}

// ===== Implement objects =====

class ClDialog : ClObject!vkDialog {

    alias objt = vkDialog;
    alias clt = typeof(this);
    alias ChatFactory = BlockFactory!ClMessage;

    private {
        bool lp;
        ChatFactory cf;
        objt uobj;
    }

    static auto getLoadFunc() {
        return delegate (VkApi api, uint c, uint o, out int sc)
                        =>  api.messagesGetDialogs(c, o, sc).map!(q => new clt(q)).array;
    }

    this(objt obj) {
        super(obj);
    }

    this(string title, int cid, int unreadc, ChatFactory fac) {
        lp = true;
        cf = fac;
        vkDialog lcobj = {
            name: title,
            id: cid
        };
        if(cf.unreadCount < 0) {
            cf.unreadCount = unreadc;
        }
        super(lcobj);
    }

    int getPeer() {
        return obj.id;
    }

    override vkDialog* getObject() {
        if(lp) {
            vkDialog rt = obj;
            auto lastone = cf.getLoadedObjects
                            .filter!(q => q !is null)
                            .takeOne;

            if(lastone.empty) return &obj;
            auto lastm = lastone.front.getObject;

            rt.lastMessage = lastm.body_lines.empty ? "" : lastm.body_lines[0];
            rt.outbox = lastm.outgoing;
            rt.unreadCount = cf.unreadCount;
            rt.unread = rt.outbox ? (lastm.unread) : (cf.unreadCount > 0);
            rt.lastmid = lastm.msg_id;
            rt.online = rt.id >= longpollGimStartId ? true : nc.getOnline(rt.id);
            rt.isChat = rt.id >= convStartId;
            uobj = rt;
            return &uobj;
        }
        else {
            obj.online = obj.id >= longpollGimStartId ? true : nc.getOnline(obj.id);
            return &obj;
        }
    }

}

class ClFriend : ClObject!vkFriend {

    alias objt = vkFriend;
    alias clt = typeof(this);

    static auto getLoadFunc() {
        return delegate (VkApi api, uint c, uint o, out int sc)
                        =>  api.friendsGet(c, o, sc).map!(q => new clt(q)).array;
    }

    this(objt obj) {
        super(obj);
    }

    override vkFriend* getObject() {
        obj.online = nc.getOnline(obj.id);
        return &obj;
    }

}

class ClAudio : ClObject!vkAudio {

    alias objt = vkAudio;
    alias clt = typeof(this);

    static auto getLoadFunc() {
        return delegate (VkApi api, uint c, uint o, out int sc)
                        =>  api.audioGet(c, o, sc).map!(q => new clt(q)).array;
    }

    this(objt obj) {
        super(obj);
    }

}

class ClMessage : ClObject!vkMessage {

    alias objt = vkMessage;
    alias clt = typeof(this);

    static private void resolveNeedNameLocal(ref vkMessage[] mw) {
        int lastfid;
        long lastut;
        foreach(ref m; mw.retro) {
            immutable bool nm = !(m.author_id == lastfid && (m.utime-lastut) <= needNameMaxDelta);
            m.needName = nm;
            lastfid = m.author_id;
            lastut = m.utime;
        }
    }

    static auto getLoadFunc(int peer, void delegate(int) setUnreads) {
        return (VkApi api, uint c, uint o, out int sc) {
            int uc;
            auto h = api.messagesGetHistory(peer, c, o, sc, uc);
            setUnreads(uc);
            resolveNeedNameLocal(h);
            return h.map!(q => new clt(q)).array;
        };
    }


    this(objt obj) {
        super(obj);
    }

    private {
        vkMessageLine[] lines;
        int lastww;
    }

    ulong getLineCount(int ww) {
        fillLines(ww);
        return lines.length;
    }

    vkMessageLine[] getLines(int ww) {
        fillLines(ww);
        return lines;
    }

    void invalidateLineCache() {
        lines = [];
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

class NetworkException : Exception {
    public {
        @safe pure nothrow this(string loc,
                                string message = "Connection lost",
                                string file =__FILE__,
                                size_t line = __LINE__,
                                Throwable next = null) {
            message = message ~ ": " ~ loc;
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

        static const int E_NETWORKFAIL = 4;
        static const int E_LPRESTART = 5;

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
