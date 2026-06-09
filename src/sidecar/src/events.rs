use crate::ipc_out;
use serde_json::Value;

pub fn emit(event: &str, data: Value) {
    ipc_out::send_event(event, data);
}
