#!/usr/bin/rdmd -L-lncursesw

import deimos.ncurses.ncurses;
import std.string, std.stdio, std.process, std.conv;
import core.stdc.locale;
import vkapi;

void init() {
  setlocale(LC_CTYPE,"");
  initscr();
}

void main(string[] args) {
  init;
  scope(exit) endwin;

  printw("Insert your access token here: ");

  spawnShell(`xdg-open "http://oauth.vk.com/authorize?client_id=5110243&scope=friends,wall,messages,audio,offline&redirect_uri=blank.html&display=popup&response_type=token" >> /dev/null`);

  char token;
  getstr(&token);

  refresh;
  auto stoken = (cast(char*)&token).to!string;
  auto api = new VKapi(stoken);
  api.vkget("messages.getDialogs", ["count": "1", "offset": "0"]).toPrettyString.writeln();

  getch;
}
