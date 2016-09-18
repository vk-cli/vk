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
  attron(COLOR_PAIR(window.mainColor));
  text.print;
  attroff(A_BOLD);
  attroff(COLOR_PAIR(window.mainColor));
}

void secondColor(string text) {
  attron(A_BOLD);
  attron(COLOR_PAIR(window.secondColor+Colors.max+1));
  text.print;
  attroff(A_BOLD);
  attroff(COLOR_PAIR(window.secondColor+Colors.max+1));
}

void clearScr() {
  for (int y = 0; y < window.height; y++) {
    wmove(stdscr, y, 0);
    print(" ".replicatestr(window.width));
  }
  wmove(stdscr, 0, 0);
}

string getChar(string charName) {
  if (window.unicodeChars) {
    switch (charName) {
      case "unread" : return "⚫ ";
      case "fwd"    : return "➥ ";
      case "play"   : return " ▶  ";
      case "pause"  : return " ▮▮ ";
      case "outbox" : return " ⇡ ";
      case "inbox"  : return " ⇣ ";
      case "cross"  : return " ✖ ";
      case "mail"   : return " ✉ ";
      case "refresh": return " ⟲";
      case "repeat" : return "⟲ ";
      case "shuffle": return "⤮";
      default       : return charName;
    }
  } else {
    switch(charName) {
      case "unread" : return "! ";
      case "fwd"    : return "fwd ";
      case "play"   : return " >  ";
      case "pause"  : return " || ";
      case "outbox" : return " ^ ";
      case "inbox"  : return " v ";
      case "cross"  : return " X ";
      case "mail"   : return " M ";
      case "refresh": return " ?";
      case "repeat" : return "o ";
      case "shuffle": return "x";
      default       : return charName;
    }
  }
}

// ===== Header =====

void statusbar() {
  string counterStr = " " ~ window.notifyCounter.to!string ~ getChar("mail");
  counterStr.selected;
  int counterStrLen = counterStr.utfLength + (counterStr.utfLength == 7) * 2;
  center(window.statusbarText, COLS-counterStrLen, ' ').selected;
}

void tabPanel() {  
  foreach(i, tab; tabMenu.tabs) {
    if (tabMenu.active == i) (" " ~ (i+1).to!string ~ ":" ~ tab.name ~ " ").selected;
    else (" " ~ (i+1).to!string ~ ":" ~ tab.name ~ " ").secondColor;
  }
  "\n".print;
  "\n".print;
}

// ===== Drawers =====

void open(Tab tab) {
  final switch (tab.name) {
    case "Dialogs": {
      //window.openedView = "Dialogs";
      //drawDialogs;
      break;
    }
    case "Music": {
      //window.openedView = "Music";
      //drawMusic;
      break;
    }
    case "Friends": {
      window.openedView = "Friends";
      drawFriends; break;
    }
    case "+": {
      "\n".print;
      center("Press Enter to add a tab here", COLS, ' ').regular;
    }
  }
}

void drawFriends() {
  auto view = friends.getView(window.height-3, window.width);
  if (view.empty) return;
  int counter = 0;
  foreach (e; view) {
    if (counter == tabMenu.tabs[tabMenu.active].selected) 
      (" " ~ e.fullName ~ " ".replicatestr(window.width-e.fullName.utfLength-1)).selected;
    else
      (" " ~ e.fullName ~ "\n").regular;
    counter++;
  }
}

void drawMusic() {}
void drawDialogs() {}