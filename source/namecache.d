module namecache;

import std.stdio, std.conv, std.algorithm, std.array;
import vkapi, utils;

struct cachedName {
    string first_name;
    string last_name;
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
                    rt = cachedName(c[0].name, " ");
                }
            } else {
                auto resp = api.usersGet(id);
                fid = resp.id;
                rt = cachedName(resp.first_name, resp.last_name);
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
                nc.cache[nm.id] = cachedName(nm.first_name, nm.last_name);
            }
            foreach(cnm; api.groupsGetById( buf.filter!(d => d < 0 && d > mailStartId).array )) { //communities
                nc.cache[cnm.id] = cachedName(cnm.name, " ");
            }
        }
        order = new int[0];
        dbm("cached " ~ nc.cache.length.to!string ~ " names, order length: " ~ order.length.to!string);
    }

}


