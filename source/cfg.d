module cfg;

import std.path, std.stdio, std.file, std.string;

string[string] load() {
  string[string] newstorage;
  auto config = expandTilde("~/.vkrc");
  if (config.exists) {
    auto f = File(config, "r");
    while (!f.eof) {
      auto line = f.readln.strip;
      if (line.length != 0) newstorage[line[0..line.indexOf("=")-1]] = line[line.indexOf("=")+2..$];
    }
    f.close;
  }
  return newstorage;
}

void save(string[string] stor) {
  auto config = expandTilde("~/.vkrc");
  auto f = File(config, "w");
  foreach(key, value; stor) {
    f.write(key ~ " = " ~ value ~ "\n");
  }
  f.close;
}