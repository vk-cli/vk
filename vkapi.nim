import osproc, strutils, json, httpclient, cgi, tables, locks, macros, asyncdispatch, asynchttpserver, strtabs

type
  API = object
    token, username: string
    userid: int
  longpollInfo = object
    key, server: string
    ts: int
  longpollResp = object
    failed, ts: int
  vkfriend = object
    first_name, last_name: string
    id: int
    online: bool

var
  api = API()
  longpollThread: Thread[int]
  threadLock: Lock

let 
  vkmethod   = "https://api.vk.com/method/"
  apiversion = "5.40"
  dummyint   = 1337

#===== api mechanics =====

proc SetToken*(tk: string = "") = 
  if tk.len == 0:
    try:
      discard getContent("http://vk.com")
    except:
      quit("Проверьте интернет соединение", QuitSuccess)
    stdout.write "Вставьте сюда access token: "
    discard execCmd("xdg-open \"http://oauth.vk.com/authorize?client_id=5110243&scope=friends,wall,messages,audio,offline&redirect_uri=blank.html&display=popup&response_type=token\" >> /dev/null")
    api.token = stdin.readLine()
  else: api.token = tk

proc GetToken*(): string = return api.token

proc asyncGet(url: string): Response {.async.} =
  let
    client = newAsyncHttpClient()
    resp = await client.request(url)
  return resp

proc request(methodname: string, vkparams: Table): string {.thread.} = 
  var url = vkmethod & methodname & "?"
  for key, value in vkparams.pairs:
    url &= key & "=" & encodeUrl(value) & "&"
  url &= "v=" & apiversion & "&access_token=" & api.token
  try:
    return asyncGet(url).body
  except:
    quit("Проверьте интернет соединение", QuitSuccess)

proc trequest(methodname: string, vkparams: Table, dontTouchResponse = false): JsonNode {.thread.} =
  let obj = parseJson(request(methodname, vkparams))
  if dontTouchResponse:
    return obj
  else:
    return obj["response"].elems[0]

proc vkinit*() = 
  SetToken(api.token)
  let response = request("users.get", {"name_case":"Nom"}.toTable)
  if "error" in response: quit("Неверный access token", QuitSuccess)

proc vktitle*(): string = 
  let response = request("users.get", {"name_case":"Nom"}.toTable)
  if "error" in response: quit("Не могу получить юзернэйм", QuitSuccess)
  let json = parseJson(response)
  api.userid = json["response"].elems[0]["id"].num.int
  return json["response"].elems[0]["first_name"].str & " " & json["response"].elems[0]["last_name"].str 

#===== longpoll =====

proc parseLongpollUpdates(arr: seq[JsonNode]) = 
  discard #todo parse updates


proc longpollParseResp(json: string): longpollResp {.thread.} =
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

proc longpollRoutine(info: longpollInfo) {.thread.} = 
  var currTs = info.ts
  while true:
    let
      lpUri = "https://" & info.server & "?act=a_check&key=" & info.key & "&ts=" & $currTs & "&wait=25&mode=2"
      resp = asyncGet(lpUri)
      #todo check server response code\status
      lpresp = longpollParseResp(resp.body)
    if lpresp.failed != -1:
      if lpresp.failed != 1:
        break #get new server
    currTs = lpresp.ts

proc getLongpollInfo(): longpollInfo {.thread.} = 
  let o = trequest("messages,getLongPollServer", {"use_ssl":"1", "need_pts":"0"}.toTable)
  return longpollInfo(
    key: getStr(o["key"]),
    server: getStr(o["server"]),
    ts: getNum(o["ts"]).int32
  )

proc longpollAsync(dummy: int) {.thread.} =
  while true:
    longpollRoutine(getLongpollInfo())


proc startLongpoll() = 
  initLock(threadLock)
  createThread(longpollThread, longpollAsync, dummyint)
  joinThread(longpollThread)

#===== api methods wrappers =====

#TESTS
let tok = readLine(stdin)
SetToken(tok)
startLongpoll()
while true:
  discard
