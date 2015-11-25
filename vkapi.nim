import osproc, strutils, json, httpclient, cgi, tables
import locks, macros, asyncdispatch, asynchttpserver, strtabs

const 
  quitOnApiError  = true
  quitOnHttpError = true

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
  longpollThread: Thread[int]
  threadLock: Lock

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

proc vkusername*(id: int = 0): string = 
  if id == 0:
    let
      rawjson = request("users.get", {"name_case":"Nom"}.toTable, "Не могу получить юзернэйм")
      json    = rawjson[0]
    api.userid = json["id"].num.int
    return json["first_name"].str & " " & json["last_name"].str
  else:
    let
      rawjson = request("users.get", {"user_ids": $id, "name_case":"Nom"}.toTable, "Не могу получить юзернэйм")
      json    = rawjson[0]
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

# proc vkmusic(): seq[tuple[track: string, duration: int, link: string]] = 