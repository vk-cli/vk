#![recursion_limit = "1024"]

extern crate futures;
extern crate futures_cpupool;
extern crate tokio_core;
extern crate curl;

#[macro_use]
extern crate log;
#[macro_use]
extern crate json;

mod utils;
mod controller;
mod musicplayer;

use controller::ControllerServer;
use musicplayer::MusicPlayer;

use log::LogLevelFilter;

use std::sync::{Arc, Mutex};
use std::thread;
use std::env;

#[macro_use]
extern crate error_chain;

mod errors {
  error_chain! { }

  impl From<::std::io::Error> for Error {
    fn from(e: ::std::io::Error) -> Error { e.to_string().into() }
  }
}

mod cfg;
mod api;
mod testapp;
mod ui;
use testapp::*;
use ui::*;



const PORT: u32 = 4000;


fn start_server(mp: &Arc<Mutex<MusicPlayer>>) {
    let mp = mp.clone();
    let _ = thread::spawn(move || ControllerServer::new(mp).start(PORT));
}


fn start_gui(mp: &Arc<Mutex<MusicPlayer>>) {
    // let mp = mp.clone();
    // let child = thread::spawn(move || render(mp));
    // child.join();
    render(mp.clone());
}


fn ping_server(msg: &str) {
    controller::ping_serv(PORT, msg);
}


fn print_usage() {
    println!("Usage: asdf [ping]");
}


fn get_music_player() -> Arc<Mutex<MusicPlayer>> {
    Arc::new(Mutex::new(MusicPlayer::new()))
}


fn main() {
    let _ = log::set_logger(|max_log_level| {
        max_log_level.set(LogLevelFilter::Info);
        Box::new(utils::Log)
    });
    let args: Vec<_> = env::args().collect();
    let mp = get_music_player();
    if args.len() == 1 {
        info!("Starting server...");
        start_server(&mp);
        start_gui(&mp);
    } else if (args.len() == 3) & (args[1] == "cmd") {
        println!("Pinging server...");
        ping_server(&args[2]);
    } else {
        print_usage();
    }
}

