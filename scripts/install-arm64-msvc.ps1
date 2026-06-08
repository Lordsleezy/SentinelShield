# Requires elevation. Installs ARM64 MSVC libraries needed to compile Rust on ARM64 Windows.
$ErrorActionPreference = "Stop"

$setup = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
$installPath = "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools"
if (-not (Test-Path $installPath)) {
    $installPath = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
}

if (-not (Test-Path $setup)) {
    Write-Error "Visual Studio Installer not found."
}

Write-Host "Installing ARM64 C++ build tools (UAC prompt may appear)..."
$proc = Start-Process -FilePath $setup -ArgumentList @(
    "modify",
    "--installPath", $installPath,
    "--add", "Microsoft.VisualStudio.Component.VC.Tools.ARM64",
    "--includeRecommended",
    "--passive",
    "--norestart"
) -Verb RunAs -Wait -PassThru

if ($proc.ExitCode -ne 0) {
    Write-Error "Installer exited with code $($proc.ExitCode). Run Visual Studio Installer manually and add ARM64 C++ build tools."
}

Write-Host "ARM64 build tools installed. Run: npm run build:sidecar"
