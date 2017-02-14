use std::sync::{Arc, Mutex};
use std::collections::{VecDeque};
use std::time::Duration;
use errors::*;
use log::*;
use utils::*;
use api::Api;
use api_objects::*;
use worker_utils::*;

use futures::Future;
use futures::future::BoxFuture;
use tokio_timer::Timer;
use robots::actors::*;

use workers::GetChunkAnswer::*;

pub type Pos = i32;

#[derive(Clone)]
pub enum M {
  GetChunkAtPos(Pos),
  PChunkReceivedUser(Pos, Vec<User>),
  PWorkTimedOut(Pos)
}

#[derive(Clone)]
pub enum GetChunkAnswer<T> {
  HasChunk(T),
  NoChunk,
  CacheFull
}

pub struct FriendsWorker {
  chunk_size: i32,
  api: Arc<Api>,
  main: Mutex<Linear<User>>,
}

impl FriendsWorker {
  pub fn new(api: Arc<Api>) -> Self {
    FriendsWorker {
      chunk_size: 100,
      api: api,
      main: Mutex::new(
        Linear {
          work: Work::Idle,
          cache: Vec::new(),
          cache_full: false,
          logpref: "friends:"
        }
      )
    }
  }
}

impl Actor for FriendsWorker {
  fn receive(&self, msg: Box<Any>, context: ActorCell) {
    if let (Ok(msg), Ok(mut c)) = (Box::<Any>::downcast::<M>(msg), self.main.lock()) {
      let pref = c.logpref;
      match msg {
        box M::GetChunkAtPos(pos) => {
          let cs = self.chunk_size;
          let get = || {
            let apiwork = self.api
              .as_ref()
              .friends_get(cs, pos)
              .boxed();
            fork(apiwork, M::PChunkReceivedUser, Duration::from_millis(4000), &context, pos, &pref);
          };
          let answ = c.get_chunk(pos, cs, get);
          context.complete(context.sender(), answ)
        },

        box M::PWorkTimedOut(wp) => {
          match c.work {
            Work::DownloadingAtPos(p) if wp == p => {
              warn!("{} task timed out at pos {}", pref, p);
              c.work = Work::Idle
            },
            _ =>
              warn!("{} late timeout \
              with pos: {}", pref, wp)
          }
        },

        box M::PChunkReceivedUser(pos, chunk) => {
          c.recv_chunk(pos, chunk);
        },

        _ => warn!("{} bad msg", pref)
      }
    } else {
      error!("friends: can't acquire lck / downcast message");
    }
  }
}