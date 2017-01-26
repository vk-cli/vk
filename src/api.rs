use std::cell::*;
use std::ops::*;

use tokio_core::reactor::Core;

use futures::Future;

use hyper;
use hyper::Url;
use hyper::client::{Client, HttpConnector, FutureResponse};

use json::parse;

type HttpClient = Client<HttpConnector>;

enum Error {
  HyperError(hyper::error::Error),
  Strange(String)
}

struct Api {
  client: HttpClient,
  uid: i32,
  token: String,
  version: String
}

impl Api {
  pub fn new(io: Core, uid: i32, token: &str) -> Api {
    let handle = io.handle();
    Api {
      uid: uid,
      token: token.to_string(),
      version: "5.62".to_string(),
      client: Client::new(&handle)
    }
  }

  pub fn get_client<'a>(&'a self) -> &'a HttpClient {
    &self.client
  }

  pub fn api_get(&self, method: &str, params: &[(&str, &str)]) -> Result<FutureResponse, Error> {
    let base = format!(
      "https://api.vk.com/method/{m}?v={v}&access_token={at}",
      m = method,
      v = self.version,
      at = self.token
    );
    let url = base + &params
      .iter()
      .map(|&(p, v)| format!("&{}={}", p, v))
      .collect::<Vec<_>>()
      .connect("");
    let hurl = Url::parse(&url)
      .map_err(|e| Error::Strange(e.to_string()))?;
    Ok(self.client.get(hurl))
  }

}