//! musicplayer.rs

use log;

use std::sync::{Arc, Mutex};


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
}


impl MusicPlayer {
    pub fn new() -> MusicPlayer {
        let artist = "artist".to_string();
        let title = "title".to_string();
        MusicPlayer {
            artist: artist,
            title: title,
        }
    }

    pub fn start_player(&self) {
        info!("Starting player...");
    }

    pub fn start(&self) {
        info!("MP: Start");
    }

    pub fn stop(&self) {
        info!("MP: Stop");
    }

    pub fn resume(&self) {
        info!("MP: Resume");
    }

    pub fn pause(&self) {
        info!("MP: Pause");
    }

    pub fn next(&self) {
        info!("MP: Next");
    }

    pub fn prev(&self) {
        info!("MP: Prev");
    }

    pub fn shuffle(&self) {
        info!("MP: Shuffle");
    }

    pub fn repeat(&self) {
        info!("MP: Repeat");
    }
}
