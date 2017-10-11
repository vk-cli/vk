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

import deimos.ncurses.ncurses;
import core.stdc.locale, core.thread, core.stdc.stdlib:exit;
import core.sys.posix.signal;
import std.string, std.stdio, std.process,
       std.conv, std.array, std.encoding,
       std.range, std.algorithm, std.concurrency,
       std.datetime, std.utf, std.regex, std.random,
       std.math, std.json;
import vkapi, cfg, localization, utils, namecache, musicplayer, vkversion;
import magicstringz;

// INIT VARS
enum Sections { left, right }
enum Buffers { none, friends, dialogs, music, chat, help, settings }
enum Colors { white, red, green, yellow, blue, pink, mint, gray }
enum DrawSetting { allMessages, onlySelectedMessage, onlySelectedMessageAndUnread }

__gshared {
  string[string] storage;
  Win win;
  VkMan api;
}

public:

struct ListElement {
  string name, text;
  void function(ref ListElement) callback;
  ListElement[] function() getter;
  bool flag;
  int id;
  bool isConference;
}

void Exit(string msg = "", int ecode = 0, bool normalExit = false) {
  endwin;

  if (normalExit) {
    mplayer.exitPlayer();
  }
  else if (mplayer !is null && mplayer.player !is null) {
    mplayer.player.killPlayer();
    writeln("player killed");
  }

  if (msg != "") {
    //writeln("FAIL");
    writeln(msg);
  }
  exit(ecode);
}

vkAudio[] getShuffledMusic(int count, int offset) {
  if (win.workaroundCounter == floor(api.getServerCount(blockType.music)/100.0)+2) win.shuffleLoadingIsOver = true;
  if (!win.shuffleLoadingIsOver) {
    win.workaroundCounter++;
    win.shuffledMusic = api.getBufferedMusic(api.getServerCount(blockType.music), 0);
    auto step = (win.shuffledMusic.length.to!real / api.getServerCount(blockType.music).to!real) * 20;
    ("[" ~ "=".replicatestr(floor(step).to!int) ~ "|" ~ "=".replicatestr(20 - floor(step).to!int) ~ "]").SetStatusbar;
  } else {
    if (!win.shuffled) {
      SetStatusbar;
      randomShuffle(win.shuffledMusic);
      win.shuffled = true;
      win.savedShuffledLen = win.shuffledMusic.length.to!int;
    } else
      return win.shuffledMusic[offset..offset+count];
  }
  return api.getBufferedMusic(count, offset);
}

private:

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
  k_shift_s  = 83,
  k_shift_rus_s = 171,
  k_a        = 97,
  k_d        = 100,
  k_rus_w    = 134,
  k_rus_a    = 132,
  k_rus_s    = 139,
  k_rus_d    = 178,
  k_shift_d  = 68,
  k_shift_rus_d  = 146,
  k_k        = 107,
  k_j        = 106,
  k_h        = 104,
  k_l        = 108,
  k_rus_h    = 128,
  k_rus_j    = 190,
  k_rus_k    = 187,
  k_rus_l    = 180,
  k_shift_l  = 76,
  k_shift_rus_l  = 148;

const int[]
  // key groups
  kg_esc     = [k_q, k_rus_q],
  kg_refresh = [k_r, k_rus_r],
  kg_up      = [k_up, k_w, k_k, k_rus_w, k_rus_k],
  kg_down    = [k_down, k_s, k_j, k_rus_s, k_rus_j],
  kg_left    = [k_left, k_a, k_h, k_rus_a, k_rus_h],
  kg_right   = [k_right, k_d, k_l, k_rus_d, k_rus_l, k_enter],
  kg_shift_right = [k_shift_d, k_shift_rus_d, k_shift_l, k_shift_rus_l],
  kg_shift_s = [k_shift_s, k_shift_rus_s],
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

string getChar(string charName) {
  if (win.unicodeChars) {
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

struct Notify {
  string text;
  TimeOfDay
    currentTime,
    clearTime;
}

struct Cursor {
  int x, y;
}

struct Track {
  string artist, title, duration;
}

struct Win {
  ListElement[]
  menu = [
    {callback:&open, getter: &GetFriends},
    {callback:&open, getter: &GetDialogs},
    {callback:&open, getter: &GetMusic},
    {callback:&open, getter: &GenerateHelp},
    {callback:&open, getter: &GenerateSettings},
    {callback:&exit}
  ],
  buffer, mbody, playerUI;
  vkAudio[] shuffledMusic;
  Notify notify;
  Cursor cursor;
  int
    namecolor = Colors.white,
    textcolor = Colors.gray,
    counter, active, section,
    menuActive, menuOffset = 15, key,
    scrollOffset, msgDrawSetting,
    activeBuffer, chatID, lastBuffer,
    lastScrollOffset, lastScrollActive,
    msgBufferSize, seekValue = 15,
    savedShuffledLen, workaroundCounter;
  string
    statusbarText, msgBuffer;
  bool
    isMusicPlaying, isConferenceOpened,
    isRainbowChat, isRainbowOnlyInGroupChats,
    isMessageWriting, showTyping, selectFlag,
    showConvNotifications, sendOnline,
    unicodeChars = true, shuffled, seekPercentFlag,
    shuffleLoadingIsOver, isInternalError;
}

void relocale() {
  win.menu[0].name = "m_friends".getLocal;
  win.menu[1].name = "m_conversations".getLocal;
  win.menu[2].name = "m_music".getLocal;
  win.menu[3].name = "m_help".getLocal;
  win.menu[4].name = "m_settings".getLocal;
  win.menu[5].name = "m_exit".getLocal;
}

void parse(ref string[string] storage) {
  if ("main_color" in storage) win.namecolor = storage["main_color"].to!int;
  if ("second_color" in storage) win.textcolor = storage["second_color"].to!int;
  if ("message_setting" in storage) win.msgDrawSetting = storage["message_setting"].to!int;
  if ("lang" in storage) if (storage["lang"] != getLang) swapLang;
  if ("rainbow" in storage) win.isRainbowChat = storage["rainbow"].to!bool;
  if ("rainbow_in_chat" in storage) win.isRainbowOnlyInGroupChats = storage["rainbow_in_chat"].to!bool;
  if ("show_typing" in storage) win.showTyping = storage["show_typing"].to!bool;
  if ("show_conv_notif" in storage) win.showConvNotifications = storage["show_conv_notif"].to!bool;
  if ("send_online" in storage) win.sendOnline = storage["send_online"].to!bool;
  if ("unicode_chars" in storage) win.unicodeChars = storage["unicode_chars"].to!bool;
  if ("seek_percent_or_value" in storage) win.seekPercentFlag = storage["seek_percent_or_value"].to!bool;

  relocale;

  if("longpoll_wait" !in storage) {
    storage["longpoll_wait"] = "25";
    storage.save;
  }
}

void update(ref string[string] storage) {
  storage["lang"] = getLang;
  storage["main_color"] = win.namecolor.to!string;
  storage["second_color"] = win.textcolor.to!string;
  storage["message_setting"] = win.msgDrawSetting.to!string;
  storage["rainbow"] = win.isRainbowChat.to!string;
  storage["rainbow_in_chat"] = win.isRainbowOnlyInGroupChats.to!string;
  storage["show_typing"] = win.showTyping.to!string;
  storage["show_conv_notif"] = win.showConvNotifications.to!string;
  storage["send_online"] = win.sendOnline.to!string;
  storage["unicode_chars"] = win.unicodeChars.to!string;
  storage["seek_percent_or_value"] = win.seekPercentFlag.to!string;
  storage.save;
}

void print(string s) {
  s.toStringz.addstr;
}

void print(int i) {
  i.to!string.toStringz.addstr;
}

string makeLink(string login, string passwd) {
  return "https://oauth.vk.com/token?grant_type=password" ~
        "&client_id=" ~ appCID ~
        "&client_secret=" ~ appSecret ~
        "&username=" ~ login ~
        "&password=" ~ passwd ~
        "&2fa_supported=1";
}

string getPassword() {
  version (linux) {
    import core.sys.linux.unistd;
    return getpass("Password (will not be echoed): ").to!string;
  }
  else {
    writeln("[ WARNING: password will be echoed in console ]");
    write("Password: ");
    return readln().chomp;
  }
}

VkMan get_token(ref string[string] storage) {

  auto tm = dur!"seconds"(10);

  write("Username (email or phone): ");
  string strusr = readln().chomp;

  string strpwd = getPassword();

  writeln("\nLogging in..");

  string url = makeLink(strusr, strpwd);
  auto got = AsyncMan.httpget(url, tm, 10);

  JSONValue resp = got.parseJSON;
  if("validation_type" in resp && (resp["validation_type"].str=="2fa_sms" || resp["validation_type"].str=="2fa_app")){
    if(resp["validation_type"].str=="2fa_sms")
      write("SMS Code ("~ resp["phone_mask"].str ~"): ");
    else if(resp["validation_type"].str=="2fa_app")
      write("App Code: ");
    string strcode = readln().chomp;

    url = makeLink(strusr, strpwd)~"&code="~strcode;
    got = AsyncMan.httpget(url, tm, 10);
    resp = got.parseJSON;
  }
  if("error" in resp) {
    writeln("\nError while auth: " ~ got);
    Exit();
  }

  string token = resp["access_token"].str;
  storage["token"] = token;
  storage["auth_v2"] = "true";

  return new VkMan(token);
}

void color() {
  if (!has_colors) {
    endwin;
    writeln("Your terminal does not support color");
  }
  start_color;
  use_default_colors;
  for (short i = 0; i < Colors.max; i++) init_pair(i, i, -1);
  for (short i = 1; i < Colors.max+1; i++) init_pair((Colors.max+1+i).to!short, i, -1.to!short);
  init_pair(Colors.max, 0, -1);
  init_pair(Colors.max+1, -1, -1);
  init_pair(Colors.max*2+1, 0, -1);
}

void selected(string text) {
  attron(A_REVERSE);
  text.regular;
  attroff(A_REVERSE);
}

void regular(string text) {
  attron(A_BOLD);
  attron(COLOR_PAIR(win.namecolor));
  text.print;
  attroff(A_BOLD);
  attroff(COLOR_PAIR(win.namecolor));
}

void colored(string text, int color) {
  int temp = win.namecolor;
  win.namecolor = color;
  text.regular;
  win.namecolor = temp;
}

void secondColor(string text) {
  attron(A_BOLD);
  attron(COLOR_PAIR(win.textcolor+Colors.max+1));
  text.print;
  attroff(A_BOLD);
  attroff(COLOR_PAIR(win.textcolor+Colors.max+1));
}

void graySelected(string text) {
  attron(A_REVERSE);
  attron(A_BOLD);
  attron(COLOR_PAIR(win.namecolor+Colors.max+1));
  text.print;
  attroff(A_BOLD);
  attroff(COLOR_PAIR(win.namecolor+Colors.max+1));
  attroff(A_REVERSE);
}

void regularWhite(string text) {
  attron(COLOR_PAIR(0));
  text.print;
  attroff(COLOR_PAIR(0));
}

void white(string text) {
  attron(A_BOLD);
  regularWhite(text);
  attroff(A_BOLD);
}

void notifyManager() {
  string notifyMsg = api.getLastLongpollMessage.replace("\n", " ");
  win.notify.currentTime = cast(TimeOfDay)Clock.currTime;

  if (notifyMsg != "" && notifyMsg != "-1") {
    if (notifyMsg.utfLength > COLS - 10) win.notify.text = notifyMsg.to!wstring[0..COLS-10].to!string;
    else win.notify.text = notifyMsg;
    win.notify.clearTime = win.notify.currentTime + seconds(1);
  }
  if (win.notify.currentTime > win.notify.clearTime) {
    win.notify.clearTime = TimeOfDay(23, 59, 59);
    win.notify.text = "";
  }
}

void statusbar() {
  string counterStr;
  notifyManager;
  win.counter = api.messagesCounter;
  if (win.counter == -1) {
    win.isInternalError = true;
    counterStr = getChar("cross");
    if (api.api.isTokenValid()) {
      "no_connection".getLocal.SetStatusbar;
    }
    else {
      "e_wrong_token".getLocal.SetStatusbar;
    }
  }
  else {
    if (win.isInternalError) SetStatusbar;
    win.isInternalError = false;
    counterStr = " " ~ win.counter.to!string ~ getChar("mail");
    if (api.isLoading) counterStr ~= getChar("refresh");
  }
  counterStr.selected;
  auto counterStrLen = counterStr.utfLength + (counterStr.utfLength == 7) * 2;
  if (win.notify.text != "") center(win.notify.text, COLS-counterStr.utfLength, ' ').selected;
  else center(win.statusbarText, COLS-counterStrLen, ' ').selected;
  " ".replicatestr((counterStr.utfLength == 7) * 2).selected;
  "\n".print;
}

void SetStatusbar(string s = "") {
  win.statusbarText = s;
}

void drawMenu() {
  foreach(i, le; win.menu) {
    auto space = (le.name.walkLength < win.menuOffset) ? " ".replicatestr(win.menuOffset-le.name.walkLength) : "";
    auto name = le.name ~ space ~ "\n";
    if (win.section == Sections.left) i == win.active ? name.selected : name.regular;
    else i == win.menuActive ? name.selected : name.regular;
  }
}

string cut(uint i, ListElement e) {
  wstring tempText = e.text.toUTF16wrepl;
  auto cut = (COLS-win.menuOffset-win.mbody[i].name.utfLength-1).to!uint;
  if (e.text.utfLength > cut) tempText = tempText[0..cut];
  return tempText.to!string;
}

void bodyToBuffer() {
  switch (win.activeBuffer) {
    case Buffers.chat: win.mbody = GetChat; break;
    case Buffers.dialogs: win.mbody = GetDialogs; break;
    case Buffers.friends: win.mbody = GetFriends; break;
    case Buffers.music: win.mbody = GetMusic; break;
    case Buffers.help: win.mbody = GenerateHelp; break;
    case Buffers.settings: win.mbody = GenerateSettings; break;
    default: break;
  }
  if (LINES-2 < win.mbody.length) win.buffer = win.mbody[0..LINES-2].dup;
  else win.buffer = win.mbody.dup;
  if (win.activeBuffer != Buffers.chat) {
    foreach(i, e; win.buffer) {
      if (e.name.utfLength.to!int + win.menuOffset+1 > COLS)
      try {
        win.buffer[i].name = e.name.to!wstring[0..COLS-win.menuOffset-1].to!string;
        }
      catch(Throwable) {
      }
      else
        win.buffer[i].name ~= " ".replicatestr(COLS - e.name.utfLength - win.menuOffset-1);
    }
  }
}

void drawDialogsList() {
  foreach(i, e; win.buffer) {
    wmove(stdscr, 2+i.to!int, win.menuOffset+1);
    if (i.to!int == win.active-win.scrollOffset) {
      e.name.selected;
      wmove(stdscr, 2+i.to!int, win.menuOffset+win.mbody[i].name.utfLength.to!int+1);
      cut(i.to!uint, e).graySelected;
    } else {
      switch (win.msgDrawSetting) {
        case DrawSetting.allMessages:
          allMessages(e, i.to!uint); break;
        case DrawSetting.onlySelectedMessage:
          onlySelectedMessage(e, i); break;
        case DrawSetting.onlySelectedMessageAndUnread:
          onlySelectedMessageAndUnread(e, i.to!uint); break;
        default: break;
      }
    }
  }
}

void allMessages(ListElement e, uint i) {
  e.flag ? e.name.regular : e.name.secondColor;
  wmove(stdscr, 2+i.to!int, win.menuOffset+win.mbody[i].name.walkLength.to!int+1);
  cut(i, e).white;
}

void onlySelectedMessage(ListElement e, ulong i) {
  e.flag ? e.name.regular : e.name.secondColor;
}

void onlySelectedMessageAndUnread(ListElement e, uint i) {
  e.flag ? e.name.regular : e.name.secondColor;
  if (e.name.indexOf(getChar("unread")) == 0) {
    wmove(stdscr, 2+i.to!int, win.menuOffset+win.mbody[i].name.walkLength.to!int+1);
    cut(i, e).white;
  }
}

void drawFriendsList() {
  foreach(i, e; win.buffer) {
    wmove(stdscr, 2+i.to!int, win.menuOffset+1);
    if (i.to!int == win.active-win.scrollOffset) {
      if (!e.flag) {
        e.name[0..$-e.text.utfLength].selected;
        e.text.selected;
      } else e.name.selected;
    } else if (e.flag) {
      e.name.regular;
    } else {
      e.name[0..$-e.text.utfLength].secondColor;
      e.text.secondColor;
    }
  }
}

void drawMusicList() {
  if (win.isMusicPlaying) {
    foreach(i, e; win.playerUI) {
      wmove(stdscr, 2+i.to!int, win.menuOffset);
      e.name.regular;
    }
    wmove(stdscr, 5, win.menuOffset+COLS/2+19);
    mplayer.repeatMode  ? getChar("repeat").regular  : getChar("repeat").secondColor;
    mplayer.shuffleMode ? getChar("shuffle").regular : getChar("shuffle").secondColor;
  }

  foreach(i, e; win.buffer) {
    wmove(stdscr, win.isMusicPlaying*5+2+i.to!int, win.menuOffset+1);
    if (!win.isMusicPlaying)
      i.to!int == win.active-win.scrollOffset ? e.name.selected : e.name.regular;
    else {
      if (e.name.canFind(getChar("play")) || e.name.canFind(getChar("pause"))) if (i.to!int == win.active-win.scrollOffset) e.name.selected; else e.name.regular;
      else i.to!int == win.active-win.scrollOffset ? e.name.selected : e.name.secondColor;
    }
  }
}

void drawBuffer() {
  switch (win.activeBuffer) {
    case Buffers.dialogs: drawDialogsList; break;
    case Buffers.friends: drawFriendsList; break;
    case Buffers.music: drawMusicList; break;
    case Buffers.chat: drawChat; break;
    default: {
      foreach(i, e; win.buffer) {
        wmove(stdscr, 2+i.to!int, win.menuOffset+1);
        i.to!int == win.active ? e.name.selected : e.name.regular;
      }
      break;
    }
  }
}

int colorHash(string name) {
  int sum;
  foreach(e; name) sum += e;
  return sum % 5 + 1;
}

void renderColoredOrRegularText(string text) {
  if (win.isRainbowChat && (!win.isRainbowOnlyInGroupChats || win.isConferenceOpened))
    text == api.me.first_name~" "~api.me.last_name ? text.secondColor : text.colored(text.colorHash);
  else
    text == api.me.first_name~" "~api.me.last_name ? text.secondColor : text.regular;
}

void drawChat() {
  foreach(i, e; win.buffer) {
    wmove(stdscr, 2+i.to!int, 1);
    if (e.flag) {
      if (e.id == -1) {
        e.name.renderColoredOrRegularText;
        " ".replicatestr(COLS-e.name.utfLength-e.text.length-2).regular;
        e.text.secondColor;
      } else {
        e.name[0..e.id].regularWhite;
        e.name[e.id..$].renderColoredOrRegularText;
        wmove(stdscr, 2+i.to!int, (COLS-e.text.length-1).to!int);
        e.text.secondColor;
      }
    } else
      e.name.regularWhite;
  }
  if (win.isMessageWriting) {
    "\n: ".print;
    win.msgBuffer.print;
    wmove(stdscr, win.buffer.length.to!int+2, win.cursor.x+2);
    "".regular;
  }
}

int activeBufferMaxLen() {
  switch (win.activeBuffer) {
    case Buffers.dialogs: return api.getServerCount(blockType.dialogs);
    case Buffers.friends: return api.getServerCount(blockType.friends);
    case Buffers.music: return api.getServerCount(blockType.music);
    case Buffers.chat: return api.getChatLineCount(win.chatID, COLS-12);
    default: return 0;
  }
}

bool activeBufferEventsAllowed() {
  switch (win.activeBuffer) {
    case Buffers.dialogs: return api.isScrollAllowed(blockType.dialogs);
    case Buffers.friends: return api.isScrollAllowed(blockType.friends);
    case Buffers.music: return api.isScrollAllowed(blockType.music);
    case Buffers.chat: return api.isChatScrollAllowed(win.chatID);
    default: return true;
  }
}

void forceRefresh() {
  switch (win.activeBuffer) {
    case Buffers.dialogs: api.toggleForceUpdate(blockType.dialogs); break;
    case Buffers.friends: api.toggleForceUpdate(blockType.friends); break;
    case Buffers.music: api.toggleForceUpdate(blockType.music); break;
    default: return;
  }
}

public void jumpToBeginning() {
  win.active = 0;
  win.scrollOffset = 0;
}

void jumpToEnd() {
  if (win.shuffled && win.activeBuffer == Buffers.music) {
    win.active = win.savedShuffledLen-1-1*(win.isMusicPlaying);
    win.scrollOffset = win.savedShuffledLen-LINES+2+(win.isMusicPlaying)*4;
  } else {
    win.active = activeBufferMaxLen-1;
    win.scrollOffset = activeBufferMaxLen-LINES+2+(win.activeBuffer == Buffers.music && win.isMusicPlaying)*5;
  }
  if (win.scrollOffset < 0) win.scrollOffset = 0;
}

int _getch() {
  int key = getch;
  if (key == 27) {
    if (getch == -1) return k_esc;
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

void menuSelect(int position) {
  SetStatusbar;
  win.section = Sections.left;
  win.active  = position;
  win.menu[win.active].callback(win.menu[win.active]);
  win.menuActive = win.active;
  if (win.activeBuffer == Buffers.music) {
    win.active = mplayer.trackNum;
    win.scrollOffset = mplayer.offset;
  } else {
    win.active = 0;
    win.scrollOffset = 0;
  }
  win.section = Sections.right;
}

void controller() {
  while (true) {
    timeout(100);
    win.key = _getch;
    if (win.key == -1) win.selectFlag = false;
    if (!win.isMessageWriting && (win.key == 49 || win.key == 50 || win.key == 51)) { menuSelect(win.key-49); break; }
    else if (win.key != -1) break;
    else if (api.isSomethingUpdated) break;
    else if (win.activeBuffer == Buffers.music && mplayer.musicState && mplayer.playtimeUpdated) break;
  }
  //if (win.key != -1) win.key.print;
  if (win.isMessageWriting) msgBufferEvents;
  else if (canFind(kg_left, win.key)) backEvent;
  else if (activeBufferEventsAllowed) {
    if (win.activeBuffer != Buffers.chat) nonChatEvents;
    else chatEvents;
  }
  checkBounds;
}

void msgBufferEvents() {
  if (win.key == k_esc || win.key == k_enter) {
    if (win.key == k_enter) {
	    if (win.msgBuffer.utfLength != 0) api.asyncSendMessage(win.chatID, win.msgBuffer);
      else api.asyncMarkMessagesAsRead(win.chatID);
    }
    win.msgBuffer = "";
    win.cursor.x = win.cursor.y = 0;
    curs_set(0);
    win.isMessageWriting = false;
  }
  else if (win.key == k_bckspc && win.msgBuffer.utfLength != 0 && win.cursor.x != 0) {
    if (win.cursor.x == win.msgBuffer.utfLength) win.msgBuffer = win.msgBuffer.to!wstring[0..$-1].to!string;
    else win.msgBuffer = win.msgBuffer.to!wstring[0..win.cursor.x-1].to!string ~ win.msgBuffer.to!wstring[win.cursor.x..$].to!string;
    win.cursor.x--;
    win.msgBufferSize = win.msgBuffer.utfLength.to!int;
  }
  else if (win.key > 0 && !canFind(kg_ignore, win.key)) {
    try {
      validate(win.msgBuffer);
      win.msgBufferSize = win.msgBuffer.utfLength.to!int;
    } catch (UTFException e) {
      if (win.cursor.x-1 != win.msgBufferSize) {
        int i, count, offset;
        char chr;
        while (count != win.cursor.x) {
          chr = win.msgBuffer[i];
          if (chr != 208 && chr != 209) ++count;
          else ++offset;
          ++i;
        }
        chr = win.msgBuffer[count+offset];
        if (chr == 208 || chr == 209) --offset;
        win.msgBuffer = win.msgBuffer[0..count+offset-1] ~ win.key.to!char ~ win.msgBuffer[count+offset-1..$];
      }
      else win.msgBuffer ~= win.key.to!char;
      return;
    }
    if (win.cursor.x == win.msgBuffer.utfLength) win.msgBuffer ~= win.key.to!char;
    else win.msgBuffer = win.msgBuffer.to!wstring[0..win.cursor.x].to!string ~ win.key.to!char ~ win.msgBuffer.to!wstring[win.cursor.x..$].to!string;
    win.cursor.x++;
    if (win.showTyping) api.setTypingStatus(win.chatID);
  }
  else if (win.key == k_home) win.cursor.x = 0;
  else if (win.key == k_end) win.cursor.x = win.msgBuffer.utfLength.to!int;
  else if (win.key == k_left && win.cursor.x != 0) win.cursor.x--;
  else if (win.key == k_right && win.cursor.x != win.msgBuffer.utfLength) win.cursor.x++;
}

void globalMplayerShortcuts() {
  if (canFind(kg_pause, win.key)) mplayer.pause;
  if (canFind(kg_next, win.key)) {
    if (mplayer.repeatMode) mplayer.trackNum++;
    mplayer.trackOver;
  }
  if (canFind(kg_prev, win.key)) {
    mplayer.trackNum -= 2-mplayer.repeatMode;
    mplayer.trackOver;
  }
  if (canFind(kg_rewind_forward, win.key)) mplayer.player.relativeSeek(win.seekValue, win.seekPercentFlag);
  if (canFind(kg_rewind_backward, win.key)) mplayer.player.relativeSeek(-win.seekValue, win.seekPercentFlag);
  if (canFind(kg_loop, win.key)) mplayer.repeatMode = !mplayer.repeatMode;
  if (canFind(kg_mix, win.key) && win.activeBuffer == Buffers.music) toggleShuffleMode;
}

void nonChatEvents() {
  globalMplayerShortcuts;
  if (canFind(kg_down, win.key)) downEvent;
  if (canFind(kg_up, win.key)) upEvent;
  else if (canFind(kg_right, win.key) && !win.selectFlag) {
    win.selectFlag = true;
    selectEvent;
  }
  else if (win.section == Sections.right) {
    if (canFind(kg_refresh, win.key)) forceRefresh;
    if (win.key == k_home) jumpToBeginning;
    else if (win.key == k_end && win.activeBuffer != Buffers.none) jumpToEnd;
    else if (win.key == k_pagedown && win.activeBuffer != Buffers.none) {
      win.scrollOffset += LINES/2;
      win.active += LINES/2;
    }
    else if (win.key == k_pageup && win.activeBuffer != Buffers.none) {
      win.scrollOffset -= LINES/2;
      win.active -= LINES/2;
      if (win.active < 0) win.active = win.scrollOffset = 0;
      if (win.scrollOffset < 0) win.scrollOffset = 0;
    }
  }
}

void chatEvents() {
  globalMplayerShortcuts;
  if (canFind(kg_up, win.key)) win.scrollOffset += 2;
  else if (canFind(kg_down, win.key)) win.scrollOffset -= 2;
  else if (win.key == k_pagedown) win.scrollOffset -= LINES/2;
  else if (win.key == k_pageup) win.scrollOffset += LINES/2;
  else if (win.key == k_home) win.scrollOffset = 0;
  else if (canFind(kg_right, win.key)) {
    curs_set(1);
    win.isMessageWriting = true;
  }
  else if (canFind(kg_shift_right, win.key)) {
      dbm("Reading from file.\n");
      // TODO! Call vim to save text in vkcliTmpMsgFile.
      string text = getMessageFromTmpFile();
      if (!text.empty)
	  api.asyncSendMessage(win.chatID, text);
  }
  else if (canFind(kg_shift_s, win.key)) {
    api.asyncMarkMessagesAsRead(win.chatID);
  }
  else if (canFind(kg_refresh, win.key)) api.toggleChatForceUpdate(win.chatID);
  if (win.scrollOffset < 0) win.scrollOffset = 0;
  else if (activeBufferMaxLen != -1 && win.scrollOffset > activeBufferMaxLen-LINES+3) win.scrollOffset = activeBufferMaxLen-LINES+3;
}

void checkBounds() {
  if (win.activeBuffer != Buffers.none && activeBufferMaxLen > 0 && win.active > activeBufferMaxLen-1) jumpToBeginning;
  else if(win.activeBuffer != Buffers.none && activeBufferMaxLen > 0 && win.active < 0) jumpToEnd;
}

void downEvent() {
  if (win.section == Sections.left) win.active >= win.menu.length-1 ? win.active = 0 : win.active++;
  else {
    if (win.active == activeBufferMaxLen-1) jumpToBeginning;
    else {
      if (win.active-win.scrollOffset == LINES-3-(win.activeBuffer == Buffers.music && win.isMusicPlaying)*5)
        win.scrollOffset++;

      if (win.shuffled && win.activeBuffer == Buffers.music && win.scrollOffset+LINES-2-win.isMusicPlaying*4 > win.savedShuffledLen) {
        jumpToBeginning;
        win.active--;
      }

      if (win.activeBuffer != Buffers.none) {
        if (activeBufferEventsAllowed) win.active++;
      } else win.active >= win.buffer.length-1 ? win.active = 0 : win.active++;
    }
  }
}

void upEvent() {
  if (win.section == Sections.left) win.active == 0 ? win.active = win.menu.length.to!int-1 : win.active--;
  else {
    if (win.activeBuffer != Buffers.none) {
        if (win.active == 0) jumpToEnd;
        else {
          if (win.active == win.scrollOffset) win.scrollOffset--;
          win.active--;
          if (win.scrollOffset < 0) win.scrollOffset = 0;
        }
    } else {
      win.active == 0 ? win.active = win.buffer.length.to!int-1 : win.active--;
    }
  }
}

void selectEvent() {
  if (win.section == Sections.left) {
    if (win.menu[win.active].callback) win.menu[win.active].callback(win.menu[win.active]);
    win.menuActive = win.active;
    if (win.activeBuffer == Buffers.music) {
      win.active = mplayer.trackNum;
      win.scrollOffset = mplayer.offset;
    }
    else win.active = 0;
    win.section = Sections.right;
  } else {
    win.lastScrollOffset = win.scrollOffset;
    win.lastScrollActive = win.active;
    if (win.isMusicPlaying && win.activeBuffer == Buffers.music) {
      if (win.active-win.scrollOffset >= 0)
        win.mbody[win.active-win.scrollOffset].callback(win.mbody[win.active-win.scrollOffset]);
    } else if (win.mbody.length != 0 && win.mbody[win.active-win.scrollOffset].callback) win.mbody[win.active-win.scrollOffset].callback(win.mbody[win.active-win.scrollOffset]);
    if (win.menuActive == 4) storage.update;
  }
}

void backEvent() {
  if (win.section == Sections.right) {
    if (win.lastBuffer != Buffers.none) {
      win.scrollOffset = win.lastScrollOffset;
      win.activeBuffer = win.lastBuffer;
      win.lastBuffer = Buffers.none;
      win.isConferenceOpened = false;
      SetStatusbar;
      if (win.scrollOffset != 0) win.active = win.lastScrollActive;
    } else {
      win.scrollOffset = 0;
      win.lastScrollOffset = 0;
      win.activeBuffer = Buffers.none;
      win.active = win.menuActive;
      win.section = Sections.left;
      win.mbody = new ListElement[0];
      win.buffer = new ListElement[0];
    }
  }
}

wstring[] run(string[] args) {
  wstring[] output;
  auto pipe = pipeProcess(args, Redirect.stdout);
  foreach(line; pipe.stdout.byLine) output ~= to!wstring(line.idup);
  return output;
}

void exit(ref ListElement le) {
  win.key = k_q;
}

void open(ref ListElement le) {
  win.mbody = le.getter();
}

void chat(ref ListElement le) {
  win.chatID = le.id;
  win.scrollOffset = 0;
  open(le);
  if (le.isConference) {
    auto len = getChar("unread").length;
    if (le.name[0..len] == getChar("unread")) le.name[len..$].SetStatusbar;
    else le.name.SetStatusbar;
    win.isConferenceOpened = true;
  }
  win.lastBuffer = win.activeBuffer;
  win.activeBuffer = Buffers.chat;
}

void run(ref ListElement le) {
  le.getter();
}

void changeLang(ref ListElement le) {
  swapLang;
  win.mbody = GenerateSettings;
  relocale;
  storage.update;
}

void changeMainColor(ref ListElement le) {
  win.namecolor == Colors.max ? win.namecolor = 0 : win.namecolor++;
  le.name = "main_color".getLocal ~ ("color"~win.namecolor.to!string).getLocal;
}

void changeSecondColor(ref ListElement le) {
  win.textcolor == Colors.max ? win.textcolor = 0 : win.textcolor++;
  le.name = "second_color".getLocal ~ ("color"~win.textcolor.to!string).getLocal;
}

void changeMsgSetting(ref ListElement le) {
  win.msgDrawSetting = win.msgDrawSetting != 2 ? win.msgDrawSetting+1 : 0;
  le.name = "msg_setting_info".getLocal ~ ("msg_setting"~win.msgDrawSetting.to!string).getLocal;
}

void toggleChatRender(ref ListElement le) {
  win.isRainbowChat = !win.isRainbowChat;
  win.mbody = GenerateSettings;
}

void toggleShowTyping(ref ListElement le) {
  win.showTyping = !win.showTyping;
  win.mbody = GenerateSettings;
}

void toggleUnicodeChars(ref ListElement le) {
  win.unicodeChars = !win.unicodeChars;
  win.mbody = GenerateSettings;
}

void toggleChatRenderOnlyGroup(ref ListElement le) {
  win.isRainbowOnlyInGroupChats = !win.isRainbowOnlyInGroupChats;
  le.name = "rainbow_in_chat".getLocal ~ (win.isRainbowOnlyInGroupChats.to!string).getLocal;
}

void toggleShowConvNotifications(ref ListElement le) {
  win.showConvNotifications = !win.showConvNotifications;
  api.showConvNotifications(win.showConvNotifications);
  le.name = "show_conv_notif".getLocal ~ (win.showConvNotifications.to!string).getLocal;
}

void toggleSendOnline(ref ListElement le) {
  win.sendOnline = !win.sendOnline;
  api.sendOnline(win.sendOnline);
  le.name = "send_online".getLocal ~ (win.sendOnline.to!string).getLocal;
}

void toggleSeekPercentOrValue(ref ListElement le) {
  win.seekPercentFlag = !win.seekPercentFlag;
  win.seekValue = win.seekPercentFlag ? 2 : 15;
  le.name = "seek_percent_or_value".getLocal ~ ("seek_" ~ win.seekPercentFlag.to!string).getLocal;
}

ListElement[] GenerateHelp() {
  win.activeBuffer = Buffers.help;
  return [
    ListElement(center("general_navig".getLocal, COLS-16, ' ')),
    ListElement("help_move".getLocal),
    ListElement("help_select".getLocal),
    ListElement("help_jump".getLocal),
    ListElement("help_homend".getLocal),
    ListElement("help_exit".getLocal),
    ListElement("help_refr".getLocal),
    ListElement("help_123".getLocal),
    ListElement("help_pause".getLocal),
    ListElement("help_loop".getLocal),
    ListElement("help_mix".getLocal),
    ListElement("help_rewind".getLocal),
  ];
}

ListElement[] GenerateSettings() {
  win.activeBuffer = Buffers.settings;
  ListElement[] list;
  list ~= [
    ListElement(center("display_settings".getLocal, COLS-16, ' ')),
    ListElement("main_color".getLocal ~ ("color"~win.namecolor.to!string).getLocal, "", &changeMainColor),
    ListElement("second_color".getLocal ~ ("color"~win.textcolor.to!string).getLocal, "", &changeSecondColor),
    ListElement("lang".getLocal, "", &changeLang, null),
    ListElement(center("convers_settings".getLocal, COLS-16, ' ')),
    ListElement("msg_setting_info".getLocal ~ ("msg_setting"~win.msgDrawSetting.to!string).getLocal, "", &changeMsgSetting),
    ListElement("rainbow".getLocal ~ (win.isRainbowChat.to!string).getLocal, "", &toggleChatRender),
  ];
  if (win.isRainbowChat) list ~= ListElement("rainbow_in_chat".getLocal ~ (win.isRainbowOnlyInGroupChats.to!string).getLocal, "", &toggleChatRenderOnlyGroup);
  list ~= ListElement("show_typing".getLocal ~ (win.showTyping.to!string).getLocal, "", &toggleShowTyping);
  list ~= ListElement("show_conv_notif".getLocal ~ (win.showConvNotifications.to!string).getLocal, "", &toggleShowConvNotifications);
  list ~= ListElement(center("general_settings".getLocal, COLS-16, ' '));
  list ~= ListElement("send_online".getLocal ~ (win.sendOnline.to!string).getLocal, "", &toggleSendOnline);
  list ~= ListElement("unicode_chars".getLocal ~ (win.unicodeChars.to!string).getLocal, "", &toggleUnicodeChars);
  list ~= ListElement(center("music_settings".getLocal, COLS-16, ' '));
  list ~= ListElement("seek_percent_or_value".getLocal ~ ("seek_" ~ win.seekPercentFlag.to!string).getLocal, "", &toggleSeekPercentOrValue);
  return list;
}

ListElement[] GetDialogs() {
  ListElement[] list;
  string
    newMsg,
    unreadText,
    lastMsg;
  uint space;

  win.activeBuffer = Buffers.dialogs;
  auto dialogs = api.getBufferedDialogs(LINES-2, win.scrollOffset);

  if (api.dialogsFactory.getBlockObject(win.scrollOffset) !is null && dialogs.length != LINES-2 && activeBufferMaxLen > LINES-2)
    dialogs = api.getBufferedDialogs(LINES-2, win.scrollOffset-(LINES-2-dialogs.length).to!int);

  foreach(e; dialogs) {
    unreadText = "";
    newMsg = e.unread ? getChar("unread") : "  ";
    if (e.outbox) newMsg = "  ";
    lastMsg = e.lastMessage.replace("\n", " ");
    if (lastMsg.utfLength > COLS-win.menuOffset-newMsg.utfLength-e.name.utfLength-3-e.unreadCount.to!string.length)
      try {
        lastMsg = lastMsg.toUTF16wrepl[0..COLS-win.menuOffset-newMsg.utfLength-e.name.utfLength-8-e.unreadCount.to!string.length].toUTF8wrepl;
      }
      catch(Throwable) {
      }
    if (e.unread) {
      if (e.outbox) unreadText ~= getChar("outbox");
      else if (e.unreadCount > 0) unreadText ~= e.unreadCount.to!string ~ getChar("inbox");
      space = COLS-win.menuOffset-newMsg.utfLength-e.name.utfLength-lastMsg.utfLength-unreadText.utfLength-4;
      if (space < COLS) unreadText = " ".replicatestr(space) ~ unreadText;
      else unreadText = "   " ~ unreadText;
    }
    list ~= ListElement(newMsg ~ e.name, ": " ~ lastMsg ~ unreadText, &chat, &GetChat, e.online, e.id, e.isChat);
  }
  return list;
}

ListElement[] GetFriends() {
  ListElement[] list;
  win.activeBuffer = Buffers.friends;
  auto friends = api.getBufferedFriends(LINES-2, win.scrollOffset);

  if (api.friendsFactory.getBlockObject(win.scrollOffset) !is null && friends.length != LINES-2 && activeBufferMaxLen > LINES-2)
    friends = api.getBufferedFriends(LINES-2, win.scrollOffset-(LINES-2-friends.length).to!int);

  foreach(e; friends)
    list ~= ListElement(e.first_name ~ " " ~ e.last_name, e.last_seen_str, &chat, &GetChat, e.online, e.id);
  return list;
}

ListElement[] setCurrentTrack() {
  if (!mplayer.player.isPlayerInit) "err_noplayer".getLocal.SetStatusbar;
  else {
    vkAudio track;
    if (!win.isMusicPlaying && LINES-3-(win.active-win.scrollOffset) <= 5) win.scrollOffset += 5-(LINES-3-(win.active-win.scrollOffset));
    if (win.isMusicPlaying && mplayer.sameTrack(win.active)) mplayer.pause;
    else {
      mplayer.play(win.active);
      mplayer.offset = win.scrollOffset;
      win.isMusicPlaying = true;
    }
  }
  return new ListElement[0];
}

void toggleShuffleMode() {
  mplayer.shuffleMode = !mplayer.shuffleMode;
  if (mplayer.shuffleMode) {
    randomShuffle(win.shuffledMusic);
    jumpToBeginning;
    mplayer.offset = win.scrollOffset;
  }
}

ListElement[] GetMusic() {
  ListElement[] list;
  string space, artistAndSong;
  int amount;
  vkAudio[] music;

  win.activeBuffer = Buffers.music;
  if (mplayer.shuffleMode)
    music = getShuffledMusic(LINES-2-win.isMusicPlaying*4, win.scrollOffset);
  else
    music = api.getBufferedMusic(LINES-2-win.isMusicPlaying*4, win.scrollOffset);
  win.playerUI = mplayer.getMplayerUI(COLS);

  foreach(e; music) {
    string indicator = (mplayer.currentTrack.id == e.id.to!string) ? mplayer.musicState ? getChar("play") : getChar("pause") : "    ";
    artistAndSong = indicator ~ e.artist ~ " - " ~ e.title;

    int width = COLS-4-win.menuOffset-e.duration_str.length.to!int;
    if (artistAndSong.utfLength > width) {
      artistAndSong = artistAndSong[0..width];
      amount = COLS-6-win.menuOffset-artistAndSong.utfLength.to!int;
    } else amount = COLS-9-win.menuOffset-e.artist.utfLength.to!int-e.title.utfLength.to!int-e.duration_str.length.to!int;

    space = " ".replicatestr(amount);
    list ~= ListElement(artistAndSong ~ space ~ e.duration_str, e.url, &run, &setCurrentTrack);
  }
  return list;
}

ListElement[] GetChat() {
  ListElement[] list;
  int verticalOffset;
  try {
    validate(win.msgBuffer);
    verticalOffset = win.msgBuffer.utfLength.to!int/COLS-1;
  } catch (UTFException e) { verticalOffset = win.msgBufferSize/COLS-1; }
  auto chat = api.getBufferedChatLines(LINES-4-verticalOffset, win.scrollOffset, win.chatID, COLS-12);
  foreach(e; chat) {
    if (e.isFwd) {
      ListElement line = {"    " ~ "| ".replicatestr(e.fwdDepth)};
      if (e.isName && !e.isSpacing) {
        line.flag = true;
        line.id = line.name.length.to!int + 4;
        line.name ~= getChar("fwd") ~ e.text;
        line.text = e.time;
      } else
        line.name ~= e.text;
      list ~= line;
    } else {
      string unreadSign = e.unread ? getChar("unread") : " ";
      list ~= !e.isName ? ListElement("  " ~ unreadSign ~ e.text) : ListElement(e.text, e.time, null, null, true, -1);
    }
  }
  return list;
}

void test() {
    //initFileDbm();
    localize();
    auto storage = load;
    if("token" !in storage) {
        writeln("cyka");
        return;
    }
    /*auto api = new VKapi(storage["token"]);
    if(!api.isTokenValid) {
        writeln("bad token");
        return;
    }

    int i = 0;
    while(true) {
        readln();
        auto pr = 2000000012;
        if(i > 4) {
            i = 0;
            pr = 2000000023;
        }
        api.setTypingStatus(pr);
        ++i;
    }*/
}

void clear() {
  for (int y = 0; y < LINES; y++) {
    wmove(stdscr, y, 0);
    print(" ".replicatestr(COLS));
  }
  wmove(stdscr, 0, 0);
}

void help() {
  writeln(
    // these help can be generated from actions (array -> hashmap)
    "-h, --help      This help page" ~ "\n" ~
    "-v, --version   Show client version" ~ "\n" ~
    "-r --reauth     Receive new auth token" ~ "\n" ~
    "Logs are here:  /tmp/vkcli-log/"
  );
}

void init() {
  updateGcSignals();
  setPosixSignals();
  setlocale(LC_CTYPE,"");
  win.lastBuffer = Buffers.none;
  setEnvLanguage;
  localize;
  relocale;
}

void main(string[] args) {
  string[] actions = ["version", "help", "reauth"];
  bool correct = false, reauth = false;

  if (args.length != 1) {
    foreach(arg; args) {
      foreach(act; actions) {
        if (arg == "-" ~ act[0] || arg == "--" ~ act) {
          correct = true;
          final switch (act) {
            case "version": writefln("vk-cli %s", currentVersion); exit(0); break;
            case "help": help(); exit(0); break;
            case "reauth": reauth = true; break;
          }
        }
      }
    }
    if (!correct) writeln("wrong arguments");
  }

  //test;
  initdbm();
  init();
  storage = load();
  storage.parse();

  try
    if(reauth == true || "token" !in storage || "auth_v2" !in storage) {
      api = storage.get_token;
      storage.save;
    }
    else api = new VkMan(storage["token"]);
  catch
    (BackendException e) Exit(e.msg);

  initscr();
  color();
  curs_set(0);
  noecho;

  mplayer = new MusicPlayer;
  mplayer.startPlayer(api);
  try
    api.setLongpollWait(storage["longpoll_wait"].to!int);
  catch(Exception)
    dbm("failed set longpoll_wait from config");
  api.showConvNotifications(win.showConvNotifications);
  api.sendOnline(win.sendOnline);

  while (!canFind(kg_esc, win.key) || win.isMessageWriting) {
    clear;
    statusbar;
    if (win.activeBuffer != Buffers.chat) drawMenu;
    bodyToBuffer;
    drawBuffer;
    refresh;
    controller;
  }

  Exit("", 0, true);
}
