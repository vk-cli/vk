use api::{Api, Error};
use futures::Future;
use cfg::Cfg;

pub fn testmain() {
  println!("vk-cli 0.8 test main");
  let cfg = Cfg::new();
  cfg.save(); //formatting test

  let api = Api::new(228, cfg.get("token").as_str().unwrap_or(""));
  let got = api.api_get("status.get", &[]);

  match got.wait() {
    Ok(r) => println!("{}", r.to_string()),
    Err(Error::RequestError(e)) => println!("req: {}", e),
    Err(Error::ApiError(code, msg)) => println!("api {}: {}", code, msg)
  }
}