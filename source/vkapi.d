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
import utils, localization, logic;

const int convStartId = 2000000000;
const int mailStartId = convStartId*-1;
const int longpollGimStartId = 1000000000;
const bool return80mc = true;
const long needNameMaxDelta = 180; //seconds, 3 min
const int typingTimeout = 4;

const uint defaultBlock = 100;
const int chatBlock = 100;
const int chatUpd = 50;

const int connectionAttempts = 10;
const int mssleepBeforeAttempt = 600;
const int vkgetCurlTimeout = 3;
const int longpollCurlTimeout = 27;
const int longpollCurlAttempts = 5;
const string timeoutFormat = "seconds";

class User {
    int id;
    string firstName, lastName, fullName;
    bool online, isFriend;
    SysTime lastSeen;

    this() {
        init();
    }

    private void init() {
        fullName = firstName ~ " " ~ lastName;
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
        return vktime(Clock.currTime, lastSeen.toUnixTime);
    }
}

class Audio {
    int id, owner, duration;
    string artist, title, url, durationString;

    this(int p_id, int p_owner, int p_dur, string p_title, string p_artist, string p_url) {
        id = p_id; owner = p_owner; duration = p_dur;
        artist = p_artist; title = p_title; url = p_url;
        init();
    }

    private void init() {
        // durationString
        auto sec = duration % 60;
        auto min = (duration - sec) / 60;
        durationString = min.to!string ~ ":" ~ tzr(min);
    }

}

struct MessageLine {
    wstring text;
    string time;
    bool unread;
    bool isName;
    bool isSpacing;
    bool isFwd;
    int fwdDepth;
}

struct FwdMessage {
    int authorId;
    long time;
    wstring text;
    int fwdDepth;
    //User[] authorsChain;

    string getTimeString() { return vktime(Clock.currTime, this.time); }

    //private auto cachedAuthor = cahcedValue();
    //User getAuthor() { return cachedAuthor.get(); }
}

class Message {
    alias MessageLines = MessageLine[];

    const int wwstep = 3;
    const long needNameMaxDelta = 180; //seconds, 3 min

    int authorId, peerId, msgId;
    string text, timeString;
    long time;
    bool outgoing, unread, needName = true;
    FwdMessage[] forwarded;

    private {
        //auto cachedAuthor = cachedValue(); // todo get from cache
        MessageLine[] lineCache;
        int lineCacheWidth;
    }

    //User getAuthor() { return cachedAuthor.get(); }

    this() {
        init();
    }

    private void init() {
        //timeString
        timeString = vktime(Clock.currTime, time);
    }

    void setNeedName(long reltime) {
        needName = (time-reltime) > needNameMaxDelta;
    }

    void invalidateLineCache() {
        lineCache = [];
    }

    MessageLine[] getLines(int width) {

        if(lineCache.length == 0 || lineCacheWidth != width) convertMessage(width);
        return lineCache;
    }

    MessageLine lspacing = {
        text: "", isSpacing: true
    };

    private void convertMessage(int ww) {
        lineCache = [];
        lineCache ~= lspacing;

        if(needName || true) { // todo needName resolve
            MessageLine name = {
                //text: getAuthor().getFullName(),
                time: timeString,
                isName: true
            };
            lineCache ~= name;
            lineCache ~= lspacing;
        }

        auto nomsg = text.length == 0;
        auto nofwd = forwarded.length == 0;
        if(nomsg && nofwd) lineCache ~= lspacing;

        if(!nomsg) {
            bool firstLineUnread = unread;
            foreach(line; text.toUTF16wrepl.wordwrap(ww).split('\n')) {
                MessageLine msg = {
                    text: line,
                    unread: firstLineUnread
                };
                lineCache ~= msg;
                firstLineUnread = false;
            }
        }

        if(!nofwd) { // todo fix digfwd in api
            foreach(fwd; forwarded) {
                immutable auto depth = fwd.fwdDepth;
                auto fwdww = ww - (depth * wwstep);
                if (fwdww < 1) fwdww = 1;

                MessageLine fwdname = {
                    //text: fwd.getAuthor().getFullName(),
                    fwdDepth: depth,
                    isFwd: true,
                    isName: true
                };
                lineCache ~= fwdname;

                foreach(line; text.toUTF16wrepl.wordwrap(fwdww).split('\n')) {
                    MessageLine msg = {
                        text: line,
                        fwdDepth: depth,
                        isFwd: true
                    };
                    lineCache ~= msg;
                }

                auto fwdspacing = lspacing;
                fwdspacing.isFwd = true;
                fwdspacing.fwdDepth = depth;
                lineCache ~= fwdspacing;
            }
        }
    }

}

class Dialog {
    alias messagesStorage = Storage!Message;

    string title;
    int id, unreadCount;
    bool unread, outbox;

    private {
        bool chat;
        messagesStorage messages;
    }

    this(int peer) {
        id = peer;
        chat = id > convStartId;
    }

    private Message getLast() {
        auto query = messages.get(0, 1);
        if(query.empty) return null;
        return query.front;
    }

    bool isChat() { return chat; }

    bool isOnline() {
        return isChat ? true : false; // todo resolve non-chat online
    }

    string getLastMessage() {
        auto l = getLast();
        if(l is null) return "";
        return l.text;
    }

    int getLastmid() {
        auto l = getLast();
        if(l is null) return 0;
        return l.msgId;
    }
}

class VkApi {
    struct vkgetparams {
        bool setloading = true;
        int attempts = connectionAttempts;
        bool thrownf = false;
        bool notifynf = true;
    }

    private const string vkurl = "https://api.vk.com/method/";
    const string vkver = "5.50";
    private string vktoken;

    this(string token) {
        vktoken = token;
    }

    string httpget(string addr, Duration timeout, uint attempts) {
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

    JSONValue vkget(string meth, string[string] params, bool dontRemoveResponse = false, vkgetparams gp = vkgetparams()) {
        if(gp.setloading) {
            //enterLoading();
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
                got = httpget(url, tm, gp.attempts);
                htloop = true;
            } catch(NetworkException e) {
                dbm(e.msg);
                //if(gp.notifynf) connectionProblems();
                if(gp.thrownf) throw e;
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

        //if(gp.setloading) leaveLoading();
        return rmresp ? resp["response"] : resp;
    }

    User[] friendsGet(int count, int offset,  int user_id = 0) {
        auto params = [ "fields": "online,last_seen", "order": "hints"];
        if(user_id != 0) params["user_id"] = user_id.to!string;
        if(count != 0) params["count"] = count.to!string;
        if(offset != 0) params["offset"] = offset.to!string;

        auto resp = vkget("friends.get", params);
        //serverCount = resp["count"].integer.to!int;


        auto ct = Clock.currTime();
        User[] rt;

        foreach(f; resp["items"].array) {
            auto last = "last_seen" in f ? f["last_seen"]["time"].integer.to!long : 0;

            //auto laststr = agotime(ct, last);
            //auto laststr = getLocal("lastseen") ~ vktime(ct, last);
            auto laststr = last > 0 ? vktime(ct, last) : getLocal("banned");

            auto fr = new User();
            fr.id = f["id"].integer.to!int;
            fr.firstName = f["first_name"].str;
            fr.lastName = f["last_name"].str;
            fr.online = f["online"].integer.to!int == 1;
            fr.lastSeen = SysTime(unixTimeToStdTime(last));
            fr.isFriend = true;

            //nc.addToCache(friend.id, cachedName(friend.first_name, friend.last_name, friend.online));

            rt ~= fr;
        }

        return rt;
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
