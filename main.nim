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

type 
  ListElement = object
    text, link          : string
    callback            : proc(ListEl: var ListElement): void
  Colors = enum
    Black = 30,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    White
  Window = object
    x, y, key, offset   : int
    active, last_active : int
    section             : int
    color               : Colors
    title               : string
    menu, body          : seq[ListElement]

proc nop(ListEl: var ListElement) = discard
proc OpenSettings(ListEl: var ListElement)
proc ChangeColor(ListEl: var ListElement)

proc spawnLE(txt: string, lnk = "", clback: proc(ListEl: var ListElement): void): ListElement = 
  return ListElement(text: txt, link: lnk, callback: clback)

var 
  win = Window(
    color:    Blue,
    title:    "Влад Балашенко", 
    menu:     @[spawnLE("Друзья", "link", nop),
                spawnLE("Сообщения", "link", nop),
                spawnLE("Музыка", "link", nop),
                spawnLE("Настройки", "link", OpenSettings)],
    body:     @[spawnLE("Test1", "link", nop),
                spawnLE("Test2", "link", nop)])

proc AlignBodyText() = 
  for i, e in win.body:
    if runeLen(e.text) + win.offset > win.x:
      win.body[i].text = e.text[0..win.x-win.offset-6] & "..."
    var align = runeLen(win.title) - win.offset - 1 
    for i, e in win.body:
      if runeLen(e.text) + win.offset < win.x:
        win.body[i].text = win.body[i].text & spaces(align - runeLen(e.text))

proc SetText(ListEl: var ListElement, s: string) = 
  ListEl.text = s
  AlignBodyText()

proc GenerateSettings(): seq[ListElement] = 
  return @[spawnLE("Цвет = " & $win.color, "link", ChangeColor)]

proc OpenSettings(ListEl: var ListElement) = 
  win.body = GenerateSettings()
  AlignBodyText()

proc ChangeColor(ListEl: var ListElement) = 
  if int(win.color) < 37: inc win.color
  else: win.color = Black
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
    of kg_down:
      if win.section == LEFT: 
        if win.active < win.menu.len-1: inc win.active
      else: 
        if win.active < win.body.len-1: inc win.active
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