import osproc, strutils, json, httpclient, cgi, tables

type
  API = object
    token, username : string
    userid          : int

var
  api* = API()

let
  vkmethod   = "https://api.vk.com/method/"
  apiversion = "5.40"

proc GetToken() = 
  discard execCmd("xdg-open \"http://oauth.vk.com/authorize?client_id=5110243&scope=friends,wall,messages,audio,offline&redirect_uri=blank.html&display=popup&response_type=token\" >> /dev/null")
  api.token = stdin.readLine()

proc request(methodname: string, vkparams: Table): string = 
  var url = vkmethod & methodname & "?"
  for key, value in vkparams.pairs:
    url &= key & "=" & encodeUrl(value) & "&"
  url &= "v=" & apiversion & "&access_token=" & api.token
  return getContent(url)

proc vkinit*() =
  GetToken()
  let response = request("users.get", {"name_case":"Nom"}.toTable)
  if "error" in response:
    quit("Неверный access token", QuitSuccess)

proc vktitle*(): string = 
  let response = request("users.get", {"name_case":"Nom"}.toTable)
  if "error" in response:
    quit("Не могу получить юзернэйм", QuitSuccess)
  let json = parseJson(response)
  api.userid = json["response"].elems[0]["id"].num.int
  return json["response"].elems[0]["first_name"].str & " " & json["response"].elems[0]["last_name"].str