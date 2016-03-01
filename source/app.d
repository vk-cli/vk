#!/usr/bin/rdmd -L-lncursesw

import deimos.ncurses.ncurses;
import core.stdc.locale, core.thread, core.stdc.stdlib:exit;
import std.string, std.stdio, std.process,
       std.conv, std.array, std.encoding,
       std.range, std.algorithm;
import vkapi, cfg, localization, utils, namecache;

// INIT VARS
enum Sections { left, right }
enum Colors { white, red, green, yellow, blue, pink, mint, gray }
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
    namecolor = Colors.white,
    textcolor = Colors.gray,
    counter, active, section,
    last_active, offset, key,
    scrollOffset, msgDrawSetting;
  string
    debugText;
  bool
    dialogsOpened;
}

struct ListElement {
  string name, text;
  void function(ref ListElement) callback;
  ListElement[] function() getter;
  bool flag;
}

void relocale() {
  win.menu[0].name = "m_friends".getLocal;
  win.menu[1].name = "m_conversations".getLocal;
  win.menu[2].name = "m_music".getLocal;
  win.menu[3].name = "m_settings".getLocal;
  win.menu[4].name = "m_exit".getLocal;
}

void parse(ref string[string] storage) {
  if ("main_color" in storage) win.namecolor = storage["main_color"].to!int;
  if ("second_color" in storage) win.textcolor = storage["second_color"].to!int;
  if ("message_setting" in storage) win.msgDrawSetting = storage["message_setting"].to!int;
  if ("lang" in storage) if (storage["lang"] == "1") swapLang;
  relocale;
}

void update(ref string[string] storage) {
  storage["lang"] = getLang;
  storage["main_color"] = win.namecolor.to!string;
  storage["second_color"] = win.textcolor.to!string;
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
  for (short i = 0; i < Colors.max; i++) {
    init_pair(i, i, -1);
  }
  for (short i = 1; i < Colors.max+1; i++) {
    init_pair((Colors.max+1+i).to!short, i, -1.to!short);
  }
  init_pair(Colors.max, 0, -1);
  init_pair(Colors.max+1, -1, -1);
  init_pair(Colors.max*2+1, 0, -1);
}

void selected(string name) {
  attron(A_REVERSE);
  name.regular;
  attroff(A_REVERSE);
}

void regular(string name) {
  attron(A_BOLD);
  attron(COLOR_PAIR(win.namecolor));
  name.print;
  attroff(A_BOLD);
  attroff(COLOR_PAIR(win.namecolor));
}

void secondColor(string name) {
  attron(A_BOLD);
  attron(COLOR_PAIR(win.textcolor+Colors.max+1));
  name.print;
  attroff(A_BOLD);
  attroff(COLOR_PAIR(win.textcolor+Colors.max+1));
}

void graySelected(string name) {
  attron(A_REVERSE);
  attron(A_BOLD);
  attron(COLOR_PAIR(win.namecolor+Colors.max+1));
  name.print;
  attroff(A_BOLD);
  attroff(COLOR_PAIR(win.namecolor+Colors.max+1));
  attroff(A_REVERSE);
}

void white(string name) {
  attron(A_BOLD);
  attron(COLOR_PAIR(0));
  name.print;
  attroff(A_BOLD);
  attroff(COLOR_PAIR(0));
}

void statusbar() {
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
    win.offset = le.name.walkLength.to!int > win.offset ? le.name.walkLength.to!int : win.offset;
  }
  win.offset++;
}

void drawMenu() {
  foreach(i, le; win.menu) {
    auto space = (le.name.walkLength < win.offset) ? " ".replicate(win.offset-le.name.walkLength) : "";
    auto name = le.name ~ space ~ "\n";
    if (win.section == Sections.left) {
      i == win.active ? name.selected : name.regular;
    } else {
      i == win.last_active ? name.selected : name.regular;
    }
  }
}

string cut(ulong i, ListElement e) {
  string tempText;
  int cut;
  tempText = e.text;
  cut = (COLS-win.offset-win.mbody[i].name.walkLength-1).to!int;
  if (e.text.walkLength > cut) {
    tempText = tempText[0..cut];
  }
  return tempText;
}

void bodyToBuffer() {
  if (win.mbody.length != 0) {
    if (LINES-2 < win.mbody.length) win.buffer = win.mbody[0..LINES-2].dup;
    else {
      if (win.dialogsOpened) win.mbody = GetDialogs;
      win.buffer = win.mbody.dup;
    }
    foreach(i, e; win.buffer) {
      if (e.name.walkLength.to!int + win.offset+1 > COLS) {
        win.buffer[i].name = e.name[0..COLS-win.offset-4];
      } else win.buffer[i].name ~= " ".replicate(COLS - e.name.walkLength - win.offset-1);
    }
  }
}

void drawDialogsList() {
  foreach(i, e; win.buffer) {
    wmove(stdscr, 2+i.to!int, win.offset+1);
    if (i.to!int == win.active-win.scrollOffset) {
      e.name.selected;
      wmove(stdscr, 2+i.to!int, win.offset+win.mbody[i].name.walkLength.to!int+1);
      cut(i, e).graySelected;
    } else {
      switch (win.msgDrawSetting) {
        case DrawSetting.allMessages:
          allMessages(e, i); break;
        case DrawSetting.onlySelectedMessage:
          onlySelectedMessage(e, i); break;
        case DrawSetting.onlySelectedMessageAndUnread:
          onlySelectedMessageAndUnread(e, i); break;
        default: break;
      }
    }
  }
}

void allMessages(ListElement e, ulong i) {
  e.flag ? e.name.regular : e.name.secondColor;
  wmove(stdscr, 2+i.to!int, win.offset+win.mbody[i].name.walkLength.to!int+1);
  cut(i, e).white;
}

void onlySelectedMessage(ListElement e, ulong i) {
  e.flag ? e.name.regular : e.name.secondColor;
}

void onlySelectedMessageAndUnread(ListElement e, ulong i) {
  if (e.name[0..3] == "⚫") {
    e.flag ? e.name.regular : e.name.secondColor;
    wmove(stdscr, 2+i.to!int, win.offset+win.mbody[i].name.walkLength.to!int+1);
    cut(i, e).white;
  } else e.flag ? e.name.regular : e.name.secondColor;
}

void drawBuffer() {
  if (win.dialogsOpened) drawDialogsList;
  else {
    foreach(i, e; win.buffer) {
      wmove(stdscr, 2+i.to!int, win.offset+1);
      i.to!int == win.active ? e.name.selected : e.name.regular;
    }
  }
}

void jumpToEnd() {
  if (win.dialogsOpened) {
    win.active = api.getDialogsCount-1;
    win.scrollOffset = api.getDialogsCount-LINES+2;
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
  else if (win.key == k_home && api.isScrollAllowed && win.section == Sections.right) { win.active = 0; win.scrollOffset = 0; }
  else if (win.key == k_end && api.isScrollAllowed && win.section == Sections.right) jumpToEnd;
  else if (win.key == k_pagedown && api.isScrollAllowed && win.section == Sections.right) {
    win.scrollOffset += LINES/2;
    win.active += LINES/2;
    if (win.active > win.buffer.length) win.active = win.scrollOffset = (win.buffer.length-1).to!int;
  }
  else if (win.key == k_pageup && api.isScrollAllowed && win.section == Sections.right) {
    win.scrollOffset -= LINES/2;
    win.active -= LINES/2;
    if (win.active < 0) win.active = win.scrollOffset = 0;
    if (win.scrollOffset < 0) win.scrollOffset = 0;
  }
  checkBounds;
}

void checkBounds() {
  if (win.dialogsOpened && api.getDialogsCount > 0 && win.active > api.getDialogsCount-1) jumpToEnd;
}

void downEvent() {
  if (win.section == Sections.left) win.active >= win.menu.length-1 ? win.active = 0 : win.active++;
  else {
    if (win.dialogsOpened) {
      if (win.active-win.scrollOffset == LINES-3) win.scrollOffset++;
      if (api.isScrollAllowed) win.active++;
    } else win.active >= win.buffer.length-1 ? win.active = 0 : win.active++;
  }
}

void upEvent() {
  if (win.section == Sections.left) win.active == 0 ? win.active = win.menu.length.to!int-1 : win.active--;
  else {
    if (win.dialogsOpened && api.isScrollAllowed) {
      win.scrollOffset > 0 ? win.scrollOffset -= 1 : win.scrollOffset += 0;
      win.active == 0 ? win.active += 0 : win.active--;
    } else win.active == 0 ? win.active = win.buffer.length.to!int-1 : win.active--;
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
    win.scrollOffset = 0;
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

void changeMainColor(ref ListElement le) {
  win.namecolor == Colors.max ? win.namecolor = 0 : win.namecolor++;
  le.name = "main_color".getLocal ~ ("color"~win.namecolor.to!string).getLocal;
}

void changeSecondColor(ref ListElement le) {
  win.textcolor == Colors.max ? win.textcolor = 0 : win.textcolor++;
  le.name = "second_color".getLocal ~ ("color"~win.textcolor.to!string).getLocal;
}

void changeMsgSetting(ref ListElement le) {
  win.msgDrawSetting = win.msgDrawSetting != 2 ? win.msgDrawSetting+1 : 0;
  le.name = "msg_setting_info".getLocal ~ ("msg_setting"~win.msgDrawSetting.to!string).getLocal;
}

ListElement[] GenerateSettings() {
  return [
    ListElement(center("display_settings".getLocal, COLS-16, ' ')),
    ListElement("main_color".getLocal ~ ("color"~win.namecolor.to!string).getLocal, "", &changeMainColor),
    ListElement("second_color".getLocal ~ ("color"~win.textcolor.to!string).getLocal, "", &changeSecondColor),
    ListElement("lang".getLocal, "", &changeLang, null),
    ListElement(center("convers_settings".getLocal, COLS-16, ' ')),
    ListElement("msg_setting_info".getLocal ~ ("msg_setting"~win.msgDrawSetting.to!string).getLocal, "", &changeMsgSetting),
  ];
}

ListElement[] GetDialogs() {
  ListElement[] listDialogs;
  auto dialogs = api.getBufferedDialogs(LINES-2, win.scrollOffset);
  string newMsg;
  foreach(e; dialogs) {
    newMsg = e.unread ? "⚫ " : "  ";
    listDialogs ~= ListElement(newMsg ~ e.name, ": " ~ e.lastMessage.replace("\n", " "), null, null, e.online);
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
    int i = 0;
    const int step = 30;
    while(true) {
        int huj;
        auto conv = api.messagesGetDialogs(step, i, huj);
        //if(conv[conv.length-1].lastMessage != getLocal("loading")) i += step;
        foreach (d; conv) {
            writeln("d " ~ d.name ~ " " ~ d.lastMessage ~ (d.online ? " online" : ""));
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
    win.counter = api.messagesCounter;
    statusbar;
    drawMenu;
    bodyToBuffer;
    drawBuffer;
    refresh;
    controller;
  }

  storage.update;
  storage.save;
  dbmclose;
  endwin;
  exit(0);
}
