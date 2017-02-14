use std::process::exit;
use std::sync::Arc;
use api::Api;
use futures::Future;
use cfg::Cfg;
use log::*;
use client::Client;

pub fn pretest() {
  println!("vk-cli 0.8 test main");

  let cfg = Cfg::new();
  cfg.save(); //formatting test

  let api = Api::new(228, cfg.get("token").as_str().unwrap_or(""));
  /*let got = api
    .friends_get(5, 0)
    .map(|f|
      f
        .iter()
        .map(|u|
          format!("{}: {} ({}){}",
                  u.id,
                  u.full_name,
                  u.last_seen.format("%Y-%m-%d %H:%M:%S"),
                  if u.banned {" (banned)"} else {""})
        )
        .collect::<Vec<_>>()
        .join("\n")
    );

  match got.wait() {
    Ok(r) => println!("{}", r.to_string()),
    Err(e) => error!("{}", e),
  }*/

  let cl = Client::new(api);
  cl.hehehtests();

  exit(0)
}