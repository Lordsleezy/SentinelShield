use crate::admin;
use crate::log_util;
use crate::protocol::Response;
use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use walkdir::WalkDir;

#[derive(Clone)]
struct Category {
    id: &'static str,
    label: &'static str,
    requires_admin: bool,
}

const CATEGORIES: &[Category] = &[
    Category {
        id: "temp_user",
        label: "Temporary files (your account)",
        requires_admin: false,
    },
    Category {
        id: "temp_windows",
        label: "Temporary files (Windows)",
        requires_admin: false,
    },
    Category {
        id: "prefetch",
        label: "Windows prefetch cache",
        requires_admin: true,
    },
    Category {
        id: "chrome_cache",
        label: "Chrome browser cache",
        requires_admin: false,
    },
    Category {
        id: "edge_cache",
        label: "Edge browser cache",
        requires_admin: false,
    },
    Category {
        id: "firefox_cache",
        label: "Firefox browser cache",
        requires_admin: false,
    },
    Category {
        id: "windows_update_cache",
        label: "Windows Update downloads",
        requires_admin: true,
    },
    Category {
        id: "recycle_bin",
        label: "Recycle Bin",
        requires_admin: false,
    },
    Category {
        id: "thumbnail_cache",
        label: "Picture thumbnails",
        requires_admin: false,
    },
    Category {
        id: "icon_cache",
        label: "Icon cache",
        requires_admin: false,
    },
    Category {
        id: "dns_cache",
        label: "DNS cache",
        requires_admin: false,
    },
    Category {
        id: "font_cache",
        label: "Font cache",
        requires_admin: true,
    },
    Category {
        id: "error_reports",
        label: "Error report files",
        requires_admin: false,
    },
];

fn dir_size(path: &Path) -> u64 {
    if !path.exists() {
        return 0;
    }
    if path.is_file() {
        return path.metadata().map(|m| m.len()).unwrap_or(0);
    }
    let mut total = 0u64;
    for entry in WalkDir::new(path).into_iter().filter_map(|e| e.ok()) {
        if entry.file_type().is_file() {
            total += entry.metadata().map(|m| m.len()).unwrap_or(0);
        }
    }
    total
}

fn glob_size(pattern: &Path) -> u64 {
    if pattern.to_string_lossy().contains('*') {
        let parent = pattern.parent().unwrap_or(Path::new("."));
        let name = pattern.file_name().and_then(|n| n.to_str()).unwrap_or("");
        let prefix = name.trim_end_matches('*');
        if !parent.exists() {
            return 0;
        }
        let mut total = 0u64;
        if let Ok(entries) = fs::read_dir(parent) {
            for entry in entries.flatten() {
                let name_str = entry.file_name().to_string_lossy().to_string();
                if name_str.starts_with(prefix) {
                    total += dir_size(&entry.path());
                }
            }
        }
        return total;
    }
    dir_size(pattern)
}

fn category_paths(id: &str) -> Vec<PathBuf> {
    let mut paths = Vec::new();
    match id {
        "temp_user" => paths.push(std::env::temp_dir()),
        "temp_windows" => paths.push(PathBuf::from(r"C:\Windows\Temp")),
        "prefetch" => paths.push(PathBuf::from(r"C:\Windows\Prefetch")),
        "chrome_cache" => {
            if let Ok(local) = std::env::var("LOCALAPPDATA") {
                paths.push(
                    PathBuf::from(local)
                        .join(r"Google\Chrome\User Data\Default\Cache"),
                );
            }
        }
        "edge_cache" => {
            if let Ok(local) = std::env::var("LOCALAPPDATA") {
                paths.push(
                    PathBuf::from(local)
                        .join(r"Microsoft\Edge\User Data\Default\Cache"),
                );
            }
        }
        "firefox_cache" => {
            if let Ok(app) = std::env::var("APPDATA") {
                let profiles = PathBuf::from(app).join(r"Mozilla\Firefox\Profiles");
                if profiles.exists() {
                    if let Ok(entries) = fs::read_dir(&profiles) {
                        for entry in entries.flatten() {
                            let cache = entry.path().join("cache2");
                            if cache.exists() {
                                paths.push(cache);
                            }
                        }
                    }
                }
            }
        }
        "windows_update_cache" => {
            paths.push(PathBuf::from(r"C:\Windows\SoftwareDistribution\Download"));
        }
        "thumbnail_cache" => {
            if let Ok(local) = std::env::var("LOCALAPPDATA") {
                paths.push(
                    PathBuf::from(local)
                        .join(r"Microsoft\Windows\Explorer\thumbcache_*.db"),
                );
            }
        }
        "icon_cache" => {
            if let Ok(local) = std::env::var("LOCALAPPDATA") {
                paths.push(PathBuf::from(local).join("IconCache.db"));
            }
        }
        "font_cache" => {
            if let Ok(windir) = std::env::var("WINDIR") {
                paths.push(PathBuf::from(windir).join(
                    r"ServiceProfiles\LocalService\AppData\Local\FontCache",
                ));
            }
        }
        "error_reports" => {
            if let Ok(app) = std::env::var("APPDATA") {
                paths.push(
                    PathBuf::from(app).join(r"Microsoft\Windows\WER\ReportQueue"),
                );
            }
            if let Ok(local) = std::env::var("LOCALAPPDATA") {
                paths.push(PathBuf::from(local).join(r"Microsoft\Windows\WER"));
            }
        }
        _ => {}
    }
    paths
}

fn measure_category(id: &str) -> u64 {
    if id == "dns_cache" {
        return 0;
    }
    if id == "recycle_bin" {
        return 0;
    }
    category_paths(id)
        .iter()
        .map(|p| glob_size(p))
        .sum()
}

fn category_available(id: &str) -> bool {
    if id == "dns_cache" || id == "recycle_bin" {
        return true;
    }
    category_paths(id).iter().any(|p| {
        if p.to_string_lossy().contains('*') {
            glob_size(p) > 0
        } else {
            p.exists()
        }
    })
}

pub fn preview(_data_dir: &Path, id: String) -> Response {
    let is_admin = admin::is_admin();
    let mut categories = Vec::new();
    let mut total_bytes = 0u64;

    for cat in CATEGORIES {
        if !category_available(cat.id) {
            continue;
        }
        let size = measure_category(cat.id);
        total_bytes += size;
        categories.push(json!({
            "id": cat.id,
            "label": cat.label,
            "size_bytes": size,
            "size_friendly": log_util::format_bytes(size),
            "safe": true,
            "requires_admin": cat.requires_admin,
            "locked": cat.requires_admin && !is_admin,
        }));
    }

    Response::ok(
        id,
        json!({
            "categories": categories,
            "total_size_friendly": log_util::format_bytes(total_bytes),
        }),
    )
}

fn delete_dir_contents(path: &Path) -> u64 {
    let mut freed = 0u64;
    if !path.exists() {
        return 0;
    }
    if path.is_file() {
        let size = path.metadata().map(|m| m.len()).unwrap_or(0);
        if fs::remove_file(path).is_ok() {
            freed += size;
        }
        return freed;
    }
    for entry in WalkDir::new(path).contents_first(true).into_iter().filter_map(|e| e.ok()) {
        let p = entry.path();
        if p == path {
            continue;
        }
        let size = if entry.file_type().is_file() {
            entry.metadata().map(|m| m.len()).unwrap_or(0)
        } else {
            0
        };
        let ok = if entry.file_type().is_dir() {
            fs::remove_dir(p).is_ok()
        } else {
            fs::remove_file(p).is_ok()
        };
        if ok {
            freed += size;
        }
    }
    freed
}

fn run_hidden(cmd: &str, args: &[&str]) -> bool {
    Command::new(cmd)
        .args(args)
        .creation_flags(0x08000000) // CREATE_NO_WINDOW
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

#[cfg(windows)]
fn empty_recycle_bin() -> u64 {
    use winapi::um::shellapi::{SHEmptyRecycleBinW, SHERB_NOCONFIRMATION, SHERB_NOPROGRESSUI, SHERB_NOSOUND};

    unsafe {
        SHEmptyRecycleBinW(
            std::ptr::null_mut(),
            std::ptr::null(),
            SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND,
        );
    }
    log_util::log_info("Emptied Recycle Bin");
    0
}

#[cfg(not(windows))]
fn empty_recycle_bin() -> u64 {
    0
}

fn clean_category(id: &str, is_admin: bool) -> Result<u64, String> {
    if let Some(cat) = CATEGORIES.iter().find(|c| c.id == id) {
        if cat.requires_admin && !is_admin {
            return Err("needs admin access".to_string());
        }
    }

    match id {
        "dns_cache" => {
            let ok = run_hidden("ipconfig", &["/flushdns"]);
            log_util::log_info(&format!("DNS flush: {ok}"));
            Ok(0)
        }
        "recycle_bin" => Ok(empty_recycle_bin()),
        "icon_cache" => {
            let mut freed = 0u64;
            for path in category_paths(id) {
                freed += delete_dir_contents(&path);
            }
            log_util::log_info("Icon cache cleared — Explorer may need a restart");
            Ok(freed)
        }
        "font_cache" => {
            run_hidden("net", &["stop", "FontCache"]);
            let mut freed = 0u64;
            for path in category_paths(id) {
                freed += delete_dir_contents(&path);
            }
            run_hidden("net", &["start", "FontCache"]);
            log_util::log_info(&format!("Font cache cleared: {} bytes", freed));
            Ok(freed)
        }
        _ => {
            let mut freed = 0u64;
            for path in category_paths(id) {
                if path.to_string_lossy().contains('*') {
                    let parent = path.parent().unwrap_or(Path::new("."));
                    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
                    let prefix = name.trim_end_matches('*');
                    if let Ok(entries) = fs::read_dir(parent) {
                        for entry in entries.flatten() {
                            if entry.file_name().to_string_lossy().starts_with(prefix) {
                                freed += delete_dir_contents(&entry.path());
                            }
                        }
                    }
                } else {
                    freed += delete_dir_contents(&path);
                }
            }
            log_util::log_info(&format!("Cleaned {id}: {} bytes freed", freed));
            Ok(freed)
        }
    }
}

pub fn run(data_dir: &Path, id: String, params: &Value) -> Response {
    let selected: Vec<String> = params
        .get("selected_ids")
        .and_then(|v| serde_json::from_value(v.clone()).ok())
        .unwrap_or_default();

    if selected.is_empty() {
        return Response::err(id, "Please choose at least one item to clean.");
    }

    let is_admin = admin::is_admin();
    let mut freed_bytes = 0u64;
    let mut items_deleted = 0u64;
    let mut skipped = Vec::new();

    let icon_cache_selected = selected.iter().any(|id| id == "icon_cache");

    for cat_id in selected {
        match clean_category(&cat_id, is_admin) {
            Ok(bytes) => {
                freed_bytes += bytes;
                items_deleted += 1;
            }
            Err(reason) => {
                let label = CATEGORIES
                    .iter()
                    .find(|c| c.id == cat_id)
                    .map(|c| c.label)
                    .unwrap_or(cat_id.as_str());
                skipped.push(json!({ "label": label, "reason": reason }));
                log_util::log_info(&format!("Skipped {cat_id}: {reason}"));
            }
        }
    }

    let freed_friendly = log_util::format_bytes(freed_bytes);
    let mut message = format!(
        "We cleared up {freed_friendly} of junk. Your computer has more room to breathe."
    );
    let mut notes = Vec::new();
    if icon_cache_selected {
        notes.push("If your icons look odd, restart File Explorer.".to_string());
        message.push_str(" You may need to restart File Explorer for icons to refresh.");
    }

    let _ = data_dir;
    Response::ok(
        id,
        json!({
            "message": message,
            "freed_bytes": freed_bytes,
            "freed_friendly": freed_friendly,
            "items_deleted": items_deleted,
            "skipped": skipped,
            "notes": notes,
        }),
    )
}

#[cfg(windows)]
use std::os::windows::process::CommandExt;
