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

import std.stdio, std.array, std.range, std.string, std.file, std.random;
import std.datetime, std.conv, std.algorithm, std.utf, std.typecons;
import std.process, core.thread, core.sync.mutex, core.exception;
import core.sys.posix.signal;
import localization, app, vkversion, musicplayer;

const bool
    loggingEnabled = true,
    debugMessagesEnabled = false,
    showTokenInLog = false;

__gshared {
    File dbgff;
    File dbglat;
    bool dbmfe = loggingEnabled;
    string dbmlog = "";
    string vkcliTmpDir = "/tmp/vkcli-tmp";
    string vkcliLogDir = "/tmp/vkcli-log";
    string vkcliTmpMsgFile = "/tmp/vkcli-tmp/messagetext";
    string dbgfname = "vklog";
    string dbglatest = "-latest";
    string mpvsck = "vkmpv-socket-";
    string mpvsocketName;
    string logName;
    string logPath;
    Mutex dbgmutex;
}

private void appendDbg(string app) {
    synchronized(dbgmutex) {
        append(logPath, app);
    }
}

string toTmpDateString(SysTime t) {
    return t.day().to!string
            ~ t.month().to!string
            ~ t.year().to!string
            ~ "-"
            ~ t.hour().tzr ~ ":"
            ~ t.minute().tzr ~ ":"
            ~ t.second().tzr
            ~ "-"
            ~ t.timezone().stdName();
}

string getPlayerSocketName() {
    if(mpvsocketName == "") throw new Exception("bad player socket name");
    return vkcliTmpDir ~ "/" ~ mpvsocketName;
}

void initdbm() {
    auto ctime = Clock.currTime();
    dbgmutex = new Mutex();
    logName = dbgfname ~ "_" ~ ctime.toTmpDateString();
    logPath = vkcliLogDir ~ "/" ~ logName;
    mpvsocketName = mpvsck ~ genStr(8);

    if(!exists(vkcliTmpDir)) mkdir(vkcliTmpDir);
    if(!exists(vkcliLogDir)) mkdir(vkcliLogDir);

    if(dbmfe) {
        string logIntro = "vk-cli " ~ currentVersion ~ " log\n" ~ ctime.toSimpleString() ~ "\n";

        auto touchResult = executeShell("umask 0177\ntouch " ~ logPath);
        if(touchResult.status != 0) {
            auto ecode = touchResult.status.to!string;
            writeln("touch failed (" ~ ecode ~ ") - logging disabled");
            dbmfe = false;
        }

        dbgff = File(logPath, "w");
        dbgff.write(logIntro);
        dbgff.close();
    }
}

void dbm(string msg) {
    if(debugMessagesEnabled) writeln("[debug]" ~ msg);
    if(dbmfe) appendDbg(msg ~ "\n");
}

void dropClient(string msg) {
    Exit(msg);
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

void logThread(string thrname = "") {
    if(thrname != "") dbm("thread started for: " ~ thrname);
}

void unwantedExit(int sig) {
    Exit("killed by signal " ~ sig.to!string, 2);
}

void writeCurrentTrack(int sig) {
    auto file = File(vkcliTmpDir ~ "/current-track", "w");
    auto track = mplayer ? mplayer.currentTrack : Track();
    file.write("[" ~ track.playtime ~ "/" ~ track.duration ~ "] " ~ track.artist ~ " - " ~ track.title);
}

void setPosixSignals() {
    version(posix) {
        sigset(SIGSEGV, a => unwantedExit(a));
        sigset(SIGUSR1, a => writeCurrentTrack(a));
    }
}

int gcSuspendSignal;
int gcResumeSignal;

void updateGcSignals() {
    version(linux) {
      gcSuspendSignal = SIGRTMIN;
      gcResumeSignal = SIGRTMIN+1;
      
      thread_term();
      thread_setGCSignals(gcSuspendSignal, gcResumeSignal);
      thread_init();
      dbm("GC signals: " ~ gcSuspendSignal.to!string ~ " " ~ gcResumeSignal.to!string);
    }
}


const uint maxuint = 4_294_967_295;
const uint maxint = 2_147_483_647;
const uint ridstart = 1;

int genId() {
    long rnd = uniform(ridstart, maxuint);
    if(rnd > maxint) {
        rnd = -(rnd-maxint);
    }
    dbm("rid: " ~ rnd.to!string);
    return rnd.to!int;
}

string genStrDict = "qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890";

string genStr(uint strln) {
    string output;
    for(uint i; i < strln; ++i) {
        size_t rnd = uniform!"[)"(0, genStrDict.length);
        output ~= genStrDict[rnd];
    }
    return output;
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

struct utf {
  ulong
    start, end;
  int spaces;
}

const utfranges = [
  utf(19968, 40959, 1),
  utf(12288, 12351, 1),
  utf(11904, 12031, 1),
  utf(13312, 19903, 1),
  utf(63744, 64255, 1),
  utf(12800, 13055, 1),
  utf(13056, 13311, 1),
  utf(12736, 12783, 1),
  utf(12448, 12543, 1),
  utf(12352, 12447, 1),
  utf(110592, 110847, 1),
  utf(65280, 65519, 1)
  ];

uint utfLength(string inp) {
    uint s = 0;
    size_t inplen = inp.length;

    for (size_t i = 0; i < inplen; ) {
        auto ic = inp[i];
        ulong c;
        ++s;

        if(ic <= 0x7F) {
            c = cast(ulong)ic;
            ++i;
        }
        else {
            c = cast(ulong)(decode!repl(inp, i));
        }

        foreach (r; utfranges) {
            if (c >= r.start && c <= r.end) {
                s += r.spaces;
                break;
            }
        }
    }
    return s;
}

S replicatestr(S)(S str, ulong n) {
    S outstr = "";
    for(ulong i = 0; i < n; ++i) {
        outstr ~= str;
    }
    return outstr;
}


string getMessageFromTmpFile() {
    string text = "";
    if (std.file.exists(vkcliTmpMsgFile))
	  text = cast(string)std.file.read(vkcliTmpMsgFile);
    std.file.write(vkcliTmpMsgFile, "");
    return text;
}
