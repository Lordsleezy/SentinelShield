use crate::protocol::Response;
use serde_json::json;

#[cfg(windows)]
pub fn is_admin() -> bool {
    #[link(name = "shell32")]
    extern "system" {
        fn IsUserAnAdmin() -> i32;
    }
    unsafe { IsUserAnAdmin() != 0 }
}

#[cfg(not(windows))]
pub fn is_admin() -> bool {
    false
}

pub fn status(id: String) -> Response {
    Response::ok(
        id,
        json!({
            "is_admin": is_admin(),
            "message": if is_admin() {
                "Running with full access."
            } else {
                "Some features need admin access."
            }
        }),
    )
}
