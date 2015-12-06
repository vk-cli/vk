import osproc, os, terminal, strutils, unicode, tables, threadpool, sequtils
from ncurses import initscr, getmaxyx, endwin, curs_set
import vkapi, cfg

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
  maxRuneOrd = 3000

type 
  Message     = object
    name, text          : string
    color               : Colors
  ListElement = object
    text, link          : string
    callback            : proc(ListEl: var ListElement): void
    getter              : proc: seq[ListElement] 
  Colors      = enum
    Gray      = 30,
    Red,
    Green,
    Yellow,
    Blue,
    Pink,
    Mint,
    White
  Window      = object
    x, y, key, offset              : int
    active, last_active, chatid    : int
    section, start, messageOffset  : int
    color                          : Colors
    title                          : string
    menu, body, buffer             : seq[ListElement]
    dialog                         : seq[Message]
    maxname, counter, scrollOffset : int
    dialogsOpened                  : bool

proc nop(ListEl: var ListElement) = discard
proc nopget(): seq[ListElement] = discard
proc open(ListEl: var ListElement)
proc chat(ListEl: var ListElement)

proc ChangeColor(ListEl: var ListElement)
proc ChangeState(ListEl: var ListElement)
proc GetFriends(): seq[ListElement]
proc GetDialogs(): seq[ListElement]
proc GetMusic(): seq[ListElement]
proc GenerateSettings(): seq[ListElement]

proc spawnLE(txt: string, lnk = "", clback: proc(ListEl: var ListElement): void, gett: proc: seq[ListElement]): ListElement = 
  return ListElement(text: txt, link: lnk, callback: clback, getter: gett)

var 
  win = Window(
    scrollOffset: 1,
    messageOffset: 0,
    color:    Blue,
    menu:     @[spawnLE("Друзья", "link", open, GetFriends),
                spawnLE("Сообщения", "link", open, GetDialogs),
                spawnLE("Музыка", "link", open, GetMusic),
                spawnLE("Настройки", "link", open, GenerateSettings)],
    )

proc AlignBodyText() = 
  for i, e in win.body:
    if runeLen(e.text) + win.offset+1 > win.x:
      win.body[i].text = e.text[0..win.x-win.offset-6] & "..."
    var align = runeLen(win.title) - win.offset - 1 
    for i, e in win.body:
      if runeLen(e.text) + win.offset < win.x:
        win.body[i].text = win.body[i].text & spaces(align - runeLen(e.text))

proc chat(ListEl: var ListElement) = 
  win.dialogsOpened = true
  win.body   = newSeq[ListElement](0)
  win.buffer = newSeq[ListElement](0)
  win.dialog = newSeq[Message](0)
  win.chatid = ListEl.link.parseInt
  var
    senderName = ""
    lastName   = "nil"
  for message in vkhistory(win.chatid, win.messageOffset, win.y).items:
    senderName = message.name
    if senderName != lastName:
      lastName = senderName
      win.dialog.add(Message(name: senderName, text: message.msg))
    else:
      win.dialog.add(Message(name: "", text: message.msg))
  win.messageOffset += win.y

proc LoadMoarMsg() = 
  var
    senderName = ""
    lastName   = "nil"
    cacheMsg = newSeq[Message](0)
  for message in vkhistory(win.chatid, win.messageOffset, win.y).items:
    senderName = message.name
    if senderName != lastName:
      lastName = senderName
      cacheMsg.add(Message(name: senderName, text: message.msg))
    else:
      cacheMsg.add(Message(name: "", text: message.msg))
  win.messageOffset += win.y
  win.dialog = concat(cacheMsg, win.dialog)

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

proc GetFriends(): seq[ListElement] = 
  var friends = newSeq[ListElement](0)
  for fr in vkfriends():
    friends.add(spawnLE(fr.name, $fr.id, chat, nopget))
  return friends

proc GetDialogs(): seq[ListElement] = 
  var chats = newSeq[ListElement](0)
  for msg in vkdialogs().items:
    chats.add(spawnLE(msg.dialog, $msg.id, chat, nopget))
  return chats

proc DurationToStr(n: int): string = 
  var sec = $(n mod 60)
  if sec.len == 1: sec = "0" & sec
  return $(n div 60) & ":" & $sec

proc GetMusic(): seq[ListElement] = 
  var music = newSeq[ListElement](0)
  for mus in vkmusic():
    var rmod = 0
    for r in mus.track.toRunes():
      if r.ord > maxRuneOrd: inc(rmod)
    var
      name: string
      durationText = DurationToStr(mus.duration)
      sp = win.x-win.offset-runeLen(mus.track)-9-rmod
    if sp < 0:
      name = "   " & mus.track
    else:
      name = "   " & mus.track & spaces(sp) & durationText
    music.add(spawnLE(name, mus.link, nop, nopget))
  return music

proc GenerateSettings(): seq[ListElement] = 
  return @[spawnLE("Цвет = " & $win.color, "link", ChangeColor, nopget)]

proc SetText(ListEl: var ListElement, s: string) = 
  ListEl.text = s
  AlignBodyText()

proc ChangeColor(ListEl: var ListElement) = 
  if int(win.color) < 37: inc win.color
  else: win.color = Gray
  ListEl.SetText("Цвет = " & $win.color)

proc clear() = discard execCmd("clear")

proc init() = 
  clear()
  getmaxyx(initscr(), win.y, win.x)
  endwin()
  discard execCmd("tput civis")
  var 
    length = win.x div 2 - runeLen(win.title) div 2
    title = spaces(length) & win.title & spaces(length)
  if runeLen(title) > win.x: title = title[0..^2]
  win.title = title
  win.maxname = win.x div 4 + 1
  for e in win.menu:
    if win.offset < runeLen(e.text): win.offset = runeLen(e.text)
  win.offset += 5
  for i, e in win.menu:
    win.menu[i].text = win.menu[i].text & spaces(win.offset - runeLen(e.text))
  SetWinx(win.x-win.maxname-4)

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
  selected(" " & $win.counter & " ✉ " & win.title[5..win.title.len] & "\n")

proc Controller() = 
  win.key = getch().ord
  case win.key:
    of kg_left:
      if win.section == RIGHT:
        win.dialog  = newSeq[Message](0)
        win.active  = win.last_active
        if win.dialogsOpened:
          win.menu[win.active].callback(win.menu[win.active])
          win.scrollOffset  = 1
          win.messageOffset = 0
          win.dialogsOpened = false
          win.active        = 0
        else:
          win.section = LEFT
          win.body    = newSeq[ListElement](0)
      else:
        win.dialog = newSeq[Message](0)
    of kg_right:
      if win.section == LEFT:
        win.menu[win.active].callback(win.menu[win.active])
        win.last_active = win.active
        win.active      = 0
        win.section     = RIGHT
      else:
        win.body[win.active].callback(win.body[win.active])
    of kg_up:
      if win.dialogsOpened:
          win.scrollOffset += win.y-3
          if win.scrollOffset+win.y-3 > win.dialog.len: LoadMoarMsg()
      else:
        if win.active > 0: dec win.active
        elif win.buffer.len != 0 and win.start != 0:
          dec win.start
          win.body = win.buffer[win.start..win.start+win.y-4]
          AlignBodyText()
    of kg_down:
      if win.section == LEFT: 
        if win.active < win.menu.len-1: inc win.active
      else:
        if win.dialogsOpened and win.scrollOffset != 1:
          win.scrollOffset -= win.y-3
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

proc DrawDialog() = 
  for i, e in win.dialog[0..^win.scrollOffset]:

    var 
      temp, sep: string
      sum = 0

    setCursorPos(0, 3+i)

    if runeLen(e.name) < win.maxname:
      temp = spaces(win.maxname-runeLen(e.name)) & e.name
    else:
      temp = e.name[0..win.maxname-4] & "..."
    if runeLen(e.name) != 0:
      sep = ": "
    else:
      sep = "  "

    for c in e.name:
      sum += c.int

    # one char padding
    temp = " " & temp

    setForegroundColor(ForegroundColor(Colors(31+sum mod 6)))
    stdout.write temp
    setForegroundColor(ForegroundColor(White))
    echo sep & e.text

proc DrawBody() = 
  for i, e in win.body:
    setCursorPos(win.offset+2, 3+i)
    if i == win.active and win.section == RIGHT: selected(e.text)
    else: regular(e.text)

proc cli() = 
  while win.key notin kg_esc:
    clear()
    if win.dialog.len == 0:
      Statusbar()
      DrawMenu()
      DrawBody()
    else:
      DrawDialog()
    Controller()

proc pushTo(config: var Table) = 
  config["token"] = GetToken()
  config["color"] = $win.color.int

proc popFrom(config: Table) = 
  if config.len != 0:
    echo "Загрузка..."
    SetToken(config["token"])
    win.color = Colors(parseInt(config["color"]))

proc updCounter() = 
  win.counter = vkcounter()
  #todo redraw statusbar

proc newMessage(name: string, msg: string) = 
  echo(name & " : " & msg)
  #win.dialog.add(Message(name: name, text: msg))

proc entryPoint() = 
  clear()
  var config = load()
  popFrom(config)
  vkinit()
  win.title = vkusername()
  win.counter = vkcounter()
  init()
  startLongpoll()
  cli()
  discard execCmd("tput cnorm")
  pushTo(config)
  save(config)
  clear() 
  quit(QuitSuccess)

{.experimental.}
when isMainModule: 
  #parallel:
  spawn longpollAsync(updCounter, newMessage)
  spawn entryPoint()
  sync()
  #ntryPoint()
