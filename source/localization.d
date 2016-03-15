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
  local["m_help"] = lang("Help", "Помощь");
  local["m_settings"] = lang("Settings", "Настройки");
  local["m_exit"] = lang("Exit", "Выход");
  local["main_color"] = lang("Main color = ", "Основной цвет = ");
  local["second_color"] = lang("Second color = ", "Дополнительный цвет = ");
  local["color0"] = lang("White", "Белый");
  local["color1"] = lang("Red", "Красный");
  local["color2"] = lang("Green", "Зеленый");
  local["color3"] = lang("Yellow", "Желтый");
  local["color4"] = lang("Blue", "Синий");
  local["color5"] = lang("Pink", "Розовый");
  local["color6"] = lang("Mint", "Мятный");
  local["color7"] = lang("Gray", "Серый");
  local["lang"] = lang("Language = English", "Язык = Русский");
  local["display_settings"] = lang("[ Display Settings ]", "[ Настройки отображения ]");
  local["convers_settings"] = lang("[ Conversations Settings ]", "[ Настройки диалогов ]");
  local["msg_setting_info"] = lang("How to draw conversations list: ", "Как отображать список диалогов: ");
  local["msg_setting0"] = lang("show everything", "показывать всё");
  local["msg_setting1"] = lang("show the selected text only", "текст только выделенного диалога");
  local["msg_setting2"] = lang("show the selected text and unread ones", "текст выделенного диалога и всех непрочитанных");
  local["loading"] = lang("Loading", "Загрузка");
  local["general_navig"] = lang("[ General navigation ]", "[ Общее управление ]");
  local["help_move"]   = lang("Arrow keys, WASD, HJKL         ->   Move cursor", "Стрелки, WASD, HJKL           ->   Двигать курсор");
  local["help_select"] = lang("Enter, right arrow key, D, L   ->   Select item", "Enter, стрелка вправо, D, L   ->   Выбрать элемент");
  local["help_jump"]   = lang("Page Up/Down                   ->   Scroll up/down for a half of screen", "Page Up/Down                  ->   Прокрутить вверх/вниз на половину экрана");
  local["help_homend"] = lang("Home/End                       ->   Jump to the beginning/end", "Home/End                      ->   Прыгнуть в начало/конец");
  local["help_exit"]   = lang("Q                              ->   Exit", "Q                             ->   Выход");
  local["rainbow"] = lang("Render rainbow in chat: ", "Рисовать радугу в диалогах: ");
  local["true"] = lang("On", "Да");
  local["false"] = lang("Off", "Нет");
  local["rainbow_in_chat"] = lang("Color only in group chats: ", "Выделять цветом только конференции: ");
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
