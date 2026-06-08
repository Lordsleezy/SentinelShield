use crate::protocol::Response;
use crate::settings;
use serde_json::{json, Value};
use std::path::Path;
use std::process::Command;

#[cfg(windows)]
fn hidden_command(program: &str, args: &[&str]) -> Option<std::process::Output> {
    use std::os::windows::process::CommandExt;
    Command::new(program)
        .args(args)
        .creation_flags(0x08000000)
        .output()
        .ok()
}

#[cfg(not(windows))]
fn hidden_command(program: &str, args: &[&str]) -> Option<std::process::Output> {
    Command::new(program).args(args).output().ok()
}

fn wifi_ssid() -> Option<String> {
    let output = hidden_command("netsh", &["wlan", "show", "interfaces"])?;
    let text = String::from_utf8_lossy(&output.stdout);
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("SSID") && !trimmed.starts_with("BSSID") {
            if let Some((_key, value)) = trimmed.split_once(':') {
                let ssid = value.trim();
                if !ssid.is_empty() {
                    return Some(ssid.to_string());
                }
            }
        }
    }
    None
}

fn local_ip() -> Option<String> {
    let output = hidden_command("ipconfig", &[])?;
    let text = String::from_utf8_lossy(&output.stdout);
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.contains("IPv4") {
            if let Some((_key, value)) = trimmed.split_once(':') {
                let ip = value.trim();
                if !ip.is_empty() && ip != "127.0.0.1" {
                    return Some(ip.to_string());
                }
            }
        }
    }
    None
}

fn parse_arp_entries() -> Vec<(String, String, String)> {
    let Some(output) = hidden_command("arp", &["-a"]) else {
        return Vec::new();
    };
    let text = String::from_utf8_lossy(&output.stdout);
    let mut entries = Vec::new();
    for line in text.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 2 && parts[0].chars().next().map(|c| c.is_ascii_digit()) == Some(true) {
            let ip = parts[0].to_string();
            let mac = parts[1].to_string().to_lowercase().replace('-', ":");
            let kind = parts.get(2).unwrap_or(&"dynamic").to_string();
            entries.push((ip, mac, kind));
        }
    }
    entries
}

fn is_multicast_or_broadcast(ip: &str, mac: &str) -> bool {
    ip.starts_with("224.")
        || ip == "255.255.255.255"
        || mac.starts_with("01:00:5e")
        || mac == "ff:ff:ff:ff:ff:ff"
}

fn suspicious_connections() -> Vec<String> {
    let Some(output) = hidden_command("netstat", &["-an"]) else {
        return Vec::new();
    };
    let text = String::from_utf8_lossy(&output.stdout);
    let suspicious_ports = ["4444", "5555", "6666", "31337", "1337"];
    let mut findings = Vec::new();
    for line in text.lines() {
        let lower = line.to_lowercase();
        if !lower.contains("established") && !lower.contains("listening") {
            continue;
        }
        for port in suspicious_ports {
            if line.contains(&format!(":{port}")) {
                findings.push(format!("Connection activity on suspicious port {port}"));
                break;
            }
        }
    }
    findings.sort();
    findings.dedup();
    findings
}

pub fn scan(data_dir: &Path, id: String) -> Response {
    let settings_data = settings::load(data_dir);
    let known_macs: Vec<String> = settings_data
        .known_devices
        .iter()
        .map(|d| d.mac.to_lowercase())
        .collect();

    let ssid = wifi_ssid().unwrap_or_else(|| "Not connected to Wi-Fi".to_string());
    let local_ip = local_ip().unwrap_or_else(|| "Unknown".to_string());
    let arp_entries = parse_arp_entries();
    let suspicious_traffic = suspicious_connections();

    let mut devices = Vec::new();
    let mut rogue_count = 0u32;

    for (ip, mac, kind) in arp_entries {
        let known = known_macs.iter().any(|k| k == &mac);
        let is_gateway = ip.ends_with(".1") || ip.ends_with(".254");
        let is_special = is_multicast_or_broadcast(&ip, &mac);
        let mut flags = Vec::new();

        if is_special {
            flags.push("Broadcast or multicast (ignored)".to_string());
        } else if !known && !is_gateway && kind == "dynamic" {
            flags.push("Unknown device on your network".to_string());
            rogue_count += 1;
        }

        let label = settings_data
            .known_devices
            .iter()
            .find(|d| d.mac.to_lowercase() == mac)
            .map(|d| d.label.clone())
            .unwrap_or_else(|| {
                if is_gateway {
                    "Router / Gateway".to_string()
                } else {
                    "Unknown device".to_string()
                }
            });

        devices.push(json!({
            "ip": ip,
            "mac": mac,
            "kind": kind,
            "label": label,
            "known": known || is_gateway || is_special,
            "flags": flags,
        }));
    }

    let traffic_warnings: Vec<Value> = suspicious_traffic
        .into_iter()
        .map(|t| json!({ "description": t, "severity": "medium" }))
        .collect();

    let message = if rogue_count == 0 && traffic_warnings.is_empty() {
        "Your network looks normal. No unknown devices or suspicious traffic found.".to_string()
    } else if rogue_count > 0 {
        format!("We found {rogue_count} device(s) on your Wi-Fi that aren't recognized.")
    } else {
        "We noticed some network activity worth reviewing.".to_string()
    };

    crate::log_util::log_info(&format!(
        "Network scan: SSID={ssid}, devices={}, rogue={rogue_count}",
        devices.len()
    ));

    Response::ok(
        id,
        json!({
            "ssid": ssid,
            "local_ip": local_ip,
            "devices": devices,
            "device_count": devices.len(),
            "rogue_count": rogue_count,
            "traffic_warnings": traffic_warnings,
            "message": message,
        }),
    )
}
