#![recursion_limit = "1024"]

extern crate futures;
extern crate futures_cpupool;
extern crate tokio_core;
extern crate curl;
extern crate ncurses;

#[macro_use]
extern crate log;
#[macro_use]
extern crate json;
#[macro_use]
extern crate quick_error;

use controller::ControllerServer;
use musicplayer::MusicPlayer;
use log::LogLevelFilter;
use std::sync::{Arc, Mutex};
use std::thread;
use std::env;
use testapp::*;
use ui::*;

mod errors;
mod utils;
mod controller;
mod musicplayer;
mod cfg;
mod api;
mod testapp;
mod ui;


const PORT: u32 = 4000;

fn start_server(mp: &Arc<Mutex<MusicPlayer>>) {
  let mp = mp.clone();
  let _ = thread::spawn(move || ControllerServer::new(mp).start(PORT));
}

fn send_msg(msg: &str) {
  controller::ping_serv(PORT, msg);
}

fn help() {
  println!("Usage: vk");
}

fn set_log_config() {
  log::set_logger(|max_log_level| {
    max_log_level.set(LogLevelFilter::Info);
    Box::new(utils::Log)
  });
}

fn main() {
  set_log_config();
  //pretest();
  let args: Vec<_> = env::args().collect();
  let musicplayer = Arc::new(Mutex::new(MusicPlayer::new()));
  if args.len() == 1 {
    start_server(&musicplayer);
    screen(musicplayer.clone());
  } else if (args.len() == 3) & (args[1] == "cmd") {
    send_msg(&args[2]);
  } else {
    help();
  }
}

