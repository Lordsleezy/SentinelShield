# Build the Rust sidecar (sentinel_shield_core.exe)
# Requires: Rust stable + Visual Studio Build Tools (Desktop development with C++)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Sidecar = Join-Path $Root "src\sidecar"

function Find-VcVars {
    $candidates = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvarsall.bat",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

function Find-RustLld {
    $triple = "x86_64-pc-windows-msvc"
    $roots = @(
        Join-Path $env:USERPROFILE ".rustup\toolchains\stable-x86_64-pc-windows-msvc"
        Join-Path $env:USERPROFILE ".rustup\toolchains\stable-aarch64-pc-windows-msvc"
    )
    foreach ($root in $roots) {
        $lld = Join-Path $root "lib\rustlib\$triple\bin\rust-lld.exe"
        if (Test-Path $lld) { return $lld }
    }
    return $null
}

$VcVars = Find-VcVars
if (-not $VcVars) {
    Write-Error "Visual Studio Build Tools not found. Install the C++ workload, then retry."
}

$env:Path = "$env:USERPROFILE\.cargo\bin;" + $env:Path
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Error "Rust (cargo) not found. Install from https://rustup.rs"
}

$Target = "x86_64-pc-windows-msvc"
$HostArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLower()
$VcArch = "x64"

# On ARM64 Windows, build scripts must run as x64 (needs x64 msvcrt.lib, not ARM64).
$CargoToolchain = if ($HostArch -eq "arm64") { "stable-x86_64-pc-windows-msvc" } else { "stable" }
if ($HostArch -eq "arm64") {
    $toolchainList = & rustup toolchain list 2>$null | Out-String
    if ($toolchainList -notmatch "stable-x86_64-pc-windows-msvc") {
        Write-Host "Installing x64 Rust toolchain for cross-compilation on ARM64 host..."
        & rustup toolchain install stable-x86_64-pc-windows-msvc --force-non-host
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Could not install x64 Rust toolchain. Run: rustup toolchain install stable-x86_64-pc-windows-msvc --force-non-host"
        }
    }
}

$Lld = Find-RustLld
if ($Lld) {
    $LldDir = Split-Path $Lld -Parent
    $env:Path = "$LldDir;$env:Path"
}

Write-Host "Building sidecar for $Target (host: $HostArch, vcvars: $VcArch, toolchain: $CargoToolchain) ..."
$cargoCmd = if ($CargoToolchain -eq "stable") {
    "cargo build --release --target $Target --manifest-path src/sidecar/Cargo.toml"
} else {
    "rustup run $CargoToolchain cargo build --release --target $Target --manifest-path src/sidecar/Cargo.toml"
}
$cmd = "call `"$VcVars`" $VcArch && cd /d `"$Root`" && $cargoCmd"
cmd /c $cmd
if ($LASTEXITCODE -ne 0) {
    Write-Error "cargo build failed with exit code $LASTEXITCODE"
}

$Exe = Join-Path $Sidecar "target\$Target\release\sentinel_shield_core.exe"
if (Test-Path $Exe) {
    Write-Host "Built: $Exe"
} else {
    Write-Error "Build failed. Executable not found at $Exe"
}
