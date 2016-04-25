/*
Copyright 2016 HaCk3D, substanceof

https://github.com/HaCk3Dq
https://github.com/substanceof

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

module utils;

import std.stdio, std.array, std.range, std.string, std.file;
import core.thread, core.sync.mutex, core.exception;
import std.datetime, std.conv, std.algorithm, std.utf, std.typecons;
import localization, app;

const bool debugMessagesEnabled = false;
const bool dbmfe = true;
const bool showTokenInLog = false;

__gshared string dbmlog = "";
__gshared dbgfname = "/tmp/vkdbg";
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

void dropClient(string msg) {
    failExit(msg);
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

string agotime (SysTime ct, long ut) { //not used
    auto pt = SysTime(ut.unixTimeToStdTime);
    auto ctm = ct.hour*60 + ct.minute;
    auto ptm = pt.hour*60 + pt.minute;
    auto tmdelta = ctm - ptm;
    const threshld = 240;

    if(
        pt.dayOfGregorianCal == ct.dayOfGregorianCal &&
        tmdelta < threshld
    ) {
        string rt;
        if(tmdelta > 60) {
            auto m = tmdelta % 60;
            auto h = (tmdelta-m) / 60;
            rt ~= h.to!string ~
             ( h == 1 ? getLocal("time_hour") : ( h > 0 && h < 5 ? getLocal("time_hours_l5") : getLocal("time_hours") ) );
            if(m != 0) rt ~= " " ~ m.to!string ~
             ( m == 1 ? getLocal("time_minute") : ( m > 0 && m < 5 ? getLocal("time_minutes_l5") : getLocal("time_minutes") ) );
        }
        else if(tmdelta == 1) rt = tmdelta.to!string ~ getLocal("time_minute");
        else rt = tmdelta.to!string ~ getLocal("time_minutes");

        return rt ~ getLocal("time_ago");
    }
    else return vktime(ct, ut);
}

/*
 local["time_minutes"] = lang(" minutes ago", " минут назад");
  local["time_minutes_l5"] = lang(" minutes ago", " минуты назад");
  local["time_minute"] = lang(" minute", " минуту");
  local["time_hours"] = lang(" hours", " часов");
  local["time_hours_l5"] = lang(" hours", " часа");
  local["time_hour"] = lang(" hour", " час");
  local["time_ago"] = lang(" ago" , " назад");
  local["lastseen"] = lang("last seen at ", "был в сети в ");
  */

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

alias Repldchar = std.typecons.Flag!"useReplacementDchar";
const Repldchar repl = Repldchar.yes;

wstring toUTF16wrepl(in char[] s) {
    wchar[] r;
    size_t slen = s.length;

    r.length = slen;
    r.length = 0;
    for (size_t i = 0; i < slen; )
    {
        dchar c = s[i];
        if (c <= 0x7F)
        {
            i++;
            r ~= cast(wchar)c;
        }
        else
        {
            c = decode!repl(s, i);
            encode(r, c);
        }
    }

    return cast(wstring)r;
}

string toUTF8wrepl(in wchar[] s) {
    char[] r;
    size_t i;
    size_t slen = s.length;

    r.length = slen;
    for (i = 0; i < slen; i++)
    {
        wchar c = s[i];

        if (c <= 0x7F)
            r[i] = cast(char)c;     // fast path for ascii
        else
        {
            r.length = i;
            while (i < slen)
                encode(r, decode!repl(s, i));
            break;
        }
    }

    return cast(string)r;
}



