use crate::log_util;
use crate::protocol::Response;
use crate::scan_engine;
use crate::settings::{self, DEFAULT_RULES_URL};
use serde_json::json;
use std::fs;
use std::path::{Path, PathBuf};

fn rules_dir(data_dir: &Path) -> PathBuf {
    std::env::var("SENTINEL_RULES_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            if data_dir.join("rules").exists() {
                data_dir.join("rules")
            } else {
                log_util::app_root().join("rules")
            }
        })
}

fn active_rules_path(data_dir: &Path) -> PathBuf {
    rules_dir(data_dir).join("starter.yar")
}

fn validate_yara(content: &str) -> bool {
    content.contains("rule ") && (content.contains("condition:") || content.contains("strings:"))
}

pub fn update_on_launch(data_dir: &Path) -> Result<String, String> {
    let settings_data = settings::load(data_dir);
    let url = if settings_data.rules_url.is_empty() {
        DEFAULT_RULES_URL.to_string()
    } else {
        settings_data.rules_url.clone()
    };
    update_from_url(data_dir, &url)
}

pub fn update(data_dir: &Path, id: String) -> Response {
    let settings_data = settings::load(data_dir);
    let url = if settings_data.rules_url.is_empty() {
        DEFAULT_RULES_URL.to_string()
    } else {
        settings_data.rules_url
    };

    match update_from_url(data_dir, &url) {
        Ok(message) => Response::ok(
            id,
            json!({
                "message": message,
                "url": url,
            }),
        ),
        Err(e) => Response::err(id, &e),
    }
}

fn update_from_url(data_dir: &Path, url: &str) -> Result<String, String> {
    log_util::log_info(&format!("Checking YARA rules update from {url}"));

    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|e| e.to_string())?;

    let response = client
        .get(url)
        .send()
        .map_err(|e| format!("Could not reach rules server: {e}"))?;

    if !response.status().is_success() {
        return Err(format!("Rules server returned status {}", response.status()));
    }

    let content = response
        .text()
        .map_err(|e| format!("Could not read rules: {e}"))?;

    if !validate_yara(&content) {
        return Err("Downloaded file does not look like valid YARA rules.".to_string());
    }

    let rules_path = active_rules_path(data_dir);
    if let Some(parent) = rules_path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }

    if rules_path.exists() {
        let backup = rules_path.with_extension("yar.bak");
        let _ = fs::copy(&rules_path, &backup);
    }

    fs::write(&rules_path, &content).map_err(|e| e.to_string())?;
    scan_engine::refresh_rules();

    log_util::log_info("YARA rules updated successfully");
    Ok("YARA rules are up to date.".to_string())
}
