use std::sync::{Arc, Mutex};
use std::thread;
use controller;
use controller::ControllerServer;
use musicplayer::MusicPlayer;

const PORT: u32 = 4000;

pub fn start_server(mp: &Arc<Mutex<MusicPlayer>>) {
  let mp = mp.clone();
  let _ = thread::spawn(move || ControllerServer::new(mp).start(PORT));
}

pub fn send_msg(msg: &str) {
  controller::ping_serv(PORT, msg);
}


