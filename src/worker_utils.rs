use workers::*;
use errors::*;
use utils::DummyResult;
use std::time::Duration;
use std::fmt::Display;
use futures::Future;
use futures::future::BoxFuture;
use tokio_timer::Timer;
use robots::actors::*;

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
          error!("{}: {}", error_prefix, e);
          None
        }
      };
      pass.map(|m|
        context.tell(pass_to, m)
      );
      Ok(())
    });
}