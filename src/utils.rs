use futures::Future;
use futures_cpupool::{CpuPool, CpuFuture};
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
    rootlog: Logger,
    pool: CpuPool
  },
  None
}

lazy_static! {
  static ref GLOBAL: ArcCell<Global> = ArcCell::new(
    Arc::new(Global::None)
  );
}

pub const WHERE: &'static str = "where";
pub const NOGLOBAL: &'static str = "global isn't initialized";

pub trait OptionUtils<R, E> {
  fn uw(self, s: &str) -> Result<R, E>;
}

pub trait ResultUtils<R> {
  fn parse_check(self, obj: &JsonValue, log: Logger, m: &'static str) -> Option<R>;
}

pub fn parallelism() -> u32 { 4 } // guaranteed to be random ofc

pub fn set_global() {
  let pool = CpuPool::new(parallelism() as usize);
  let drain = slog_term::streamer().compact().build().fuse();
  let root = slog::Logger::root(drain, o!());

  GLOBAL.set(
    Arc::new(
      Global::Has {
        rootlog: root,
        pool: pool
      }
    )
  );
}

pub fn get_logger() -> Logger {
  match *GLOBAL.get().as_ref() {
    Global::Has { ref rootlog, .. } => rootlog.clone(),
    _ => panic!(NOGLOBAL)
  }
}

pub fn spawn_on_pool<U>(f: U) -> CpuFuture<U::Item, U::Error>
  where U: Future + Send + 'static,
        U::Item: Send + 'static,
        U::Error: Send + 'static {
  match *GLOBAL.get().as_ref() {
    Global::Has { ref pool, .. } => pool.spawn(f),
    _ => panic!(NOGLOBAL)
  }
}
