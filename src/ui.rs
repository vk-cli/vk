use std::sync::{Arc, Mutex};
use std::char;
use ncurses::*;
use musicplayer::MusicPlayer;

const Q_KEYS     : [u32; 2] = [ 113, 1081 ];
const UP_KEYS    : [u32; 2] = [ 119, 1094 ];
const DOWN_KEYS  : [u32; 2] = [ 115, 1099 ];
const LEFT_KEYS  : [u32; 2] = [ 97, 1092 ];
const RIGHT_KEYS : [u32; 3] = [ 100, 1074, 10 ];

struct Window {
  key: u32,
  size: (i32, i32),
  title: &'static str,
}

impl Window {
  fn new() -> Window {
    Window {
      key: 0,
      title: "Enter any character (q to exit):\n",
      size: (0, 0),
    }
  }

  fn set_size(&mut self) -> bool {
    let mut temp_size = (0, 0);
    getmaxyx(stdscr(), &mut temp_size.1, &mut temp_size.0);
    if temp_size != self.size {
      self.size = temp_size;
      return true;
    }
    false
  }

  fn set_key(&mut self) {
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
  cbreak();
}

pub fn screen(musicplayer: Arc<Mutex<MusicPlayer>>) {
  init();
  let mut win = Window::new();

  while !Q_KEYS.contains(&win.key) {
    // clear();
    printw(win.title);
    win.set_size();
    win.set_key();

    win.print_keycode();
    printw(" is ");
    win.print_key();
    printw("\n");
    refresh();
  }

  endwin();
}
