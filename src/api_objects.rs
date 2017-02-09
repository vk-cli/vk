use chrono::prelude::*;

pub struct User {
  pub id: i32,
  pub full_name: String,
  pub online: bool,
  pub last_seen: DateTime<UTC>
}