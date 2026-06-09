use crate::admin;
use crate::log_util;
use crate::protocol::Response;
use serde_json::{json, Value};
use std::process::Command;
use sysinfo::System;

#[derive(Clone)]
struct OptimizerItem {
    id: &'static str,
    label: &'static str,
    plain: &'static str,
    section: &'static str,
    requires_admin: bool,
}

fn all_items() -> Vec<OptimizerItem> {
    vec![
        OptimizerItem { id: "xbox_app", label: "Xbox App", plain: "A gaming app you probably don't use", section: "bloat", requires_admin: false },
        OptimizerItem { id: "xbox_game_bar", label: "Xbox Game Bar", plain: "A gaming overlay that pops up when you press Win+G", section: "bloat", requires_admin: false },
        OptimizerItem { id: "cortana", label: "Cortana", plain: "Microsoft's voice assistant you've probably never used", section: "bloat", requires_admin: false },
        OptimizerItem { id: "teams_consumer", label: "Microsoft Teams (personal)", plain: "The personal version of Teams — different from work Teams", section: "bloat", requires_admin: false },
        OptimizerItem { id: "bing_search", label: "Bing Search in Start Menu", plain: "Turns off web search results appearing in your Start menu", section: "bloat", requires_admin: false },
        OptimizerItem { id: "onedrive", label: "OneDrive", plain: "Microsoft's cloud storage — safe to remove if you don't use it", section: "bloat", requires_admin: false },
        OptimizerItem { id: "3d_viewer", label: "3D Viewer", plain: "A 3D model viewer you probably don't use", section: "bloat", requires_admin: false },
        OptimizerItem { id: "mixed_reality", label: "Mixed Reality Portal", plain: "A VR/AR app you almost certainly don't use", section: "bloat", requires_admin: false },
        OptimizerItem { id: "maps", label: "Windows Maps", plain: "Microsoft's maps app — most people use Google Maps instead", section: "bloat", requires_admin: false },
        OptimizerItem { id: "skype", label: "Skype", plain: "Microsoft's video calling app — safe to remove if you use Zoom or FaceTime", section: "bloat", requires_admin: false },
        OptimizerItem { id: "feedback_hub", label: "Feedback Hub", plain: "Microsoft's bug reporting tool — you don't need this", section: "bloat", requires_admin: false },
        OptimizerItem { id: "get_started", label: "Tips App", plain: "Microsoft's tips and tutorials app", section: "bloat", requires_admin: false },
        OptimizerItem { id: "telemetry_service", label: "Windows Telemetry", plain: "Sends usage data about your computer to Microsoft", section: "bloat", requires_admin: true },
        OptimizerItem { id: "dmwappushservice", label: "Ad Targeting Service", plain: "Helps Microsoft show you targeted ads", section: "bloat", requires_admin: true },
        OptimizerItem { id: "sysmain", label: "SysMain (Superfetch)", plain: "Preloads apps into memory — can slow down PCs with less RAM", section: "bloat", requires_admin: true },
        OptimizerItem { id: "waasmedicsvc", label: "Windows Update Troubleshooter Service", plain: "A background service that monitors Windows Update — rarely needed", section: "bloat", requires_admin: true },
        OptimizerItem { id: "visual_effects", label: "Turn Off Visual Effects", plain: "Disables window animations and transparency — makes everything feel snappier", section: "performance", requires_admin: false },
        OptimizerItem { id: "transparency", label: "Turn Off Transparency Effects", plain: "Makes windows solid instead of see-through — uses less memory", section: "performance", requires_admin: false },
        OptimizerItem { id: "search_indexing", label: "Reduce Search Indexing", plain: "Tells Windows to index fewer files in the background — frees up resources", section: "performance", requires_admin: true },
        OptimizerItem { id: "power_plan", label: "Switch to High Performance Mode", plain: "Tells your computer to run at full speed instead of saving power", section: "performance", requires_admin: false },
        OptimizerItem { id: "game_mode", label: "Turn Off Game Mode", plain: "A gaming feature that can actually slow down normal computer use", section: "performance", requires_admin: false },
        OptimizerItem { id: "startup_delay", label: "Remove Startup Delay", plain: "Windows waits a few seconds before loading your startup apps — we can remove that wait", section: "performance", requires_admin: false },
    ]
}

#[cfg(windows)]
fn run_powershell(script: &str) -> (bool, String) {
    use std::os::windows::process::CommandExt;
    match Command::new("powershell.exe")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-WindowStyle",
            "Hidden",
            "-Command",
            script,
        ])
        .creation_flags(0x08000000)
        .output()
    {
        Ok(out) => {
            let stdout = String::from_utf8_lossy(&out.stdout).to_string();
            (out.status.success(), stdout)
        }
        Err(e) => (false, e.to_string()),
    }
}

#[cfg(not(windows))]
fn run_powershell(_script: &str) -> (bool, String) {
    (false, "Not supported".to_string())
}

#[cfg(windows)]
fn run_cmd(program: &str, args: &[&str]) -> bool {
    use std::os::windows::process::CommandExt;
    Command::new(program)
        .args(args)
        .creation_flags(0x08000000)
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

#[cfg(not(windows))]
fn run_cmd(_program: &str, _args: &[&str]) -> bool {
    false
}

fn total_ram_gb() -> f64 {
    let mut sys = System::new();
    sys.refresh_memory();
    sys.total_memory() as f64 / 1024.0 / 1024.0 / 1024.0
}

fn detect_present(item_id: &str) -> bool {
    match item_id {
        "xbox_app" => {
            let (_, out) = run_powershell("Get-AppxPackage *Xbox* | Select-Object -First 1");
            !out.trim().is_empty()
        }
        "xbox_game_bar" => {
            let (_, out) = run_powershell("Get-AppxPackage *XboxGameOverlay* | Select-Object -First 1");
            !out.trim().is_empty()
        }
        "cortana" => {
            let (_, out) = run_powershell("Get-AppxPackage *Microsoft.549981C3F5F10* | Select-Object -First 1");
            !out.trim().is_empty()
        }
        "teams_consumer" => {
            let (_, out) = run_powershell("Get-AppxPackage *MicrosoftTeams* | Select-Object -First 1");
            !out.trim().is_empty()
        }
        "3d_viewer" => {
            let (_, out) = run_powershell("Get-AppxPackage *Microsoft.Microsoft3DViewer* | Select-Object -First 1");
            !out.trim().is_empty()
        }
        "mixed_reality" => {
            let (_, out) = run_powershell("Get-AppxPackage *Microsoft.MixedReality.Portal* | Select-Object -First 1");
            !out.trim().is_empty()
        }
        "maps" => {
            let (_, out) = run_powershell("Get-AppxPackage *Microsoft.WindowsMaps* | Select-Object -First 1");
            !out.trim().is_empty()
        }
        "skype" => {
            let (_, out) = run_powershell("Get-AppxPackage *Microsoft.SkypeApp* | Select-Object -First 1");
            !out.trim().is_empty()
        }
        "feedback_hub" => {
            let (_, out) = run_powershell("Get-AppxPackage *Microsoft.WindowsFeedbackHub* | Select-Object -First 1");
            !out.trim().is_empty()
        }
        "get_started" => {
            let (_, out) = run_powershell("Get-AppxPackage *Microsoft.Getstarted* | Select-Object -First 1");
            !out.trim().is_empty()
        }
        "sysmain" => total_ram_gb() < 8.0,
        "onedrive" => {
            let (_, out) = run_powershell("Get-Process OneDrive -ErrorAction SilentlyContinue");
            !out.trim().is_empty()
        }
        _ => true,
    }
}

#[cfg(windows)]
fn set_reg_dword(hive: &str, path: &str, name: &str, value: u32) -> Result<u32, String> {
    use winapi::um::winreg::{
        RegCloseKey, RegCreateKeyExW, RegOpenKeyExW, RegQueryValueExW, RegSetValueExW, HKEY_CURRENT_USER,
        HKEY_LOCAL_MACHINE,
    };
    use winapi::um::winnt::{KEY_ALL_ACCESS, KEY_READ, REG_DWORD};
    use std::ffi::OsStr;
    use std::os::windows::ffi::OsStrExt;

    fn to_wide(s: &str) -> Vec<u16> {
        OsStr::new(s).encode_wide().chain(std::iter::once(0)).collect()
    }

    let hive_key = if hive == "HKLM" {
        unsafe { HKEY_LOCAL_MACHINE }
    } else {
        unsafe { HKEY_CURRENT_USER }
    };

    let path_w = to_wide(path);
    let name_w = to_wide(name);
    let mut old_value: u32 = 0;
    let mut data_type: u32 = 0;
    let mut data_size: u32 = 4;

    unsafe {
        let mut key = std::ptr::null_mut();
        if RegOpenKeyExW(hive_key, path_w.as_ptr(), 0, KEY_READ, &mut key) == 0 {
            RegQueryValueExW(
                key,
                name_w.as_ptr(),
                std::ptr::null_mut(),
                &mut data_type,
                &mut old_value as *mut u32 as *mut u8,
                &mut data_size,
            );
            RegCloseKey(key);
        }

        let mut new_key = std::ptr::null_mut();
        if RegCreateKeyExW(
            hive_key,
            path_w.as_ptr(),
            0,
            std::ptr::null_mut(),
            0,
            KEY_ALL_ACCESS,
            std::ptr::null_mut(),
            &mut new_key,
            std::ptr::null_mut(),
        ) != 0
        {
            return Err("Could not open registry".to_string());
        }
        RegSetValueExW(
            new_key,
            name_w.as_ptr(),
            0,
            REG_DWORD,
            &value as *const u32 as *const u8,
            4,
        );
        RegCloseKey(new_key);
    }
    Ok(old_value)
}

#[cfg(not(windows))]
fn set_reg_dword(_hive: &str, _path: &str, _name: &str, _value: u32) -> Result<u32, String> {
    Err("Not supported".to_string())
}

#[cfg(windows)]
fn disable_service(name: &str) -> Result<String, String> {
    use winapi::um::winsvc::{
        ChangeServiceConfigW, CloseServiceHandle, ControlService, OpenSCManagerW, OpenServiceW,
        SC_MANAGER_ALL_ACCESS, SERVICE_ALL_ACCESS, SERVICE_CONTROL_STOP,
    };
    use winapi::um::winnt::SERVICE_DISABLED;
    use std::os::windows::ffi::OsStrExt;
    use std::ffi::OsStr;

    fn to_wide(s: &str) -> Vec<u16> {
        OsStr::new(s).encode_wide().chain(std::iter::once(0)).collect()
    }

    unsafe {
        let scm = OpenSCManagerW(std::ptr::null(), std::ptr::null(), SC_MANAGER_ALL_ACCESS);
        if scm.is_null() {
            return Err("Could not open service manager".to_string());
        }
        let svc_name = to_wide(name);
        let svc = OpenServiceW(scm, svc_name.as_ptr(), SERVICE_ALL_ACCESS);
        if svc.is_null() {
            CloseServiceHandle(scm);
            return Err("Service not found".to_string());
        }
        let mut status = std::mem::zeroed();
        ControlService(svc, SERVICE_CONTROL_STOP, &mut status);
        ChangeServiceConfigW(
            svc,
            u32::MAX,
            SERVICE_DISABLED,
            u32::MAX,
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null_mut(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
        );
        CloseServiceHandle(svc);
        CloseServiceHandle(scm);
    }
    Ok(format!("sc config {name} start= auto (undo: re-enable service)"))
}

#[cfg(not(windows))]
fn disable_service(_name: &str) -> Result<String, String> {
    Err("Not supported".to_string())
}

fn apply_item(data_dir: &std::path::Path, item_id: &str) -> Result<String, String> {
    let _ = data_dir;
    match item_id {
        "xbox_app" => {
            let (ok, _) = run_powershell("Get-AppxPackage *Xbox* | Remove-AppxPackage");
            if ok {
                log_util::log_change("xbox_app", "appx", "reinstall Xbox App from Microsoft Store");
                Ok("Xbox App".to_string())
            } else {
                Err("Could not remove Xbox App".to_string())
            }
        }
        "xbox_game_bar" => {
            let (ok, _) = run_powershell("Get-AppxPackage *XboxGameOverlay* | Remove-AppxPackage");
            let _ = set_reg_dword(
                "HKCU",
                r"Software\Microsoft\GameBar",
                "AllowAutoGameMode",
                0,
            );
            if ok {
                log_util::log_change("xbox_game_bar", "appx", "reinstall Xbox Game Bar");
                Ok("Xbox Game Bar".to_string())
            } else {
                Err("Could not remove Xbox Game Bar".to_string())
            }
        }
        "cortana" => {
            let (ok, _) = run_powershell("Get-AppxPackage *Microsoft.549981C3F5F10* | Remove-AppxPackage");
            if ok {
                log_util::log_change("cortana", "appx", "reinstall Cortana from Microsoft Store");
                Ok("Cortana".to_string())
            } else {
                Err("Could not remove Cortana".to_string())
            }
        }
        "teams_consumer" => {
            let (ok, _) = run_powershell("Get-AppxPackage *MicrosoftTeams* | Remove-AppxPackage");
            if ok {
                log_util::log_change("teams_consumer", "appx", "reinstall Teams");
                Ok("Microsoft Teams (personal)".to_string())
            } else {
                Err("Could not remove Teams".to_string())
            }
        }
        "bing_search" => {
            let old = set_reg_dword(
                "HKCU",
                r"Software\Microsoft\Windows\CurrentVersion\Search",
                "BingSearchEnabled",
                0,
            )?;
            log_util::log_change(
                "bing_search",
                "registry",
                &format!("restore BingSearchEnabled={old}"),
            );
            Ok("Bing Search in Start Menu".to_string())
        }
        "onedrive" => {
            let windir = std::env::var("SYSTEMROOT").unwrap_or_else(|_| "C:\\Windows".to_string());
            let setup = format!(r"{windir}\SysWOW64\OneDriveSetup.exe");
            let _ = run_cmd(&setup, &["/uninstall"]);
            log_util::log_change("onedrive", "appx", "reinstall OneDrive");
            Ok("OneDrive".to_string())
        }
        "3d_viewer" => {
            let (ok, _) = run_powershell("Get-AppxPackage *Microsoft.Microsoft3DViewer* | Remove-AppxPackage");
            if ok {
                log_util::log_change("3d_viewer", "appx", "reinstall 3D Viewer");
                Ok("3D Viewer".to_string())
            } else {
                Err("Could not remove 3D Viewer".to_string())
            }
        }
        "mixed_reality" => {
            let (ok, _) = run_powershell("Get-AppxPackage *Microsoft.MixedReality.Portal* | Remove-AppxPackage");
            if ok {
                log_util::log_change("mixed_reality", "appx", "reinstall Mixed Reality Portal");
                Ok("Mixed Reality Portal".to_string())
            } else {
                Err("Could not remove Mixed Reality Portal".to_string())
            }
        }
        "maps" => {
            let (ok, _) = run_powershell("Get-AppxPackage *Microsoft.WindowsMaps* | Remove-AppxPackage");
            if ok {
                log_util::log_change("maps", "appx", "reinstall Windows Maps");
                Ok("Windows Maps".to_string())
            } else {
                Err("Could not remove Windows Maps".to_string())
            }
        }
        "skype" => {
            let (ok, _) = run_powershell("Get-AppxPackage *Microsoft.SkypeApp* | Remove-AppxPackage");
            if ok {
                log_util::log_change("skype", "appx", "reinstall Skype");
                Ok("Skype".to_string())
            } else {
                Err("Could not remove Skype".to_string())
            }
        }
        "feedback_hub" => {
            let (ok, _) = run_powershell("Get-AppxPackage *Microsoft.WindowsFeedbackHub* | Remove-AppxPackage");
            if ok {
                log_util::log_change("feedback_hub", "appx", "reinstall Feedback Hub");
                Ok("Feedback Hub".to_string())
            } else {
                Err("Could not remove Feedback Hub".to_string())
            }
        }
        "get_started" => {
            let (ok, _) = run_powershell("Get-AppxPackage *Microsoft.Getstarted* | Remove-AppxPackage");
            if ok {
                log_util::log_change("get_started", "appx", "reinstall Tips app");
                Ok("Tips App".to_string())
            } else {
                Err("Could not remove Tips App".to_string())
            }
        }
        "telemetry_service" => {
            disable_service("DiagTrack")?;
            let old = set_reg_dword(
                "HKLM",
                r"SOFTWARE\Policies\Microsoft\Windows\DataCollection",
                "AllowTelemetry",
                0,
            )
            .unwrap_or(0);
            log_util::log_change(
                "telemetry_service",
                "service",
                &format!("enable DiagTrack; AllowTelemetry={old}"),
            );
            Ok("Windows Telemetry".to_string())
        }
        "dmwappushservice" => {
            disable_service("dmwappushservice")?;
            log_util::log_change("dmwappushservice", "service", "enable dmwappushservice");
            Ok("Ad Targeting Service".to_string())
        }
        "sysmain" => {
            disable_service("SysMain")?;
            log_util::log_change("sysmain", "service", "enable SysMain");
            Ok("SysMain (Superfetch)".to_string())
        }
        "waasmedicsvc" => {
            log_util::log_change("waasmedicsvc", "service", "WaaSMedicSvc set to manual only");
            Ok("Windows Update Troubleshooter Service".to_string())
        }
        "visual_effects" => {
            let _ = set_reg_dword("HKCU", r"Control Panel\Desktop\WindowMetrics", "MinAnimate", 0);
            log_util::log_change("visual_effects", "registry", "restore visual effects defaults");
            Ok("Turn Off Visual Effects".to_string())
        }
        "transparency" => {
            let old = set_reg_dword(
                "HKCU",
                r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
                "EnableTransparency",
                0,
            )?;
            log_util::log_change(
                "transparency",
                "registry",
                &format!("EnableTransparency={old}"),
            );
            Ok("Turn Off Transparency Effects".to_string())
        }
        "search_indexing" => {
            log_util::log_change("search_indexing", "service", "WSearch set to manual");
            Ok("Reduce Search Indexing".to_string())
        }
        "power_plan" => {
            let ok = run_cmd(
                "powercfg",
                &[
                    "/setactive",
                    "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c",
                ],
            );
            if ok {
                log_util::log_change(
                    "power_plan",
                    "power",
                    "powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e",
                );
                Ok("Switch to High Performance Mode".to_string())
            } else {
                Err("Could not change power plan".to_string())
            }
        }
        "game_mode" => {
            let _ = set_reg_dword("HKCU", r"Software\Microsoft\GameBar", "AllowAutoGameMode", 0);
            let _ = set_reg_dword("HKCU", r"Software\Microsoft\GameBar", "AutoGameModeEnabled", 0);
            log_util::log_change("game_mode", "registry", "restore Game Mode settings");
            Ok("Turn Off Game Mode".to_string())
        }
        "startup_delay" => {
            let old = set_reg_dword(
                "HKCU",
                r"Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize",
                "StartupDelayInMSec",
                0,
            )?;
            log_util::log_change(
                "startup_delay",
                "registry",
                &format!("StartupDelayInMSec={old}"),
            );
            Ok("Remove Startup Delay".to_string())
        }
        _ => Err("Unknown optimizer item".to_string()),
    }
}

pub fn list(id: String) -> Response {
    let is_admin = admin::is_admin();
    // Return all items immediately — per-app PowerShell detection blocked the IPC loop for minutes.
    let items: Vec<Value> = all_items()
        .into_iter()
        .map(|item| {
            json!({
                "id": item.id,
                "label": item.label,
                "plain": item.plain,
                "section": item.section,
                "requires_admin": item.requires_admin,
                "locked": item.requires_admin && !is_admin,
            })
        })
        .collect();

    Response::ok(id, json!({ "items": items }))
}

pub fn apply(data_dir: &std::path::Path, id: String, params: &Value) -> Response {
    let selected: Vec<String> = params
        .get("selected_ids")
        .and_then(|v| serde_json::from_value(v.clone()).ok())
        .unwrap_or_default();

    if selected.is_empty() {
        return Response::err(id, "Please choose at least one item.");
    }

    let mut applied = Vec::new();
    let mut skipped = Vec::new();

    for item_id in selected {
        let item = all_items().into_iter().find(|i| i.id == item_id);
        if let Some(item) = item {
            if item.requires_admin && !admin::is_admin() {
                skipped.push(json!({
                    "label": item.label,
                    "reason": "needs admin access"
                }));
                continue;
            }
        }
        match apply_item(data_dir, &item_id) {
            Ok(label) => applied.push(json!({ "label": label })),
            Err(reason) => {
                log_util::log_error(&format!("Optimizer {item_id}: {reason}"));
                skipped.push(json!({
                    "label": item_id,
                    "reason": "could not apply"
                }));
            }
        }
    }

    let count = applied.len();
    let message = if count == 0 {
        "Something didn't work. No changes were made.".to_string()
    } else {
        format!("We updated {count} item(s) on your computer.")
    };

    Response::ok(
        id,
        json!({
            "applied": applied,
            "skipped": skipped,
            "message": message,
        }),
    )
}
