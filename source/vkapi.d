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
import std.exception, core.exception, std.process;
import std.net.curl, std.uri, std.json;
import std.range, std.algorithm;
import std.parallelism, std.concurrency, core.thread, core.sync.mutex;
import utils, namecache, localization;

class User {
    int id;
    string firstName, lastName;
    bool online, isFriend;
    SysTime lastSeen;

    private {
        auto cachedFullName = cachedValue!string(&getFullNameInit);
    }

    this(int p_id, string p_fname, string p_lname, bool p_friend = false, bool p_online = fals, SysTime p_lastseen = null) {
        id = p_id; firstName = p_fname; lastName = p_lname;
        isFriend = p_friend; online = p_online; p_lastseen = lastSeen;
    }

    private string getFullNameInit() {
        return firstName ~ " " ~ lastName;
    }

    string getFullName() {
        return cachedFullName.get();
    }

    void setOnlineStatus(bool status) {
        if (status != online) {
            online = status;
            if(!status) {
                lastSeen = Clock.currTime();
            }
        }
    }

    string getFormattedLastSeen() {
        if(lastSeen is null) return "";
        return vktime(Clock.currTime, lastSeen);
    }
}

class Audio {
    int id, owner, duration;
    string artist, title, url;

    private {
        auto cachedDurationString = cachedValue!string(&getDurationStringInit);
    }

    this(int p_id, int p_owner, int p_dur, string p_title, string p_artist, string p_url) {
        id = p_id; owner = p_owner; duration = p_dur;
        artist = p_artist; title = p_title; url = p_url;
    }

    private string getDurationStringInit() {
        auto sec = duration % 60;
        auto min = (duration - sec) / 60;
        return min.to!string ~ ":" ~ tzr(min);
    }

    string getDurationString() {
        return cachedDurationString.get();
    }
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
            //dbm("up " ~ key ~ "=" ~ val);
            auto cval = val.encode.replace("+", "%2B");
            url ~= key ~ "=" ~ cval ~ "&";
        }
        url ~= "v=" ~ vkver ~ "&access_token=";
        if(!showTokenInLog) dbm("request: " ~ url ~ "***");
        url ~= vktoken;
        if(showTokenInLog) dbm("request: " ~ url);
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
            vkget("account.setOnline", emptyparam, false, gp);
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
            vkget("account.setOffline", [ "voip": "0" ], false, gp);
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
            if(msg["read_state"].integer == 0) ds.unread = true;
            if(msg["out"].integer == 1) ds.outbox = true;
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
            auto last = "last_seen" in f ? f["last_seen"]["time"].integer.to!long : 0;

            //auto laststr = agotime(ct, last);
            //auto laststr = getLocal("lastseen") ~ vktime(ct, last);
            auto laststr = last > 0 ? vktime(ct, last) : getLocal("banned");

            vkFriend friend = {
              first_name: f["first_name"].str,
              last_name: f["last_name"].str,
              id: f["id"].integer.to!int,
              online: ( f["online"].integer.to!int == 1 ),
              last_seen_utime: last,  last_seen_str: laststr
            };

            nc.addToCache(friend.id, cachedName(friend.first_name, friend.last_name, friend.online));

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

        vkgetparams gp = {
            setloading: true,
            attempts: 4,
            thrownf: true,
            notifynf: false
        };

        auto params = ["peer_id": pid.to!string ];
        params["message"] = msg;
        if(rndid != 0) params["random_id"] = rndid.to!string;
        if(fwd.length != 0) params["forward_messages"] = fwd.map!(q => q.to!string).join(",");
        if(attaches.length != 0) params["attachment"] = attaches.join(",");

        auto resp = vkget("messages.send", params, false, gp);
        return resp.integer.to!int;
    }
}
