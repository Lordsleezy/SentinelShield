mod admin;
mod cleaner;
mod events;
mod ipc_out;
mod log_util;
mod memory;
mod network;
mod optimizer;
mod protocol;
mod realtime;
mod rules_updater;
mod scan_engine;
mod scanner;
mod schedule;
mod settings;
mod startup;
mod tasks;
mod threat_history;
mod undo;

use protocol::{Request, Response};
use std::path::PathBuf;

fn main() {
    let data_dir = std::env::var("SENTINEL_DATA_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."));
    log_util::init(&data_dir);
    log_util::log_info("Sentinel Shield sidecar started (Stage 2)");

    schedule::start_worker(data_dir.clone());

    let rules_dir = data_dir.clone();
    std::thread::spawn(move || {
        match rules_updater::update_on_launch(&rules_dir) {
            Ok(msg) => log_util::log_info(&msg),
            Err(e) => log_util::log_error(&format!("Rules update on launch: {e}")),
        }
    });

    realtime::auto_start_if_enabled(&data_dir);

    let stdin = std::io::stdin();
    for line in stdin.lines().flatten() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let req: Request = match serde_json::from_str(line) {
            Ok(r) => r,
            Err(e) => {
                log_util::log_error(&format!("Invalid request JSON: {e}"));
                continue;
            }
        };
        let data_dir = data_dir.clone();
        std::thread::spawn(move || {
            let resp = handle(&data_dir, req);
            ipc_out::send_response(&resp);
        });
    }
}

fn handle(data_dir: &std::path::Path, req: Request) -> Response {
    match req.cmd.as_str() {
        "ping" => Response::ok(req.id, serde_json::json!({ "status": "ready" })),
        "is_admin" => admin::status(req.id),
        "scan" => scanner::scan(data_dir, req.id, &req.params),
        "quarantine" => scanner::quarantine(data_dir, req.id, &req.params),
        "realtime_start" => realtime::start(data_dir, req.id),
        "realtime_stop" => realtime::stop(data_dir, req.id),
        "realtime_status" => realtime::status(data_dir, req.id),
        "schedule_get" => schedule::get_settings(data_dir, req.id),
        "schedule_set" => schedule::set_settings(data_dir, req.id, &req.params),
        "network_scan" => network::scan(data_dir, req.id),
        "rules_update" => rules_updater::update(data_dir, req.id),
        "threat_history_list" => threat_history::list(data_dir, req.id, &req.params),
        "threat_history_clear" => threat_history::clear(data_dir, req.id),
        "settings_get" => {
            let s = settings::load(data_dir);
            Response::ok(req.id, serde_json::json!(s))
        }
        "settings_set" => {
            let mut s = settings::load(data_dir);
            if let Some(url) = req.params.get("rules_url").and_then(|v| v.as_str()) {
                s.rules_url = url.to_string();
            }
            if let Some(enabled) = req.params.get("realtime_enabled").and_then(|v| v.as_bool()) {
                s.realtime_enabled = enabled;
            }
            match settings::save(data_dir, &s) {
                Ok(()) => Response::ok(req.id, serde_json::json!({ "message": "Settings saved." })),
                Err(e) => Response::err(req.id, &e),
            }
        }
        "cleaner_preview" => cleaner::preview(data_dir, req.id),
        "cleaner_run" => cleaner::run(data_dir, req.id, &req.params),
        "memory_status" => memory::status(req.id),
        "memory_free" => memory::free(req.id),
        "optimizer_list" => optimizer::list(req.id),
        "optimizer_apply" => optimizer::apply(data_dir, req.id, &req.params),
        "startup_list" => startup::list(req.id),
        "startup_disable" => startup::disable(data_dir, req.id, &req.params),
        "tasks_list" => tasks::list(req.id),
        "tasks_disable" => tasks::disable(data_dir, req.id, &req.params),
        "undo_list" => undo::list(data_dir, req.id),
        "undo_apply" => undo::apply(data_dir, req.id, &req.params),
        _ => Response::err(req.id, "That action is not available."),
    }
}
