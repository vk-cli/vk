use std;
use curl;
use json;

quick_error! {
  #[derive(Debug)]
  pub enum ReqError {
    NetworkError(desc: String) {
      description(&desc)
      display("[e] nw: {}", desc)
    }

    RequestError(desc: String) {
      from(e: curl::Error) -> (format!("curl - {}", e))
      from(e: json::Error) -> (format!("json - {}", e))
      description(&desc)
      display("[e] request: {}", desc)
    }

    ApiError(code: i32, desc: String) {
      description(&desc)
      display("[e] api {}: {}", code, desc)
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
      display("[e] cfg open: {}", desc)
    }

    SaveError(desc: &'static str) {
      description(desc)
      display("[e] cfg save: {}", desc)
    }
  }
}

pub type CfgRes<T> = Result<T, CfgError>;
pub type ReqRes<T> = Result<T, ReqError>;
