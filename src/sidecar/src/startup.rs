use crate::log_util;
use crate::protocol::Response;
use serde_json::{json, Value};
use std::path::Path;

fn stable_id(name: &str, source: &str) -> String {
    format!("{source}_{name}")
        .replace(['\\', '/', ' '], "_")
        .to_lowercase()
}

#[cfg(windows)]
fn read_run_key(hive: &str, subkey: &str) -> Vec<(String, String, String)> {
    use std::ffi::OsStr;
    use std::os::windows::ffi::OsStrExt;
    use winapi::um::winreg::{
        RegCloseKey, RegEnumValueW, RegOpenKeyExW, HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE,
    };
    use winapi::um::winnt::KEY_READ;

    fn to_wide(s: &str) -> Vec<u16> {
        OsStr::new(s).encode_wide().chain(std::iter::once(0)).collect()
    }

    let hive_key = if hive == "HKLM" {
        unsafe { HKEY_LOCAL_MACHINE }
    } else {
        unsafe { HKEY_CURRENT_USER }
    };

    let mut entries = Vec::new();
    unsafe {
        let subkey_w = to_wide(subkey);
        let mut key = std::ptr::null_mut();
        if RegOpenKeyExW(hive_key, subkey_w.as_ptr(), 0, KEY_READ, &mut key) != 0 {
            return entries;
        }
        let mut index = 0u32;
        loop {
            let mut name_buf = [0u16; 512];
            let mut name_len = name_buf.len() as u32;
            let mut data_buf = [0u8; 2048];
            let mut data_len = data_buf.len() as u32;
            let mut data_type = 0u32;
            let result = RegEnumValueW(
                key,
                index,
                name_buf.as_mut_ptr(),
                &mut name_len,
                std::ptr::null_mut(),
                &mut data_type,
                data_buf.as_mut_ptr(),
                &mut data_len,
            );
            if result != 0 {
                break;
            }
            let name = String::from_utf16_lossy(&name_buf[..name_len as usize]);
            let value = if data_type == 1 || data_type == 2 {
                // REG_SZ / REG_EXPAND_SZ are UTF-16 LE
                let wide_len = (data_len as usize) / 2;
                let wide: Vec<u16> = data_buf[..data_len as usize]
                    .chunks_exact(2)
                    .map(|c| u16::from_le_bytes([c[0], c[1]]))
                    .take(wide_len)
                    .collect();
                let end = wide.iter().position(|&c| c == 0).unwrap_or(wide.len());
                String::from_utf16_lossy(&wide[..end])
            } else {
                String::from_utf8_lossy(&data_buf[..data_len as usize]).to_string()
            };
            entries.push((name, value, hive.to_string()));
            index += 1;
        }
        RegCloseKey(key);
    }
    entries
}

#[cfg(not(windows))]
fn read_run_key(_hive: &str, _subkey: &str) -> Vec<(String, String, String)> {
    Vec::new()
}

fn friendly_name_for(value: &str) -> (String, &'static str) {
    let lower = value.to_lowercase();
    if lower.contains("onedrive") {
        ("OneDrive Cloud Backup".to_string(), "disable")
    } else if lower.contains("teams") {
        ("Microsoft Teams".to_string(), "disable")
    } else if lower.contains("spotify") {
        ("Spotify Music".to_string(), "keep")
    } else if lower.contains("discord") {
        ("Discord Chat".to_string(), "keep")
    } else if lower.contains("steam") {
        ("Steam Game Store".to_string(), "keep")
    } else {
        let file = value
            .split(['\\', '/'])
            .last()
            .unwrap_or(value)
            .to_string();
        (file, "keep")
    }
}

pub fn list(id: String) -> Response {
    let mut items = Vec::new();

    for (name, value, source) in read_run_key("HKCU", r"Software\Microsoft\Windows\CurrentVersion\Run") {
        let (friendly, action) = friendly_name_for(&value);
        items.push(json!({
            "id": stable_id(&name, &source),
            "name": name,
            "friendly_name": friendly,
            "path": value,
            "source": source,
            "recommended_action": action,
        }));
    }

    for (name, value, source) in read_run_key("HKLM", r"Software\Microsoft\Windows\CurrentVersion\Run") {
        let (friendly, action) = friendly_name_for(&value);
        items.push(json!({
            "id": stable_id(&name, &source),
            "name": name,
            "friendly_name": friendly,
            "path": value,
            "source": source,
            "recommended_action": action,
        }));
    }

    if let Ok(appdata) = std::env::var("APPDATA") {
        let startup = Path::new(&appdata).join(r"Microsoft\Windows\Start Menu\Programs\Startup");
        if startup.exists() {
            if let Ok(entries) = std::fs::read_dir(&startup) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    let name = entry.file_name().to_string_lossy().to_string();
                    let (friendly, action) = friendly_name_for(&path.to_string_lossy());
                    items.push(json!({
                        "id": stable_id(&name, "Startup Folder"),
                        "name": name,
                        "friendly_name": friendly,
                        "path": path.to_string_lossy(),
                        "source": "Startup Folder",
                        "recommended_action": action,
                    }));
                }
            }
        }
    }

    Response::ok(id, json!({ "items": items }))
}

#[cfg(windows)]
fn disable_startup_entry(source: &str, name: &str, value: &str) -> Result<(), String> {
    use std::ffi::OsStr;
    use std::os::windows::ffi::OsStrExt;
    use winapi::um::winreg::{
        RegCloseKey, RegCreateKeyExW, RegDeleteValueW, RegOpenKeyExW, RegSetValueExW,
        HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE,
    };
    use winapi::um::winnt::{KEY_ALL_ACCESS, REG_SZ};

    fn to_wide(s: &str) -> Vec<u16> {
        OsStr::new(s).encode_wide().chain(std::iter::once(0)).collect()
    }

    let hive_key = if source == "HKLM" {
        unsafe { HKEY_LOCAL_MACHINE }
    } else {
        unsafe { HKEY_CURRENT_USER }
    };

    let run_path = r"Software\Microsoft\Windows\CurrentVersion\Run";
    let disabled_path = r"Software\Microsoft\Windows\CurrentVersion\Run_Disabled";

    unsafe {
        let run_w = to_wide(run_path);
        let disabled_w = to_wide(disabled_path);
        let name_w = to_wide(name);
        let value_w = to_wide(value);

        let mut disabled_key = std::ptr::null_mut();
        RegCreateKeyExW(
            hive_key,
            disabled_w.as_ptr(),
            0,
            std::ptr::null_mut(),
            0,
            KEY_ALL_ACCESS,
            std::ptr::null_mut(),
            &mut disabled_key,
            std::ptr::null_mut(),
        );
        RegSetValueExW(
            disabled_key,
            name_w.as_ptr(),
            0,
            REG_SZ,
            value_w.as_ptr() as *const u8,
            (value_w.len() * 2) as u32,
        );
        RegCloseKey(disabled_key);

        let mut run_key = std::ptr::null_mut();
        RegOpenKeyExW(hive_key, run_w.as_ptr(), 0, KEY_ALL_ACCESS, &mut run_key);
        RegDeleteValueW(run_key, name_w.as_ptr());
        RegCloseKey(run_key);
    }

    log_util::log_change(
        &format!("startup_{name}"),
        "startup",
        &format!("restore {name}={value} in Run key ({source})"),
    );
    Ok(())
}

#[cfg(not(windows))]
fn disable_startup_entry(_source: &str, _name: &str, _value: &str) -> Result<(), String> {
    Err("Not supported".to_string())
}

pub fn disable(_data_dir: &Path, id: String, params: &Value) -> Response {
    let entries: Vec<Value> = params
        .get("entries")
        .and_then(|v| serde_json::from_value(v.clone()).ok())
        .unwrap_or_default();

    let mut disabled = Vec::new();
    for entry in entries {
        let name = entry.get("name").and_then(|v| v.as_str()).unwrap_or("");
        let path = entry.get("path").and_then(|v| v.as_str()).unwrap_or("");
        let source = entry.get("source").and_then(|v| v.as_str()).unwrap_or("HKCU");
        let friendly = entry
            .get("friendly_name")
            .and_then(|v| v.as_str())
            .unwrap_or(name);

        if name.is_empty() {
            continue;
        }
        match disable_startup_entry(source, name, path) {
            Ok(()) => disabled.push(json!({ "friendly_name": friendly })),
            Err(e) => log_util::log_error(&format!("Startup disable failed: {e}")),
        }
    }

    let count = disabled.len();
    let message = if count == 0 {
        "Something didn't work. No changes were made.".to_string()
    } else {
        format!("We disabled {count} startup item(s).")
    };

    Response::ok(
        id,
        json!({
            "disabled": disabled,
            "message": message,
        }),
    )
}
