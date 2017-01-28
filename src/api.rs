use futures::Future;
use futures::future::BoxFuture;
use futures_cpupool::CpuPool;

use curl;
use curl::easy::Easy;

use json::{parse, JsonValue};

pub type ApiResponse = BoxFuture<JsonValue, Error>;

pub enum Error {
  RequestError(String),
  ApiError(i32, String)
}

pub struct Api {
  pool: CpuPool,
  uid: i32,
  token: String,
  version: String
}

impl Api {
  pub fn new(uid: i32, token: &str) -> Api {
    Api {
      pool: CpuPool::new(6),
      uid: uid,
      token: token.to_string(),
      version: "5.62".to_string()
    }
  }

  pub fn http_get(&self, url: String) -> ApiResponse {
    // todo use tokio_core w/ hyper instead of curl
    self.pool
      .spawn_fn(move || {
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

        let res: Result<(_, Vec<_>), curl::Error> = Ok((h.response_code()?, buf));
        res
      })
      .map_err(|e| Error::RequestError(e.to_string()))
      .and_then(|(code, data)| {
        match code {
          200 => {
            let resp = &String::from_utf8_lossy(&data);
            parse(resp)
              .map_err(|e| Error::RequestError(e.to_string()))
          }
          x => Err(Error::RequestError(format!("code {}", x)))
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

    let url = format!("{}&access_token={}", logurl, self.token);
    self.http_get(url)
      .and_then(|mut val| {
        let resp = val["response"].take();
        let ref err = val["error"];
        if err.is_null() && !resp.is_null() { Ok(resp) }
        else {
          match (err["error_code"].as_i32(), err["error_msg"].as_str()) {
            (Some(code), Some(msg)) => Err(Error::ApiError(code, msg.to_string())),
            _ => Err(Error::ApiError(-1, err.dump()))
          }
        }
      })
      .boxed()
  }
}