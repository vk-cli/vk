
import std.stdio, std.conv, std.string, std.regex, std.array, std.datetime, std.random, core.time;
import std.exception, core.exception, std.process;
import std.net.curl, std.uri, std.json;
import std.range, std.algorithm;
import std.parallelism, std.concurrency, core.thread, core.sync.mutex;
import vkapi, logic, cfg, utils, localization;

string[string] config;

void main(string[] args) {
    updateGcSignals();
    localize();
    config = load();
    auto token = config["token"];

    initdbm();
    async = new Async();
    auto api = new VkApi(token);
    auto str = new Storage!User((o, c) => api.friendsGet(c, o));
    auto view = new View!User(str);

    for(int i; i < 5; ++i) {
        auto lc = view.getView(5, 228);
        while(lc.empty) Thread.sleep(dur!"msecs"(485));
        lc.each!(q => writeln(q.fullName));
        view.moveForward(i+1);
        writeln();
    }

    exit(0);
}