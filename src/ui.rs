extern crate ncurses;

use std::char;
use self::ncurses::*;

pub fn render() {
  setlocale(LcCategory::all, "en_US.UTF-8");
  initscr();
  raw();

  // Allow for extended keyboard (like F1).
  keypad(stdscr(), true);
  noecho();

  printw("Enter any character (q to exit):\n");

  'main: loop {
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
        printw("Key pressed: ");
        attron(A_BOLD() | A_BLINK());
        printw(&format!("{} - ", c));
        if c == 113 { break 'main; }
        printw(format!("{}\n", char::from_u32(c as u32).expect("Invalid char")).as_ref());
        attroff(A_BOLD() | A_BLINK());
      }

      None => {}
    }

    refresh(); 
  }
  // getch();
  endwin();
}
