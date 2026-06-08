use crate::log_util;
use crate::protocol::Response;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::fs;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::time::Instant;
use uuid::Uuid;
use walkdir::WalkDir;
use yara::{Compiler, Rules};

const MAX_SCAN_DEPTH: usize = 6;
const MAX_SCAN_FILE_BYTES: u64 = 50 * 1024 * 1024;
const SKIP_DIR_NAMES: &[&str] = &[
    "node_modules", ".git", "target", "dist", "build", ".cargo", "__pycache__", ".venv",
    "venv", ".idea", ".vs",
];
const EXECUTABLE_EXTENSIONS: &[&str] = &[
    "exe", "dll", "scr", "msi", "cpl", "sys", "com", "pif", "bat", "cmd", "ps1", "vbs", "js",
    "jar",
];

struct ScanHit {
    path: String,
    friendly_name: String,
    reason: String,
    recommendation: String,
}

fn rules_path() -> PathBuf {
    std::env::var("SENTINEL_RULES_DIR")
        .map(|d| PathBuf::from(d).join("starter.yar"))
        .unwrap_or_else(|_| log_util::app_root().join("rules").join("starter.yar"))
}

fn hashes_path() -> PathBuf {
    log_util::app_root().join("data").join("known_bad_hashes.txt")
}

fn load_bad_hashes() -> HashSet<String> {
    let path = hashes_path();
    let Ok(content) = fs::read_to_string(&path) else {
        log_util::log_error(&format!("Could not read hash file: {}", path.display()));
        return HashSet::new();
    };
    content
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .map(|l| l.split_whitespace().next().unwrap_or(l).to_lowercase())
        .filter(|h| h.len() == 64)
        .collect()
}

fn compile_rules() -> Option<Rules> {
    let path = rules_path();
    let compiler = match Compiler::new() {
        Ok(c) => c,
        Err(e) => {
            log_util::log_error(&format!("YARA init failed: {e}"));
            return None;
        }
    };
    let compiler = match compiler.add_rules_file(&path) {
        Ok(c) => c,
        Err(e) => {
            log_util::log_error(&format!("YARA rules load failed ({}): {e}", path.display()));
            return None;
        }
    };
    match compiler.compile_rules() {
        Ok(rules) => Some(rules),
        Err(e) => {
            log_util::log_error(&format!("YARA compile failed: {e}"));
            None
        }
    }
}

fn default_scan_targets() -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Ok(user) = std::env::var("USERPROFILE") {
        let home = PathBuf::from(&user);
        paths.push(home.join("Downloads"));
        paths.push(home.join("Desktop"));
        paths.push(home.join("Documents"));
    }
    paths.push(std::env::temp_dir());
    paths.push(PathBuf::from(r"C:\Windows\Temp"));
    paths
}

fn walk_files(roots: &[PathBuf]) -> Vec<PathBuf> {
    let mut files = Vec::new();
    for root in roots {
        if !root.exists() {
            continue;
        }
        for entry in WalkDir::new(root)
            .follow_links(false)
            .max_depth(MAX_SCAN_DEPTH)
            .into_iter()
            .filter_entry(|e| {
                if !e.file_type().is_dir() {
                    return true;
                }
                let name = e.file_name().to_string_lossy();
                !SKIP_DIR_NAMES
                    .iter()
                    .any(|skip| name.eq_ignore_ascii_case(skip))
            })
            .filter_map(|e| e.ok())
        {
            let path = entry.path().to_path_buf();
            if path.is_file() {
                files.push(path);
            }
        }
    }
    files
}

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
    default_scan_targets()
}

fn hash_file(path: &Path) -> Option<String> {
    let mut file = fs::File::open(path).ok()?;
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 8192];
    loop {
        let n = file.read(&mut buffer).ok()?;
        if n == 0 {
            break;
        }
        hasher.update(&buffer[..n]);
    }
    Some(format!("{:x}", hasher.finalize()))
}

fn double_extension(path: &Path) -> Option<String> {
    let name = path.file_name()?.to_str()?.to_lowercase();
    for pat in [".pdf.exe", ".doc.exe", ".jpg.exe", ".txt.scr", ".png.exe"] {
        if name.ends_with(pat) {
            return Some(
                "This file uses a double extension that may hide what it really is.".to_string(),
            );
        }
    }
    None
}

fn should_scan_content(path: &Path) -> bool {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase())
        .unwrap_or_default();
    ext.is_empty() || EXECUTABLE_EXTENSIONS.contains(&ext.as_str())
}

fn extension_mismatch(path: &Path) -> Option<String> {
    let ext = path.extension()?.to_str()?.to_lowercase();
    if ext.is_empty() {
        return None;
    }
    let kind = infer::get_from_path(path).ok()??;
    let detected = kind.extension();
    if detected.is_empty() {
        return None;
    }
    if !EXECUTABLE_EXTENSIONS.contains(&detected) {
        return None;
    }
    if detected != ext && !ext.ends_with(detected) {
        let friendly = match ext.as_str() {
            "pdf" => "PDF document",
            "doc" | "docx" => "Word document",
            "jpg" | "jpeg" | "png" => "picture",
            "txt" => "text file",
            "exe" => "program",
            _ => "file",
        };
        return Some(format!(
            "This file is pretending to be a {friendly} but it's actually a program."
        ));
    }
    None
}

fn yara_hits(rules: &Rules, path: &Path) -> Vec<String> {
    let Ok(results) = rules.scan_file(path, 0) else {
        return Vec::new();
    };
    results
        .iter()
        .map(|rule| {
            rule.metadatas
                .iter()
                .find(|m| m.identifier == "description")
                .and_then(|m| match m.value {
                    yara::MetadataValue::String(s) => Some(s.to_string()),
                    _ => None,
                })
                .unwrap_or_else(|| rule.identifier.to_string())
        })
        .collect()
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

fn scan_file(rules: Option<&Rules>, bad_hashes: &HashSet<String>, path: &Path) -> Option<ScanHit> {
    if !path.is_file() {
        return None;
    }
    if let Ok(meta) = fs::metadata(path) {
        if meta.len() > MAX_SCAN_FILE_BYTES {
            return None;
        }
    }

    let friendly_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown file")
        .to_string();
    let path_str = path.display().to_string();

    let mut reasons = Vec::new();

    if let Some(hash) = hash_file(path) {
        if bad_hashes.contains(&hash) {
            reasons.push("This file matches a known harmful file signature.".to_string());
            log_util::log_info(&format!("Hash match: {} ({hash})", path.display()));
        }
    }

    if let Some(reason) = double_extension(path) {
        reasons.push(reason);
        log_util::log_info(&format!("Double extension: {}", path.display()));
    }

    if should_scan_content(path) {
        if let Some(reason) = extension_mismatch(path) {
            reasons.push(reason);
            log_util::log_info(&format!("Extension mismatch: {}", path.display()));
        }

        if let Some(rules) = rules {
            for desc in yara_hits(rules, path) {
                log_util::log_info(&format!("YARA hit on {}: {desc}", path.display()));
                reasons.push(desc);
            }
        }
    }

    if reasons.is_empty() {
        return None;
    }

    let reason = reasons.join(" ");
    log_util::log_info(&format!("Threat reported (not quarantined): {}", path.display()));

    Some(ScanHit {
        path: path_str,
        friendly_name,
        reason,
        recommendation: "Review this file. Tap Quarantine only if you want it moved.".to_string(),
    })
}

pub fn scan(data_dir: &Path, id: String, params: &Value) -> Response {
    let _ = data_dir;
    log_util::log_info("Starting antivirus scan (report-only, no auto-quarantine)");
    let bad_hashes = load_bad_hashes();
    let rules = compile_rules();
    let mut items = Vec::new();
    let roots = scan_roots_from_params(params);
    let files = walk_files(&roots);
    let files_total = files.len() as u32;
    let started = Instant::now();

    emit_progress(&id, "Preparing scan...", 0, files_total, started);

    for (index, path) in files.iter().enumerate() {
        let files_scanned = (index + 1) as u32;
        let current_file = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("unknown file")
            .to_string();

        if files_scanned == 1
            || files_scanned == files_total
            || files_scanned % 10 == 0
        {
            emit_progress(&id, &current_file, files_scanned, files_total, started);
        }

        if let Some(hit) = scan_file(rules.as_ref(), &bad_hashes, path) {
            items.push(json!({
                "path": hit.path,
                "friendly_name": hit.friendly_name,
                "reason": hit.reason,
                "recommendation": hit.recommendation,
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
        Ok(dest) => Response::ok(
            id,
            json!({
                "message": "We moved the file to quarantine.",
                "quarantine_path": dest.display().to_string(),
            }),
        ),
        Err(e) => {
            log_util::log_error(&format!("Quarantine failed for {path_str}: {e}"));
            Response::err(id, "Could not quarantine that file.")
        }
    }
}
