module localization;

import std.stdio, std.conv;

struct lang {
  string en;
  string ru;
}

const int
  En = 0,
  Ru = 1;

private lang[string] local;
private int currentLang = 0;

void localize() {
  local["e_input_token"] = lang("Insert your access token here: ", "Вставьте свой access token сюда: ");
  local["e_wrong_token"] = lang("Wrong token, try again\n", "Неверный access token, попробуйте еще раз");
  local["m_friends"] = lang("Friends", "Друзья");
  local["m_conversations"] = lang("Conversations", "Диалоги");
  local["m_music"] = lang("Music", "Музыка");
  local["m_settings"] = lang("Settings", "Настройки");
  local["m_exit"] = lang("Exit", "Выход");
  local["color"] = lang("Color = ", "Цвет = ");
  local["color0"] = lang("White", "Белый");
  local["color1"] = lang("Red", "Красный");
  local["color2"] = lang("Green", "Зеленый");
  local["color3"] = lang("Yellow", "Желтый");
  local["color4"] = lang("Blue", "Синий");
  local["color5"] = lang("Pink", "Розовый");
  local["color6"] = lang("Mint", "Мятный");
  local["lang"] = lang("Language = English", "Язык = Русский");
  local["display_settings"] = lang("[ Display Settings ]", "[ Настройки отображения ]");
  local["convers_settings"] = lang("[ Conversations Settings ]", "[ Настройки диалогов ]");
  local["msg_setting_info"] = lang("How to draw conversations list: ", "Как отображать список диалогов: ");
  local["msg_setting0"] = lang("show everything", "показывать всё");
  local["msg_setting1"] = lang("show the selected text only", "текст только выделенного диалога");
  local["msg_setting2"] = lang("show the selected text and unread ones", "текст выделенного диалога и всех непрочитанных");
  local["loading"] = lang("Loading", "Загрузка");
}

void swapLang() {
  currentLang = (currentLang == En) ? Ru : En;
}

string getLang() {
  return currentLang.to!string;
}

string getLocal(string id) {
  return currentLang == En ? local[id].en : local[id].ru;
}
