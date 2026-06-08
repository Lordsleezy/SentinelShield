use serde_json::{json, Value};
use std::io::{self, Write};

pub fn emit(event: &str, data: Value) {
    let payload = json!({
        "type": "event",
        "event": event,
        "data": data,
    });
    if let Ok(line) = serde_json::to_string(&payload) {
        let _ = writeln!(io::stdout(), "{line}");
        let _ = io::stdout().flush();
    }
}
