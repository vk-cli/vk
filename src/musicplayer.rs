use std::sync::{Arc, Mutex};
use slog::Logger;
use utils::*;

struct Track {
  artist: String,
  title: String,
  duration: String,
  playtime: String,
  id: String,
  duration_seconds: u32,
}


pub struct MusicPlayer {
  artist: String,
  title: String,
  pub log: Logger
}

impl MusicPlayer {
  pub fn new() -> MusicPlayer {
    let artist = "artist".to_string();
    let title = "title".to_string();
    MusicPlayer {
      artist: artist,
      title: title,
      log: get_logger().new(o!(WHERE => "mp"))
    }
  }

  pub fn start_player(&self) {
    info!(self.log, "Starting player...");
  }

  pub fn start(&self) {
    info!(self.log, "MP: Start");
  }

  pub fn stop(&self) {
    info!(self.log, "MP: Stop");
  }

  pub fn resume(&self) {
    info!(self.log, "MP: Resume");
  }

  pub fn pause(&self) {
    info!(self.log, "MP: Pause");
  }

  pub fn next(&self) {
    info!(self.log, "MP: Next");
  }

  pub fn prev(&self) {
    info!(self.log, "MP: Prev");
  }

  pub fn shuffle(&self) {
    info!(self.log, "MP: Shuffle");
  }

  pub fn repeat(&self) {
    info!(self.log, "MP: Repeat");
  }
}
