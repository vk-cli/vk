module localization;

import std.stdio;

struct lang {
  string En;
  string Ru;
}

const int LANG_EN = 0;
const int LANG_RU = 1;

private lang[string] local;
private int currentLang = 0;

void localize() {
    local["menu_friends"] = lang("Friends", "Друзья");
    local["menu_conversations"] = lang("Conversations", "Диалоги");
    local["menu_music"] = lang("Music", "Музыка");
}

void setLang(int lang) {
    currentLang = lang;
}

string getLocal(string id, int lang = currentLang) {
    switch(lang){
        case LANG_EN:
            return local[id].En;
            break;
        case LANG_RU:
            return local[id].Ru;
            break;
        default:
            return "";
            break;
    }
}

