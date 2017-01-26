extern crate futures;
extern crate hyper;
extern crate tokio_core;

#[macro_use]
extern crate json;

mod api;
mod testapp;
use testapp::*;

fn main() {
  testmain();
}
