import osproc, os, terminal, strutils, unicode
from ncurses import initscr, getmaxyx, endwin, curs_set

const 
  # keys
  k_CC     = 3
  k_CD     = 4
  k_enter  = 13
  k_up     = 65
  k_down   = 66
  k_left   = 68
  k_right  = 67
  k_w      = 119
  k_s      = 115
  k_a      = 97
  k_d      = 100
  k_rus_w  = 134
  k_rus_a  = 132
  k_rus_s  = 139
  k_rus_d  = 178
  k_k      = 107
  k_j      = 106
  k_h      = 104
  k_l      = 108
  k_rus_h  = 128
  k_rus_j  = 190
  k_rus_k  = 187
  k_rus_l  = 180

  # key groups
  kg_esc   = [k_CC, k_CD]
  kg_up    = [k_up, k_w, k_k, k_rus_w, k_rus_k]
  kg_down  = [k_down, k_s, k_j, k_rus_s, k_rus_j]
  kg_left  = [k_left, k_a, k_h, k_rus_a, k_rus_h]
  kg_right = [k_right, k_d, k_l, k_rus_d, k_rus_l, k_enter]

  # aliases for active sections
  LEFT     = 0
  RIGHT    = 1

  # music
  play  = "▶ "
  pause = "▮▮"

type 
  ListElement = object
    text, link          : string
    callback            : proc(ListEl: var ListElement): void
    getter              : proc: seq[ListElement] 
  Colors  = enum
    Gray = 30,
    Red,
    Green,
    Yellow,
    Blue,
    Pink,
    Mint,
    White
  Window  = object
    x, y, key, offset   : int
    active, last_active : int
    section, start      : int
    color               : Colors
    title               : string
    menu, body, buffer  : seq[ListElement]

proc nop(ListEl: var ListElement) = discard
proc nopgen(): seq[ListElement] = discard

proc ChangeColor(ListEl: var ListElement)
proc ChangeState(ListEl: var ListElement)
proc open(ListEl: var ListElement)
proc GetDialogs(): seq[ListElement]
proc GetMusic(): seq[ListElement]
proc GetFriends(): seq[ListElement]
proc GenerateSettings(): seq[ListElement]

proc spawnLE(txt: string, lnk = "", clback: proc(ListEl: var ListElement): void, gett: proc: seq[ListElement]): ListElement = 
  return ListElement(text: txt, link: lnk, callback: clback, getter: gett)

var 
  win = Window(
    color:    Blue,
    title:    "Влад Балашенко", 
    menu:     @[spawnLE("Друзья", "link", open, GetFriends),
                spawnLE("Сообщения", "link", open, GetDialogs),
                spawnLE("Музыка", "link", open, GetMusic),
                spawnLE("Настройки", "link", open, GenerateSettings)],
    )

proc AlignBodyText() = 
  for i, e in win.body:
    if runeLen(e.text) + win.offset > win.x:
      win.body[i].text = e.text[0..win.x-win.offset-6] & "..."
    var align = runeLen(win.title) - win.offset - 1 
    for i, e in win.body:
      if runeLen(e.text) + win.offset < win.x:
        win.body[i].text = win.body[i].text & spaces(align - runeLen(e.text))

proc open(ListEl: var ListElement) = 
  win.buffer = ListEl.getter()
  if win.buffer.len+2 < win.y:
    win.body = win.buffer
    win.buffer = newSeq[ListElement](0)
  else:
    win.start = 0
    win.body = win.buffer[0..win.y-4]
  AlignBodyText()

proc ChangeState(ListEl: var ListElement) = 
  if play in ListEl.text:
    ListEl.text[1..4] = pause
  else:
    ListEl.text[1..6] = play

proc GetMusic(): seq[ListElement] = 
  var music = newSeq[ListElement](0)
  for e in 1..60:
    var track: string
    if e == 7:
      track = " ▶  Artist - Track " & $e
    else:
      track = "    Artist - Track " & $e
    if e == 7:
      music.add(spawnLE(track & spaces(win.x-win.offset-runeLen(track)-7) & "13:37", "link", ChangeState, nopgen))
    else:
      music.add(spawnLE(track & spaces(win.x-win.offset-runeLen(track)-7) & "13:37", "link", nop, nopgen))
  return music

proc GetDialogs(): seq[ListElement] = 
  var chats = newSeq[ListElement](0)
  for e in 1..60:
    if e in [1,3,4]:
      chats.add(spawnLE("[+] Chat " & $e, "link", nop, nopgen))
    else:
      chats.add(spawnLE("    Chat " & $e, "link", nop, nopgen))
  return chats

proc GetFriends(): seq[ListElement] = 
  var friends = newSeq[ListElement](0)
  for e in 1..60:
    friends.add(spawnLE("Friend " & $e, "link", nop, nopgen))
  return friends

proc SetText(ListEl: var ListElement, s: string) = 
  ListEl.text = s
  AlignBodyText()

proc GenerateSettings(): seq[ListElement] = 
  return @[spawnLE("Цвет = " & $win.color, "link", ChangeColor, nopgen)]

proc ChangeColor(ListEl: var ListElement) = 
  if int(win.color) < 37: inc win.color
  else: win.color = Gray
  ListEl.SetText("Цвет = " & $win.color)

proc clear() = discard execCmd("clear")

proc init() = 
  getmaxyx(initscr(), win.y, win.x)
  endwin()
  discard execCmd("tput civis")
  var 
    length = win.x div 2 - runeLen(win.title) div 2
    title = spaces(length) & win.title & spaces(length)
  if runeLen(title) > win.x: title = title[0..^2]
  win.title = title
  for e in win.menu:
    if win.offset < runeLen(e.text): win.offset = runeLen(e.text)
  win.offset += 5
  for i, e in win.menu:
    win.menu[i].text = win.menu[i].text & spaces(win.offset - runeLen(e.text))

proc selected(text: string) = 
  setStyle({styleReverse, styleBright})
  setForegroundColor(ForegroundColor(win.color))
  echo text
  resetAttributes()

proc regular(text: string) = 
  setStyle({styleBright})
  setForegroundColor(ForegroundColor(win.color))
  echo text
  resetAttributes()

proc Statusbar() = 
  selected(" 3 ✉ " & win.title[5..win.title.len] & "\n")

proc Controller() = 
  win.key = getch().ord
  case win.key:
    of kg_left:
      if win.section == RIGHT:
        win.active = win.last_active
        win.section = LEFT
        win.body = newSeq[ListElement](0)
    of kg_right:
      if win.section == LEFT:
        win.menu[win.active].callback(win.menu[win.active])
        win.last_active = win.active
        win.active = 0
        win.section = RIGHT
      else:
        win.body[win.active].callback(win.body[win.active])
    of kg_up:
      if win.active > 0: dec win.active
      elif win.buffer.len != 0 and win.start != 0:
        dec win.start
        win.body = win.buffer[win.start..win.start+win.y-4]
        AlignBodyText()
    of kg_down:
      if win.section == LEFT: 
        if win.active < win.menu.len-1: inc win.active
      else:
        if win.active < win.body.len-1: inc win.active
        elif win.buffer.len != 0 and win.start+win.y-3 != win.buffer.len:
          inc win.start
          win.body = win.buffer[win.start..win.start+win.y-4]
          AlignBodyText()
    else: discard

proc DrawMenu() = 
  for i, e in win.menu:
    if win.section == LEFT:
      if i == win.active: selected(e.text)
      else: regular(e.text)
    else:
      if i == win.last_active: selected(e.text)
      else: regular(e.text)

proc DrawBody() = 
  for i, e in win.body:
    setCursorPos(win.offset+2, 3+i)
    if i == win.active and win.section == RIGHT: selected(e.text)
    else: regular(e.text)

proc main() = 
  init()
  while win.key notin kg_esc:
    clear()
    Statusbar()
    DrawMenu()
    DrawBody()
    Controller()

when isMainModule: 
  main()
  discard execCmd("tput cnorm")
  clear() 