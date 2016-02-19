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

VKapi get_token(ref string[string] stor) {
  char token;
  "Insert your access token here: ".print;
  spawnShell(`xdg-open "http://oauth.vk.com/authorize?client_id=5110243&scope=friends,wall,messages,audio,offline&redirect_uri=blank.html&display=popup&response_type=token" >> /dev/null`);
  getstr(&token);
  auto strtoken = (cast(char*)&token).to!string;
  stor["token"] = strtoken;
  return new VKapi(strtoken);
}

void main(string[] args) {
  init;
  scope(exit)    endwin;
  scope(failure) endwin();

  auto storage = load;
  auto api = "token" in storage ? new VKapi(storage["token"]) : get_token(storage);
  api.vkget("messages.getDialogs", ["count": "1", "offset": "0"]).toPrettyString.print;

  refresh;
  getch;
  storage.save;
}
