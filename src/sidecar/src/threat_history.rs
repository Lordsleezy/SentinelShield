use crate::protocol::Response;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::fs::{self, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThreatRecord {
    pub id: String,
    pub timestamp: String,
    pub source: String,
    pub path: String,
    pub friendly_name: String,
    pub reason: String,
    pub action: String,
}

fn history_path(data_dir: &Path) -> PathBuf {
    data_dir.join("threats.jsonl")
}

pub fn record(
    data_dir: &Path,
    source: &str,
    path: &str,
    friendly_name: &str,
    reason: &str,
    action: &str,
) -> ThreatRecord {
    let entry = ThreatRecord {
        id: uuid::Uuid::new_v4().to_string(),
        timestamp: Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        source: source.to_string(),
        path: path.to_string(),
        friendly_name: friendly_name.to_string(),
        reason: reason.to_string(),
        action: action.to_string(),
    };
    let file_path = history_path(data_dir);
    if let Ok(mut file) = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&file_path)
    {
        if let Ok(line) = serde_json::to_string(&entry) {
            let _ = writeln!(file, "{line}");
        }
    }
    crate::log_util::log_info(&format!(
        "Threat recorded [{source}]: {friendly_name} — {reason}"
    ));
    entry
}

pub fn list(data_dir: &Path, id: String, params: &Value) -> Response {
    let limit = params
        .get("limit")
        .and_then(|v| v.as_u64())
        .unwrap_or(100) as usize;
    let path = history_path(data_dir);
    let mut records = Vec::new();

    if let Ok(file) = fs::File::open(&path) {
        let reader = BufReader::new(file);
        for line in reader.lines().map_while(Result::ok) {
            if line.trim().is_empty() {
                continue;
            }
            if let Ok(record) = serde_json::from_str::<ThreatRecord>(&line) {
                records.push(record);
            }
        }
    }

    records.reverse();
    records.truncate(limit);

    Response::ok(
        id,
        json!({
            "records": records,
            "count": records.len(),
        }),
    )
}

pub fn clear(data_dir: &Path, id: String) -> Response {
    let path = history_path(data_dir);
    let _ = fs::remove_file(&path);
    Response::ok(id, json!({ "message": "Threat history cleared." }))
}
