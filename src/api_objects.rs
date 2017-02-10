use chrono::prelude::*;
use json::JsonValue;

use utils::OptionUtils;
use errors::*;

impl<T> OptionUtils<T, ReqError> for Option<T> {
  fn uw(self, s: &str) -> ReqRes<T> {
    self.ok_or(ReqError::ParseError(s.to_string()))
  }
}

pub struct User {
  pub id: i32,
  pub full_name: String,
  pub online: bool,
  pub banned: bool,
  pub last_seen: DateTime<UTC>
}

impl User {
  // TODO implement From<JsonValue>
  pub fn from_json(o: &JsonValue) -> ReqRes<Self> {
    let id = o["id"].as_i32().uw("user - no id")?;
    let first_name = o["first_name"].as_str().uw("user - no fname")?.to_string();
    let last_name = o["last_name"].as_str().uw("user - no lname")?;

    let ls_utime = o["last_seen"]["time"].as_i64().unwrap_or(0);
    let last_seen = UTC.timestamp(ls_utime, 0);

    Ok( User {
      id: id,
      full_name: first_name + " " + last_name,
      last_seen: last_seen,
      online: o["online"].as_u32().unwrap_or(0) == 1,
      banned: ls_utime == 0
    })
  }
}
