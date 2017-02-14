use errors::*;
use utils::DummyResult;
use std::time::Duration;
use std::fmt::Display;
use futures::Future;
use futures::future::BoxFuture;
use tokio_timer::Timer;
use robots::actors::*;

use workers::*;
use workers::GetChunkAnswer::*;

pub fn fork<T, E>(f: BoxFuture<Vec<T>, E>, timeout: Duration, context: &ActorCell, pos: Pos, error_prefix: &'static str)
  where T: Clone + Send + Sync + 'static,
        E: Display {

  let context = context.clone();
  let pass_to = context.actor_ref().clone();
  let work = f.map_err(|e| work_error(e));

  Timer::default()
    .sleep(timeout) //todo link with request timeout + timeout ladder
    .then(|_| Err(work_timeout()))
    .select(work)
    .map(|(res, _)| res)
    .map_err(|(err, _)| err)
    .then(|res| -> DummyResult {
      let pass = match res {
        Ok(r) => Some(M::PChunkReceived(pos, r)),
        Err(WorkerError::WorkTimedOut) => Some(M::PWorkTimedOut(pos)),
        Err(e) => {
          error!("{} {}", error_prefix, e);
          None
        }
      };
      pass.map(|m|
        context.tell(pass_to, m)
      );
      Ok(())
    });
}

pub enum Work {
  DownloadingAtPos(Pos),
  Idle
}

pub struct Linear<T> {
  pub work: Work,
  pub cache: Vec<T>,
  pub cache_full: bool,
  pub logpref: &'static str
}

impl<T: Clone> Linear<T> {
  pub fn get_chunk<F>(&mut self, pos: Pos, size: Pos, f: F) -> GetChunkAnswer<Vec<T>>
    where F: Fn() -> () {

    let reqrange = (pos + size) as usize;
    let upos = pos as usize;

    if self.cache_full {
      CacheFull
    } else if reqrange < self.cache.len() {
      HasChunk(self.cache[upos..reqrange].to_vec())
    } else {
      match self.work {
        Work::Idle if upos <= self.cache.len() => {
          f();
          self.work = Work::DownloadingAtPos(pos);
          debug!("{} task started at pos {}", self.logpref, pos);
          NoChunk
        },
        _ => NoChunk
      }
    }
  }

  pub fn recv_chunk(&mut self, pos: Pos, chunk: Vec<T>) {
    let upos = pos as usize;
    let pref = self.logpref;
    match self.work {
      Work::DownloadingAtPos(p)
      if pos == p && upos <= self.cache.len() => {
        if chunk.len() == 0 {
          info!("{} cache full (received empty chunk)", pref);
          self.cache_full = true;
        } else {
          let mut ln = self.cache.len();
          while upos < ln {
            self.cache.remove(ln - 1);
            ln = self.cache.len();
          }
          self.cache.extend_from_slice(&chunk[..]);
        }
        debug!("{} chunk received to pos {}({})", pref, pos, chunk.len());
        self.work = Work::Idle;
      },
      _ =>
        warn!("{} incorrect chunk \
              \npos: {}, lcache: {}", pref, pos, self.cache.len())
    }
  }
}