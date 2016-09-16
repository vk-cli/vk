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

module cache;

import std.stdio, std.conv, std.algorithm, std.array, std.range;
import core.sync.mutex;
import vkapi, utils, logic;

class Cache(T) { // test-impl for cache
    immutable typestring = T.stringof;
    
    T[] midcache;
    
    bool hasCacheFor(int pos, int count) {
        return (midcache.length >= pos + count);
    }
    
    T[] getCache(int pos, int count) {
        if (!hasCacheFor(pos, count))
            throw new InternalException(-1,
                "no cache found for this range " ~ pos.to!string ~ "(" ~ count.to!string ~ ")");
        return midcache[pos .. (pos + count)];
    }
}


class UserCache {
    alias UserDwFunc = User[] delegate(int[] ids);

    __gshared {
        Mutex lock;
        UserDwFunc userDw;
        private bool dwPresent;

        User[int] users; //by peer id (positive, <2b)
        //Group[int] groups; //by peer id (negative, >-2b) TODO
    }

    int[] resolveQueue;

    this() {
        lock = new Mutex();
        userDw = i => [];
    }

    void updateDownloaders(UserDwFunc userdw) {
        userDw = userdw;
        dwPresent = true;
    }

    @property bool isDownloaderPresent() {
        return dwPresent;
    }

    void add(User[] ul) {
        ul.each!(u => users[u.id] = u);
    }

    void request(int[] peers) {
        resolveQueue ~= peers;
    }

    string getName(int peer) {
        if(peer > 0 && peer < convStartId) {
            if(auto u = peer in users) 
                return u.fullName;
            else
                resolve([peer]);
        }
        else if (peer < 0 && peer > mailStartId) {
            //todo groups
        }
        return peer.to!string; //fallback
    }

    User getUser(int peer) {
        if(auto p = peer in users)
            return *p;
        else
            return null;
    }

    void resolve() {
        auto req = resolveQueue.uniq().array();
        resolveQueue = [];
        resolve(req);
    }

    void resolve(int[] peers) {
        async.queue("user_cache_resolve", genId(), {
                resolveSync(peers);
                //todo rehash
                //todo notify-resolved
            });
    }

    void resolveSync(int[] peers) {
        auto freshUsers = 
            userDw(peers.filter!(id => id > 0 && id < convStartId).array());
        synchronized(lock) {
            freshUsers
                .each!(u => users[u.id] = u);
        }
    }

}