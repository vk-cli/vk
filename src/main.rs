#![recursion_limit = "1024"]

extern crate futures;
extern crate futures_cpupool;
extern crate tokio_core;
extern crate curl;
extern crate ncurses;
extern crate chrono;
extern crate fern;

#[macro_use]
extern crate log;
#[macro_use]
extern crate json;
#[macro_use]
extern crate quick_error;

mod errors;
mod utils;
mod controller;
mod musicplayer;
mod server_utils;
mod cfg;
mod api;
mod api_objects;
mod testapp;
mod ui;

use controller::ControllerServer;
use musicplayer::MusicPlayer;
use server_utils::*;
use utils::*;
use std::sync::{Arc, Mutex};
use std::env;
use testapp::*;
use ui::*;


fn main() {
  set_log_config();
  pretest();

  let args: Vec<_> = env::args().collect();
  let musicplayer = Arc::new(Mutex::new(MusicPlayer::new())); // todo move init
  if args.len() == 1 {
    start_server(&musicplayer);
    screen(musicplayer.clone());
  } else if (args.len() == 3) & (args[1] == "cmd") {
    send_msg(&args[2]);
  } else {
    help();
  }
}

fn help() {
  println!("Usage: vk");
}

