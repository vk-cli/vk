module apptest;

import std.range, std.algorithm;
import logic, utils, vkapi;

enum TabType {
    users,
    dialogs,
    messages,
    audio,
    unknown
}

TabDrawerBase[] tabs;
TabDrawerBase currentTab;

bool somethingUpdated; // dummy

void example() {
    auto mp = new MainProvider("hujovyj_token");
    tabs ~= new TabDrawer!User(mp.makeFriendsView); // добавить вкладку с друзьями

    // рисование интерфейса??

    tabs[0].redraw(); // рисуем
    tabs[0].moveForward(); //двигаемся
    tabs[0].redraw(); // перерисовываем
    // ни одного свитч-кейза, все типы скрыты за базовым классом, который не темплейт
    // но вся логика/рисование опирается на типы и происходит внутри класса-наследника базового, рожденного темплетом
}

template getType(T) { // преобразование типа в значение енума на этапе компиляции
                      // написал только ради примера использования enum'а в кач-ве ретерна из темлпейта 
                      // (вместо алиаса)
    static if(is(T == User)) {
        enum getType = TabType.users;
    }
    else static if(is(T == Dialog)) {
        enum getType = TabType.dialog;
    }
    else static if(is(T == Audio)) {
        enum getType = TabType.audio;
    }
    else static if(is(T == Message)) {
        enum getType = TabType.messages;
    }
    else {
        enum getType = TabType.unknown;
    }
}

abstract class TabDrawerBase {
    TabType type;
    string title;

    void moveForward();
    void moveBackward();
    void redraw();
    void reloadView(int height, int width);
}

template TabDrawer(T) {
    class TabDrawerImpl : TabDrawerBase {
        View!T view;
        //HistoryView!T hview;
        T[] currentView;

        this(View!T _view) {
            view = _view;
            type = getType!T;
        }

        override void moveForward() {
            view.moveForward();
            currentView = [];
        }

        override void moveBackward() {
            view.moveBackward();
            currentView = [];
        }

        override void redraw() {
            if(currentView.length == 0 || somethingUpdated) {
                reloadView(228, 322);
            }
            // общие операции рисования
            static if (is(T == User)) {
                // специфичные для объекта User операции рисования
            }
            else static if (is(T == Dialog)) {
                // same for Dialog
            }
            else {
                static assert(0, "Cannot draw this type (" ~ T.stringof ~ ")");
            }
        }

        override void reloadView(int height, int width) {
            //currentView = view.getView(height, width) 
            // пока getView возвращает MergedChunks, будет обычный Array
            currentView = []; // для примера
        }

    }

    alias TabDrawer = TabDrawerImpl;
}