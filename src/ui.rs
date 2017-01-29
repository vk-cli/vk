use std::sync::{Arc, Mutex};
use std::char;
use ncurses::*;
use musicplayer::MusicPlayer;

struct Window {
  key: u32,
  title: String,
}

impl Window {
  fn new() -> Window {
    Window {
      key: 0,
      title: "test title".to_string(),
    }
  }

  fn get_key(& mut self) {
    let ch = get_wch();
    match ch {
      Some(WchResult::KeyCode(c)) => self.key = c as u32,
      Some(WchResult::Char(c)) => self.key = c,
      _ => {}
    }
  }

  fn print_keycode(&self) {
    attron(A_BOLD() | A_BLINK());
    printw(&format!("{}", self.key));
    attroff(A_BOLD() | A_BLINK());
  }

  fn print_key(&self) {
    attron(A_BOLD() | A_BLINK());
    printw(format!("{}", char::from_u32(self.key).expect("Invalid char")).as_ref());
    attroff(A_BOLD() | A_BLINK());
  }
}

fn init() {
  setlocale(LcCategory::all, "en_US.UTF-8");
  initscr();
  raw();
  keypad(stdscr(), true);
  noecho();
}

pub fn screen(mp: Arc<Mutex<MusicPlayer>>) {
  init();
  let mut win = Window::new();

  printw("Enter any character (q to exit):\n");
  while win.key != 113 {
    win.get_key();
    win.print_keycode();
    printw(" is ");
    win.print_key();
    printw("\n");
    refresh();
  }

  endwin();
}
