#!/usr/bin/rdmd -L-lncursesw

import deimos.ncurses.ncurses;
import std.string, std.stdio, std.process,
       std.conv, std.array, std.encoding,
       std.range;
import core.stdc.locale;
import vkapi, cfg;

// INIT VARS
enum Sections { left, right }

int 
  textcolor = Colors.mint,
  counter, active, section,
  last_active, key;
string
  title;

struct ListElement {
  string text, link;
  int callback;
  int getter;
}

void init() {
  setlocale(LC_CTYPE,"");
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
  attron(COLOR_PAIR(textcolor));
  text.print;
  attroff(A_BOLD);
  attroff(COLOR_PAIR(textcolor));
}

void statusbar(VKapi api) {
  string notify = " " ~ counter.to!string ~ " ✉ ";
  notify.selected;
  center(api.me.first_name~" "~api.me.last_name, COLS+2-notify.length, ' ').selected;
  "\n".print;
}

void draw(ListElement[] menu) {
  foreach(i, le; menu) {
    const space = " ".replicate(COLS/8 - le.text.walkLength);
    const text = le.text ~ space ~ "\n";
    if (section == Sections.left) {
      i == active ? text.selected : text.regular;
    } else {
      i == last_active ? text.selected : text.regular;
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
  ListElement[] menu = [
    {"Friends"},
    {"Messages"},
    {"Music"},
    {"Settings"}
  ];
  init;
  color;
  curs_set(0);
  //noecho;
  //cbreak;
  scope(exit)    endwin;
  scope(failure) endwin;

  auto storage = load;
  auto api = "token" in storage ? new VKapi(storage["token"]) : storage.get_token;
  while (!api.isTokenValid) {
    "Wrong token, try again".print;
    api = storage.get_token;
  }
    
  api.statusbar;
  menu.draw;
  refresh;
  getch;

  storage.save;
}
