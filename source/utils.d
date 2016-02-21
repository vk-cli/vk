module utils;

import std.stdio, std.array, std.file;

const bool debugMessagesEnabled = false;//true;

void dbm(string msg) {
    if(debugMessagesEnabled) writeln("[debug]" ~ msg);
}

string longpollReplaces(string inp) {
    return inp
        .replace("<br>", "\n")
        .replace("&quot;", "\"")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&");
}