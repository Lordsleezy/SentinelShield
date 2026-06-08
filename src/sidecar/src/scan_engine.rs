use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use walkdir::WalkDir;
use yara::{Compiler, Rules};

pub const MAX_SCAN_DEPTH: usize = 6;
pub const MAX_SCAN_FILE_BYTES: u64 = 50 * 1024 * 1024;
pub const SKIP_DIR_NAMES: &[&str] = &[
    "node_modules", ".git", "target", "dist", "build", ".cargo", "__pycache__", ".venv",
    "venv", ".idea", ".vs",
];
pub const EXECUTABLE_EXTENSIONS: &[&str] = &[
    "exe", "dll", "scr", "msi", "cpl", "sys", "com", "pif", "bat", "cmd", "ps1", "vbs", "js",
    "jar",
];

#[derive(Clone, Debug)]
pub struct ThreatHit {
    pub path: String,
    pub friendly_name: String,
    pub reason: String,
}

static RULES: OnceLock<Mutex<Option<Arc<Rules>>>> = OnceLock::new();
static BAD_HASHES: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();

fn rules_cache() -> &'static Mutex<Option<Arc<Rules>>> {
    RULES.get_or_init(|| Mutex::new(None))
}

fn hashes_cache() -> &'static Mutex<HashSet<String>> {
    BAD_HASHES.get_or_init(|| Mutex::new(load_bad_hashes()))
}

fn rules_path() -> PathBuf {
    std::env::var("SENTINEL_RULES_DIR")
        .map(|d| PathBuf::from(d).join("starter.yar"))
        .unwrap_or_else(|_| crate::log_util::app_root().join("rules").join("starter.yar"))
}

fn hashes_path() -> PathBuf {
    crate::log_util::app_root()
        .join("data")
        .join("known_bad_hashes.txt")
}

fn load_bad_hashes() -> HashSet<String> {
    let path = hashes_path();
    let Ok(content) = fs::read_to_string(&path) else {
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

pub fn refresh_rules() {
    if let Ok(mut guard) = rules_cache().lock() {
        *guard = compile_rules().map(Arc::new);
    }
}

fn compile_rules() -> Option<Rules> {
    let path = rules_path();
    let compiler = Compiler::new().ok()?;
    let compiler = compiler.add_rules_file(&path).ok()?;
    compiler.compile_rules().ok()
}

pub fn get_rules() -> Option<Arc<Rules>> {
    let mut guard = rules_cache().lock().ok()?;
    if guard.is_none() {
        *guard = compile_rules().map(Arc::new);
    }
    guard.clone()
}

pub fn default_watch_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Ok(user) = std::env::var("USERPROFILE") {
        let home = PathBuf::from(&user);
        paths.push(home.join("Downloads"));
        paths.push(home.join("Desktop"));
        paths.push(home.join("Documents"));
    }
    paths.push(std::env::temp_dir());
    paths
}

pub fn default_scan_targets() -> Vec<PathBuf> {
    let mut paths = default_watch_paths();
    paths.push(PathBuf::from(r"C:\Windows\Temp"));
    paths
}

pub fn collect_files(roots: &[PathBuf]) -> Vec<PathBuf> {
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
    if detected.is_empty() || !EXECUTABLE_EXTENSIONS.contains(&detected) {
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

pub fn analyze_file(path: &Path) -> Option<ThreatHit> {
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
    let bad_hashes = hashes_cache().lock().ok()?;
    let mut reasons = Vec::new();

    if let Some(hash) = hash_file(path) {
        if bad_hashes.contains(&hash) {
            reasons.push("This file matches a known harmful file signature.".to_string());
        }
    }

    if let Some(reason) = double_extension(path) {
        reasons.push(reason);
    }

    if should_scan_content(path) {
        if let Some(reason) = extension_mismatch(path) {
            reasons.push(reason);
        }
        if let Some(rules) = get_rules() {
            for desc in yara_hits(&rules, path) {
                reasons.push(desc);
            }
        }
    }

    if reasons.is_empty() {
        return None;
    }

    Some(ThreatHit {
        path: path_str,
        friendly_name,
        reason: reasons.join(" "),
    })
}
