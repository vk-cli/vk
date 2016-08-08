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

const int
  // func keys
  k_up           = -2,
  k_down         = -3,
  k_right        = -4,
  k_left         = -5,
  k_home         = -6,
  k_ins          = -7,
  k_del          = -8,
  k_end          = -9,
  k_pageup       = -10,
  k_pagedown     = -11,
  k_enter        = 10,
  k_esc          = 27,
  k_tab          = 8,
  k_ctrl_bckspc  = 9,
  k_prev         = 91,
  k_rus_prev     = 133,
  k_next         = 93,
  k_rus_next     = 138,
  k_o            = 111,
  k_rus_o        = 137,
  k_m            = 109,
  k_rus_m        = 140,
  kg_rew_bck     = 60,
  kg_rew_fwd     = 62,
  kg_rew_bck_rus = 145,
  kg_rew_fwd_rus = 174,

  // keys
  k_q        = 113,
  k_rus_q    = 185,
  k_p        = 112,
  k_rus_p    = 183,
  k_r        = 114,
  k_rus_r    = 186,
  k_bckspc   = 127,
  k_w        = 119,
  k_s        = 115,
  k_a        = 97,
  k_d        = 100,
  k_rus_w    = 134,
  k_rus_a    = 132,
  k_rus_s    = 139,
  k_rus_d    = 178,
  k_k        = 107,
  k_j        = 106,
  k_h        = 104,
  k_l        = 108,
  k_rus_h    = 128,
  k_rus_j    = 190,
  k_rus_k    = 187,
  k_rus_l    = 180;

const int[]
  // key groups
  kg_esc     = [k_q, k_rus_q],
  kg_refresh = [k_r, k_rus_r],
  kg_up      = [k_up, k_w, k_k, k_rus_w, k_rus_k],
  kg_down    = [k_down, k_s, k_j, k_rus_s, k_rus_j],
  kg_left    = [k_left, k_a, k_h, k_rus_a, k_rus_h],
  kg_right   = [k_right, k_d, k_l, k_rus_d, k_rus_l, k_enter],
  kg_ignore  = [k_right, k_left, k_up, k_down, k_bckspc, k_esc,
                k_pageup, k_pagedown, k_end, k_ins, k_del,
                k_home, k_tab, k_ctrl_bckspc],
  kg_pause   = [k_p, k_rus_p],
  kg_loop    = [k_o, k_rus_o],
  kg_mix     = [k_m, k_rus_m],
  kg_prev    = [k_prev, k_rus_prev],
  kg_next    = [k_next, k_rus_next],
  kg_rewind_backward = [kg_rew_bck, kg_rew_bck_rus],
  kg_rewind_forward  = [kg_rew_fwd, kg_rew_fwd_rus];

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