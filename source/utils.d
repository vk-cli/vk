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

auto joinerBidirectional(RoR)(RoR r)
if (isBidirectionalRange!RoR && isBidirectionalRange!(ElementType!RoR))
{
    static struct Result
    {
    alias ResultType = typeof(this);
    private:
        RoR _items;
        ElementType!RoR _current;
        enum prepare =
        q{
            // Skip over empty subranges.
            if (_items.empty) return;
            /*while (_items.front.empty)
            {
                _items.popFront();
                if (_items.empty) return;
            }*/
            // We cannot export .save method unless we ensure subranges are not
            // consumed when a .save'd copy of ourselves is iterated over. So
            // we need to .save each subrange we traverse.
            static if (isForwardRange!RoR && isForwardRange!(ElementType!RoR))
                _current = _items.front.save;
            else
                _current = _items.front;
        };
    public:
        this(RoR r)
        {
            _items = r;
            //mixin(prepare); // _current should be initialized in place

            // Skip over empty subranges.
            /*while (!_items.empty && _items.front.empty)
                _items.popFront();*/

            if (_items.empty)
                _current = _current.init;   // set invalid state
            else
            {
                // We cannot export .save method unless we ensure subranges are not
                // consumed when a .save'd copy of ourselves is iterated over. So
                // we need to .save each subrange we traverse.
                static if (isForwardRange!RoR && isForwardRange!(ElementType!RoR))
                    _current = _items.front.save;
                else
                    _current = _items.front;
            }
        }
        static if (isInfinite!RoR)
        {
            enum bool empty = false;
        }
        else
        {
            @property auto empty()
            {
                return _items.empty;
            }
        }

        @property auto ref front()
        {
            assert(!empty);
            return _current.front;
        }
        void popFront()
        {
            assert(!_current.empty);
            _current.popFront();
            if (_current.empty)
            {
                assert(!_items.empty);
                _items.popFront();
                mixin(prepare);
            }
        }

        @property auto ref back()
        {
            assert(!empty);
            return _current.back;
        }
        void popBack()
        {
            assert(!_current.empty);
            _current.popBack();
            if(_current.empty)
            {
                assert(!_items.empty);
                _items.popBack();
                mixin(prepare);
            }
        }


        static if (isForwardRange!RoR && isForwardRange!(ElementType!RoR))
        {
            @property auto save()
            {
                Result copy = this;
                copy._items = _items.save;
                copy._current = _current.save;
                return copy;
            }
        }
    }
    return Result(r);
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

auto ror = ["ClCl", "u cant touch my pragmas", "substanceof eboshil zdes'"];
//pragma(msg, "isBidirectional TakeBackResult " ~ isBidirectionalRange!(TakeBackResult!string).stringof);
pragma(msg, "isBidirectional joinerBidirectional "
                    ~ isBidirectionalRange!((joinerBidirectional(ror)).ResultType).stringof);


