#!/usr/bin/rdmd -L-lncursesw

import deimos.ncurses.ncurses;
import core.stdc.locale;
import std.string, std.stdio, std.process,
       std.conv, std.array, std.encoding,
       std.range, std.algorithm, core.thread,
       core.stdc.stdlib:exit;
import vkapi, cfg, localization, utils, namecache;

// INIT VARS
enum Sections { left, right }
enum Colors { white, red, green, yellow, blue, pink, mint }
enum DrawSetting { allMessages, onlySelectedMessage, onlySelectedMessageAndUnread }
Win win;
VKapi api;

const int 
  // func keys
  k_pageup   = 53,
  k_pagedown = 54,
  k_home     = 49,
  k_end      = 52,
  // keys
  k_q      = 113,
  k_enter  = 10,
  k_up     = 65,
  k_down   = 66,
  k_left   = 68,
  k_right  = 67,
  k_w      = 119,
  k_s      = 115,
  k_a      = 97,
  k_d      = 100,
  k_rus_w  = 134,
  k_rus_a  = 132,
  k_rus_s  = 139,
  k_rus_d  = 178,
  k_k      = 107,
  k_j      = 106,
  k_h      = 104,
  k_l      = 108,
  k_rus_h  = 128,
  k_rus_j  = 190,
  k_rus_k  = 187,
  k_rus_l  = 180;

const int[] 
  // key groups
  kg_esc   = [k_q],
  kg_up    = [k_up, k_w, k_k, k_rus_w, k_rus_k],
  kg_down  = [k_down, k_s, k_j, k_rus_s, k_rus_j],
  kg_left  = [k_left, k_a, k_h, k_rus_a, k_rus_h],
  kg_right = [k_right, k_d, k_l, k_rus_d, k_rus_l, k_enter];

struct Win {
  ListElement[]
  menu = [
    {},
    {callback:&open, getter: &GetDialogs},
    {},
    {callback:&open, getter: &GenerateSettings},
    {callback:&exit}
  ], 
  buffer, mbody;
  int
    textcolor = Colors.white,
    counter, active, section,
    last_active, offset, key,
    scrollOffset, msgDrawSetting;
  string
    debugText;
  bool
    dialogsOpened;
}

struct ListElement {
  string text = "", link;
  void function(ref ListElement) callback;
  ListElement[] function() getter;
}

void relocale() {
  win.menu[0].text = "m_friends".getLocal;
  win.menu[1].text = "m_conversations".getLocal;
  win.menu[2].text = "m_music".getLocal;
  win.menu[3].text = "m_settings".getLocal;
  win.menu[4].text = "m_exit".getLocal;
}

void parse(ref string[string] storage) {
  if ("color" in storage) win.textcolor = storage["color"].to!int;
  if ("message_setting" in storage) win.msgDrawSetting = storage["message_setting"].to!int;
  if ("lang" in storage) if (storage["lang"] == "1") swapLang;
  relocale;
}

void update(ref string[string] storage) {
  storage["lang"] = getLang;
  storage["color"] = win.textcolor.to!string;
  storage["message_setting"] = win.msgDrawSetting.to!string;
}

void init() {
  setlocale(LC_CTYPE,"");
  localize;
  relocale;
  initscr;
  setOffset;
}

void print(string s) {
  s.toStringz.printw;
}

void print(int i) {
  i.to!string.toStringz.printw;
}

VKapi get_token(ref string[string] storage) {
  char token;
  "e_input_token".getLocal.print;
  spawnShell(`xdg-open "http://oauth.vk.com/authorize?client_id=5110243&scope=friends,wall,messages,audio,offline&redirect_uri=blank.html&display=popup&response_type=token" >> /dev/null`);
  echo;
  getstr(&token);
  noecho;
  auto strtoken = (cast(char*)&token).to!string;
  storage["token"] = strtoken;
  return new VKapi(strtoken);
}

void color() {
  if (!has_colors) {
    endwin;
    writeln("Your terminal does not support color");
  }
  start_color;
  use_default_colors;
  for (short i = 1; i < 7; i++) {
    init_pair(i, i, -1);
  }
  for (short i = 1; i < 7; i++) {
    init_pair((7+i).to!short, i, 0.to!short);
  }
  init_pair(7, -1, 0);
}

void selected(string text) {
  attron(A_REVERSE);
  text.regular;
  attroff(A_REVERSE);
}

void regular(string text) {
  attron(A_BOLD);
  attron(COLOR_PAIR(win.textcolor));
  text.print;
  attroff(A_BOLD);
  attroff(COLOR_PAIR(win.textcolor));
}

void gray(string text) {
  attron(A_BOLD);
  attron(COLOR_PAIR(0));
  text.print;
  attroff(A_BOLD);
  attroff(COLOR_PAIR(0));
}

void graySelected(string text) {
  attron(A_REVERSE);
  attron(A_BOLD);
  attron(COLOR_PAIR(win.textcolor+7));
  text.print;
  attroff(A_BOLD);
  attroff(COLOR_PAIR(win.textcolor+7));
  attroff(A_REVERSE);
}

void statusbar(VKapi api) {
  if (win.debugText == "") {
    string notify = " " ~ win.counter.to!string ~ " ✉ ";
    notify.selected;
    center(api.me.first_name~" "~api.me.last_name, COLS+2-notify.length, ' ').selected;
    "\n".print;
  } else {
    center(win.debugText, COLS, ' ').selected;
    "\n".print;
  }
}

void Debug(string s = "") {
  win.debugText = s;
}

void setOffset() {
  foreach(le; win.menu) {
    win.offset = le.text.walkLength.to!int > win.offset ? le.text.walkLength.to!int : win.offset;
  }
  win.offset++;
}

void drawMenu() {
  foreach(i, le; win.menu) {
    auto space = (le.text.walkLength < win.offset) ? " ".replicate(win.offset-le.text.walkLength) : "";
    auto text = le.text ~ space ~ "\n";
    if (win.section == Sections.left) {
      i == win.active ? text.selected : text.regular;
    } else {
      i == win.last_active ? text.selected : text.regular;
    }
  }
}

string cut(ulong i, ListElement e) {
  string tempText;
  int cut;
  tempText = e.link;
  cut = (COLS-win.offset-win.mbody[i].text.walkLength-1).to!int;
  if (e.link.walkLength > cut) {
    tempText = tempText[0..cut];
  }
  return tempText;
}

void bodyToBuffer() {
  if (win.mbody.length != 0) {
    if (LINES-2 < win.mbody.length) win.buffer = win.mbody[0..LINES-2].dup;
    else {
      win.buffer = win.mbody.dup;
      if (win.dialogsOpened) {
        win.mbody = GetDialogs;
        win.buffer = win.mbody.dup;
      }
    }
    foreach(i, e; win.buffer) {
      if (e.text.walkLength.to!int + win.offset+1 > COLS) {
        win.buffer[i].text = e.text[0..COLS-win.offset-4];
      } else win.buffer[i].text ~= " ".replicate(COLS - e.text.walkLength - win.offset-1);
    }
  }
}

void allMessages() {
  foreach(i, e; win.buffer) {
    wmove(stdscr, 2+i.to!int, win.offset+1);
    if (i.to!int == win.active-win.scrollOffset) {
      e.text.selected;
      wmove(stdscr, 2+i.to!int, win.offset+win.mbody[i].text.walkLength.to!int+1);
      cut(i, e).graySelected;
    } else {
      e.text.regular;
      wmove(stdscr, 2+i.to!int, win.offset+win.mbody[i].text.walkLength.to!int+1);
      cut(i, e).gray;
    }
  }
}

void onlySelectedMessage() {
  foreach(i, e; win.buffer) {
    wmove(stdscr, 2+i.to!int, win.offset+1);
    if (i.to!int == win.active-win.scrollOffset) {
      e.text.selected;
      wmove(stdscr, 2+i.to!int, win.offset+win.mbody[i].text.walkLength.to!int+1);
      cut(i, e).graySelected;
    } else {
      e.text.regular;
    }
  }
}

void onlySelectedMessageAndUnread() {
  foreach(i, e; win.buffer) {
    wmove(stdscr, 2+i.to!int, win.offset+1);
    if (i.to!int == win.active-win.scrollOffset) {
      e.text.selected;
      wmove(stdscr, 2+i.to!int, win.offset+win.mbody[i].text.walkLength.to!int+1);
      cut(i, e).graySelected;
    } else {
      if (e.text[0..3] == "⚫") {
        e.text.regular;
        wmove(stdscr, 2+i.to!int, win.offset+win.mbody[i].text.walkLength.to!int+1);
        cut(i, e).gray;
      } else e.text.regular;
    }
  }
}

void drawBuffer() {
  bodyToBuffer;
  if (win.dialogsOpened) {
    switch (win.msgDrawSetting) {
      case DrawSetting.allMessages: allMessages; break;
      case DrawSetting.onlySelectedMessage: onlySelectedMessage; break;
      case DrawSetting.onlySelectedMessageAndUnread: onlySelectedMessageAndUnread; break;
      default: break;
    }
  } else {
    foreach(i, e; win.buffer) {
      wmove(stdscr, 2+i.to!int, win.offset+1);
      i.to!int == win.active ? e.text.selected : e.text.regular;
    }
  }
}

void controller() {
  while (true) {
    timeout(1050);
    auto ch = getch;
    win.key = ch;
    if(ch != -1) break;
    if(api.isSomethingUpdated) break;
  }
  win.key.print;
  if (canFind(kg_down, win.key)) downEvent;
  else if (canFind(kg_up, win.key)) upEvent;
  else if (canFind(kg_right, win.key)) selectEvent;
  else if (canFind(kg_left, win.key)) backEvent;
  else if (win.key == k_home) {
    win.active = 0;
    win.scrollOffset = 0;
  }
  else if (win.key == k_end) {
    win.active = win.mbody.length.to!int;
    win.scrollOffset = win.mbody.length.to!int;
  }
  else if (win.key == k_pagedown) {
    win.scrollOffset += (LINES-2)/2;
    win.active += (LINES-2)/2;
  }
  else if (win.key == k_pageup) {
    (win.scrollOffset - (LINES-2)/2) > 0 ? win.scrollOffset -= (LINES-2)/2 : win.scrollOffset = 0;
    (win.active - (LINES-2)/2) > 0 ? win.active -= (LINES-2)/2 : win.active = 0;
  }
}

void downEvent() {
  if (win.section == Sections.left) {
    win.active >= win.menu.length-1 ? win.active = 0 : win.active++;
  } else {
    if (win.dialogsOpened) {
      if (win.active-win.scrollOffset == LINES-3) {
        win.scrollOffset += 1;
        win.mbody = GetDialogs;
      }
      win.active++;
    } else {
      win.active >= win.buffer.length-1 ? win.active = 0 : win.active++;
    }
  }
}

void upEvent() {
  if (win.section == Sections.left) {
    win.active == 0 ? win.active = win.menu.length.to!int-1 : win.active--;
  } else {
    if (win.dialogsOpened) {
      win.scrollOffset > 0 ? win.scrollOffset -= 1 : win.scrollOffset += 0;
      win.active == 0 ? win.active += 0 : win.active--;
    } else {   
      win.active == 0 ? win.active = win.buffer.length.to!int-1 : win.active--;
    }
  }
}

void selectEvent() {
  if (win.section == Sections.left) {
    if (win.menu[win.active].callback) win.menu[win.active].callback(win.menu[win.active]);
    win.last_active = win.active;
    win.active = 0;
    win.section = Sections.right;
  } else {
    if (win.mbody[win.active].callback) win.mbody[win.active].callback(win.mbody[win.active]);
  }
}

void backEvent() {
  if (win.section == Sections.right) {
    if (win.dialogsOpened) win.dialogsOpened = false;
    win.active = win.last_active;
    win.section = Sections.left;
    win.mbody = new ListElement[0];
    win.buffer = new ListElement[0];
  }
}

void exit(ref ListElement le) {
  win.key = k_q;
}

void open(ref ListElement le) {
  win.mbody = le.getter();
}

void changeLang(ref ListElement le) {
  swapLang;
  win.mbody = GenerateSettings;
  relocale;
}

void changeColor(ref ListElement le) {
  win.textcolor == 6 ? win.textcolor = 0 : win.textcolor++;
  le.text = "color".getLocal ~ ("color"~win.textcolor.to!string).getLocal;
}

void changeMsgSetting(ref ListElement le) {
  win.msgDrawSetting = win.msgDrawSetting != 2 ? win.msgDrawSetting+1 : 0;
  le.text = "msg_setting_info".getLocal ~ ("msg_setting"~win.msgDrawSetting.to!string).getLocal;
}

ListElement[] GenerateSettings() {
  return [
    ListElement(center("display_settings".getLocal, COLS-16, ' '), "", null, null),
    ListElement("color".getLocal ~ ("color"~win.textcolor.to!string).getLocal, "", &changeColor, null),
    ListElement("lang".getLocal, "", &changeLang, null),
    ListElement(center("convers_settings".getLocal, COLS-16, ' '), "", null, null),
    ListElement("msg_setting_info".getLocal ~ ("msg_setting"~win.msgDrawSetting.to!string).getLocal, "", &changeMsgSetting, null),
  ];
}

ListElement[] GetDialogs() {
  ListElement[] listDialogs;
  auto dialogs = api.getBufferedDialogs(LINES-2, win.scrollOffset);
  string tempName;
  foreach(e; dialogs) {
    tempName = e.unread ? "⚫ " : "  ";
    listDialogs ~= ListElement(tempName ~ e.name, ": " ~ e.lastMessage.replace("\n", " "));
  }
  win.dialogsOpened = true;
  return listDialogs;
}

void test() {
    //initFileDbm();
    localize();
    auto storage = load;
    if("token" !in storage) {
        writeln("cyka");
        return;
    }
    auto api = new VKapi(storage["token"]);
    if(!api.isTokenValid) {
        writeln("bad token");
        return;
    }
    //api.asyncLongpoll();
    //readln();
    while(true) {
        auto conv = api.getBufferedDialogs(5, 0);
        foreach (d; conv) {
            writeln("d " ~ d.name ~ " " ~ d.lastMessage);
        }
        readln();
    }
    //dbm("dbuf: " ~ api.pb.alldialogs.length.to!string);
    //nc.dbmAll();
    //auto fr = api.friendsGet();
    //foreach(f; fr) dbm(f.first_name ~ " " ~ f.last_name ~ " " ~ (f.online ? "!" : ""));

    //auto aud = api.audioGet(0, 0, 10);
    //foreach(a; aud) dbm(a.artist ~ " - " ~ a.title ~ "  " ~ a.duration_str);

    /+auto allsh = api.messagesGetHistory(convStartId+23, 25, 0, -1, false);
    foreach(ww; allsh) {
        writeln(ww.author_name ~ " " ~ ww.time_str);
        foreach(ml; ww.body_lines) writeln(ml);
        writeln("maxdep: " ~ ww.fwd_depth.to!string);
        writeln(digTest(ww.fwd));
    }+/

    //readln();
    //ticker();
}

string digTest(vkFwdMessage[] huj) {
    string lel = "";
    string pref = "| ";
    foreach(h; huj) {
        lel ~= pref ~ h.author_name ~ " " ~ h.time_str ~ "\n";
        foreach(s; h.body_lines) lel ~= pref ~ s ~ "\n";
        auto fw = digTest(h.fwd);
        foreach(fs; fw.split("\n")) lel ~= pref ~ fs ~ "\n";
    }
    return lel;
}

void main(string[] args) {
  //test;
  init;
  color;
  curs_set(0);
  noecho;
  scope(exit)    endwin;
  scope(failure) endwin;

  auto storage = load;
  storage.parse;

  api = "token" in storage ? new VKapi(storage["token"]) : storage.get_token;
  while (!api.isTokenValid) {
    "e_wrong_token".getLocal.print;
    api = storage.get_token;
  }
  api.asyncLongpoll();

  while (!canFind(kg_esc, win.key)) {
    clear;
    win.counter = api.messagesCounter();
    api.statusbar;
    drawMenu;
    drawBuffer;
    refresh;
    controller;
  }

  storage.update;
  storage.save;
  dbmclose();
  endwin;
  exit(0);
}
