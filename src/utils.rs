use log::{self, LogRecord, LogLevel, LogMetadata, LogLevelFilter};

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

pub fn set_log_config() {
  log::set_logger(|max_log_level| {
    max_log_level.set(LogLevelFilter::Info);
    Box::new(Log)
  });
}
