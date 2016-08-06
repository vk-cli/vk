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
import std.string, core.thread;
import app, utils;

void print(string text) {
  text.toStringz.addstr;
}

void clearScr() {
  for (int y = 0; y < window.height; y++) {
    wmove(stdscr, y, 0);
    print(" ".replicatestr(window.width));
  }
  wmove(stdscr, 0, 0);
}

void open(string tab) {
  final switch (tab) {
    case "dialogs": drawDialogs; break;
    case "music": drawMusic; break;
    case "friends": drawFriends; break;
  }
}

void drawFriends() {
  auto view = friends.getView(window.height, window.width);
  if (view.empty) return;
  foreach (e; view) {
    (e.fullName ~ "\n").print;
  }
}

void drawMusic() {}
void drawDialogs() {}