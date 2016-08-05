
import std.stdio, std.conv, std.string, std.regex, std.array, std.datetime, std.random, core.time;
import std.exception, core.exception, std.process;
import std.net.curl, std.uri, std.json;
import std.range, std.algorithm;
import std.parallelism, std.concurrency, core.thread, core.sync.mutex;
import vkapi, logic, cfg, utils, localization;

string[string] config;

void main(string[] args) {
    updateGcSignals();
	initdbm();
    localize();

    config = load();
    auto token = config["token"];

	auto api = new MainProvider(token);

	auto usersView = api.friendsList.getView(20, 80);

	while (usersView.empty) {
		writeln("...");
		Thread.sleep(dur!"msecs"(500));
	}

	foreach (e; usersView) {
		e.fullName.writeln();
	}

	auto usersInfo = api.getInfo(list.friends);
	writeln("== is users updated: " ~ usersInfo.isUpdated.to!string ~ " ==");

    exit(0);
}