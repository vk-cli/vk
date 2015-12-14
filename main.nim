import osproc, os, terminal, strutils, unicode, tables, threadpool, sequtils
from ncurses import initscr, getmaxyx, endwin, curs_set
import vkapi, cfg

proc memset(s: pointer, c: cint, n: csize) {.header: "<string.h>",
  importc: "memset", tags: [].}
proc fgets(c: cstring, n: int, f: File): cstring {.importc: "fgets",
  header: "<stdio.h>", tags: [ReadIOEffect].}
proc memchr(s: pointer, c: cint, n: csize): pointer {.importc: "memchr",
  header: "<string.h>", tags: [].}

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
  maxRuneOrd = 10000

type 
  Message     = object
    name, text, time    : string
    unread              : bool
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
    title, username                : string
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

proc spawnLE(txt: string, lnk = "", clback: proc(ListEl: var ListElement): void,
  gett: proc: seq[ListElement]): ListElement = 
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
  setLongpollChat(win.chatid)
  for message in vkhistory(win.chatid, win.messageOffset, win.y).items:
    var
      lastname = ""
      i = 1
    if win.dialog.len != 0:
      while lastname == "":
        lastname = win.dialog[^i].name
        inc i
    if message.msg.len != 0:
      if lastname != message.name:
        win.dialog.add(Message(name: "", text: "", time: "", unread: false))
        win.dialog.add(Message(name: message.name, text: message.msg, time: message.strtime, unread: message.unread))
      else:
        win.dialog.add(Message(name: "", text: message.msg, time: message.strtime, unread: message.unread))
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
      cacheMsg.add(Message(name: "", text: "", time: "", unread: false))
      cacheMsg.add(Message(name: senderName, text: message.msg, time: message.strtime, unread: message.unread))
    else:
      cacheMsg.add(Message(name: "", text: message.msg, time: message.strtime, unread: message.unread))
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
  let length = win.x div 2 - runeLen(win.username) div 2
  win.title = spaces(length) & win.username & spaces(length)
  if runeLen(win.title) > win.x: win.title = win.title[0..^2]
  win.maxname = win.x div 5 + 1
  for e in win.menu:
    if win.offset < runeLen(e.text): win.offset = runeLen(e.text)
  win.offset += 5
  for i, e in win.menu:
    win.menu[i].text = win.menu[i].text & spaces(win.offset - runeLen(e.text))
  SetWinx(win.x-win.maxname-4)

proc readinput(f: File, line: var TaintedString): bool =
  var pos = 0
  # Use the currently reserved space for a first try
  
  # var space = cast[PGenericSeq](line.string).space
  var space = 0
  line.string.setLen(space)

  while true:
    # memset to \l so that we can tell how far fgets wrote, even on EOF, where
    # fgets doesn't append an \l
    memset(addr line.string[pos], '\l'.ord, space)
    if fgets(addr line.string[pos], space, f) == nil:
      line.string.setLen(0)
      return false
    let m = memchr(addr line.string[pos], '\l'.ord, space)
    if m != nil:
      # \l found: Could be our own or the one by fgets, in any case, we're done
      var last = cast[ByteAddress](m) - cast[ByteAddress](addr line.string[0])
      if last > 0 and line.string[last-1] == '\c':
        line.string.setLen(last-1)
        return true
        # We have to distinguish between two possible cases:
        # \0\l\0 => line ending in a null character.
        # \0\l\l => last line without newline, null was put there by fgets.
      elif last > 0 and line.string[last-1] == '\0':
        if last < pos + space - 1 and line.string[last+1] != '\0':
          dec last
      line.string.setLen(last)
      return true
    else:
      # fgets will have inserted a null byte at the end of the string.
      dec space
    # No \l found: Increase buffer and read more
    inc pos, space
    space = 128 # read in 128 bytes at a time
    line.string.setLen(pos+space)

proc input(f: File): TaintedString =
  result = TaintedString(newStringOfCap(80))
  discard readLine(f, result)

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
        setLongpollChat(0)
        win.dialog = newSeq[Message](0)
    of kg_right:
      if win.section == LEFT:
        win.menu[win.active].callback(win.menu[win.active])
        win.last_active = win.active
        win.active      = 0
        win.section     = RIGHT
      else:
        if win.dialogsOpened:
          setCursorPos(0, win.y)
          stdout.write(": ")
          let msg = stdin.input()
          if msg.len != 0:
            if not vksendAsync(win.chatid, msg):
              echo "Сообщение не отправлено, подождите отправки предыдущего"
              discard stdin.readLine()
        else: win.body[win.active].callback(win.body[win.active])
    of kg_up:
      if win.dialogsOpened:
          win.scrollOffset += win.y-3
          if win.scrollOffset+4 > win.dialog.len: LoadMoarMsg()
          if win.scrollOffset > win.dialog.len and win.y > win.dialog.len:
            win.scrollOffset = 1
          if win.dialog.len-win.scrollOffset < win.y:
            win.scrollOffset = win.dialog.len-win.y+1
            if win.scrollOffset <= 0: win.scrollOffset = 1
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
          if win.scrollOffset <= 0: win.scrollOffset = 1
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
  const
    datew = 5
    fullw = datew+2
  for i, e in win.dialog[0..^win.scrollOffset]:
    var 
      temp: string
      time: string
      sep = ": "
      sum = 0
      max = win.maxname-fullw
    setCursorPos(0, 3+i)
    if runeLen(e.name) < max:
      temp = spaces(max-runeLen(e.name)) & e.name
    else:
      temp = e.name[0..max-4] & "..."

    time = " " & e.time
    if e.time.len == 0:
      time &= spaces(datew)
    if e.unread: time &= "⚫"
    else: time &= " "

    if e.name.len == 0: sep = "  "
    for c in e.name: sum += c.int
    # one char padding
    temp = " " & temp

    setForegroundColor(ForegroundColor(Colors(31+sum mod 6)))
    stdout.write temp
    setForegroundColor(ForegroundColor(White))
    stdout.write time
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

proc Update(ncounter: int) = 
  let last = win.counter
  win.counter = ncounter
  if last != win.counter and win.last_active == 1:
    win.buffer = GetDialogs()
    if win.buffer.len+2 < win.y:
      win.body = win.buffer
      win.buffer = newSeq[ListElement](0)
    else:
      win.start = 0
      win.body = win.buffer[0..win.y-4]
    AlignBodyText()

proc newMessage(m: vkmessage) = 
  if win.dialog.len != 0:
    var
      lastname = ""
      i = 1
    while lastname == "":
      lastname = win.dialog[^i].name
      inc i
    if lastname != m.name:
      win.dialog.add(Message(name: "", text: "", time: "", unread: false))
      win.dialog.add(Message(name: m.name, text: m.msg, time: m.strtime, unread: m.unread))
    else:
      win.dialog.add(Message(name: "", text: m.msg, time: m.strtime, unread: m.unread))
    clear()
    DrawDialog()

proc readMessage(msgid: int) = 
  discard

proc sentMessage(sendid: int, newmsgid: int, newunread: bool, newtime: float, newstrtime: string) = 
  dwr("sentmessage sid:" & $sendid & " mid:" & $newmsgid & " uflag:" & $newunread & " (" & newstrtime & ")")

proc entryPoint() = 
  clear()
  var config = load()
  popFrom(config)
  vkinit()
  win.username = vkusername()
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
  spawn longpollAsync(Update, newMessage, readMessage, sentMessage)
  spawn eventLoop()
  spawn entryPoint()
  sync()
  #ntryPoint()
