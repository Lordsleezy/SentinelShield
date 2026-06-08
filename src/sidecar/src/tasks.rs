use crate::log_util;
use crate::protocol::Response;
use serde_json::{json, Value};
use std::path::Path;
use std::process::Command;

fn stable_task_id(name: &str) -> String {
    name.replace(['\\', '/'], "_").to_lowercase()
}

const TASK_PATHS: &[(&str, &str, &str)] = &[
    (
        r"\Microsoft\Windows\Customer Experience Improvement Program",
        "Customer Experience Program",
        "Sends information about how you use your computer to Microsoft",
    ),
    (
        r"\Microsoft\Windows\Application Experience",
        "Application Experience",
        "Collects data about installed programs in the background",
    ),
    (
        r"\Microsoft\Windows\DiskDiagnostic",
        "Disk Diagnostic",
        "Runs disk checks you rarely need",
    ),
    (
        r"\Microsoft\Windows\Autochk",
        "Automatic Disk Check",
        "Schedules disk checks that can slow startup",
    ),
];

#[cfg(windows)]
fn run_hidden(program: &str, args: &[&str]) -> Option<String> {
    use std::os::windows::process::CommandExt;
    Command::new(program)
        .args(args)
        .creation_flags(0x08000000)
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
}

#[cfg(not(windows))]
fn run_hidden(_program: &str, _args: &[&str]) -> Option<String> {
    None
}

fn list_tasks_in_folder(folder: &str) -> Vec<(String, String)> {
    let output = run_hidden("schtasks", &["/query", "/fo", "CSV", "/tn", folder]);
    let Some(text) = output else {
        return Vec::new();
    };
    let mut tasks = Vec::new();
    for line in text.lines().skip(1) {
        let parts: Vec<&str> = line.split(',').collect();
        if let Some(name) = parts.first() {
            let name = name.trim_matches('"');
            if !name.is_empty() {
                tasks.push((name.to_string(), folder.to_string()));
            }
        }
    }
    tasks
}

pub fn list(id: String) -> Response {
    let mut items = Vec::new();
    for (path, friendly, plain) in TASK_PATHS {
        for (task_name, folder) in list_tasks_in_folder(path) {
            items.push(json!({
                "id": stable_task_id(&task_name),
                "name": task_name,
                "task_path": folder,
                "friendly_name": friendly,
                "plain_description": plain,
            }));
        }
    }
    Response::ok(id, json!({ "items": items }))
}

pub fn disable(_data_dir: &Path, id: String, params: &Value) -> Response {
    let tasks: Vec<Value> = params
        .get("tasks")
        .and_then(|v| serde_json::from_value(v.clone()).ok())
        .unwrap_or_default();

    let mut disabled = Vec::new();
    for task in tasks {
        let name = task.get("name").and_then(|v| v.as_str()).unwrap_or("");
        let friendly = task
            .get("friendly_name")
            .and_then(|v| v.as_str())
            .unwrap_or(name);
        if name.is_empty() {
            continue;
        }
        let full_name = format!(r"\{}", name.trim_start_matches('\\'));
        let ok = run_hidden("schtasks", &["/change", "/tn", &full_name, "/disable"]).is_some();
        if ok {
            log_util::log_change(
                &format!("task_{name}"),
                "task",
                &format!("schtasks /change /tn \"{full_name}\" /enable"),
            );
            disabled.push(json!({ "friendly_name": friendly }));
        } else {
            log_util::log_error(&format!("Could not disable task: {name}"));
        }
    }

    let count = disabled.len();
    let message = if count == 0 {
        "Something didn't work. No changes were made.".to_string()
    } else {
        format!("We disabled {count} scheduled task(s).")
    };

    Response::ok(
        id,
        json!({
            "disabled": disabled,
            "message": message,
        }),
    )
}
