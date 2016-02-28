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

struct nameCache {
    apiTransfer apiInfo;
    int[] order;
    cachedName[int] cache;
}

struct nameCacheTransfer {
    int[] order;
    cachedName[int] cache;
}

nameCache createNC(nameCache old, apiTransfer apist) {
    auto fold = old;
    fold.apiInfo = apist;
    return fold;
}

void dbmAll(ref nameCache nc) {
    foreach(k, v; nc.cache) {
        dbm(k.to!string ~ " - " ~ v.strName);
    }
}

void requestId(ref nameCache nc, int[] ids) {
    nc.order ~= ids;
    dbm("requestId ids: " ~ ids.length.to!string ~ " order: " ~ nc.order.length.to!string);
}

void requestId(ref nameCache nc, int id) {
    nc.order ~= id;
}

void addToCache(ref nameCache nc, int id, cachedName name){
    nc.cache[id] = name;
}

cachedName getName(ref nameCache nc, int id) {
    if(id in nc.cache) {
        return nc.cache[id];
    }
    dbm("got non-cached name!");
    try {
        auto api = new VKapi(nc.apiInfo);
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

void resolveNames(ref nameCache nc) {
    dbm("start name resolving, order length: " ~ nc.order.length.to!string);
    if(nc.order.length == 0) return;
    auto api = new VKapi(nc.apiInfo);
    int[] clean = nc.order
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
        foreach(nm; api.usersGet( buf.filter!(d => d > 0 || d < convStartId).array )) { //users
            nc.cache[nm.id] = cachedName(nm.first_name, nm.last_name);
        }
        foreach(cnm; api.groupsGetById( buf.filter!(d => d < 0 && d > convStartId).array )) { //communities
            nc.cache[cnm.id] = cachedName(cnm.name, " ");
        }
    }
    nc.order = new int[0];
    dbm("cached " ~ nc.cache.length.to!string ~ " names, order length: " ~ nc.order.length.to!string);
}

