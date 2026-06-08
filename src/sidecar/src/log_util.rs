use chrono::Utc;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

static LOG_PATH: Mutex<Option<PathBuf>> = Mutex::new(None);

pub fn init(data_dir: &Path) {
    let logs_dir = data_dir.join("logs");
    let _ = fs::create_dir_all(&logs_dir);
    let quarantine_dir = data_dir.join("quarantine");
    let _ = fs::create_dir_all(&quarantine_dir);
    let log_path = logs_dir.join("shield.log");
    if let Ok(mut guard) = LOG_PATH.lock() {
        *guard = Some(log_path);
    }
}

fn log_path() -> Option<PathBuf> {
    LOG_PATH.lock().ok()?.clone()
}

pub fn write_line(message: &str) {
    let Some(path) = log_path() else {
        return;
    };
    let timestamp = Utc::now().format("%Y-%m-%dT%H:%M:%SZ");
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(file, "[{timestamp}] {message}");
    }
}

pub fn log_info(message: &str) {
    write_line(&format!("[INFO] {message}"));
}

pub fn log_error(message: &str) {
    write_line(&format!("[ERROR] {message}"));
}

pub fn log_change(id: &str, change_type: &str, undo_ref: &str) {
    let timestamp = Utc::now().format("%Y-%m-%dT%H:%M:%SZ");
    write_line(&format!(
        "[{timestamp}] [CHANGE] [{id}] [type:{change_type}] [{undo_ref}]"
    ));
}

pub fn read_log_lines() -> Vec<String> {
    let Some(path) = log_path() else {
        return Vec::new();
    };
    fs::read_to_string(path)
        .unwrap_or_default()
        .lines()
        .map(str::to_owned)
        .collect()
}

pub fn format_bytes(bytes: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = KB * 1024;
    const GB: u64 = MB * 1024;
    if bytes >= GB {
        format!("{:.1} GB", bytes as f64 / GB as f64)
    } else if bytes >= MB {
        format!("{:.1} MB", bytes as f64 / MB as f64)
    } else if bytes >= KB {
        format!("{:.1} KB", bytes as f64 / KB as f64)
    } else {
        format!("{bytes} bytes")
    }
}

pub fn app_root() -> PathBuf {
    std::env::var("SENTINEL_APP_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            std::env::current_exe()
                .ok()
                .and_then(|p| p.parent().map(|p| p.to_path_buf()))
                .unwrap_or_else(|| PathBuf::from("."))
        })
}
