import osproc, strutils, json, httpclient, cgi, tables, sequtils
import locks, macros, asyncdispatch, asynchttpserver, strtabs, os, times

const 
  quitOnApiError  = true
  quitOnHttpError = true
  conferenceIdStart = 2000000000
  longpollRestartSleep = 2000

type 
  API = object
    token, username: string
    userid: int

  longpollInfo = object
    key, server: string
    ts: int
  longpollResp = object
    failed, ts: int

var 
  api = API()
  threadLock: Lock
  longpollAllowed = false
  longpollChatid = 0
  nameCache = initTable[int, string]()

let 
  vkmethod   = "https://api.vk.com/method/"
  apiversion = "5.40"

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

proc GetToken*(): string = return api.token

proc request(methodname: string, vkparams: Table, error_msg: string, returnPure = false): JsonNode = 
  var url = vkmethod & methodname & "?"
  for key, value in vkparams.pairs:
    url &= key & "=" & encodeUrl(value) & "&"
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

proc vkinit*() = 
  SetToken(api.token)
  discard request("users.get", {"name_case":"Nom"}.toTable, "Неверный access token")

#===== api methods wrappers =====

proc vkcounter*(): int =
  let rawjson = request("account.getCounters", {"filter": "messages"}.toTable, "Не могу загрузить счетчик сообщений")
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
    if fr["online"].bval: status = "⚫ "
    let name = status & fr["first_name"].str & " " & fr["last_name"].str
    friends.add((name, fr["id"].num.int))
  return friends 

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

proc vkdialogs*(): seq[tuple[dialog: string, id: int]] = 
  let
    json = request("messages.getDialogs", {"count":"200"}.toTable, "Unable to get dialogs")
    count = json["count"].num.int32
  var
    uids = newSeq[int](0)
    preitems = newSeq[tuple[title: string, unread: bool, getname: bool, id: int]](0)
    items = newSeq[tuple[dialog: string, id: int]](0)
  if count > 0:
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
      var dst = ""
      if p.unread: dst &= "⚫ "
      if p.getname:
        if not unames.hasKey(p.id):
          dst &= "unable to get name: id " & $p.id
        else:
          dst &= unames[p.id]
      else:
        dst &= p.title
      items.add((dst, p.id))

  return items

#===== longpoll =====

proc parseLongpollUpdates(arr: seq[JsonNode]) = 
  if longpollChatid < 1: return
  for u in arr:
    let q = u.getElems()
    if q[0].num == 4: #message update
      let
        msgid = q[1].num.int32
        chatid = q[3].num.int32
        time = q[4].num.int32
        text = q[6].str
        att = q[7]
      if chatid != longpollChatid: return
      var fromid = chatid
      if fromid >= conferenceIdStart:
        fromid = att["from"].num.int32
      let name = vkusername(fromid)
      #addMessage(name, text)

proc longpollParseResp(json: string): longpollResp  =
  var
    o = parseJson(json)
    fail = -1
    ts = -1
  if hasKey(o, "failed"): 
    fail = getNum(o["failed"]).int32
  else:
    if hasKey(o, "updates"):
      acquire(threadLock)
      echo(json)
      parseLongpollUpdates(getElems(o["updates"]))
      release(threadLock)
  if hasKey(o, "ts"):
    ts = getNum(o["ts"]).int32
  return longpollResp(ts: ts, failed: fail)

proc longpollRoutine(info: longpollInfo) = 
  var currTs = info.ts
  while true:
    let
      lpUri = "https://" & info.server & "?act=a_check&key=" & info.key & "&ts=" & $currTs & "&wait=25&mode=2"
      resp = get(lpUri)
      #todo check server response code\status
      lpresp = longpollParseResp(resp.body)
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

proc longpollAsync*() {.thread,gcsafe.} =
  while true:
    if longpollAllowed: longpollRoutine(getLongpollInfo())
    sleep(longpollRestartSleep)

proc startLongpoll*() = 
  initLock(threadLock)
  longpollAllowed = true

proc setLongpollChat*(chatid: int, conference = false) = 
  var cid = chatid
  if conference: cid += conferenceIdStart
  longpollChatid = chatid
