#!/usr/bin/rdmd -L-lncursesw

import deimos.ncurses.ncurses;
import std.string, std.stdio, std.process, std.conv;
import core.stdc.locale;
import vkapi, cfg;

void init() {
  setlocale(LC_CTYPE,"");
  initscr();
}

void print(string s) {
  s.toStringz.printw;
}

VKapi get_token() {
  char token;
  "Insert your access token here: ".print;
  spawnShell(`xdg-open "http://oauth.vk.com/authorize?client_id=5110243&scope=friends,wall,messages,audio,offline&redirect_uri=blank.html&display=popup&response_type=token" >> /dev/null`);
  getstr(&token);
  auto strtoken = (cast(char*)&token).to!string;
  storage["token"] = strtoken;
  return new VKapi(strtoken);
}

VKapi set_token(string token) {
  return new VKapi(token);
}

void main(string[] args) {
  init;
  scope(exit)    endwin;
  scope(failure) endwin();

  auto storage = load;
  auto api = "token" in storage ? set_token(storage["token"]) : get_token;
  api.vkget("messages.getDialogs", ["count": "1", "offset": "0"]).toPrettyString.print;

  refresh;
  getch;
  storage.save;
}
