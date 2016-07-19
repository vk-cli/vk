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
import utils, cache, localization;

const int convStartId = 2000000000;
const int mailStartId = convStartId*-1;
const int longpollGimStartId = 1000000000;
const bool return80mc = true;
const long needNameMaxDelta = 180; //seconds, 3 min
const int typingTimeout = 4;

const uint defaultBlock = 100;
const int chatBlock = 100;
const int chatUpd = 50;

class User {
    int id;
    string firstName, lastName;
    bool online, isFriend;
    SysTime lastSeen;

    private {
        auto cachedFullName = cachedValue!string(&getFullNameInit);
    }

    this() {

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

    private auto cachedTimeString = cachedValue(() => vktime(Clock.currTime, time));
    string getTimeString() { return cachedTimeString.get(); }

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

    this(int aid, int pid, int mid, long ut, string txt, FwdMessage[] fwds, bool outg, bool unr) {
        authorId = aid; peerId = pid; msgId = mid;
        text = txt; forwarded = fwds; time = ut;
        outgoing = outg; unread = unr;
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
                text: getAuthor().getFullName(),
                time: getTimeString(),
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
            foreach(line; text.wordwrap(ww).split('\n')) {
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
                auto fwdww = ww - ( * wwstep);
                if (fwdww < 1) fwdww = 1;

                MessageLine fwdname = {
                    text: fwd.getAuthor().getFullName(),
                    fwdDepth: depth,
                    isFwd: true,
                    isName: true
                };
                lineCache ~= fwdname;

                foreach(line; text.wordwrap(fwdww).split('\n')) {
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
    string title;
    int id, unreadCount;
    bool unread, outbox;

    private {
        bool chat;
        Storage!Mesage messages;
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

    private const string vkurl = "https://api.vk.com/method/";
    const string vkver = "5.50";
    private string vktoken;

    this(string token) {
        vktoken = token;
    }

    User[] friendsGet(int count, int offset, out int serverCount, int user_id = 0) {
        auto params = [ "fields": "online,last_seen", "order": "hints"];
        if(user_id != 0) params["user_id"] = user_id.to!string;
        if(count != 0) params["count"] = count.to!string;
        if(offset != 0) params["offset"] = offset.to!string;

        auto resp = vkget("friends.get", params);
        serverCount = resp["count"].integer.to!int;


        auto ct = Clock.currTime();
        User[] rt;

        foreach(f; resp["items"].array) {
            auto last = "last_seen" in f ? f["last_seen"]["time"].integer.to!long : 0;

            //auto laststr = agotime(ct, last);
            //auto laststr = getLocal("lastseen") ~ vktime(ct, last);
            auto laststr = last > 0 ? vktime(ct, last) : getLocal("banned");

            auto f = new User();
            f.id = f["id"].integer.to!int;
            f.firstName = f["first_name"].str;
            f.lastName = f["last_name"].str;
            f.online = f["online"].integer.to!int == 1;
            f.lastSeen = SysTime(unixTimeToStdTime(last));
            f.isFriend = true;

            //nc.addToCache(friend.id, cachedName(friend.first_name, friend.last_name, friend.online));

            rt ~= f;
        }

        return rt;
    }
}
