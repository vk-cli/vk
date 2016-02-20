module localization;

import std.stdio;

struct lang {
  string en;
  string ru;
}

const int
  EN = 0,
  RU = 1;

private lang[string] local;
private int currentLang = 0;

void localize() {
  local["m_friends"] = lang("Friends", "Друзья");
  local["m_conversations"] = lang("Conversations", "Диалоги");
  local["m_music"] = lang("Music", "Музыка");
  local["m_settings"] = lang("Settings", "Настройки");
}

void setLang(int lang) {
  currentLang = lang;
}

string getLocal(string id) {
  switch(currentLang){
    case EN: return local[id].en;
    case RU: return local[id].ru;
    default: return "";
  }
}

