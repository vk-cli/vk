import  std.stdio, std.conv, std.string, core.thread,
        core.sys.posix.stdlib, core.time, std.array;

import deimos.ncurses.ncurses;
import ui, controller, vkapi, logic, cfg, utils, localization, vkversion;

string[string] config;
MainProvider api;

View!User friends;
View!Audio music;
View!Dialog dialogs;

void[] tabs;

void init() {
  updateGcSignals;
  initdbm;
  localize;

  //initscr;
  curs_set(0);
  noecho;

  config = load;
  api = new MainProvider(config["token"]);
  friends = api.friendsList;
}

void main(string[] args) {
  foreach(e; args) {
    if (e == "-v" || e == "-version") {
      writefln("vk-cli %s", currentVersion);
      exit(0);
    }
  }
  init;

  //auto castedvar = cast(View!User)var

  tabs = [friends, music, dialogs];
  writefln("%s", friends);
  while (friends.getView(30, 80).empty) Thread.sleep(dur!"msecs"(500));
  foreach (e; friends.getView(30, 80)) (e.fullName ~ "\n").print;

  getch;

  Exit;
}
