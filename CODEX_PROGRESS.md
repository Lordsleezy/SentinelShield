# Sentinel Shield — Product Summary

**Date:** 2026-06-09  
**Version:** 0.1.2  
**Status:** **Ready for real-device testing** — sidecar IPC hang fixed in installed builds.

**Repository:** [Lordsleezy/SentinelShield](https://github.com/Lordsleezy/SentinelShield)

---

## What Sentinel Shield Is

Sentinel Shield is a senior-friendly Windows protection suite: malware scanning, real-time monitoring, system cleanup, and human escalation paths to Sentinel Prime services. An Android companion app (`companion/`) extends protection to phones.

| Platform | Product | Location |
|----------|---------|----------|
| Windows | Sentinel Shield | Root repo — Electron + React + Rust sidecar |
| Android | Sentinel Prime Companion | `companion/` — Expo + native Kotlin module |

---

## Installed Build Fix — Sidecar IPC Hang (v0.1.2)

**Symptom:** Scanner worked; Cleaner, Protection, Network, History, Memory, Optimizer hung on "Working..." indefinitely.

**Root causes:**

| # | Cause | Fix |
|---|-------|-----|
| 1 | **Single-threaded stdin loop** — `optimizer_list` ran 12+ PowerShell `Get-AppxPackage` calls sequentially (~minutes), blocking all other IPC commands queued behind it | Dispatch every command on a **background thread** in `main.rs` |
| 2 | **stdout race** — schedule/realtime background threads emitted events while responses were printed, corrupting JSON lines so pending promises never resolved | New `ipc_out.rs` mutex serializes all stdout writes |
| 3 | **`cleaner_preview` slow** — unbounded `WalkDir` on large cache dirs blocked the loop for minutes | `max_depth(6)` on directory size walks |
| 4 | **Rules update on launch** blocked first commands | Moved `rules_updater::update_on_launch` to background thread |

**Diagnostics added:**

- **UI:** `SidecarStatusIndicator` — "Protection engine ready" / "starting…" / "offline"
- **Main process:** `runDiagnostics()` logs `ping`, `memory_status`, `cleaner_preview`, `optimizer_list`, `network_scan`, `threat_history_list`, `realtime_status` on launch (see `%APPDATA%/SentinelShield/logs/shield.log`)
- **IPC timeouts:** 90s default, 10min for scan/cleaner/network — prevents infinite "Working..."

**Admin note:** Optimizer/cleaner items marked `requires_admin` show locked without elevation; commands still return data (no hang).

---

## Stage 1 — Stability & Packaging (Complete)

| Feature | Result |
|---------|--------|
| Report-only scanning | No auto-quarantine; user chooses per file |
| Scan progress UI | File count, current file, ETA via IPC |
| Scanner hardening | Depth limits, dev-dir skips, tighter YARA rules |
| Startup / optimizer fixes | UTF-16 registry decode, `bing_search` fix |
| Windows installer | NSIS x64 → `release/SentinelShield-Setup-{version}.exe` |
| GitHub Actions CI | Builds sidecar + Electron + uploads installer + `latest.yml` |

---

## Stage 2 — Active Protection (Complete)

| Feature | Key files |
|---------|-----------|
| Real-time protection | `realtime.rs`, `ProtectionTab.tsx` |
| Scheduled scans | `schedule.rs`, `settings.json` |
| Network scanner | `network.rs`, `NetworkTab.tsx` |
| YARA auto-updater | `rules_updater.rs` (on sidecar launch) |
| Threat history | `threat_history.rs`, `HistoryTab.tsx` |

**Sidecar commands:** `realtime_start/stop/status`, `schedule_get/set`, `network_scan`, `rules_update`, `threat_history_list/clear`, `settings_get/set`

**Events:** `threat_detected`, `scheduled_scan_complete`, `realtime_started`

---

## Stage 3 — Product Polish (Complete)

| Feature | Notes |
|---------|-------|
| Sentinel Care | `EscalateCareButton` → `https://care.sentinelprime.org` |
| Sentinel Market | `ShopMarketButton` → `https://market.sentinelprime.org` (when RAM &lt; 8 GB or ≥ 85% used) |
| Senior friendly mode | `SeniorMode.tsx` — one big **Scan Now**, persisted toggle |
| App auto-update | `electron-updater` → GitHub Releases; `UpdateBanner.tsx` |
| Android companion | `companion/` — call screening, permission audit, cleaner |

### App auto-update

- Checks GitHub Releases ~5s after launch (production only)
- Downloads silently; installs on quit or optional **Restart now**
- **v0.1.1** published to test updater from installed **v0.1.0**

### Android companion (`companion/`)

| Tab | Feature |
|-----|---------|
| Calls | Spam blocker via `ROLE_CALL_SCREENING` |
| Apps | Permission auditor — flags 2+ sensitive permissions |
| Cleaner | Clears app cache and temp files |

```bash
cd companion
npm install
npx expo prebuild --platform android
npm run android
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Electron main (index.ts, updater.ts, sidecar.ts)       │
│  IPC: shield:request, shield:event, shield:update       │
└────────────────────┬────────────────────────────────────┘
                     │ stdin/stdout JSON
┌────────────────────▼────────────────────────────────────┐
│  Rust sidecar (sentinel_shield_core.exe)                │
│  scanner, realtime, schedule, network, rules_updater   │
└─────────────────────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│  React renderer — 7 tabs + senior mode + banners        │
└─────────────────────────────────────────────────────────┘
```

**Data dir:** `%APPDATA%/SentinelShield` — logs, quarantine, `settings.json`, `threats.jsonl`

---

## Build Commands

```powershell
npm run dev          # development
npm run build        # renderer + main + sidecar
npm run dist         # full NSIS installer
```

Installer output: `release/SentinelShield-Setup-0.1.1.exe`

---

## Known Items for Real Device Testing

### Windows (Sentinel Shield)

| # | Item | Notes |
|---|------|-------|
| 1 | Auto-updater E2E | Install v0.1.0, push triggers CI release v0.1.1; confirm banner appears |
| 2 | Unsigned installer | Code signing skipped without cert — SmartScreen warning expected |
| 3 | Admin features | Optimizer/registry changes need **Run as Administrator** |
| 4 | Legacy quarantine | ~370 files in `data/quarantine/` from pre-fix scans — not auto-restored |
| 5 | Scan scope | Default scans Downloads, Desktop, Documents, Temp — Desktop slow on dev machines |
| 6 | Hardware market CTA | Memory tab shows **Shop at Sentinel Market** when RAM &lt; 8 GB or ≥ 85% full |
| 7 | Sentinel Care / Market links | Require internet; open default browser |

### Android (Sentinel Prime Companion)

| # | Item | Notes |
|---|------|-------|
| 1 | Call screening role | User must grant **Call screening** role in Android settings (API 29+) |
| 2 | `QUERY_ALL_PACKAGES` | Permission auditor needs this on Android 11+ — may require Play Console declaration |
| 3 | Physical device | Call screening cannot be fully tested on emulator |
| 4 | Prebuild required | `npx expo prebuild --platform android` before native build |
| 5 | Cleaner scope | Clears companion app caches — not system-wide without additional permissions |

### CI / Releases

| # | Item | Notes |
|---|------|-------|
| 1 | Version bumps | Increment `package.json` version before each release for updater to detect updates |
| 2 | `latest.yml` | Must be attached to GitHub Release alongside `.exe` |
| 3 | Companion not in CI | Android app built locally or via EAS — not in Windows CI workflow |

---

## Sentinel Prime Integrations

| Service | URL | When shown |
|---------|-----|------------|
| Sentinel Care | `care.sentinelprime.org` | Scan failures, threats, real-time alerts |
| Sentinel Market | `market.sentinelprime.org` | Low RAM or persistent high memory usage |

---

## Commit History (Milestones)

| Commit | Milestone |
|--------|-----------|
| `c73e675` | Initial Windows app |
| `4cf455d` | Stage 1 — stability, installer, CI |
| `dc04fb1` | Stage 2 — realtime, network, history |
| `f02e355` | Stage 3 — Care, senior mode, updater, companion |
| *(pending)* | v0.1.1 — Market link, final testing prep |

---

*Shield development is complete. Stand by for next instructions.*
