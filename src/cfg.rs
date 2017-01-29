use json::{parse, JsonValue};
use std::ops::Deref;
use std::env::home_dir;
use std::path::{Path, PathBuf};
use std::fs::File;
use std::io::{Read, Write};
use std::string::ToString;

use errors::*;
use error_chain::ChainedError;

fn spawn(p: &Path) -> JsonValue {
  println!("cfg: spawning config");
  let cfg = JsonValue::new_object();

  match write(p, &cfg) {
    Err(e) => println!("cfg: spawn failed - {}", e),
    _ => ()
  }

  cfg
}

fn write (p: &Path, cfg: &JsonValue) -> Result<()> {
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

pub struct Cfg {
  path: Option<String>,
  conf: JsonValue
}

impl Cfg {
  pub fn new() -> Cfg {
    let p = get_path();
    let cfgp = match p.to_str() {
      Some("") | None => None,
      Some(x) => Some(x.to_string())
    };

    if !p.exists() {
      Cfg { conf: spawn(p.as_path()), path: cfgp }
    } else {
      let open = || -> Result<_> {
        let mut raw = String::new();
        File::open(&p)
          .and_then(|mut f| f.read_to_string(&mut raw))
          .chain_err(|| "can't open file")?;
        Ok(
          parse(&raw)
            .chain_err(|| "can't parse config")?
        )
      };
      match open() {
        Ok(c) => Cfg { conf: c, path: cfgp },
        Err(e) => {
          println!("cfg: {}", e.display());
          Cfg { conf: spawn(p.as_path()), path: cfgp }
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

  pub fn save(&self) -> Result<()> {
    if let Some(ref p) = self.path {
      write(Path::new(&p), &self.conf)
    }
    else {
      Err("no config path".into())
    }
  }
}