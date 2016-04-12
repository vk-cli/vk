module utils;

import std.stdio, std.array, std.range, std.string, std.file;
import core.thread, core.sync.mutex, core.exception;
import std.datetime, std.conv, std.algorithm;

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

class JoinerBidirectionalResult(RoR)
if (isBidirectionalRange!RoR && isBidirectionalRange!(ElementType!RoR))
{

    alias rortype = ElementType!RoR;

    private {
        RoR range;
        rortype
            rfront = null,
            rback = null;
}

    this(RoR r) {
        range = r;
    }

    private void prepareFront() {
        if(range.empty) return;
        while(range.front.empty) {
            range.popFront();
            if(range.empty) return;
        }
        rfront = range.front;
    }

    private void prepareBack() {
        if(range.empty) return;
        while(range.back.empty) {
            range.popBack();
            if(range.empty) return;
        }
        rback = range.back;
    }

    @property bool empty() {
        return range.empty;
    }

    @property auto front() {
        if(rfront is null) prepareFront();
        assert(!empty);
        assert(!rfront.empty);
        return rfront.front;
    }

    @property auto back() {
        if(rback is null) prepareBack();
        assert(!empty);
        assert(!rback.empty);
        return rback.back;
    }

    void popFront() {
        if(rfront is null) prepareFront();
        else {
            rfront.popFront();

            if(rfront.empty) {
                range.popFront();
                prepareFront();
            }
        }
    }

    void popBack() {
        if(rback is null) prepareBack();
        else {
            rback.popBack();
            if(rback.empty) {
                range.popBack();
                prepareBack();
            }
        }
    }

    auto moveBack() {
        return back;
    }

    auto save() {
        return this;
    }

}

auto joinerBidirectional(RoR)(RoR range) {
    return new JoinerBidirectionalResult!RoR(range);
}

auto takeBackArray(R)(R range, size_t hm) {
    ElementType!R[] outr;
    size_t iter;
    while(iter < hm && !range.empty) {
        outr ~= range.back();
        range.popBack();
        ++iter;
    }
    reverse(outr);
    return outr;
}

class InputRetroResult(R)
if (isInputRange!R)
{
    private R rng;

    this(R range) {
        rng = range;
    }

    void popFront() {
        rng.popFront();
    }

    void popBack() {
        rng.popFront();
    }

    auto front() {
        return rng.front;
    }

    auto back() {
        return rng.front;
    }

    auto empty() {
        return rng.empty;
    }

    auto moveBack() {
        return back;
    }

    auto save() {
        return this;
    }

}

auto inputRetro(R)(R range) {
    return new InputRetroResult!R(range);
}

auto ror = ["ClCl", "u cant touch my pragmas", "substanceof eboshil zdes'"];
alias rortp = typeof(ror);
//pragma(msg, "isBidirectional TakeBackResult " ~ isBidirectionalRange!(TakeBackResult!string).stringof);
pragma(msg, "isBidirectional joinerBidirectional "
                    ~ isBidirectionalRange!(JoinerBidirectionalResult!rortp).stringof);


