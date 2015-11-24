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



proc request(methodname: string, vkparams: Table): string = 
  var url = vkmethod & methodname & "?"
  for key, value in vkparams.pairs:
    url &= key & "=" & encodeUrl(value) & "&"
  url &= "v=" & apiversion & "&access_token=" & api.token
  try:
    return getContent(url)
  except:
    quit("Проверьте интернет соединение", QuitSuccess)

proc trequest(methodname: string, vkparams: Table, dontTouchResponse = false): JsonNode =
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


#===== api methods wrappers =====

