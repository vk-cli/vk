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

module logic;

import std.stdio, std.conv, std.string, std.regex, std.array, std.datetime, std.random, core.time;
import std.exception, core.exception, std.process;
import std.net.curl, std.uri, std.json;
import std.range, std.algorithm;
import std.parallelism, std.concurrency, core.thread, core.sync.mutex;
import utils, namecache, localization, vkapi;

const int defaultLoadCount = 100;

auto async = new Async();

class Async {
    alias taskfunc = void delegate();

    struct task {
        this(taskfunc f) {
            func = f;
            thread.start();
        }

        taskfunc func;
        auto thread = new Thread(
            () => func()
        );
    }

    struct taskqueue {
        this(taskfunc f) {
            add(f);
            thread.start();
        }

        void add(taskfunc f) {
            queue ~= f;
        }

        taskfunc[] queue;
        auto thread = new Thread( {
            while(true) {
                for(int i; i < queue.length; ++i) {
                    queue[i]();
                }
                while(queue.length == 0) sleep(300);
            }
        } );
    }

    task[string] singles;
    taskqueue[string] queues;

    const string
        q_loadChunk = "load_chunk";

    void single(string name, taskfunc f) {
        auto t = name in singles;
        if( (t && !t.thread.isRunning) || !t ) {
            singles[name] = task(f);
            dbm("async: thread started for " ~ name);
        }
        else {
            dbm("async: single " ~ name ~ " already running!");
        }
    }

    void queue(string name, taskfunc f) {
        auto q = name in queues;
        if(q) {
            q.add(f);
        }
        else {
            queues[name] = taskqueue(f);
            dbm("async: thread started for " ~ name ~ " queue");
        }
    }
}

class Chunk(T) {
    this(T[] obj, int off) {
        objects = obj;
        offset = off;
    }

    T[] objects;
    int offset;
    int count() { return objects.length; }
    int end() { return offset + count(); }
}

class MergedChunks(T) {
    alias typedchunk = Chunk!T;

    private {
        Storage!T meta;
        typedchunk last;
        bool lastempty;
        size_t iter;
        size_t localiter;
        size_t max;
    }

    this(Storage!T s, int pos, int count) {
        meta = s;
        iter = pos;
        max = count;
    }

    private void findchunk() {
        auto query = meta.store
            .retro
            .filter!(q => q.offset <= iter);
        if(!query.empty) {
            last = query.front();
            lastempty = false;
            localiter = 0;
        }
        else {
            lastempty = true;
            meta.load(iter, defaultLoadCount);
        }
    }

    void popFront() {
        ++iter;
        ++localiter;
    }

    T front() {
        if(empty()) return null; // todo check need exception
        return last[localiter];
    }

    bool empty() {
        if(iter >= max) return true;
        if(last is null || localiter >= last.count || lastempty) {
            findchunk();
        }
        return lastempty;
    }

    auto moveFront() {
        return front();
    }

}

unittest {
    assert(Chunk!(int).init is null);
    assert(isInputRange!(MergedChunks!int));
}

class Storage(T) {
    alias typedchunk = Chunk!T;
    alias typecoll = T[];
    alias loader = typecoll delegate(int offset, int count);

    private {
        loader loadfunc;
        int asyncId;
        string asyncLoaderKey;
    }

    typedchunk[] store;

    this(loader loadf) {
        loadfunc = loadf;
        asyncId = genId();
        asyncLoaderKey = async.q_loadChunk ~ " " ~ asyncId.to!string;
    }

    private void loadSync(int pos, int count) {
        auto freshChunk = loadfunc(pos, count);
        c ~= Chunk(freshChunk, offset);
    }

    void load(int pos, int count) {
        async.queue(asyncLoaderKey, () => loadSync(pos, count));
    }

    auto get(int pos, int count) {
        return new MergedChunks(this, pos, count);
    }
}

abstract class SuperView(T) {
    T[] getView(int height, int width);
    void moveForward(int step = 1);
    void moveBackward(int step = 1);
}

class View(T) : SuperView!T {
    alias storage = Storage!T;

    private {
        storage buff;
        size_t position;
    }

    this(storage st) {
        buff = st;
    }

    override auto getView(int height, int width) {
        return buff.get(position, height);
    }

    override moveForward(int step = 1) {
        position += step;
        // todo preload
    }

    override moveBackward(int step = 1) {
        position -= step;
        if(position < 0) position = 0;
    }
}

