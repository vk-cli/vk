module namecache;

import std.stdio, std.conv, std.algorithm, std.array;
import vkapi, utils;

struct cachedName {
    string first_name;
    string last_name;
}

string strName(cachedName inp) {
    return inp.first_name ~ " " ~ inp.last_name;
}

class Namecache {

    this(VKapi vkapie) {
        api = vkapie;
    }

    VKapi api;

    private int[] order;
    private cachedName[int] cache;

    void dbmAll() {
        foreach(k, v; cache) {
            dbm(k.to!string ~ " - " ~ v.strName);
        }
    }

    void requestId(int[] ids) {
        order ~= ids;
        dbm("requestId ids: " ~ ids.length.to!string ~ " order: " ~ order.length.to!string);
    }

    void requestId(int id) {
        order ~= id;
    }

    void addToCache(int id, cachedName name){
        cache[id] = name;
    }

    cachedName getName(int id) {
        if(id in cache) {
            return cache[id];
        }
        dbm("got non-cached name!");
        try {
            auto resp = api.usersGet(id);
            auto rt = cachedName(resp.first_name, resp.last_name);
            cache[resp.id] = rt;
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
                        .filter!(q => q !in cache)
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
            foreach(nm; api.usersGet(buf)) {
                cache[nm.id] = cachedName(nm.first_name, nm.last_name);
            }
        }
        order = new int[0];
        dbm("cached " ~ cache.length.to!string ~ " names, order length: " ~ order.length.to!string);
    }

}