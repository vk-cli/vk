/*
Copyright 2016 HaCk3D, substanceof

https://github.com/HaCk3Dq
https://github.com/substanceof

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

module ui;

import deimos.ncurses.ncurses;
import std.string, std.conv, core.thread;
import app, utils;

enum Colors { white, red, green, yellow, blue, pink, mint, gray }



// ===== Basic Stuff =====

void color() {
  if (!has_colors) Exit("Your terminal does not support color");
  start_color;
  use_default_colors;
  for (short i = 0; i < Colors.max; i++) init_pair(i, i, -1);
  for (short i = 1; i < Colors.max+1; i++) init_pair((Colors.max+1+i).to!short, i, -1.to!short);
  init_pair(Colors.max, 0, -1);
  init_pair(Colors.max+1, -1, -1);
  init_pair(Colors.max*2+1, 0, -1);
}

void print(T)(T text) {
  text.to!string.toStringz.addstr;
}

void selected(T)(T text) {
  attron(A_REVERSE);
  text.regular;
  attroff(A_REVERSE);
}

void regular(T)(T text) {
  attron(A_BOLD);
  attron(COLOR_PAIR(window.main_color));
  text.print;
  attroff(A_BOLD);
  attroff(COLOR_PAIR(window.main_color));
}

void clearScr() {
  for (int y = 0; y < window.height; y++) {
    wmove(stdscr, y, 0);
    print(" ".replicatestr(window.width));
  }
  wmove(stdscr, 0, 0);
}

// ===== Header =====

void statusbar() {
  center(window.statusbarText, COLS, ' ').selected;
}

void tabView() {
  window.main_color = Colors.blue;
  " 1:Friends ".selected;
  window.main_color = Colors.gray;
  " 2:VK [dev] ".replicatestr(6).selected;
  window.main_color = Colors.blue;
  "\n".print;
  "\n".print;
}

// ===== Drawers =====

void open(string tab) {
  final switch (tab) {
    case "Dialogs": {
      window.openedView = "Dialogs";
      drawDialogs; break;
    }
    case "Music": {
      window.openedView = "Music";
      drawMusic; break;
    }
    case "Friends": {
      window.openedView = "Friends";
      drawFriends; break;
    }
  }
}

void drawFriends() {
  auto view = friends.getView(window.height-3, window.width);
  if (view.empty) return;
  foreach (e; view) {
    (" " ~ e.fullName ~ "\n").regular;
  }
}

void drawMusic() {}
void drawDialogs() {}