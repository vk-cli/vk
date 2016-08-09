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

struct Tab {
  string name;
  bool locked;
}

struct TabMenu {
  Tab[] tabs;
  byte selected;
}

struct Window {
  int key, height, width,
      mainColor, secondColor;
  bool sizeChanged;
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
  tabMenu.tabs = [Tab("Dialogs"),
                  Tab("Music"),
                  Tab("Friends"),
                  Tab("id_123"),
                  Tab("chat_321")
                 ];
}

void getWindowSize() {
  if (window.height != LINES || window.width != COLS) window.sizeChanged = true;
  else window.sizeChanged = false;
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
    timeout(100);
    getWindowSize;
    window.key = _getch;

    window.mainColor = Colors.blue;
    window.secondColor = Colors.gray;

    if (isCurrentViewUpdated) {
      clearScr;
      statusbar;
      tabView;
      tabMenu.selected = 2;
      tabMenu.tabs[tabMenu.selected].open;
    }
  }

  Exit;
}
