module utils;

import std.stdio, std.array, std.string, std.file, core.thread, core.sync.mutex, core.exception, std.datetime, std.conv;

const bool debugMessagesEnabled = false;
const bool dbmfe = true;

__gshared string dbmlog = "";
__gshared dbgfname = "dbg";
File dbgff;
__gshared Mutex dbgmutex;

private void appendDbg(string app) {
    synchronized(dbgmutex) {
        dbgfname.append(app);
    }
}

void initdbm() {
    if(!dbmfe) return;
    dbgmutex = new Mutex();
    dbgff = File(dbgfname, "w");
    dbgff.write("log\n");
    dbgff.close();
}

void dbmclose() {
    if(!dbmfe) return;
}

void dbm(string msg) {
    if(debugMessagesEnabled) writeln("[debug]" ~ msg);
    if(dbmfe) appendDbg(msg ~ "\n");
}

string tzr(int inpt) {
    auto r = inpt.to!string;
    if(inpt > -1 && inpt < 10) return ("0" ~ r);
    else return r;
}

string vktime(SysTime ct, long ut) {
    auto t = SysTime(unixTimeToStdTime(ut));
    return (t.dayOfGregorianCal == ct.dayOfGregorianCal) ?
            (tzr(t.hour) ~ ":" ~ tzr(t.minute)) :
                (tzr(t.day) ~ "." ~ tzr(t.month) ~ ( t.year != ct.year ? "." ~ t.year.to!string[$-2..$] : "" ) );
}

string longpollReplaces(string inp) {
    return inp
        .replace("<br>", "\n")
        .replace("&quot;", "\"")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&");
}

T[] slice(T)(ref T[] src, int count, int offset) {
    try {
        return src[offset..(offset+count)]; //.map!(d => &d).array;
    } catch (RangeError e) {
        dbm("utils slice count: " ~ count.to!string ~ ", offset: " ~ offset.to!string);
        dbm("catched slice ex: " ~ e.msg);
        return [];
    }
}

S[] wordwrap(S)(S s, size_t mln) {
    auto wrplines = s.wrap(mln).split("\n");
    S[] lines;
    foreach(ln; wrplines) {
        S[] crp = ["", ln];
        while(crp.length > 1) {
            crp = cropstr(crp[1] ,mln);
            lines ~= crp[0];
        }
    }
    return lines[0..$-1];
}

private S[] cropstr(S)(S s, size_t mln) {
    if(s.length > mln) return [ s[0..mln], s[mln..$] ];
    else return [s];
}