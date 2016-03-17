#!/usr/bin/rdmd -L-lncursesw

import deimos.ncurses.ncurses;
import core.stdc.locale, core.thread, core.stdc.stdlib:exit;
import std.string, std.stdio, std.process,
       std.conv, std.array, std.encoding,
       std.range, std.algorithm;
import vkapi, cfg, localization, utils, namecache;

// INIT VARS
enum Sections { left, right }
enum Buffers { none, friends, dialogs, music, chat }
enum Colors { white, red, green, yellow, blue, pink, mint, gray }
enum DrawSetting { allMessages, onlySelectedMessage, onlySelectedMessageAndUnread }
Win win;
VKapi api;

const int 
  // func keys
  k_pageup   = 53,
  k_pagedown = 54,
  k_home     = 49,
  k_end      = 52,
  // keys
  k_q        = 113,
  k_rus_q    = 185,
  k_r        = 114,
  k_rus_r    = 186,
  k_enter    = 10,
  k_up       = 65,
  k_down     = 66,
  k_left     = 68,
  k_right    = 67,
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
  kg_right   = [k_right, k_d, k_l, k_rus_d, k_rus_l, k_enter];

const string 
  unread = "⚫ ",
  fwd    = "➥ ",
  play   = " ▶  ",
  pause  = " ▮▮ ";

const utfranges = [
  utf(19968, 40959, 1),
  utf(12288, 12351, 1),
  utf(11904, 12031, 1),
  utf(13312, 19903, 1),
  utf(63744, 64255, 1),
  utf(12800, 13055, 1),
  utf(13056, 13311, 1),
  utf(12736, 12783, 1),
  utf(12448, 12543, 1),
  utf(12352, 12447, 1),
  utf(110592, 110847, 1),
  utf(65280, 65519, 1)
  ];

struct utf {
  ulong 
    start, end;
  int spaces;
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
  buffer, mbody;
  int
    namecolor = Colors.white,
    textcolor = Colors.gray,
    counter, active, section,
    menuActive, menuOffset, key,
    scrollOffset, msgDrawSetting,
    activeBuffer, chatID, lastBuffer,
    lastScrollOffset, lastScrollActive;
  string
    debugText, currentPlayingTrack;
  bool
    isMusicPlaying, isConferenceOpened,
    isRainbowChat, isRainbowOnlyInGroupChats;
  Track currentTrack = {};
}

struct ListElement {
  string name, text;
  void function(ref ListElement) callback;
  ListElement[] function() getter;
  bool flag;
  int id;
  bool isConference;
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
  if ("lang" in storage) if (storage["lang"] == "1") swapLang;
  if ("rainbow" in storage) win.isRainbowChat = storage["rainbow"].to!bool;
  if ("rainbow_in_chat" in storage) win.isRainbowOnlyInGroupChats = storage["rainbow_in_chat"].to!bool;
  relocale;
}

void update(ref string[string] storage) {
  storage["lang"] = getLang;
  storage["main_color"] = win.namecolor.to!string;
  storage["second_color"] = win.textcolor.to!string;
  storage["message_setting"] = win.msgDrawSetting.to!string;
  storage["rainbow"] = win.isRainbowChat.to!string;
  storage["rainbow_in_chat"] = win.isRainbowOnlyInGroupChats.to!string;
}

void init() {
  setlocale(LC_CTYPE,"");
  win.lastBuffer = Buffers.none;
  localize;
  relocale;
  initscr;
  setOffset;
}

void print(string s) {
  s.toStringz.addstr;
}

void print(int i) {
  i.to!string.toStringz.addstr;
}

VKapi get_token(ref string[string] storage) {
  char token;
  "e_input_token".getLocal.print;
  spawnShell(`xdg-open "http://oauth.vk.com/authorize?client_id=5110243&scope=friends,wall,messages,audio,offline&redirect_uri=blank.html&display=popup&response_type=token" >> /dev/null`);
  echo;
  getstr(&token);
  noecho;
  auto strtoken = (cast(char*)&token).to!string;
  storage["token"] = strtoken;
  return new VKapi(strtoken);
}

void color() {
  if (!has_colors) {
    endwin;
    writeln("Your terminal does not support color");
  }
  start_color;
  use_default_colors;
  for (short i = 0; i < Colors.max; i++) {
    init_pair(i, i, -1);
  }
  for (short i = 1; i < Colors.max+1; i++) {
    init_pair((Colors.max+1+i).to!short, i, -1.to!short);
  }
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

void statusbar() {
  if (win.debugText == "") {
    string notify = " " ~ win.counter.to!string ~ " ✉ ";
    notify.selected;
    center(" ", COLS+2-notify.length, ' ').selected;
    "\n".print;
  } else {
    center(win.debugText, COLS, ' ').selected;
    "\n".print;
  }
}

void SetStatusbar(string s = "") {
  win.debugText = s;
}

void setOffset() {
  foreach(le; win.menu) {
    win.menuOffset = le.name.walkLength.to!int > win.menuOffset ? le.name.walkLength.to!int : win.menuOffset;
  }
  win.menuOffset++;
}

void drawMenu() {
  foreach(i, le; win.menu) {
    auto space = (le.name.walkLength < win.menuOffset) ? " ".replicate(win.menuOffset-le.name.walkLength) : "";
    auto name = le.name ~ space ~ "\n";
    if (win.section == Sections.left) i == win.active ? name.selected : name.regular;
    else i == win.menuActive ? name.selected : name.regular;
  }
}

ulong utfLength(string inp) {
  auto wstrInput = inp.to!wstring;
  ulong s = wstrInput.walkLength;
  foreach(w; wstrInput) {
    auto c = (cast(ulong)w);
    foreach(r; utfranges) {
      if(c >= r.start && c <= r.end) {
        s += r.spaces;
        break;
      }
    }
  }
  return s;
}

string cut(ulong i, ListElement e) {
  string tempText = e.text;
  int cut = (COLS-win.menuOffset-win.mbody[i].name.walkLength-1).to!int;
  if (e.text.walkLength > cut) tempText = tempText[0..cut];
  return tempText;
}

void bodyToBuffer() {
  if (win.mbody.length != 0) {
    switch (win.activeBuffer) {
      case Buffers.chat: win.mbody = GetChat; break;
      case Buffers.dialogs: win.mbody = GetDialogs; break;
      case Buffers.friends: win.mbody = GetFriends; break;
      case Buffers.music: win.mbody = GetMusic; if (win.active < 5 && win.isMusicPlaying) win.active = 5; break;
      default: break;
    }
    if (LINES-2 < win.mbody.length) win.buffer = win.mbody[0..LINES-2].dup;
    else win.buffer = win.mbody.dup;
    if (win.activeBuffer != Buffers.chat) {
      foreach(i, e; win.buffer) {
        if (e.name.utfLength.to!int + win.menuOffset+1 > COLS) {
          win.buffer[i].name = e.name.to!wstring[0..COLS-win.menuOffset-4].to!string;
        } else win.buffer[i].name ~= " ".replicate(COLS - e.name.utfLength - win.menuOffset-1);
      }
    }
  }
}

void drawDialogsList() {
  foreach(i, e; win.buffer) {
    wmove(stdscr, 2+i.to!int, win.menuOffset+1);
    if (i.to!int == win.active-win.scrollOffset) {
      e.name.selected;
      wmove(stdscr, 2+i.to!int, win.menuOffset+win.mbody[i].name.utfLength.to!int+1);
      cut(i, e).graySelected;
    } else {
      switch (win.msgDrawSetting) {
        case DrawSetting.allMessages:
          allMessages(e, i); break;
        case DrawSetting.onlySelectedMessage:
          onlySelectedMessage(e, i); break;
        case DrawSetting.onlySelectedMessageAndUnread:
          onlySelectedMessageAndUnread(e, i); break;
        default: break;
      }
    }
  }
}

void allMessages(ListElement e, ulong i) {
  e.flag ? e.name.regular : e.name.secondColor;
  wmove(stdscr, 2+i.to!int, win.menuOffset+win.mbody[i].name.walkLength.to!int+1);
  cut(i, e).white;
}

void onlySelectedMessage(ListElement e, ulong i) {
  e.flag ? e.name.regular : e.name.secondColor;
}

void onlySelectedMessageAndUnread(ListElement e, ulong i) {
  if (e.name[0..3] == "⚫") {
    e.flag ? e.name.regular : e.name.secondColor;
    wmove(stdscr, 2+i.to!int, win.menuOffset+win.mbody[i].name.walkLength.to!int+1);
    cut(i, e).white;
  } else e.flag ? e.name.regular : e.name.secondColor;
}

void drawFriendsList() {
  foreach(i, e; win.buffer) {
    wmove(stdscr, 2+i.to!int, win.menuOffset+1);
    i.to!int == win.active-win.scrollOffset ? e.name.selected : e.flag ? e.name.regular : e.name.secondColor;
  }
}

void drawMusicList() {
  foreach(i, e; win.buffer) {
    wmove(stdscr, 2+i.to!int, win.menuOffset+1);
    if (win.isMusicPlaying) {
      if (i < 5) e.name.regular;
      else {
        if (e.name.canFind(play) || e.name.canFind(pause)) if (i.to!int == win.active-win.scrollOffset) e.name.selected; else e.name.regular;
        else i.to!int == win.active-win.scrollOffset ? e.name.selected : e.name.secondColor;
      }
    } else
      i.to!int == win.active-win.scrollOffset ? e.name.selected : e.name.regular;
  }
}

void drawBuffer() {
  switch (win.activeBuffer) {
    case Buffers.dialogs: drawDialogsList; break;
    case Buffers.friends: drawFriendsList; break;
    case Buffers.music: drawMusicList; break;
    case Buffers.chat: drawChat; break;
    case Buffers.none: {
      foreach(i, e; win.buffer) {
        wmove(stdscr, 2+i.to!int, win.menuOffset+1);
        i.to!int == win.active ? e.name.selected : e.name.regular;
      }
      break;
    }
    default: break;
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
        " ".replicate(COLS-e.name.utfLength-e.text.length-2).regular;
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
}

int activeBufferLen() {
  switch (win.activeBuffer) {
    case Buffers.dialogs: return api.getServerCount(blockType.dialogs);
    case Buffers.friends: return api.getServerCount(blockType.friends);
    case Buffers.music: return api.getServerCount(blockType.music);
    case Buffers.chat: return api.getChatLineCount(win.chatID);
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

void jumpToEnd() {
  win.active = activeBufferLen-1;
  win.scrollOffset = activeBufferLen-LINES+2;
}

void controller() {
  while (true) {
    timeout(1050);
    auto ch = getch;
    win.key = ch;
    if(ch != -1) break;
    if(api.isSomethingUpdated) break;
  }
  //win.key.print;
  if (canFind(kg_left, win.key)) backEvent;
  if (activeBufferEventsAllowed) {
    if (win.activeBuffer != Buffers.chat) nonChatEvents;
    else chatEvents;
  }
  checkBounds;
}

void nonChatEvents() {
  if (canFind(kg_down, win.key)) downEvent;
  else if (canFind(kg_up, win.key)) upEvent;
  else if (canFind(kg_right, win.key)) selectEvent;
  else if (win.section == Sections.right) {
    if (canFind(kg_refresh, win.key)) bodyToBuffer;
    if (win.key == k_home) { win.active = 0; win.scrollOffset = 0; }
    else if (win.key == k_end) jumpToEnd;
    else if (win.key == k_pagedown) {
      win.scrollOffset += LINES/2;
      win.active += LINES/2;
    }
    else if (win.key == k_pageup) {
      win.scrollOffset -= LINES/2;
      win.active -= LINES/2;
      if (win.active < 0) win.active = win.scrollOffset = 0;
      if (win.scrollOffset < 0) win.scrollOffset = 0;
    }
  }
}

void chatEvents() {
  if (canFind(kg_up, win.key)) win.scrollOffset += 2;
  else if (canFind(kg_down, win.key)) win.scrollOffset -= 2;
  else if (win.key == k_pagedown) win.scrollOffset -= LINES/2;
  else if (win.key == k_pageup) win.scrollOffset += LINES/2;
  else if (win.key == k_home) win.scrollOffset = 0;
  else if (win.key == k_end) jumpToEnd;
  if (win.scrollOffset < 0) win.scrollOffset = 0;
}

void checkBounds() {
  if (win.activeBuffer != Buffers.none && activeBufferLen > 0 && win.active > activeBufferLen-1) jumpToEnd;
}

void downEvent() {
  if (win.section == Sections.left) win.active >= win.menu.length-1 ? win.active = 0 : win.active++;
  else {
    if (win.active-win.scrollOffset == LINES-3) win.scrollOffset++;
    if (win.activeBuffer != Buffers.none) {
      if (activeBufferEventsAllowed) win.active++; 
    } else win.active >= win.buffer.length-1 ? win.active = 0 : win.active++;
  }
}

void upEvent() {
  if (win.section == Sections.left) win.active == 0 ? win.active = win.menu.length.to!int-1 : win.active--;
  else {
    if (win.activeBuffer != Buffers.none && activeBufferEventsAllowed) {
      win.scrollOffset > 0 ? win.scrollOffset -= 1 : win.scrollOffset += 0;
      win.active == 0 ? win.active += 0 : win.active--;
    } else win.active == 0 ? win.active = win.buffer.length.to!int-1 : win.active--;
  }
}

void selectEvent() {
  if (win.section == Sections.left) {
    if (win.menu[win.active].callback) win.menu[win.active].callback(win.menu[win.active]);
    win.menuActive = win.active;
    win.active = 0;
    win.section = Sections.right;
  } else {
    win.lastScrollOffset = win.scrollOffset;
    win.lastScrollActive = win.active;
    if (win.isMusicPlaying && win.activeBuffer == Buffers.music) {
      setCurrentTrack;
      win.mbody[win.active-win.scrollOffset].callback(win.mbody[win.active-win.scrollOffset]);
    } else if (win.mbody[win.active-win.scrollOffset].callback) win.mbody[win.active-win.scrollOffset].callback(win.mbody[win.active-win.scrollOffset]);
  }
}

void backEvent() {
  if (win.section == Sections.right) {
    if (win.lastBuffer != Buffers.none) {
      win.scrollOffset = win.lastScrollOffset;
      win.activeBuffer = win.lastBuffer;
      win.lastBuffer = Buffers.none;
      SetStatusbar;
      win.isConferenceOpened = false;
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
    if (le.name[0..3] == "⚫") le.name[3..$].SetStatusbar;
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

void changeChatRender(ref ListElement le) {
  win.isRainbowChat = !win.isRainbowChat;
  win.mbody = GenerateSettings;
}

void changeChatRenderOnlyGroup(ref ListElement le) {
  win.isRainbowOnlyInGroupChats = !win.isRainbowOnlyInGroupChats;
  le.name = "rainbow_in_chat".getLocal ~ (win.isRainbowOnlyInGroupChats.to!string).getLocal;
}

ListElement[] GenerateHelp() {
  return [
    ListElement(center("general_navig".getLocal, COLS-16, ' ')),
    ListElement("help_move".getLocal),
    ListElement("help_select".getLocal),
    ListElement("help_jump".getLocal),
    ListElement("help_homend".getLocal),
    ListElement("help_exit".getLocal),
  ];
}

ListElement[] GenerateSettings() {
  ListElement[] list;
  list ~= [
    ListElement(center("display_settings".getLocal, COLS-16, ' ')),
    ListElement("main_color".getLocal ~ ("color"~win.namecolor.to!string).getLocal, "", &changeMainColor),
    ListElement("second_color".getLocal ~ ("color"~win.textcolor.to!string).getLocal, "", &changeSecondColor),
    ListElement("lang".getLocal, "", &changeLang, null),
    ListElement(center("convers_settings".getLocal, COLS-16, ' ')),
    ListElement("msg_setting_info".getLocal ~ ("msg_setting"~win.msgDrawSetting.to!string).getLocal, "", &changeMsgSetting),
    ListElement("rainbow".getLocal ~ (win.isRainbowChat.to!string).getLocal, "", &changeChatRender),
  ];
  if (win.isRainbowChat) list ~= ListElement("rainbow_in_chat".getLocal ~ (win.isRainbowOnlyInGroupChats.to!string).getLocal, "", &changeChatRenderOnlyGroup);
  return list;
}

ListElement[] GetDialogs() {
  ListElement[] list;
  auto dialogs = api.getBufferedDialogs(LINES-2, win.scrollOffset);
  string newMsg;
  foreach(e; dialogs) {
    newMsg = e.unread ? unread : "  ";
    list ~= ListElement(newMsg ~ e.name, ": " ~ e.lastMessage.replace("\n", " "), &chat, &GetChat, e.online, e.id, e.isChat);
  }
  win.activeBuffer = Buffers.dialogs;
  return list;
}

ListElement[] GetFriends() {
  ListElement[] list;
  auto friends = api.getBufferedFriends(LINES-2, win.scrollOffset);
  foreach(e; friends) {
    list ~= ListElement(e.first_name ~ " " ~ e.last_name, e.id.to!string, &chat, &GetChat, e.online, e.id);
  }
  win.activeBuffer = Buffers.friends;
  return list;
}

ListElement[] MusicPlayer() {
  ListElement[] mplayer;
  mplayer ~= ListElement(" ".replicate((COLS-16)/2-win.currentTrack.artist.utfLength/2)~win.currentTrack.artist);
  mplayer ~= ListElement(" ".replicate((COLS-16)/2-win.currentTrack.title.utfLength/2)~win.currentTrack.title);
  mplayer ~= ListElement(center("0:00 / " ~ win.currentTrack.duration, COLS-16, ' '));
  mplayer ~= ListElement(center("[========================|==========]", COLS-16, ' '));
  mplayer ~= ListElement("");
  return mplayer;
}

ListElement[] setCurrentTrack() {
  if (!win.isMusicPlaying) {
    if (win.active > LINES-8) {
      if (win.scrollOffset == 0) win.scrollOffset += win.active-LINES+8;
      else win.scrollOffset += 5;
    }
    win.active += 5;
    win.isMusicPlaying = true;
  }
  vkAudio track = api.getBufferedMusic(1, win.active-5)[0];
  win.currentPlayingTrack   = track.artist ~ " - " ~ track.title;
  win.currentTrack.artist   = track.artist;
  win.currentTrack.title    = track.title;
  win.currentTrack.duration = track.duration_str;
  return new ListElement[0];
}

ListElement[] GetMusic() {
  ListElement[] list;
  string space, artistAndSong;
  int amount;
  vkAudio[] music;

  if (win.isMusicPlaying) {
    music = api.getBufferedMusic(LINES-6, win.scrollOffset);
    list ~= MusicPlayer;
  } else
    music = api.getBufferedMusic(LINES-2, win.scrollOffset);

  foreach(e; music) {
    string indicator = win.currentPlayingTrack == e.artist ~ " - " ~ e.title ? play : "    ";
    artistAndSong = indicator ~ e.artist ~ " - " ~ e.title;
    if (artistAndSong.utfLength > COLS-9-win.menuOffset-e.duration_str.length.to!int) {
      artistAndSong = artistAndSong[0..COLS-9-win.menuOffset-e.duration_str.length.to!int];
      amount = COLS-6-win.menuOffset-artistAndSong.utfLength.to!int;
    } else amount = COLS-9-win.menuOffset-e.artist.utfLength.to!int-e.title.utfLength.to!int-e.duration_str.length.to!int;
    space = " ".replicate(amount);
    list ~= ListElement(artistAndSong ~ space ~ e.duration_str, e.url, &run, &setCurrentTrack);
  }
  win.activeBuffer = Buffers.music;
  return list;
}

ListElement[] GetChat() {
  ListElement[] list;
  auto chat = api.getBufferedChatLines(LINES-4, win.scrollOffset, win.chatID);
  foreach(e; chat) {
    if (e.isFwd) {
      ListElement line = {"    " ~ "| ".replicate(e.fwdDepth)};
      if (e.isName && !e.isSpacing) {
        line.flag = true;
        line.id = line.name.length.to!int + 4;
        line.name ~= fwd ~ e.text;
        line.text = e.time;
      } else 
        line.name ~= e.text;
      list ~= line;
    } else {
      string unreadSign = e.unread ? unread : " ";
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
    auto api = new VKapi(storage["token"]);
    if(!api.isTokenValid) {
        writeln("bad token");
        return;
    }

    string unc = "TsuйShiMaMiRe – ニンゲン・コーティング";
    writeln(unc);
    //writeln("def: " ~ unc.length.to!string);
    //writeln("walk: " ~ walkLength(unc).to!string);
    //writeln("kl: " ~ unc.utfLength.to!string);
    writeln("slcx");
    writeln(unc.to!wstring[0..8].to!string);

    api.asyncLongpoll();
    readln();
    //auto tstmid = api.messagesSend(2000000023, "govneco", 3239);
    //writeln(tstmid.to!string);
    auto dlgg = api.getBufferedDialogs(10, 0);
    int i = 0;
    const int step = 48;
    while(true) {
        int huj;
        auto conv = api.getBufferedChatLines(step, i, convStartId + 12);
        //if(conv[conv.length-1].lastMessage != getLocal("loading")) i += step;
        foreach (d; conv) {
            //writeln("d " ~ d.name ~ " " ~ d.lastMessage ~ (d.online ? " online" : ""));
            //writeln("m " ~ d.author_name ~ ": " ~ d.body_lines.join ~ " " ~ d.time_str ~ " nm:" ~ d.needName.to!string);
            if(d.isFwd) writeln("| ".replicate(d.fwdDepth) ~ d.text ~ " " ~ d.time);
            else writeln(d.text ~ " " ~ d.time);
        }
        readln();
    }
    //dbm("cbuf: " ~ api.pb.alldialogs.length.to!string);
    //nc.dbmAll();
    //auto fr = api.friendsGet();
    //foreach(f; fr) dbm(f.first_name ~ " " ~ f.last_name ~ " " ~ (f.online ? "!" : ""));

    //auto aud = api.audioGet(0, 0, 10);
    //foreach(a; aud) dbm(a.artist ~ " - " ~ a.title ~ "  " ~ a.duration_str);

    /+auto allsh = api.messagesGetHistory(convStartId+23, 25, 0, -1, false);
    foreach(ww; allsh) {
        writeln(ww.author_name ~ " " ~ ww.time_str);
        foreach(ml; ww.body_lines) writeln(ml);
        writeln("maxdep: " ~ ww.fwd_depth.to!string);
        writeln(digTest(ww.fwd));
    }+/



    readln();
    //ticker();
}

void main(string[] args) {
  initdbm;
  //test;
  init;
  color;
  curs_set(0);
  noecho;
  scope(exit)    endwin;
  scope(failure) endwin;

  auto storage = load;
  storage.parse;

  api = "token" in storage ? new VKapi(storage["token"]) : storage.get_token;
  while (!api.isTokenValid) {
    "e_wrong_token".getLocal.print;
    api = storage.get_token;
  }
  api.asyncLongpoll();

  while (!canFind(kg_esc, win.key)) {
    clear;
    win.counter = api.messagesCounter;
    statusbar;
    if (win.activeBuffer != Buffers.chat) drawMenu;
    bodyToBuffer;
    drawBuffer;
    refresh;
    controller;
  }

  storage.update;
  storage.save;
  dbmclose;
  endwin;
  exit(0);
}
