use chrono::prelude::*;
use json::JsonValue;
use slog;
use slog::{DrainExt, Logger};
use slog_term;
use crossbeam::sync::ArcCell;
use std::sync::Arc;
use std::fs;

pub type DummyResult = Result<(), ()>;
pub type Rstr = &'static str;

enum Global {
  Has {
    rootlog: Logger
  },
  None
}

lazy_static! {
  static ref GLOBAL: ArcCell<Global> = ArcCell::new(
    Arc::new(Global::None)
  );
}

pub const WHERE: &'static str = "where";

pub trait OptionUtils<R, E> {
  fn uw(self, s: &str) -> Result<R, E>;
}

pub trait ResultUtils<R> {
  fn parse_check(self, obj: &JsonValue, log: Logger, m: &'static str) -> Option<R>;
}

pub fn parallelism() -> u32 { 4 } // guaranteed to be random ofc

pub fn set_global() {
  let drain = slog_term::streamer().compact().build().fuse();
  let root = slog::Logger::root(drain, o!());

  GLOBAL.set(
    Arc::new(
      Global::Has {
        rootlog: root
      }
    )
  );
}

pub fn get_logger() -> Logger {
  match *GLOBAL.get().as_ref() {
    Global::Has { ref rootlog, .. } => rootlog.clone(),
    _ => panic!("global isn't initialized")
  }
}
