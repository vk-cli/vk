module localization;

import std.stdio;

struct Lang {
  string[string] text;
}

Lang[2] localize() {
  Lang[2] lang;
  lang[0].text["lol"] = "test2";
  return lang;
}