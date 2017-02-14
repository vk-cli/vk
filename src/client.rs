use std::sync::{Arc};
use std::thread::sleep;
use std::time::Duration;
use robots::actors::*;

use api::Api;
use api_objects::*;
use workers::*;
use workers::GetChunkAnswer;
use utils::*;

pub struct Client {
  acts: ActorSystem,
  api: Arc<Api>
}

impl Client {
  pub fn new(api: Api) -> Self {
    let acts = ActorSystem::new("client".to_owned());
    acts.spawn_threads(parallelism());
    Client {
      acts: acts,
      api: Arc::new(api)
    }
  }

  pub fn hehehtests(&self) {
    let ref acts = self.acts;
    let hehehprops = Props::new(Arc::new(FriendsWorker::new), self.api.clone());
    let fw = acts.actor_of(hehehprops, "friends_wrk".to_owned());
    for n in 0..6 {
      println!("try {}", n);
      let res: GetChunkAnswer<Vec<User>> = acts.extract_result(
        acts.ask(fw.clone(), M::GetChunkAtPos(0), "get_chunk".to_owned())
      );
      match res {
        GetChunkAnswer::HasChunk(c) => {
          c.iter().map(|u| println!("{}: {} ({}){}",
                                                u.id,
                                                u.full_name,
                                                u.last_seen.format("%Y-%m-%d %H:%M:%S"),
                                                if u.banned {" (banned)"} else {""}));
        },
        GetChunkAnswer::NoChunk => println!("no chunk"),
        GetChunkAnswer::CacheFull => println!("cache full")
      };
      println!();
      sleep(Duration::from_secs(3));
    }
  }
}