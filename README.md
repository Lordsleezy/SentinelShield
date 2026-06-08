# Sentinel Shield

Simple, local Windows protection — plain English, no jargon, fully offline.

Built for people who want clear answers and safe fixes without technical jargon.

## Requirements

- Windows 10 (1903+) or Windows 11 x64
- Node.js 20+
- Rust stable toolchain
- Visual Studio Build Tools with the **Desktop development with C++** workload

## Development

```powershell
npm install
npm run build:sidecar
npm run dev
```

The sidecar builds to `src/sidecar/target/x86_64-pc-windows-msvc/release/sentinel_shield_core.exe`.

On **ARM64 Windows**, the build script automatically installs the x64 Rust toolchain (`stable-x86_64-pc-windows-msvc --force-non-host`) so build scripts link against x64 MSVC libraries. You still need Visual Studio Build Tools with the **x64 C++** workload. Then run:

```powershell
npm run build:sidecar
```

If that still fails, install ARM64 MSVC tools as Administrator:

```powershell
npm run install:arm64-msvc
npm run build:sidecar
```

Or build on a native x64 Windows PC.

## Production build

```powershell
npm run build
npm start
```

## Features

- **Scanner** — YARA-based virus scan with quarantine
- **Cleaner** — Preview and remove temp files, browser cache, and more
- **Memory** — Free up RAM with one button
- **Optimizer** — Remove bloatware, tune performance, manage startup and tasks

All detailed output is written to `logs/shield.log`. Flagged files are moved to `quarantine/`.
