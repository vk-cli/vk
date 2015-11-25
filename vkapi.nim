import osproc, strutils, json, httpclient, cgi, tables
import locks, macros, asyncdispatch, asynchttpserver, strtabs

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

proc request(methodname: string, vkparams: Table): string = 
  var url = vkmethod & methodname & "?"
  for key, value in vkparams.pairs:
    url &= key & "=" & encodeUrl(value) & "&"
  url &= "v=" & apiversion & "&access_token=" & api.token
  try:
    return getContent(url)
  except:
    quit("Проверьте интернет соединение", QuitSuccess)

proc vkinit*() = 
  SetToken(api.token)
  let response = request("users.get", {"name_case":"Nom"}.toTable)
  if "error" in response: quit("Неверный access token", QuitSuccess)

proc parse(response: string): JsonNode = 
  let json = parseJson(response)
  return json["response"]

#===== api methods wrappers =====

proc vktitle*(): string = 
  let 
    response = request("users.get", {"name_case":"Nom"}.toTable)
    json = parse(response)[0]
  if "error" in response: quit("Не могу получить юзернэйм", QuitSuccess)
  api.userid = json["id"].num.int
  return json["first_name"].str & " " & json["last_name"].str 

proc vkfriends*(): seq[tuple[string:string]] = 
  let
    response = request("friends.get", {"user_id": $api.user_id, "order": "hints", "fields": "first_name, last_name"}.toTable)
    json = parse(response).getFields[1][1]
  if "error" in response: quit("Не могу загрузить друзей", QuitSuccess)
  var
    friends = newSeq[tuple[string:string]](0)
    status = "  "
  for fr in json:
    if fr["online"].num == 1: status = "⚫ "
    let fullname = status & fr["first_name"].str & " " & fr["last_name"].str
    friends.add(tuple[fullname: fr["id"].str])
  return friends