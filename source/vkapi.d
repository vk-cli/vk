module vkapi;

import std.stdio, std.net.curl, std.conv, std.string, std.json;



class VKapi{

// ===== API & networking =====

    const string vkurl = "https://api.vk.com/method/";
    const string vkver = "5.45";
    string vktoken = "";

    this(string token){
        if(token.length != 85){
            throw BackendException("Invalid token length");
        }
        vktoken = token;
    }

    string httpget(string addr) {
        auto content = get(addr).to!string; //todo try network errors
        return content;
    }

    JSONValue vkget(string meth, string[string] params, bool dontRemoveResponse = false){
        bool rmresp = dontRemoveResponse;
        auto url = vkurl ~ meth ~ "?"; //so blue
        foreach(key; params.keys) {
            auto val = params[key];
            url ~= key ~ "=" ~ val ~ "&"; //todo fix val for url
        }
        url ~= "v=" ~ vkver ~ "&access_token=" ~ vktoken;
        JSONValue resp = httpget(url).parseJSON;

        if(resp.type == JSON_TYPE.OBJECT) {
            if("error" in resp){

                auto eobj = resp["error"];
                auto emsg = ("error_text" in eobj) ? eobj["error_text"].str : eobj["error_msg"].str;
                auto ecode = eobj["error_code"].uinteger;
                throw ApiErrorException(emsg, ecode);

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
        @safe pure nothrow this(string message,
                                int error_code,
                                string file =__FILE__,
                                size_t line = __LINE__,
                                Throwable next = null) {
            super(message, file, line, next);
        }
    }
}