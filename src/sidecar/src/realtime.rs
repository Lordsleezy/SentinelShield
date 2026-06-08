use crate::events;
use crate::protocol::Response;
use crate::scan_engine;
use crate::settings;
use crate::threat_history;
use notify::{RecursiveMode, Watcher};
use notify_debouncer_mini::{new_debouncer, DebounceEventResult};
use serde_json::json;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

static RUNNING: AtomicBool = AtomicBool::new(false);
static THREAD_STARTED: OnceLock<Mutex<bool>> = OnceLock::new();

fn thread_started() -> &'static Mutex<bool> {
    THREAD_STARTED.get_or_init(|| Mutex::new(false))
}

fn handle_detection(data_dir: &Path, path: &Path, source: &str) {
    let Some(hit) = scan_engine::analyze_file(path) else {
        return;
    };

    let record = threat_history::record(
        data_dir,
        source,
        &hit.path,
        &hit.friendly_name,
        &hit.reason,
        "reported",
    );

    events::emit(
        "threat_detected",
        json!({
            "source": source,
            "path": hit.path,
            "friendly_name": hit.friendly_name,
            "reason": hit.reason,
            "record_id": record.id,
            "message": format!("We found something suspicious: {}", hit.friendly_name),
        }),
    );
}

pub fn start(data_dir: &Path, id: String) -> Response {
    if RUNNING.load(Ordering::SeqCst) {
        return Response::ok(
            id,
            json!({
                "active": true,
                "message": "Real-time protection is already running.",
            }),
        );
    }

    let mut settings_data = settings::load(data_dir);
    settings_data.realtime_enabled = true;
    let _ = settings::save(data_dir, &settings_data);

    let already = thread_started().lock().map(|g| *g).unwrap_or(false);
    if !already {
        let data_dir_owned = data_dir.to_path_buf();
        if let Ok(mut guard) = thread_started().lock() {
            *guard = true;
        }
        std::thread::spawn(move || {
            let data_dir = data_dir_owned;
            let Ok(mut debouncer) = new_debouncer(
                Duration::from_secs(2),
                move |result: DebounceEventResult| {
                    if !RUNNING.load(Ordering::SeqCst) {
                        return;
                    }
                    let Ok(events_list) = result else {
                        return;
                    };
                    for debounced in events_list {
                        let path = debounced.path;
                        if path.is_file() {
                            handle_detection(&data_dir, &path, "realtime");
                        }
                    }
                },
            ) else {
                return;
            };

            for watch_path in scan_engine::default_watch_paths() {
                if watch_path.exists() {
                    let _ = debouncer.watcher().watch(&watch_path, RecursiveMode::Recursive);
                }
            }

            while RUNNING.load(Ordering::SeqCst) {
                std::thread::sleep(Duration::from_secs(2));
            }
        });
    }

    RUNNING.store(true, Ordering::SeqCst);
    crate::log_util::log_info("Real-time protection started");
    events::emit(
        "realtime_started",
        json!({ "message": "Real-time protection is now watching your folders." }),
    );

    Response::ok(
        id,
        json!({
            "active": true,
            "message": "Real-time protection is now on. We'll alert you if something suspicious appears.",
        }),
    )
}

pub fn stop(data_dir: &Path, id: String) -> Response {
    RUNNING.store(false, Ordering::SeqCst);
    let mut settings_data = settings::load(data_dir);
    settings_data.realtime_enabled = false;
    let _ = settings::save(data_dir, &settings_data);
    crate::log_util::log_info("Real-time protection stopped");

    Response::ok(
        id,
        json!({
            "active": false,
            "message": "Real-time protection is off.",
        }),
    )
}

pub fn status(data_dir: &Path, id: String) -> Response {
    let active = RUNNING.load(Ordering::SeqCst);
    let settings_data = settings::load(data_dir);

    Response::ok(
        id,
        json!({
            "active": active,
            "enabled_in_settings": settings_data.realtime_enabled,
            "watch_paths": scan_engine::default_watch_paths()
                .iter()
                .map(|p| p.display().to_string())
                .collect::<Vec<_>>(),
        }),
    )
}

pub fn auto_start_if_enabled(data_dir: &Path) {
    let settings_data = settings::load(data_dir);
    if settings_data.realtime_enabled {
        let _ = start(data_dir, "auto-start".to_string());
    }
}
