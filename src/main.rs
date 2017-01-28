extern crate futures;
extern crate futures_cpupool;
extern crate tokio_core;
extern crate curl;

#[macro_use]
extern crate json;

mod api;
mod testapp;
mod ui;
use testapp::*;
use ui::*;

fn main() {
  // testmain();
  render();
}

