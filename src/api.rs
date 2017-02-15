use std::fmt::{Debug, Display};

use futures::Future;
use futures::future::BoxFuture;
use futures_cpupool::CpuPool;

use curl;
use curl::easy::Easy;

use json::{parse, JsonValue};

use chrono::prelude::*;

use slog::Logger;
use utils::*;
use api_objects::*;
use errors::*;

pub type MethodResponse<T> = BoxFuture<T, ReqError>;
pub type ApiResponse = MethodResponse<JsonValue>;

impl<R: Debug, E: Display> ResultUtils<R> for Result<R, E> {
  fn parse_check(self, o: &JsonValue, log: Logger, m: &'static str) -> Option<R> {
    if self.is_ok() { self.ok() } else {
      error!(log, "{}: {}", m, self.unwrap_err());
      debug!(log, "failed json: \n{}", o.pretty(2));
      None
    }
  }
}

pub struct Api {
  pool: CpuPool,
  uid: i32,
  token: String,
  version: String,
  log: Logger
}

impl Api {
  pub fn new(uid: i32, token: &str) -> Api {
    Api {
      pool: CpuPool::new(parallelism() as usize),
      uid: uid,
      token: token.to_string(),
      version: "5.62".to_string(),
      log: get_logger().new(o!(WHERE => "api"))
    }
  }

  pub fn http_get(&self, url: String) -> ApiResponse {
    // todo use tokio_core w/ hyper instead of curl
    self.pool
      .spawn_fn(move || -> ReqRes<(_, Vec<_>)> {
        let mut h = Easy::new();
        let mut buf = Vec::new();

        h.url(&url)?;
        {
          let mut tf = h.transfer();
          tf.write_function(|c| {
            buf.extend_from_slice(c);
            Ok(c.len())
          })?;
          tf.perform()?;
        }

        Ok((h.response_code()?, buf))
      })
      .and_then(|(code, data)| {
        match code {
          200 => {
            let resp = &String::from_utf8_lossy(&data);
            Ok(parse(resp)?)
          }
          x => Err(ReqError::NetworkError(format!("code {}", x)))
        }
      })
      .boxed()
  }

  pub fn api_get(&self, method: &str, params: &[(&str, &str)]) -> ApiResponse {
    let base = format!(
      "https://api.vk.com/method/{m}?v={v}",
      m = method,
      v = self.version
    );

    let logurl = base + &params
      .iter()
      .map(|&(p, v)| format!("&{}={}", p, v))
      .collect::<Vec<_>>()
      .join("");

    debug!(self.log, "request: {}", logurl);

    let url = format!("{}&access_token={}", logurl, self.token);
    self.http_get(url)
      .and_then(|mut val| {
        let resp = val["response"].take();
        let ref err = val["error"];
        if err.is_null() && !resp.is_null() { Ok(resp) } else {
          match (err["error_code"].as_i32(),
                 err["error_msg"].as_str()
                   .or(err["error_description"].as_str())
          ) {
            (Some(code), Some(msg)) => Err(ReqError::ApiError(code, msg.to_string())),
            _ => Err(ReqError::ApiError(-1, err.dump()))
          }
        }
      })
      .boxed()
  }

  pub fn friends_get(&self, count: i32, offset: i32) -> MethodResponse<Vec<User>> {
    let log = self.log.clone();
    self.api_get("friends.get", &[
      ("count", &count.to_string()[..]),
      ("offset", &offset.to_string()[..]),
      ("order", "hints"),
      ("fields", "online,last_seen")
    ])
      .and_then(move |friend_list| Ok(
        friend_list["items"]
          .members()
          .flat_map(|f| {
            let u = User::from_json(f);
            u.parse_check(f, log.clone(), "can't parse friend") //todo check fuckin 2x clone
          })
          .collect::<Vec<_>>()
      ))
      .boxed()
  }
}
