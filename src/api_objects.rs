use chrono::prelude::*;
use json::JsonValue;

pub struct User {
  pub id: i32,
  pub full_name: String,
  pub online: bool,
  pub last_seen: DateTime<UTC>
}

impl User {

  // TODO implement From<JsonValue>
  pub fn from_json_value(object: &JsonValue) -> Self {
    let id = object["id"].as_i32().unwrap_or(-1);
    let first_name = object["first_name"].as_str().unwrap_or("nofname").to_string();
    let last_name = object["last_name"].as_str().unwrap_or("nolname");
    let online = object["online"].as_u32().unwrap_or(0) == 1;
    let last_seen = UTC.timestamp(object["last_seen"]["time"].as_i64().unwrap_or(0), 0);
    User { id: id, full_name: first_name + " " + last_name, online: online, last_seen: last_seen }
  }
}
