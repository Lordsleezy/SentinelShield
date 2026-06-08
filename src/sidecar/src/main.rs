mod admin;
mod cleaner;
mod log_util;
mod memory;
mod optimizer;
mod protocol;
mod scanner;
mod startup;
mod tasks;
mod undo;

use protocol::{Request, Response};
use std::path::PathBuf;

fn main() {
    let data_dir = std::env::var("SENTINEL_DATA_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."));
    log_util::init(&data_dir);
    log_util::log_info("Sentinel Shield sidecar started");

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
        let resp = handle(&data_dir, req);
        if let Ok(out) = serde_json::to_string(&resp) {
            println!("{out}");
        }
    }
}

fn handle(data_dir: &std::path::Path, req: Request) -> Response {
    match req.cmd.as_str() {
        "ping" => Response::ok(req.id, serde_json::json!({ "status": "ready" })),
        "is_admin" => admin::status(req.id),
        "scan" => scanner::scan(data_dir, req.id),
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
