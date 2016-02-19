module vkapi;

import std.stdio, std.conv, std.string;
import std.exception, core.exception;
import std.net.curl, std.uri, std.json;
import utils;


class VKapi{

// ===== API & networking =====

    const string vkurl = "https://api.vk.com/method/";
    const string vkver = "5.45";
    string vktoken = "";

    this(string token){
        if(token.length != 85){
            throw new BackendException("Invalid token length");
        }
        vktoken = token;
    }

    string httpget(string addr) {
        string content;
        bool ok = false;

        while(!ok){
            try{
                content = get(addr).to!string;
                ok = true;
            } catch (CurlException e) {
                dbm("network error: " ~ e.msg);
                //todo sleep here
            }
        }
        return content;
    }

    JSONValue vkget(string meth, string[string] params, bool dontRemoveResponse = false){
        bool rmresp = dontRemoveResponse;
        auto url = vkurl ~ meth ~ "?"; //so blue
        foreach(key; params.keys) {
            auto val = params[key];
            url ~= key ~ "=" ~ val.encode ~ "&";
        }
        url ~= "v=" ~ vkver ~ "&access_token=" ~ vktoken;
        JSONValue resp = httpget(url).parseJSON;

        if(resp.type == JSON_TYPE.OBJECT) {
            if("error" in resp){

                auto eobj = resp["error"];
                immutable auto emsg = ("error_text" in eobj) ? eobj["error_text"].str : eobj["error_msg"].str;
                immutable auto ecode = eobj["error_code"].uinteger.to!int;
                throw new ApiErrorException(emsg, ecode);

            } else {
                rmresp = false;
            }
        }

        return rmresp ? resp : resp["response"];
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