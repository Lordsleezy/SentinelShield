use crate::events;
use crate::protocol::Response;
use crate::scan_engine;
use crate::settings::{self, ScheduleSettings};
use crate::threat_history;
use chrono::{Datelike, Local, Timelike, Weekday};
use serde_json::{json, Value};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

static WORKER_STARTED: OnceLock<()> = OnceLock::new();
static LAST_RUN_DAY: OnceLock<Mutex<Option<String>>> = OnceLock::new();

fn last_run() -> &'static Mutex<Option<String>> {
    LAST_RUN_DAY.get_or_init(|| Mutex::new(None))
}

fn weekday_to_u32(day: Weekday) -> u32 {
    match day {
        Weekday::Mon => 0,
        Weekday::Tue => 1,
        Weekday::Wed => 2,
        Weekday::Thu => 3,
        Weekday::Fri => 4,
        Weekday::Sat => 5,
        Weekday::Sun => 6,
    }
}

fn should_run_now(schedule: &ScheduleSettings) -> bool {
    if !schedule.enabled {
        return false;
    }
    let now = Local::now();
    let day = weekday_to_u32(now.weekday());
    if !schedule.days.contains(&day) {
        return false;
    }
    let hour = now.hour();
    let minute = now.minute();
    if hour != schedule.hour || minute != schedule.minute {
        return false;
    }
    let today = now.format("%Y-%m-%d").to_string();
    if let Ok(guard) = last_run().lock() {
        if guard.as_deref() == Some(today.as_str()) {
            return false;
        }
    }
    true
}

fn run_scheduled_scan(data_dir: &Path) {
    crate::log_util::log_info("Starting scheduled background scan");
    let roots = scan_engine::default_scan_targets();
    let files = scan_engine::collect_files(&roots);
    let file_count = files.len();
    let mut threat_count = 0u32;

    for path in files {
        if let Some(hit) = scan_engine::analyze_file(&path) {
            threat_count += 1;
            let record = threat_history::record(
                data_dir,
                "scheduled",
                &hit.path,
                &hit.friendly_name,
                &hit.reason,
                "reported",
            );
            events::emit(
                "threat_detected",
                json!({
                    "source": "scheduled",
                    "path": hit.path,
                    "friendly_name": hit.friendly_name,
                    "reason": hit.reason,
                    "record_id": record.id,
                    "message": format!("Scheduled scan found: {}", hit.friendly_name),
                }),
            );
        }
    }

    let today = Local::now().format("%Y-%m-%d").to_string();
    if let Ok(mut guard) = last_run().lock() {
        *guard = Some(today);
    }

    let message = if threat_count == 0 {
        "Scheduled scan finished. Nothing suspicious found.".to_string()
    } else {
        format!("Scheduled scan found {threat_count} suspicious file(s).")
    };

    crate::log_util::log_info(&format!("Scheduled scan complete: {threat_count} threats"));
    events::emit(
        "scheduled_scan_complete",
        json!({
            "threat_count": threat_count,
            "files_scanned": file_count,
            "message": message,
        }),
    );
}

pub fn start_worker(data_dir: PathBuf) {
    WORKER_STARTED.get_or_init(|| {
        std::thread::spawn(move || {
            loop {
                std::thread::sleep(Duration::from_secs(30));
                let schedule = settings::load(&data_dir).schedule;
                if should_run_now(&schedule) {
                    run_scheduled_scan(&data_dir);
                }
            }
        });
    });
}

pub fn get_settings(data_dir: &Path, id: String) -> Response {
    let settings_data = settings::load(data_dir);
    Response::ok(
        id,
        json!({
            "schedule": settings_data.schedule,
        }),
    )
}

pub fn set_settings(data_dir: &Path, id: String, params: &Value) -> Response {
    let mut settings_data = settings::load(data_dir);
    if let Some(schedule) = params.get("schedule") {
        if let Ok(updated) = serde_json::from_value::<ScheduleSettings>(schedule.clone()) {
            settings_data.schedule = updated;
        }
    }
    match settings::save(data_dir, &settings_data) {
        Ok(()) => Response::ok(
            id,
            json!({
                "schedule": settings_data.schedule,
                "message": "Scan schedule saved.",
            }),
        ),
        Err(e) => Response::err(id, &e),
    }
}
