use crate::protocol::Response;
use serde_json::{json, Value};
use std::io::{self, Write};
use std::sync::Mutex;

static STDOUT_LOCK: Mutex<()> = Mutex::new(());

fn write_line(line: &str) {
    if let Ok(_guard) = STDOUT_LOCK.lock() {
        let _ = writeln!(io::stdout(), "{line}");
        let _ = io::stdout().flush();
    }
}

pub fn send_response(resp: &Response) {
    if let Ok(out) = serde_json::to_string(resp) {
        write_line(&out);
    }
}

pub fn send_progress(request_id: &str, data: Value) {
    let payload = json!({
        "type": "progress",
        "id": request_id,
        "data": data,
    });
    if let Ok(line) = serde_json::to_string(&payload) {
        write_line(&line);
    }
}

pub fn send_event(event: &str, data: Value) {
    let payload = json!({
        "type": "event",
        "event": event,
        "data": data,
    });
    if let Ok(line) = serde_json::to_string(&payload) {
        write_line(&line);
    }
}
