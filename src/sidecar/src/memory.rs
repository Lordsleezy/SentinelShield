use crate::log_util;
use crate::protocol::Response;
use serde_json::json;
use sysinfo::{ProcessesToUpdate, System};
use std::process::Command;
use std::thread;
use std::time::Duration;

fn read_memory() -> (u64, u64, u64, u32) {
    let mut sys = System::new();
    sys.refresh_memory();
    let total = sys.total_memory();
    let used = sys.used_memory();
    let available = sys.available_memory();
    let pct = if total > 0 {
        ((used as f64 / total as f64) * 100.0).round() as u32
    } else {
        0
    };
    (total, used, available, pct)
}

fn memory_to_gb(bytes: u64) -> String {
    log_util::format_bytes(bytes)
}

fn total_ram_gb(total: u64) -> f64 {
    total as f64 / 1024.0 / 1024.0 / 1024.0
}

fn recommend_hardware_upgrade(total: u64, used_pct: u32) -> bool {
    total_ram_gb(total) < 8.0 || used_pct >= 85
}

fn hardware_message(total: u64, used_pct: u32) -> Option<&'static str> {
    if !recommend_hardware_upgrade(total, used_pct) {
        return None;
    }
    if total_ram_gb(total) < 8.0 {
        Some("Your computer has less than 8 GB of memory. A RAM upgrade or newer device may help.")
    } else {
        Some("Your memory is very full even after cleanup. A hardware upgrade may be worth considering.")
    }
}

pub fn status(id: String) -> Response {
    let (total, used, available, used_pct) = read_memory();
    let status_line = format!("Your memory is {used_pct}% full");
    let upgrade = recommend_hardware_upgrade(total, used_pct);
    Response::ok(
        id,
        json!({
            "used_pct": used_pct,
            "used_friendly": memory_to_gb(used),
            "free_friendly": memory_to_gb(available),
            "total_friendly": memory_to_gb(total),
            "status_line": status_line,
            "recommend_hardware_upgrade": upgrade,
            "hardware_message": hardware_message(total, used_pct),
        }),
    )
}

const PROTECTED: &[&str] = &["System", "smss.exe", "csrss.exe", "wininit.exe", "lsass.exe"];

#[cfg(windows)]
fn flush_working_sets() {
    use sysinfo::System;
    use winapi::um::processthreadsapi::OpenProcess;
    use winapi::um::psapi::EmptyWorkingSet;
    use winapi::um::winbase::SetProcessWorkingSetSize;
    use winapi::um::winnt::{PROCESS_QUERY_INFORMATION, PROCESS_SET_QUOTA};

    let mut sys = System::new_all();
    sys.refresh_processes(ProcessesToUpdate::All);

    for (pid, process) in sys.processes() {
        let name = process.name();
        if PROTECTED.iter().any(|p| name.eq_ignore_ascii_case(p)) {
            continue;
        }
        let pid_u32 = pid.as_u32();
        unsafe {
            let handle = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_SET_QUOTA, 0, pid_u32);
            if !handle.is_null() {
                EmptyWorkingSet(handle);
                let _ = winapi::um::handleapi::CloseHandle(handle);
            }
        }
    }

    unsafe {
        let self_handle = winapi::um::processthreadsapi::GetCurrentProcess();
        SetProcessWorkingSetSize(self_handle, usize::MAX, usize::MAX);
    }
}

#[cfg(not(windows))]
fn flush_working_sets() {}

#[cfg(windows)]
fn purge_standby_list() {
    const SYSTEM_MEMORY_LIST_INFORMATION: u32 = 80;
    const MEMORY_PURGE_STANDBY_LIST: i32 = 4;

    #[link(name = "ntdll")]
    extern "system" {
        fn NtSetSystemInformation(
            class: u32,
            info: *mut std::ffi::c_void,
            length: u32,
        ) -> i32;
    }

    let command: i32 = MEMORY_PURGE_STANDBY_LIST;
    unsafe {
        let status = NtSetSystemInformation(
            SYSTEM_MEMORY_LIST_INFORMATION,
            &command as *const i32 as *mut std::ffi::c_void,
            std::mem::size_of::<i32>() as u32,
        );
        log_util::log_info(&format!("Standby list purge status: {status}"));
    }
}

#[cfg(not(windows))]
fn purge_standby_list() {}

#[cfg(windows)]
fn flush_dns() {
    use std::os::windows::process::CommandExt;
    let _ = Command::new("ipconfig")
        .args(["/flushdns"])
        .creation_flags(0x08000000)
        .output();
    log_util::log_info("DNS cache flushed during memory free");
}

#[cfg(not(windows))]
fn flush_dns() {}

pub fn free(id: String) -> Response {
    let (_, _, available_before, before_pct) = read_memory();
    let total_before = read_memory().0;

    flush_dns();
    flush_working_sets();
    purge_standby_list();

    thread::sleep(Duration::from_secs(1));

    let (_, _, available_after, after_pct) = read_memory();
    let freed_bytes = available_after.saturating_sub(available_before);
    let freed_friendly = memory_to_gb(freed_bytes);

    let message = format!(
        "Your memory went from {before_pct}% full to {after_pct}% full. We freed up {freed_friendly}."
    );

    log_util::log_info(&format!(
        "Memory free: {before_pct}% -> {after_pct}%, freed ~{freed_bytes} bytes"
    ));

    let upgrade = recommend_hardware_upgrade(total_before, after_pct);
    Response::ok(
        id,
        json!({
            "before_pct": before_pct,
            "after_pct": after_pct,
            "freed_friendly": freed_friendly,
            "message": message,
            "recommend_hardware_upgrade": upgrade,
            "hardware_message": hardware_message(total_before, after_pct),
        }),
    )
}
