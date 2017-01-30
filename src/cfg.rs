use json::{parse, JsonValue};
use std::ops::Deref;
use std::env::home_dir;
use std::path::{Path, PathBuf};
use std::fs::File;
use std::io::{Read, Write};
use std::string::ToString;

use errors::*;

struct SpawnResult(JsonValue, CfgRes<()>);

fn spawn(p: &Path) -> SpawnResult {
  println!("cfg: spawning config");
  // todo log this ^^
  let cfg = JsonValue::new_object();
  let f_res = write(p, &cfg);
  SpawnResult(cfg, f_res)
}

fn write (p: &Path, cfg: &JsonValue) -> CfgRes<()> {
  let mut f = File::create(p)?;
  f.write_all(cfg.pretty(2).as_bytes())?;
  f.sync_all()?;
  Ok(())
}

fn get_path() -> PathBuf {
  if let Some(mut p) = home_dir() {
    p.push("vk.conf");
    p
  } else {
    PathBuf::new()
  }
}

fn make_path(p: &Path) -> Option<String> {
  match p.to_str() {
    Some("") | None => None,
    Some(x) => Some(x.to_string())
  }
}

fn make_cfg(p: &Path) -> Cfg {
  let SpawnResult(c_conf, e_spawn) = spawn(&p);
  if let Err(e) = e_spawn {
    println!("cfg spawn: {}", e)
  };
  // todo log file spawn error
  Cfg { conf: c_conf, path: make_path(&p) }
}

pub struct Cfg {
  path: Option<String>,
  conf: JsonValue
}

impl Cfg {
  pub fn new() -> Cfg {
    let p = get_path();

    if !p.exists() {
      make_cfg(p.as_path())
    } else {
      let open = || -> CfgRes<_> {
        let mut raw = String::new();
        File::open(&p)
          .and_then(|mut f| f.read_to_string(&mut raw))?;
        Ok(parse(&raw)?)
      };
      match open() {
        Ok(c) => Cfg { conf: c, path: make_path(p.as_path()) },
        Err(e) => {
          println!("cfg: {}", e);
          // todo log this ^^
          make_cfg(p.as_path())
        }
      }
    }
  }

  pub fn get<'a>(&'a self, key: &str) -> &'a JsonValue {
    &self.conf[key]
  }

  pub fn set<T>(&mut self, key: &str, val: T)
    where JsonValue: From<T> {
    self.conf[key] = val.into()
  }

  pub fn save(&self) -> CfgRes<()> {
    if let Some(ref p) = self.path {
      write(Path::new(&p), &self.conf)
    }
    else {
      Err(CfgError::SaveError("no config path"))
    }
  }
}