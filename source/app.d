#!/usr/bin/rdmd -L-lncursesw

import deimos.ncurses.ncurses;
import std.string, std.stdio, std.process, std.conv;
import core.stdc.locale;
import vkapi, cfg;

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

enum Colors { white, red, green, yellow, blue, magenta, cyan }

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
  //noecho;
  //cbreak;
  scope(exit)    endwin;
  scope(failure) endwin;

  auto storage = load;
  auto api = "token" in storage ? new VKapi(storage["token"]) : get_token(storage);
  while (!api.isTokenValid) {
    api = get_token(storage);
  }

  attron(A_BOLD);
  attron(A_REVERSE);
  attron(COLOR_PAIR(Colors.green));

  api.vkget("messages.getDialogs", ["count": "1", "offset": "0"]).toPrettyString.print;
  
  attroff(COLOR_PAIR(0));

  refresh;
  getch;
  storage.save;
}
