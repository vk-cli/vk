import osproc, strutils, json, httpclient, cgi, tables, sequtils, re
import locks, macros, asyncdispatch, asynchttpserver, strtabs, os, times, unicode
from future import `=>`

const 
  quitOnApiError  = true
  quitOnHttpError = true
  conferenceIdStart = 2000000000
  longpollRestartSleep = 2000
  vkmethod   = "https://api.vk.com/method/"
  apiversion = "5.40"
  fwdprefix = "| "
  fwdname = "➥ "
  wmodstep = -2

type 
  API = object
    token, username: string
    userid: int

  longpollInfo = object
    key, server: string
    ts: int
  longpollResp = object
    failed, ts: int

  vkmessage* = object
    msgid*, fromid*, chatid*: int
    msg*, name*: string
    fwdm*, findname*: bool
    fwduid*: int

var 
  api = API()
  threadLock: Lock
  longpollAllowed = false
  longpollChatid = 0
  nameCache = initTable[int, string]()
  nameUids: seq[int]
  winx: int

#===== api mechanics =====

proc checkError(json: JsonNode): string =
  if json.hasKey("error"): 
    let errobj = json["error"]
    if errobj.hasKey("error_text"): return errobj["error_text"].str
    if errobj.hasKey("error_msg"): return errobj["error_msg"].str
  else:
    return ""

proc handleError(json: JsonNode): bool = 
  let err = checkError(json)
  if err == "": return true
  echo("Api error: " & err)
  if quitOnApiError: 
    quit("Application exit", QuitSuccess)
  else: return false

proc handleHttpError(emsg: string) = 
  echo("Http error: " & emsg)
  if quitOnHttpError: quit("Проверьте интернет соединение", QuitSuccess)

proc SetToken*(tk: string = "") = 
  if tk.len == 0:
    try:
      discard getContent("http://vk.com")
    except:
      handleHttpError(getCurrentExceptionMsg())
    stdout.write "Вставьте сюда access token: "
    discard execCmd("xdg-open \"http://oauth.vk.com/authorize?client_id=5110243&scope=friends,wall,messages,audio,offline&redirect_uri=blank.html&display=popup&response_type=token\" >> /dev/null")
    api.token = stdin.readLine()
  else: api.token = tk

proc SetWinx*(maxWidth: int) = winx = maxWidth

proc GetToken*(): string = return api.token

proc request(methodname: string, vkparams: Table, error_msg: string, offset = -1, count = -1, returnPure = false): JsonNode= 
  var url = vkmethod & methodname & "?"
  for key, value in vkparams.pairs:
    url &= key & "=" & encodeUrl(value) & "&"

  if offset > -1 and count > -1: 
    url &= "offset=" & $offset & "&" & "count=" & $count & "&"

  url &= "v=" & apiversion & "&access_token=" & api.token
  var response: string
  try:
    response = getContent(url)
  except:
    handleHttpError(getCurrentExceptionMsg())
  let pjson = parseJson(response)
  if returnPure: return pjson
  if not handleError(pjson):
    echo(error_msg, QuitSuccess)
    return
  else:
    return pjson["response"]

proc getNextOffset(offset: int, argcount: int, count: int): int = 
  if offset+argcount < count:
    return offset+argcount
  else:
    return 0

proc vkinit*() = 
  SetToken(api.token)
  discard request("users.get", {"name_case":"Nom"}.toTable, "Неверный access token")

#===== api methods wrappers =====

proc vkcounter*(): int =
  let rawjson = request("account.getCounters", {"filter": "messages"}.toTable, "Не могу загрузить счетчик сообщений")
  if rawjson.kind != JObject: return 0
  if rawjson.hasKey("messages"):
    return rawjson.getFields[0][1].num.int
  else:
    return 0

proc vkusernames*(ids: seq[int]): Table[int, string] = 
  var
    rtnames = initTable[int, string]()
    fids = newSeq[int](0)

  for w in ids:
    if nameCache.hasKey(w): 
      rtnames[w] = nameCache[w]
    else:
      fids.add(w)

  let
    jids = map(fids, proc(x: int): string = return $x)
    sids = join(jids, ",")

  let rawjson = request("users.get", {"user_ids": sids, "name_case":"Nom"}.toTable, "Не могу получить юзернэйм")
  let jelems = rawjson.getElems()
  for j in jelems:
    let
      name = j["first_name"].str & " " & j["last_name"].str
      id = j["id"].num.int32
    rtnames[id] = name
    nameCache.add(id, name)
  return rtnames

proc vkusername*(id: int = 0): string = 
  if id == 0: 
    let j = request("users.get", {"name_case":"Nom"}.toTable, "Не могу получить юзернэйм").elems[0]
    api.userid = j["id"].num.int
    return j["first_name"].str & " " & j["last_name"].str
  else:
    return vkusernames(@[id])[id]

proc vkfriends*(): seq[tuple[name: string, id: int]] = 
  let
    rawjson = request("friends.get", {"user_id": $api.userid, "order": "hints", "fields": "first_name"}.toTable, "Не могу загрузить друзей")
    json    = rawjson.getFields[1][1]
  var friends = newSeq[tuple[name: string, id: int]](0)
  for fr in json:
    var status = "  "
    if fr["online"].num == 1: status = "⚫ "
    let name = status & fr["first_name"].str & " " & fr["last_name"].str
    friends.add((name, fr["id"].num.int))
  return friends 

proc cropMsg(msg: string, wmod: int = 0): seq[string] = 
  if msg.len <= winx: return msg.splitLines()
  let lf = "\n".toRunes()[0]
  var
    tx = msg.toRunes()
    cc = 0
  for n in low(tx)..high(tx):
    if n+1 == high(tx): break
    if tx[n+1] == lf: 
      cc = 0
      continue
    if cc == (winx+wmod):
      cc = 0
      tx.insert("\n".toRunes(), n)
    else:
      inc(cc)
  return ($tx).splitLines()

proc getMessages(items: seq[JsonNode], dialogid: int): seq[vkmessage]
proc getFwdMessages(fwdmsg: seq[JsonNode], p: vkmessage, lastwmod = -2): seq[vkmessage]

proc uidsInit() = nameUids = newSeq[int](0)
proc parseUidsForNames(items: seq[JsonNode], idname = "user_id") = 
  for t in items:
    let u = t[idname].num.int
    if not nameUids.contains(u): nameUids.add(u)

proc resolveNames(rm: var seq[vkmessage]) = 
  let names = vkusernames(nameUids)
  for n in low(rm)..high(rm):
    let q = rm[n]
    if q.findname and not q.fwdm:
      rm[n].name = names[q.fromid]
    elif q.findname and q.fwdm and q.fwduid > 0:
      rm[n].msg = q.msg & names[q.fwduid]


proc getFwdMessages(fwdmsg: seq[JsonNode], p: vkmessage, lastwmod = -2): seq[vkmessage] = 
  var
    fs = newSeq[vkmessage](0) 
    lastuid   = -2
  parseUidsForNames(fwdmsg, "user_id")
  for f in fwdmsg:
    var
      wfid = f["user_id"].num.int
      wmsg = cropMsg(f["body"].str, lastwmod)
    if wfid != lastuid:
      lastuid = wfid
      fs.add(vkmessage(
          chatid: p.chatid, fromid: p.fromid, msgid: p.msgid,
          name: "", fwdm: true, findname: true,
          fwduid: wfid,
          msg: fwdprefix & fwdname
        ))

    for l in wmsg:
      fs.add(vkmessage(
          chatid: p.chatid, fromid: p.fromid, msgid: p.msgid,
          name: "", fwdm: true, findname: false,
          fwduid: wfid,
          msg: fwdprefix & l
        ))

    if f.hasKey("fwd_messages"):
      for cl in getFwdMessages(f["fwd_messages"].getElems(), p, (lastwmod+wmodstep)):
        var cm = cl
        cm.msg = fwdprefix & cm.msg
        fs.add(cm)
      
  return fs


proc getMessages(items: seq[JsonNode], dialogid: int): seq[vkmessage] = 
  var
    qitems = newSeq[vkmessage](0)
  parseUidsForNames(items, "from_id")
  for m in items:
    var
      mitems = newSeq[vkmessage](0)
      mfwd = newSeq[vkmessage](0)
      mlines = cropMsg(m["body"].str)
      mid = m["id"].num.int
      mfrom = m["from_id"].num.int

    let qmm = vkmessage(
        msgid: mid, fromid: mfrom, chatid: dialogid,
        name: "", msg: mlines[0],
        fwdm: false, findname: true
      )

    if m.hasKey("fwd_messages"):
      mfwd = getFwdMessages(m["fwd_messages"].getElems(), qmm)

    mitems.add(qmm)
    if mlines.len > 1: 
      for fml in 1..mlines.high():
        mitems.add(vkmessage(
            msgid: mid, fromid: mfrom, chatid: dialogid,
            name: "", msg: mlines[fml],
            fwdm: false, findname: false
          ))
    for ffm in mfwd:
      mitems.add(ffm)
    qitems.insert(mitems, 0)
  qitems.resolveNames()
  return qitems

proc vkhistory*(userid: int, offset = 0, count = 200): tuple[items: seq[vkmessage], next_offset: int] = 
  let
    json = request("messages.getHistory", {"user_id":($userid), "rev":"0"}.toTable, "Unable to get msghistory", offset, count)
  var
    allcount = json["count"].num.int32
    noffset = getNextOffset(offset, count, allcount)
    items: seq[vkmessage]
  if allcount > 0:
    uidsInit()
    items = getMessages(json["items"].getElems(), userid)
  return (items, noffset)

proc vksend(peerid: int, msg: string): bool = 
  if msg.len == 0: return false
  let resp = request("messages.send", {"peer_id":($peerid), "message":msg}.toTable, "Unable to send message")
  if resp.kind != JInt: return false
  return true

proc vkmusic*(): seq[tuple[track: string, duration: int, link: string]] =
  let
    rawjson = request("audio.get", {"user_id": $api.user_id, "need_user": "0"}.toTable, "Не могу загрузить музыку")
    json    = rawjson.getFields[1][1]
  var music = newSeq[tuple[track: string, duration: int, link: string]](0)
  for track in json:
    let
      trackname     = track["artist"].str & " - " & track["title"].str
      trackduration = track["duration"].num.int
      url           = track["url"].str
    music.add((trackname, trackduration, url))
  return music

proc vkdialogs*(offset = 0, count = 200): tuple[items: seq[tuple[dialog: string, id: int]], next_offset: int] = 
  let
    json = request("messages.getDialogs", initTable[string, string](), "Unable to get dialogs", offset, count)
  var
    preitems = newSeq[tuple[title: string, unread: bool, getname: bool, id: int]](0)
    uids = newSeq[int](0)
    items = newSeq[tuple[dialog: string, id: int]](0)
    allcount = json["count"].num.int32
    noffset = getNextOffset(offset, count, allcount)
  if allcount > 0:
    let rawitems = json["items"].getElems()
    for d in rawitems:
      let m = d["message"]
      var
        st = ""
        dlgid = 0
        unreadf = false
        getname = false
      if d.hasKey("unread"): 
        if d["unread"].num.int32 > 0: unreadf = true
      if m.hasKey("chat_id"):
        dlgid = conferenceIdStart + m["chat_id"].num.int32
        st = m["title"].str
      else:
        dlgid = m["user_id"].num.int32
        st = ""
        getname = true
        uids.add(dlgid)
      preitems.add((st, unreadf, getname, dlgid))

    let unames = vkusernames(uids)
    for p in preitems:
      var dst = "  "
      if p.unread: dst = "⚫ "
      if p.getname:
        if not unames.hasKey(p.id):
          dst &= "unable to get name: id " & $p.id
        else:
          dst &= unames[p.id]
      else:
        dst &= p.title
      items.add((dst, p.id))

  return (items, noffset)

proc vkmsgbyid(ids: seq[int]): seq[vkmessage] = 
  let
    i = ids.map(q => $q).join(",")
    j = request("messages.getById", {"message_ids": i}.toTable, "unable to get messages")
    items = j["items"].getElems()
    names = vkusernames(items.map(q => q["user_id"].num.int))
  var r = newSeq[vkmessage](0)
  for q in items:
    let fid = q["user_id"].num.int
    r.add(vkmessage(
      msgid: q["id"].num.int,
      fromid: fid, chatid: -1,
      msg: q["body"].str,
      name: names[fid]
    ))
  return r

#===== longpoll =====

proc parseLongpollUpdates(arr: seq[JsonNode], longmsg: proc(name: string, msg: string)) = 
  if longpollChatid < 1: return
  for u in arr:
    let q = u.getElems()
    if q[0].num == 4: #message update
      let
        msgid = q[1].num.int
        chatid = q[3].num.int
        time = q[4].num.int
        text = q[6].str
        att = q[7]
      if chatid != longpollChatid: return
      #echo(att.pretty())
      var
        fromid = chatid
        lfwd = newSeq[int](0)
        qfwd = newSeq[tuple[uid: int, txt: string]](0)
        vfwd = newseq[vkmessage](0)
      if fromid >= conferenceIdStart:
        fromid = att["from"].str.parseInt()

      if att.hasKey("fwd"):
        let
          fwd = att["fwd"].str.split(",")
        for ff in fwd:
          let
            b = ff.findBounds(re(r"\d+_"))
            lst = b.last+1
          if b.first == 0:
            lfwd.add(parseInt(ff[lst..high(ff)]))
        if lfwd.len > 0:
          vfwd = vkmsgbyid(lfwd)
          qfwd = vfwd.map(f => (f.fromid, f.msg))

      var name = initTable[int, string]() 
      for f in vfwd: name[f.fromid] = f.name
      name[fromid] = vkusername(fromid)
      #let pre = vkpremsg(msgid: msgid, fromid: fromid, body: text, fwd: qfwd)
      #for sm in getMessages(pre, chatid, name):
      #  longmsg(sm.name, sm.msg)

proc longpollParseResp(json: string, updc: proc(), longmsg: proc(name: string, msg: string)): longpollResp  =
  var
    o = parseJson(json)
    fail = -1
    ts = -1
  if hasKey(o, "failed"): 
    fail = getNum(o["failed"]).int32
  else:
    if hasKey(o, "updates"):
      acquire(threadLock)
      #echo(json)
      updc()
      parseLongpollUpdates(getElems(o["updates"]), longmsg)
      release(threadLock)
  if hasKey(o, "ts"):
    ts = getNum(o["ts"]).int32
  return longpollResp(ts: ts, failed: fail)

proc longpollRoutine(info: longpollInfo, updc: proc(), longmsg: proc(name: string, msg: string)) = 
  var currTs = info.ts
  while true:
    let
      lpUri = "https://" & info.server & "?act=a_check&key=" & info.key & "&ts=" & $currTs & "&wait=25&mode=2"
      resp = get(lpUri)
      #todo check server response code\status
      lpresp = longpollParseResp(resp.body, updc, longmsg)
    if lpresp.failed != -1:
      if lpresp.failed != 1:
        break #get new server
    currTs = lpresp.ts

proc getLongpollInfo(): longpollInfo = 
  let o = request("messages.getLongPollServer", {"use_ssl":"1", "need_pts":"0"}.toTable, "unable to get Longpoll server")
  return longpollInfo(
    key: getStr(o["key"]),
    server: getStr(o["server"]),
    ts: getNum(o["ts"]).int32
  )

proc longpollAsync*(updc: proc(), longmsg: proc(name: string, msg: string)) {.thread,gcsafe.} =
  while true:
    if longpollAllowed: longpollRoutine(getLongpollInfo(), updc, longmsg)
    sleep(longpollRestartSleep)

proc startLongpoll*() = 
  initLock(threadLock)
  longpollAllowed = true

proc setLongpollChat*(chatid: int, conference = false) = 
  var cid = chatid
  if conference: cid += conferenceIdStart
  longpollChatid = cid
