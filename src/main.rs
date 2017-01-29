#![recursion_limit = "1024"]

extern crate futures;
extern crate futures_cpupool;
extern crate tokio_core;
extern crate curl;

#[macro_use]
extern crate json;

#[macro_use]
extern crate error_chain;

mod errors {
  error_chain! { }

  impl From<::std::io::Error> for Error {
    fn from(e: ::std::io::Error) -> Error { e.to_string().into() }
  }
}

mod cfg;
mod api;
mod testapp;
use testapp::*;

fn main() {
  testmain();
}

