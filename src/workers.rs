use std::sync::{Arc, Mutex};
use std::collections::{VecDeque};
//use std::ops::{Index};
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

struct FriendsWorker {
  chunk_size: i32,
  api: Arc<Api>,
  work: Mutex<Work>,
  linear_cache: Mutex<Vec<User>>
}

impl FriendsWorker {
  fn new(api: &Arc<Api>) -> Self {
    FriendsWorker {
      chunk_size: 100,
      api: api.clone(),
      work: Mutex::new(Work::Idle),
      linear_cache: Mutex::new(Vec::new())
    }
  }
}

impl Actor for FriendsWorker {
  fn receive(&self, msg: Box<Any>, context: ActorCell) {
    type T = User;
    if let (Ok(msg), Ok(mut cache), Ok(mut work))
    = (Box::<Any>::downcast::<M<T>>(msg), self.linear_cache.lock(), self.work.lock()) {
      match msg {
        box M::GetChunkAtPos(pos) => {
          let reqrange = (pos + self.chunk_size) as usize;
          let upos = pos as usize;

          let answ = if reqrange < cache.len() {
            Some(cache[upos..reqrange].to_vec())
          } else {
            match *work {
              Work::Idle if upos <= cache.len() => {
                self.api
                  .as_ref()
                  .friends_get(self.chunk_size, pos);
                *work = Work::DownloadingAtPos(pos);
                debug!("friends wrk: task started at pos {}", pos);
                None
              },
              _ => None
            }
          };
          context.complete(context.sender(), answ)
        },

        box M::PWorkTimedOut(wp) => {
          match *work {
            Work::DownloadingAtPos(p) if wp == p => {
              warn!("friends wrk: task timed out at pos {}", p);
              *work = Work::Idle
            },
            _ =>
              warn!("friends wrk: late timeout \
              with pos: {}", wp)
          }
        },

        box M::PChunkReceived(pos, chunk) => {
          let upos = pos as usize;
          match *work {
            Work::DownloadingAtPos(p)
            if pos == p && upos <= cache.len() => {
              while upos < cache.len() {
                let ln = cache.len();
                cache.remove(ln-1);
              }
              cache.extend_from_slice(&chunk[..]);
              debug!("friends wrk: chunk received to pos {}({})", pos, chunk.len());
              *work = Work::Idle;
            },
            _ =>
              warn!("friends wrk: incorrect chunk \
              \npos: {}, lcache: {}", pos, cache.len())
          }
        },

        _ => ()
      }
    }
  }
}