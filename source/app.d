#!/usr/bin/rdmd -L-lncursesw

import deimos.ncurses.ncurses;
import core.stdc.locale;
import std.string, std.stdio, std.process,
       std.conv, std.array, std.encoding,
       std.range;
import vkapi, cfg, localization;

// INIT VARS
enum Sections { left, right }
Win win;

struct Win {
  ListElement[] menu = [
                     {"Friends"},
                     {"Conversations"},
                     {"Music"},
                     {"Settings"}];
  int 
    textcolor = Colors.mint,
    counter, active, section,
    last_active;
  string
    title;
  int
    key;
}

struct ListElement {
  string text, link;
  int callback;
  int getter;
}

void relocale() {
    win.menu[0].text = "m_friends".getLocal;
    win.menu[1].text = "m_conversations".getLocal;
    win.menu[2].text = "m_music".getLocal;
    win.menu[3].text = "m_settings".getLocal;
}

void init() {
  setlocale(LC_CTYPE,"");
  localize();
  setLang(EN);
  relocale();
  initscr;
}

void print(string s) {
  s.toStringz.printw;
}

VKapi get_token(ref string[string] storage) {
  char token;
  "Insert your access token here: ".print;
  spawnShell(`xdg-open "http://oauth.vk.com/authorize?client_id=5110243&scope=friends,wall,messages,audio,offline&redirect_uri=blank.html&display=popup&response_type=token" >> /dev/null`);
  getstr(&token);
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
}

enum Colors { white, red, green, yellow, blue, pink, mint }

void selected(string text) {
  attron(A_REVERSE);
  regular(text);
  attroff(A_REVERSE);
}

void regular(string text) {
  attron(A_BOLD);
  attron(COLOR_PAIR(win.textcolor));
  text.print;
  attroff(A_BOLD);
  attroff(COLOR_PAIR(win.textcolor));
}

void statusbar(VKapi api) {
  string notify = " " ~ win.counter.to!string ~ " ✉ ";
  notify.selected;
  center(api.me.first_name~" "~api.me.last_name, COLS+2-notify.length, ' ').selected;
  "\n".print;
  win.title.print;
}

void draw(ListElement[] menu) {
  foreach(i, le; menu) {
    immutable auto space = " ".replicate(COLS/8 - le.text.walkLength);
    immutable auto text = le.text ~ space ~ "\n";
    if (win.section == Sections.left) {
      i == win.active ? text.selected : text.regular;
    } else {
      i == win.last_active ? text.selected : text.regular;
    }
  }
}

void test() {
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
    api.startLongpoll();
}

void main(string[] args) {
  //test();
  init;
  color;
  curs_set(0);
  noecho;
  //cbreak;
  scope(exit)    endwin;
  scope(failure) endwin;

  auto storage = load;
  auto api = "token" in storage ? new VKapi(storage["token"]) : storage.get_token;
  while (!api.isTokenValid) {
    "Wrong token, try again".print;
    api = storage.get_token;
  }
  
  while (win.key != 10) {
    //clear;
    api.statusbar;
    win.menu.draw;
    refresh;
    win.key = getch;
    win.key.to!string.print;
  }

  storage.save;
}
