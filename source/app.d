import  std.stdio, std.conv, std.string, std.regex, std.array, std.random,
        std.datetime, core.time,
        std.exception, core.exception, std.process,
        std.net.curl, std.uri, std.json,
        std.range, std.algorithm,
        std.parallelism, std.concurrency, core.thread, core.sync.mutex;

import deimos.ncurses.ncurses;
import ui, controller, vkapi, logic, cfg, utils, localization, vkversion;

string[string] config;

void init() {
  updateGcSignals;
  initdbm;
  localize;
  initscr;
  curs_set(0);
  noecho;
  config = load;
}

void Exit(string msg = "") {
  endwin;
  if (msg != "") {
    string
      boldRed   = "\033[31m\x1b[1m",
      boldWhite = "\033[39m\x1b[1m",
      resetAttr = "\x1b[0m";
    (boldRed ~ "Error: " ~ boldWhite ~ msg ~ resetAttr).writeln;
  }
  exit(0);
}

void main(string[] args) {
  foreach(e; args) {
    if (e == "-v" || e == "-version") {
      writefln("vk-cli %s", currentVersion);
      exit(0);
    }
  }
  init;

  auto api = new MainProvider(config["token"]);

  auto usersView = api.friendsList.getView(30, 80);
  while (usersView.empty) Thread.sleep(dur!"msecs"(500));
  foreach (e; usersView) (e.fullName ~ "\n").print;

  auto usersInfo = api.getInfo(list.friends);
  print("[ users are updated: " ~ usersInfo.isUpdated.to!string ~ " ]");

  getch;

  Exit("kakaya-to ebola slomalas'");
}
