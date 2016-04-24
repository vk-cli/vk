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

module namecache;

import std.stdio, std.conv, std.algorithm, std.array;
import vkapi, utils;

struct cachedName {
    string first_name;
    string last_name;
    bool online;
}

struct nameCacheStorage {
    cachedName[int] cache;
}

string strName(cachedName inp) {
    auto ln = inp.last_name;
    auto rt = inp.first_name;
    if(ln.length != 0) rt ~= " " ~ ln;
    return rt;
}

__gshared auto nc = nameCacheStorage();

class nameCache {
    VkApi api;
    int[] order;

    this(VkApi api) {
        this.api = api;
    }

    static void defeatNameCache() {
        nc = nameCacheStorage();
    }

    void requestId(int[] ids) {
        order ~= ids;
        dbm("requestId ids: " ~ ids.length.to!string ~ " order: " ~ order.length.to!string);
    }

    void requestId(int id) {
        order ~= id;
    }

    void addToCache(int id, cachedName name){
        nc.cache[id] = name;
    }

    void setOnline(int id, bool online) {
        auto c = id in nc.cache;
        if(c) {
            c.online = online;
        }
    }

    bool getOnline(int id, bool forced = false) {
        auto c = id in nc.cache;
        if(c) return c.online;
        else if (forced) return getName(id).online;
        else return false;
    }

    cachedName getName(int id) {
        if(id in nc.cache) {
            return nc.cache[id];
        }
        dbm("got non-cached name!");
        try {
            
            cachedName rt;
            int fid;
            if(id < 0) {
                dbm("got community id");
                auto c = api.groupsGetById([ id ]);
                if(c.length == 0) {
                    return cachedName("community", id.to!string);
                } else {
                    fid = c[0].id;
                    rt = cachedName(c[0].name, " ", true);
                }
            } else {
                auto resp = api.usersGet(id);
                fid = resp.id;
                rt = cachedName(resp.first_name, resp.last_name, resp.online);
            }
            nc.cache[fid] = rt;
            return rt;
        } catch (ApiErrorException e) {
            if (e.errorCode == 6) {
                dbm("too many requests, returning default name");
                return cachedName("default", "name");
            } else {
                //rethrow
                throw e;
            }
        }
    }

    void resolveNames() {
        dbm("start name resolving, order length: " ~ order.length.to!string);
        if(order.length == 0) return;
        int[] clean = order
                        .filter!(q => q !in nc.cache)
                        .array;

        const int max = 1000;
        int n = 0;
        int len = clean.length.to!int;
        bool cnt = true;
        while(cnt) {
            int d = len - n;
            int[] buf;
            if(d > max) {
                int up = n+max+1;
                buf = clean[n..up];
                n += max;
            } else {
                int up = n+d;
                buf = clean[n..up];
                cnt = false;
            }
            foreach(nm; api.usersGet( buf.filter!(d => d > 0 || d < mailStartId).array )) { //users
                nc.cache[nm.id] = cachedName(nm.first_name, nm.last_name, nm.online);
            }
            foreach(cnm; api.groupsGetById( buf.filter!(d => d < 0 && d > mailStartId).array )) { //communities
                nc.cache[cnm.id] = cachedName(cnm.name, " ", true);
            }
        }
        order = new int[0];
        dbm("cached " ~ nc.cache.length.to!string ~ " names, order length: " ~ order.length.to!string);
    }

}


