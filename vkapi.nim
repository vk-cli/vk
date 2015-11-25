import osproc, strutils, json, httpclient, cgi, tables
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

proc parse(response: string): JsonNode = 
  let json = parseJson(response)
  return json["response"]

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

proc request(methodname: string, vkparams: Table, error_msg: string): JsonNode = 
  var url = vkmethod & methodname & "?"
  for key, value in vkparams.pairs:
    url &= key & "=" & encodeUrl(value) & "&"
  url &= "v=" & apiversion & "&access_token=" & api.token
  var response: string
  try:
    response = getContent(url)
  except:
    handleHttpError(getCurrentExceptionMsg())
  let 
    rawjson = parse(response)
  if not handleError(rawjson):
    echo(error_msg, QuitSuccess)
    return
  else:
    return rawjson

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

proc vkusername*(id: int = 0): string = 
  var rawjson: JsonNode
  if id == 0: rawjson = request("users.get", {"name_case":"Nom"}.toTable, "Не могу получить юзернэйм")
  else: rawjson = request("users.get", {"user_ids": $id, "name_case":"Nom"}.toTable, "Не могу получить юзернэйм")
  let json = rawjson[0]
  api.userid = json["id"].num.int
  return json["first_name"].str & " " & json["last_name"].str

proc vkfriends*(): seq[tuple[name: string, id: int]] = 
  let
    rawjson = request("friends.get", {"user_id": $api.user_id, "order": "hints", "fields": "first_name"}.toTable, "Не могу загрузить друзей")
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
