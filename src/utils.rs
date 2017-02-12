use log::{self, LogRecord, LogLevel, LogMetadata, LogLevelFilter};
use chrono::prelude::*;
use json::JsonValue;
use fern;
use std::fs;

pub trait OptionUtils<R, E> {
  fn uw(self, s: &str) -> Result<R, E>;
}

pub trait ResultUtils<R> {
  fn parse_check(self, obj: &JsonValue, msg: &'static str) -> Option<R>;
}

pub fn set_log_config() {
  let logfilter = || log::LogLevelFilter::Trace; // Trace < Debug < Info < Warn < Error
  let logcfg = fern::DispatchConfig {
    format: Box::new(
      |msg: &str, level: &log::LogLevel, _location: &log::LogLocation|
      format!("[{}][{}] {}", Local::now().format("%H:%M:%S"), level, msg)
    ),
    output: vec![fern::OutputConfig::stdout()],
    //output: vec![fern::OutputConfig::file_with_options("", fs::OpenOptions::create_new(true))],
    level: logfilter()
  };
  if let Err(e) = fern::init_global_logger(logcfg, logfilter()) {
    panic!("can't initialize logger: {}", e);
  }
}
