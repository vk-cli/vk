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

module controller;

import deimos.ncurses.ncurses;

int _getch() {
  int key = getch;
  if (key == 27) {
    if (getch == -1) return 27;     // Esc
    else {
      switch (getch) {
        case 65: return -2;         // Up
        case 66: return -3;         // Down
        case 67: return -4;         // Right
        case 68: return -5;         // Left
        case 49: getch; return -6;  // Home
        case 72: getch; return -6;  // Home
        case 50: getch; return -7;  // Ins
        case 51: getch; return -8;  // Del
        case 52: getch; return -9;  // End
        case 70: getch; return -9;  // End
        case 53: getch; return -10; // Pg Up
        case 54: getch; return -11; // Pg Down
        default: return -1;
      }
    }
  }
  return key;
}