import deimos.ncurses.ncurses;
import std.stdio, std.conv, std.string, std.array;
import core.sys.posix.stdlib, core.time; 
import ui, controller, vkapi, logic, cfg, utils, localization, vkversion;

public:

View!User friends;
View!Audio music;
View!Dialog dialogs;
Window window;

private:

string[string] config;
TabMenu tabMenu;
MainProvider api;

struct TabMenu {
  string[] tabs;
  byte selected;
}

struct Window {
  int key, height, width;
  bool sizeChanged;
  string openedView;
}

void init() {
  updateGcSignals;
  initdbm;
  localize;

  initscr;
  curs_set(0);
  noecho;

  config = load;
  api = new MainProvider(config["token"]);

  friends = api.friendsList;
  music   = api.musicList;
  dialogs = api.dialogList;
  tabMenu.tabs = ["dialogs", "music", "friends", "id_123", "chat_321"];
}

void getWindowSize() {
  if (window.height != LINES-3 || window.width != COLS) window.sizeChanged = true;
  else window.sizeChanged = false;
  window.height = LINES-3;
  window.width = COLS;
}

bool isCurrentViewUpdated() {
  if (window.key != -1) return true;
  if (window.sizeChanged) return true;
  final switch (window.openedView) {
    case "dialogs": return dialogs.info.isUpdated;
    case "music":   return music.info.isUpdated;
    case "friends": return friends.info.isUpdated;
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

  while (window.key != 27) {
    timeout(100);
    getWindowSize;
    window.key = _getch;

    if (isCurrentViewUpdated) {
      clearScr;
      tabMenu.selected = 2;
      tabMenu.tabs[tabMenu.selected].open;
    }
  }

  Exit;
}
