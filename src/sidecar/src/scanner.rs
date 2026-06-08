use crate::log_util;
use crate::protocol::Response;
use crate::scan_engine;
use crate::threat_history;
use serde_json::{json, Value};
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::time::Instant;
use uuid::Uuid;

fn emit_progress(
    request_id: &str,
    current_file: &str,
    files_scanned: u32,
    files_total: u32,
    started: Instant,
) {
    let elapsed = started.elapsed().as_secs_f64();
    let eta_seconds = if files_scanned > 0 && files_total > files_scanned {
        let remaining = (files_total - files_scanned) as f64;
        let rate = elapsed / files_scanned as f64;
        (rate * remaining).round() as u32
    } else {
        0
    };

    let payload = json!({
        "type": "progress",
        "id": request_id,
        "data": {
            "current_file": current_file,
            "files_scanned": files_scanned,
            "files_total": files_total,
            "eta_seconds": eta_seconds,
        }
    });
    if let Ok(line) = serde_json::to_string(&payload) {
        let _ = writeln!(io::stdout(), "{line}");
        let _ = io::stdout().flush();
    }
}

fn scan_roots_from_params(params: &Value) -> Vec<PathBuf> {
    if let Some(paths) = params.get("paths").and_then(|v| v.as_array()) {
        let custom: Vec<PathBuf> = paths
            .iter()
            .filter_map(|v| v.as_str())
            .map(PathBuf::from)
            .filter(|p| p.exists())
            .collect();
        if !custom.is_empty() {
            return custom;
        }
    }
    scan_engine::default_scan_targets()
}

pub fn move_to_quarantine(data_dir: &Path, path: &Path) -> Result<PathBuf, String> {
    if !path.is_file() {
        return Err("File not found.".to_string());
    }
    let name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown");
    let dest_name = format!("{}_{}", Uuid::new_v4(), name);
    let dest = data_dir.join("quarantine").join(dest_name);
    fs::rename(path, &dest).map_err(|e| e.to_string())?;
    log_util::log_info(&format!(
        "User quarantined {} -> {}",
        path.display(),
        dest.display()
    ));
    Ok(dest)
}

pub fn scan(data_dir: &Path, id: String, params: &Value) -> Response {
    log_util::log_info("Starting antivirus scan (report-only, no auto-quarantine)");
    let roots = scan_roots_from_params(params);
    let files = scan_engine::collect_files(&roots);
    let files_total = files.len() as u32;
    let started = Instant::now();
    let mut items = Vec::new();

    emit_progress(&id, "Preparing scan...", 0, files_total, started);

    for (index, path) in files.iter().enumerate() {
        let files_scanned = (index + 1) as u32;
        let current_file = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("unknown file")
            .to_string();

        if files_scanned == 1 || files_scanned == files_total || files_scanned % 10 == 0 {
            emit_progress(&id, &current_file, files_scanned, files_total, started);
        }

        if let Some(hit) = scan_engine::analyze_file(path) {
            threat_history::record(
                data_dir,
                "manual",
                &hit.path,
                &hit.friendly_name,
                &hit.reason,
                "reported",
            );
            items.push(json!({
                "path": hit.path,
                "friendly_name": hit.friendly_name,
                "reason": hit.reason,
                "recommendation": "Review this file. Tap Quarantine only if you want it moved.",
            }));
        }
    }

    let threat_count = items.len();
    let message = if threat_count == 0 {
        "We didn't find anything suspicious. You're all clear.".to_string()
    } else if threat_count == 1 {
        "We found 1 suspicious file. Review it below — nothing was moved.".to_string()
    } else {
        format!("We found {threat_count} suspicious files. Review them below — nothing was moved.")
    };

    log_util::log_info(&format!("Scan complete: {threat_count} threats reported"));
    Response::ok(
        id,
        json!({
            "message": message,
            "threat_count": threat_count,
            "items": items,
        }),
    )
}

pub fn quarantine(data_dir: &Path, id: String, params: &Value) -> Response {
    let path_str = params
        .get("path")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    if path_str.is_empty() {
        return Response::err(id, "No file was selected.");
    }

    let path = PathBuf::from(path_str);
    match move_to_quarantine(data_dir, &path) {
        Ok(dest) => {
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                threat_history::record(
                    data_dir,
                    "manual",
                    path_str,
                    name,
                    "User quarantined this file",
                    "quarantined",
                );
            }
            Response::ok(
                id,
                json!({
                    "message": "We moved the file to quarantine.",
                    "quarantine_path": dest.display().to_string(),
                }),
            )
        }
        Err(e) => {
            log_util::log_error(&format!("Quarantine failed for {path_str}: {e}"));
            Response::err(id, "Could not quarantine that file.")
        }
    }
}
