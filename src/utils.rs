use log::{self, LogRecord, LogLevel, LogMetadata, LogLevelFilter};
use chrono::prelude::*;
use json::JsonValue;
use slog_stdlog;
use std::fs;

pub type DummyResult = Result<(), ()>;
pub type Rstr = &'static str;

pub trait OptionUtils<R, E> {
  fn uw(self, s: &str) -> Result<R, E>;
}

pub trait ResultUtils<R> {
  fn parse_check(self, obj: &JsonValue, msg: &'static str) -> Option<R>;
}

pub fn parallelism() -> u32 { 4 } // guaranteed to be random ofc

pub fn set_log_config() {
  if let Err(e) = slog_stdlog::init() {
    panic!("can't initialize logger: {}", e);
  }
}
