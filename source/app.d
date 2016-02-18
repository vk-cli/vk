#!/usr/bin/rdmd -L-lncursesw

import deimos.ncurses.ncurses;
import std.getopt;
import std.string;
import std.c.locale;

void main(string[] args) {
  scope(exit) endwin();

  setlocale(LC_CTYPE,"");

  immutable hello = toStringz("UTF-8 тест: привет)");

  initscr();
  printw(hello);
  refresh();
  getch();
}
