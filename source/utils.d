module utils;

import std.stdio;

const bool debugMessagesEnabled = true;

void dbm(string msg) {
    if(debugMessagesEnabled) writeln("[debug]" ~ msg);
}