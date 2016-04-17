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

import std.path, std.stdio, std.file, std.string;

string[string] load() {
  string[string] storage;
  auto config = expandTilde("~/.vkrc");
  if (config.exists) {
    auto f = File(config, "r");
    while (!f.eof) {
      auto line = f.readln.strip;
      if (line.length != 0) storage[line[0..line.indexOf("=")-1]] = line[line.indexOf("=")+2..$];
    }
    f.close;
  }
  return storage;
}

void save(string[string] stor) {
  auto config = expandTilde("~/.vkrc");
  auto f = File(config, "w");
  foreach(key, value; stor) {
    f.write(key ~ " = " ~ value ~ "\n");
  }
  f.close;
}