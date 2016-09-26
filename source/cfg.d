/*
Copyright 2016 HaCk3D, substanceof

https://github.com/HaCk3Dq
https://github.com/substanceof

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

module cfg;

import deimos.ncurses.ncurses;
import std.path, std.stdio, std.file, std.string, std.regex, std.process, std.conv;
import localization, ui, utils;

string parseToken(string token) {
  auto ctoken = regex(r"^\s*[0-9a-f]+\s*$");
  if (matchFirst(token, ctoken).empty) {
    auto rtoken = regex(r"(?:.*access_token=)([0-9a-f]+)(?:&)");
    auto cap = matchFirst(token, rtoken);
    if (cap.length != 2) Exit("e_wrong_token".getLocal);
    token = cap[1];
  }
  return token;
}

string get_token() {
  char token, start_browser;
  string
    token_link = "https://oauth.vk.com/authorize?client_id=5110243&scope=friends,wall,messages,audio,offline&redirect_uri=blank.html&display=popup&response_type=token";
  "e_start_browser".getLocal.regular;
  getstr(&start_browser);
  "e_token_info".getLocal.regular;
  if (start_browser == 'N' || start_browser == 'n'){
    "e_follow_link".getLocal.regular;
    token_link.print;
    "\n\n".print;
  } else {
    spawnShell(`xdg-open "`~token_link~`" &>/dev/null`);
    "\n".print;
  }
  "e_input_token".getLocal.regular;
  getstr(&token);
  string strToken = (cast(char*)&token).to!string;
  return strToken.parseToken;
}

void load(ref string[string] storage) {
  auto config = expandTilde("~/.vkrc");
  if (config.exists) {
    auto f = File(config, "r");
    while (!f.eof) {
      auto line = f.readln.strip;
      if (line.length != 0)
        storage[line[0 .. line.indexOf("=") - 1]] = line[line.indexOf("=") + 2 .. $];
    }
    f.close;
  }
}

void save(string[string] storage) {
  auto config = expandTilde("~/.vkrc");
  auto f = File(config, "w");
  foreach (key, value; storage) {
    f.write(key ~ " = " ~ value ~ "\n");
  }
  f.close;
}
