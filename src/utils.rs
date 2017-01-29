//! utils.rs

use log::{self, LogRecord, LogLevel, LogMetadata};


pub struct Log;

impl log::Log for Log {
    fn enabled(&self, metadata: &LogMetadata) -> bool {
        metadata.level() <= LogLevel::Info
    }

    fn log(&self, record: &LogRecord) {
        if self.enabled(record.metadata()) {
            println!("[{}] {}", record.level(), record.args());
        }
    }
}

