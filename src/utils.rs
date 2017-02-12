use log::{self, LogRecord, LogLevel, LogMetadata, LogLevelFilter};
use chrono::prelude::*;
use json::JsonValue;
use fern;

pub trait OptionUtils<R, E> {
  fn uw(self, s: &str) -> Result<R, E>;
}

pub trait ResultUtils<R> {
  fn parse_check(self, obj: &JsonValue, msg: &'static str) -> Option<R>;
}

pub fn set_log_config() {
  let logcfg = fern::DispatchConfig {
    format: Box::new(
      |msg: &str, level: &log::LogLevel, _location: &log::LogLocation|
      format!("[{}][{}] {}", Local::now().format("%H:%M:%S"), level, msg)
    ),
    output: vec![fern::OutputConfig::stdout()],
    level: log::LogLevelFilter::Trace
  };
  if let Err(e) = fern::init_global_logger(logcfg, log::LogLevelFilter::Trace) {
    panic!("can't initialize logger: {}", e);
  }
}
