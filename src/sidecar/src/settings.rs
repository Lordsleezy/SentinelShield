use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

pub const DEFAULT_RULES_URL: &str =
    "https://raw.githubusercontent.com/Lordsleezy/SentinelShield/main/rules/starter.yar";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScheduleSettings {
    pub enabled: bool,
    pub hour: u32,
    pub minute: u32,
    pub days: Vec<u32>,
}

impl Default for ScheduleSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            hour: 2,
            minute: 0,
            days: vec![0, 1, 2, 3, 4, 5, 6],
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KnownDevice {
    pub mac: String,
    pub label: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSettings {
    pub realtime_enabled: bool,
    pub schedule: ScheduleSettings,
    pub rules_url: String,
    pub known_devices: Vec<KnownDevice>,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            realtime_enabled: false,
            schedule: ScheduleSettings::default(),
            rules_url: DEFAULT_RULES_URL.to_string(),
            known_devices: Vec::new(),
        }
    }
}

fn settings_path(data_dir: &Path) -> PathBuf {
    data_dir.join("settings.json")
}

pub fn load(data_dir: &Path) -> AppSettings {
    let path = settings_path(data_dir);
    let Ok(content) = fs::read_to_string(&path) else {
        return AppSettings::default();
    };
    serde_json::from_str(&content).unwrap_or_default()
}

pub fn save(data_dir: &Path, settings: &AppSettings) -> Result<(), String> {
    let path = settings_path(data_dir);
    let json = serde_json::to_string_pretty(settings).map_err(|e| e.to_string())?;
    fs::write(path, json).map_err(|e| e.to_string())
}
