use api::{Api, Error};
use futures::Future;

pub fn testmain() {
  println!("vk-cli 0.8 test main");
  let api = Api::new(228, "");
  let got = api.api_get("status.get", &[]);

  match got.wait() {
    Ok(r) => println!("{}", r.to_string()),
    Err(Error::RequestError(e)) => println!("req: {}", e),
    Err(Error::ApiError(code, msg)) => println!("api {}: {}", code, msg)
  }
}