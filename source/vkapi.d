module vkapi;

import std.stdio, std.net.curl, std.conv, std.string, std.json;

class VKapi{

    const string vkurl = "https://api.vk.com/method/";
    const string vkver = "5.45";
    string vktoken = "0";

    this(string token){
        vktoken = token;
    }

    string httpget(string addr) {
        auto content = get(addr).to!string; //todo try network errors
        return content;
    }

    JSONValue vkget(string meth, string[string] params, bool dontRemoveResponse = false){
        auto url = vkurl ~ meth ~ "?";
        foreach(key; params.keys) {
            auto val = params[key];
            url ~= key ~ "=" ~ val ~ "&"; //todo fix val for url
        }
        url ~= "v=" ~ vkver ~ "&access_token=" ~ vktoken;
        JSONValue resp = httpget(url).parseJSON;

        if(resp.type == JSON_TYPE.OBJECT && "error" in resp) {
            writeln("vk api error:"); //todo exceptions
            writeln(resp.toPrettyString);
        }

        if(dontRemoveResponse){
            return resp;
        } else {
            return resp["response"];
        }
    }

}