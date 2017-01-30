use std::process::exit;
use api::Api;
use futures::Future;
use cfg::Cfg;

pub fn pretest() {
  println!("vk-cli 0.8 test main");
  let cfg = Cfg::new();
  cfg.save(); //formatting test

  let api = Api::new(228, cfg.get("token").as_str().unwrap_or(""));
  let got = api.api_get("status.get", &[]);

  match got.wait() {
    Ok(r) => println!("{}", r.to_string()),
    Err(e) => println!("{}", e),
  }

  exit(0)
}