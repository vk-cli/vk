use std;
use curl;
use json;

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

pub type CfgRes<T> = Result<T, CfgError>;
pub type ReqRes<T> = Result<T, ReqError>;
