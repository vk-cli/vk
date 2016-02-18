#!/usr/bin/rdmd -L-lncursesw

import deimos.ncurses.ncurses;
import std.string, std.stdio;
import core.stdc.locale;
import vkapi;

void init() {
  setlocale(LC_CTYPE,"");
  initscr();
}

void main(string[] args) {
  scope(exit) endwin;
  init;

  printw("Insert your access token here: ");
  refresh;
  getch;
}
