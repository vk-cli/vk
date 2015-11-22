import osproc, strutils, json, httpclient

proc GetToken*(): string =
  discard execCmd("xdg-open \"http://oauth.vk.com/authorize?client_id=5110243&scope=notify,friends,photos,audio,video,docs,notes,messages,pages,status,wall,groups,notifications,stats,questions,offers,offline&redirect_uri=blank.html&display=popup&response_type=token\" >> /dev/null")
  var token = stdin.readLine()
  token = token[44..token.find("&", 44)-1]
  let 
    raw_json = getContent("https://api.vk.com/method/users.get?access_token=" & token)
    json = parseJson(raw_json)
  return $json["response"].elems[0]["first_name"] & $json["response"].elems[0]["last_name"]