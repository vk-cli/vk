use std::sync::{Arc, Mutex};
use std::collections::{VecDeque};
use errors::*;
use log::*;
use api::Api;
use api_objects::*;

use futures::Future;
use futures::future::BoxFuture;
use robots::actors::*;

type Pos = i32;

pub enum M<C> {
  GetChunkAtPos(Pos),
  PChunkReceived(Pos, Vec<C>),
  PWorkTimedOut(Pos)
}

enum Work {
  DownloadingAtPos(Pos),
  Idle
}

struct Linear<T> {
  work: Work,
  cache: Vec<T>,
  cache_full: bool
}

struct FriendsWorker {
  chunk_size: i32,
  api: Arc<Api>,
  main: Mutex<Linear<User>>,
}

impl FriendsWorker {
  fn new(api: &Arc<Api>) -> Self {
    FriendsWorker {
      chunk_size: 100,
      api: api.clone(),
      main: Mutex::new(
        Linear {
          work: Work::Idle,
          cache: Vec::new(),
          cache_full: false
        }
      )
    }
  }
}

impl Actor for FriendsWorker {
  fn receive(&self, msg: Box<Any>, context: ActorCell) {
    type T = User;
    if let (Ok(msg), Ok(mut c))
    = (Box::<Any>::downcast::<M<T>>(msg), self.main.lock()) {
      match msg {
        box M::GetChunkAtPos(pos) => {
          let reqrange = (pos + self.chunk_size) as usize;
          let upos = pos as usize;

          let answ = if reqrange < c.cache.len() {
            Some(c.cache[upos..reqrange].to_vec())
          } else {
            match c.work {
              Work::Idle if upos <= c.cache.len() => {
                self.api
                  .as_ref()
                  .friends_get(self.chunk_size, pos);
                c.work = Work::DownloadingAtPos(pos);
                debug!("friends wrk: task started at pos {}", pos);
                None
              },
              _ => None
            }
          };
          context.complete(context.sender(), answ)
        },

        box M::PWorkTimedOut(wp) => {
          match c.work {
            Work::DownloadingAtPos(p) if wp == p => {
              warn!("friends wrk: task timed out at pos {}", p);
              c.work = Work::Idle
            },
            _ =>
              warn!("friends wrk: late timeout \
              with pos: {}", wp)
          }
        },

        box M::PChunkReceived(pos, chunk) => {
          let upos = pos as usize;
          match c.work {
            Work::DownloadingAtPos(p)
            if pos == p && upos <= c.cache.len() => {
              let mut ln = c.cache.len();
              while upos < ln {
                c.cache.remove(ln - 1);
                ln = c.cache.len();
              }
              c.cache.extend_from_slice(&chunk[..]);
              debug!("friends wrk: chunk received to pos {}({})", pos, chunk.len());
              c.work = Work::Idle;
            },
            _ =>
              warn!("friends wrk: incorrect chunk \
              \npos: {}, lcache: {}", pos, c.cache.len())
          }
        },
        //todo fullcheck
        //todo move out struct to common mutex
        //todo finalize fget

        _ => ()
      }
    }
  }
}