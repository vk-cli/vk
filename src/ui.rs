extern crate ncurses;

use musicplayer::MusicPlayer;

use std::sync::{Arc, Mutex};

use std::char;
use self::ncurses::*;

pub fn render(mp: Arc<Mutex<MusicPlayer>>) {
  let locale_conf = LcCategory::all;
  setlocale(locale_conf, "en_US.UTF-8");
  initscr();
  raw();

  /* Allow for extended keyboard (like F1). */
  keypad(stdscr(), true);
  noecho();

  printw("Enter a character: ");

  let ch = get_wch();
  match ch {
    Some(WchResult::KeyCode(KEY_MOUSE)) => {}

    Some(WchResult::KeyCode(c)) => {
      attron(A_BOLD() | A_BLINK());
      printw(&format!("\n{}", c));
      attroff(A_BOLD() | A_BLINK());
      printw(" pressed");
    }

    Some(WchResult::Char(c)) => {
      printw("\nKey pressed: ");
      attron(A_BOLD() | A_BLINK());
      printw(format!("{}\n", char::from_u32(c as u32).expect("Invalid char")).as_ref());
      attroff(A_BOLD() | A_BLINK());
    }

    None => {}
  }

  /* Refresh, showing the previous message. */
  refresh();

  nocbreak();
  getch();
  endwin();
}
