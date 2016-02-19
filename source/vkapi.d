module vkapi;

import std.stdio, std.conv, std.string;
import std.exception, core.exception;
import std.net.curl, std.uri, std.json;
import utils;


// ===== API objects =====

struct vkUser{
    string first_name;
    string last_name;
    int id;
}

class VKapi{

// ===== API & networking =====

    private const string vkurl = "https://api.vk.com/method/";
    const string vkver = "5.45";
    private string vktoken = "";
    bool isTokenValid;
    vkUser me;

    this(string token){
        vktoken = token;
        isTokenValid = checkToken(token);
    }

    private bool checkToken(string token){
        if(token.length != 85) return false;
        try{
            me = usersGet();
        } catch (ApiErrorException e) {
            dbm("ApiErrorException: " ~ e.msg);
            return false;
        } catch (BackendException e){
            dbm("BackendException: " ~ e.msg);
            return false;
        }
        return true;
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
        dbm("request: " ~ url);
        JSONValue resp = httpget(url).parseJSON;

        if(resp.type == JSON_TYPE.OBJECT) {
            if("error" in resp){

                auto eobj = resp["error"];
                immutable auto emsg = ("error_text" in eobj) ? eobj["error_text"].str : eobj["error_msg"].str;
                immutable auto ecode = eobj["error_code"].uinteger.to!int;
                throw new ApiErrorException(emsg, ecode);

            } else if ("response" !in resp) {
                rmresp = false;
            }
        }

        return rmresp ? resp : resp["response"];
    }

    // ===== API method wrappers =====

    vkUser usersGet(int userId = 0, string fields = "", string nameCase = "nom"){
        string[string] params;
        if(userId != 0) params["user_ids"] = userId.to!string;
        if(fields != "") params["fields"] = fields;
        if(nameCase != "nom") params["name_case"] = nameCase;
        auto resp = vkget("users.get", params);

        if(resp.array.length != 1) throw new BackendException("users.get (one user) fail: response array length != 1");
        resp = resp[0];

        vkUser rt = {
            id:resp["id"].integer.to!int,
            first_name:resp["first_name"].str,
            last_name:resp["last_name"].str
        };
        return rt;
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