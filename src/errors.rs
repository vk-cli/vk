use std;
use curl;
use json;

use std::fmt::Display;
use workers::Pos;

quick_error! {
  #[derive(Debug)]
  pub enum ReqError {
    NetworkError(desc: String) {
      description(&desc)
      display("nw: {}", desc)
    }

    RequestError(desc: String) {
      from(e: curl::Error) -> (format!("curl - {}", e))
      from(e: json::Error) -> (format!("json - {}", e))
      description(&desc)
      display("request: {}", desc)
    }

    ApiError(code: i32, desc: String) {
      description(&desc)
      display("api {}: {}", code, desc)
    }

    ParseError(subj: String) {
      description(&subj)
      display("parse error: {}", subj)
    }
  }
}

quick_error! {
  #[derive(Debug)]
  pub enum CfgError {
    OpenError(desc: String) {
      from(e: json::Error) -> (format!("json - {}", e))
      from(e: std::io::Error) -> (format!("io - {}", e))
      description(&desc)
      display("cfg open: {}", desc)
    }

    SaveError(desc: &'static str) {
      description(desc)
      display("cfg save: {}", desc)
    }
  }
}

quick_error! {
  #[derive(Debug)]
  pub enum WorkerError {
    Common(wname: String, desc: String) {
      display("worker {}: {}", wname, desc)
    }
    WorkError(cause: String) {
      display("work failed: {}", cause)
    }
    WorkTimedOut {
      display("work timed out")
    }
  }
}

pub fn work_error<E: Display>(cause: E) -> WorkerError {
  WorkerError::WorkError(format!("{}", cause))
}

pub fn work_timeout() -> WorkerError {
  WorkerError::WorkTimedOut
}

pub type CfgRes<T> = Result<T, CfgError>;
pub type ReqRes<T> = Result<T, ReqError>;
pub type WorkerRes<T> = Result<T, WorkerError>;
