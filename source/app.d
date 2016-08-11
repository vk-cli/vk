import deimos.ncurses.ncurses;
import std.stdio, std.conv, std.string, std.array, std.algorithm;
import core.sys.posix.stdlib, core.time, core.stdc.locale; 
import ui, controller, vkapi, logic, cfg, utils, localization, vkversion;

public:

View!User friends;
View!Audio music;
View!Dialog dialogs;
Window window;
TabMenu tabMenu;

private:

string[string] config;
MainProvider api;

struct TabMenu {
  string[] tabs;
  int selected;
}

struct Window {
  int key, height, width,
      mainColor, secondColor,
      notifyCounter;
  bool sizeChanged, unicodeChars = true;
  string openedView, statusbarText;
}

void loadConfig() {
  config.load;
  if ("token" !in config) {
    config["token"] = get_token;
    config.save;
  }
  api = new MainProvider(config["token"]);
}

void init() {
  updateGcSignals;
  initdbm;
  setlocale(LC_CTYPE,"");
  localize;
  initscr;
  curs_set(0);
  color;

  loadConfig;
  noecho;

  friends = api.friendsList;
  music   = api.musicList;
  dialogs = api.dialogList;
  tabMenu.tabs = ["Dialogs", "Music", "Friends", "+", "+", "+", "+", "+", "+"];
}

void getWindowSize() {
  window.sizeChanged = (window.height != LINES || window.width != COLS) ? true : false;
  window.height = LINES;
  window.width = COLS;
}

bool isCurrentViewUpdated() {
  if (window.key != -1) return true;
  if (window.sizeChanged) return true;
  //if (notify) return true;
  switch (window.openedView) {
    case "Dialogs": return dialogs.info.isUpdated;
    case "Music":   return music.info.isUpdated;
    case "Friends": return friends.info.isUpdated;
    default: return false;
  }
}

void main(string[] args) {
  foreach(e; args) {
    if (e == "-v" || e == "-version") {
      ("vk-cli " ~ currentVersion).writeln;
      exit(0);
    }
  }
  init;
  scope(failure) endwin;

  while (!canFind(kg_esc, window.key)) {
    getWindowSize;
    getKey;

    window.mainColor = Colors.blue;
    window.secondColor = Colors.gray;

    if (isCurrentViewUpdated) {
      clearScr;
      statusbar;
      tabPanel;
      tabMenu.tabs[tabMenu.selected].open;
    }
  }

  Exit;
}
