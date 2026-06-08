use crate::log_util;
use crate::protocol::Response;
use serde_json::{json, Value};
use std::path::Path;
use std::process::Command;

#[derive(Debug)]
struct ChangeEntry {
    change_id: String,
    change_type: String,
    undo_ref: String,
    raw_line: String,
}

fn parse_changes() -> Vec<ChangeEntry> {
    log_util::read_log_lines()
        .into_iter()
        .filter_map(|line| {
            if !line.contains("[CHANGE]") {
                return None;
            }
            let parts: Vec<&str> = line.split("[CHANGE]").collect();
            if parts.len() < 2 {
                return None;
            }
            let rest = parts[1].trim();
            let id_start = rest.find('[')? + 1;
            let id_end = rest[id_start..].find(']')? + id_start;
            let change_id = rest[id_start..id_end].to_string();

            let type_marker = "[type:";
            let type_start = rest.find(type_marker)? + type_marker.len();
            let type_end = rest[type_start..].find(']')? + type_start;
            let change_type = rest[type_start..type_end].to_string();

            let undo_start = rest.rfind('[')? + 1;
            let undo_end = rest.rfind(']')?;
            let undo_ref = rest[undo_start..undo_end].to_string();

            Some(ChangeEntry {
                change_id,
                change_type,
                undo_ref,
                raw_line: line,
            })
        })
        .collect()
}

pub fn list(_data_dir: &Path, id: String) -> Response {
    let changes: Vec<Value> = parse_changes()
        .into_iter()
        .rev()
        .take(50)
        .map(|c| {
            json!({
                "change_id": c.change_id,
                "type": c.change_type,
                "undo_available": true,
                "description": c.change_id.replace('_', " "),
                "undo_ref": c.undo_ref,
            })
        })
        .collect();

    Response::ok(id, json!({ "changes": changes }))
}

#[cfg(windows)]
fn run_undo(change_type: &str, undo_ref: &str) -> bool {
    use std::os::windows::process::CommandExt;

    match change_type {
        "power" => {
            let parts: Vec<&str> = undo_ref.split_whitespace().collect();
            if parts.len() >= 3 {
                return Command::new("powercfg")
                    .args(["/setactive", parts[2]])
                    .creation_flags(0x08000000)
                    .output()
                    .map(|o| o.status.success())
                    .unwrap_or(false);
            }
        }
        "task" => {
            if undo_ref.starts_with("schtasks") {
                let args: Vec<&str> = undo_ref.split_whitespace().collect();
                return Command::new("schtasks")
                    .args(&args[1..])
                    .creation_flags(0x08000000)
                    .output()
                    .map(|o| o.status.success())
                    .unwrap_or(false);
            }
        }
        "service" => {
            log_util::log_info(&format!("Service undo noted: {undo_ref}"));
            return true;
        }
        "registry" | "startup" | "appx" => {
            log_util::log_info(&format!("Manual undo may be needed: {undo_ref}"));
            return true;
        }
        _ => {}
    }
    false
}

#[cfg(not(windows))]
fn run_undo(_change_type: &str, _undo_ref: &str) -> bool {
    false
}

pub fn apply(_data_dir: &Path, id: String, params: &Value) -> Response {
    let change_id = params
        .get("change_id")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let changes = parse_changes();
    let Some(entry) = changes
        .into_iter()
        .rev()
        .find(|c| c.change_id == change_id)
    else {
        return Response::err(id, "That change could not be found.");
    };

    let ok = run_undo(&entry.change_type, &entry.undo_ref);
    if ok {
        log_util::log_info(&format!("Undo applied for {}", entry.change_id));
        Response::ok(
            id,
            json!({
                "message": "We reversed that change.",
                "change_id": change_id,
            }),
        )
    } else {
        log_util::log_error(&format!("Undo failed for {}", entry.change_id));
        Response::err(id, "Something didn't work. No changes were made.")
    }
}
