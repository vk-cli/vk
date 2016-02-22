module localization;

import std.stdio;

struct lang {
  string en;
  string ru;
}

const int
  En = 0,
  Ru = 1;

private lang[string] local;
private int currentLang = 0;

enum Colors { white, red, green, yellow, blue, pink, mint }

void localize() {
  local["e_input_token"] = lang("Insert your access token here: ", "Вставьте свой access token сюда: ");
  local["e_wrong_token"] = lang("Wrong token, try again\n", "Неверный access token, попробуйте еще раз");
  local["m_friends"] = lang("Friends", "Друзья");
  local["m_conversations"] = lang("Conversations", "Диалоги");
  local["m_music"] = lang("Music", "Музыка");
  local["m_settings"] = lang("Settings", "Настройки");
  local["color"] = lang("Color = ", "Цвет = ");
  local["color0"] = lang("White", "Белый");
  local["color1"] = lang("Red", "Красный");
  local["color2"] = lang("Green", "Зеленый");
  local["color3"] = lang("Yellow", "Желтый");
  local["color4"] = lang("Blue", "Синий");
  local["color5"] = lang("Pink", "Розовый");
  local["color6"] = lang("Mint", "Мятный");
}

void setLang(int lang) {
  currentLang = lang;
}

int getLang() {
  return currentLang;
}

string getLocal(string id) {
  switch(currentLang){
    case En: return local[id].en;
    case Ru: return local[id].ru;
    default: return "";
  }
}

