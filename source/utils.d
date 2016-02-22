module utils;

import std.stdio, std.array, std.file;

const bool debugMessagesEnabled = false;
File dbmfile;
bool dbmfe = false;

void dbminit() {
    dbmfile = File("dbg", "w");
}

void dbcl() {
    dbmfile.close();
}

void dbm(string msg) {
    if(debugMessagesEnabled) writeln("[debug]" ~ msg);
    if(dbmfe) dbmfile.write(msg ~ "\n");
}

string longpollReplaces(string inp) {
    return inp
        .replace("<br>", "\n")
        .replace("&quot;", "\"")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&");
}