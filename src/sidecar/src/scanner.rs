use crate::log_util;
use crate::protocol::Response;
use serde_json::json;
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use uuid::Uuid;
use walkdir::WalkDir;
use yara::{Compiler, Rules};

struct ScanHit {
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

fn scan_targets() -> Vec<PathBuf> {
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

fn quarantine_file(data_dir: &Path, path: &Path) -> Result<PathBuf, String> {
    let name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown");
    let dest_name = format!("{}_{}", Uuid::new_v4(), name);
    let dest = data_dir.join("quarantine").join(dest_name);
    fs::rename(path, &dest).map_err(|e| e.to_string())?;
    log_util::log_info(&format!("Quarantined {} -> {}", path.display(), dest.display()));
    Ok(dest)
}

fn scan_file(data_dir: &Path, rules: Option<&Rules>, bad_hashes: &HashSet<String>, path: &Path) -> Option<ScanHit> {
    if !path.is_file() {
        return None;
    }
    let friendly_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown file")
        .to_string();

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

    if reasons.is_empty() {
        return None;
    }

    let reason = reasons.join(" ");
    let recommendation = match quarantine_file(data_dir, path) {
        Ok(_) => "We've moved it to quarantine.".to_string(),
        Err(e) => {
            log_util::log_error(&format!("Quarantine failed for {}: {e}", path.display()));
            "We recommend deleting this.".to_string()
        }
    };

    Some(ScanHit {
        friendly_name,
        reason,
        recommendation,
    })
}

pub fn scan(data_dir: &Path, id: String) -> Response {
    log_util::log_info("Starting antivirus scan");
    let bad_hashes = load_bad_hashes();
    let rules = compile_rules();
    let mut items = Vec::new();

    for root in scan_targets() {
        if !root.exists() {
            continue;
        }
        for entry in WalkDir::new(&root)
            .follow_links(false)
            .into_iter()
            .filter_map(|e| e.ok())
        {
            let path = entry.path();
            if path.is_dir() {
                continue;
            }
            if let Some(hit) = scan_file(data_dir, rules.as_ref(), &bad_hashes, path) {
                items.push(json!({
                    "friendly_name": hit.friendly_name,
                    "reason": hit.reason,
                    "recommendation": hit.recommendation,
                }));
            }
        }
    }

    let threat_count = items.len();
    let message = if threat_count == 0 {
        "We didn't find anything suspicious. You're all clear.".to_string()
    } else if threat_count == 1 {
        "We found 1 suspicious file. Here's what we recommend.".to_string()
    } else {
        format!("We found {threat_count} suspicious files. Here's what we recommend.")
    };

    log_util::log_info(&format!("Scan complete: {threat_count} threats"));
    Response::ok(
        id,
        json!({
            "message": message,
            "threat_count": threat_count,
            "items": items,
        }),
    )
}
