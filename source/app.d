#!/usr/bin/rdmd -L-lncursesw

import std.string;
import std.c.locale;
import deimos.ncurses.ncurses;

void main() {
    scope(exit) endwin();

    setlocale(LC_CTYPE,"");

    immutable hello = toStringz("UTF-8 тест: привет)");

    initscr();
    printw(hello);
    refresh();
    getch();
}
