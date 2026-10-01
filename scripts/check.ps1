#!/usr/bin/env pwsh
# Strict build, unit tests, console self-test and forbidden-API scan.
# Mirrors the macOS scripts/check.sh contract on Windows.
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Invoke-NativeCommand {
    param(
        [string]$Description,
        [scriptblock]$Command
    )

    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE"
    }
}

Write-Host '==> dotnet build (Release, warnings as errors)'
Invoke-NativeCommand 'dotnet build' { dotnet build YTools.Windows.sln -c Release -warnaserror }

Write-Host '==> dotnet test (Release)'
Invoke-NativeCommand 'dotnet test' { dotnet test YTools.Windows.sln -c Release --no-build }

Write-Host '==> Release self-test'
$exe = Join-Path $root 'src\YTools.Windows\bin\Release\net8.0-windows\YTools.exe'
$log = Join-Path $env:TEMP 'ytools-selftest.log'
if (Test-Path $log) { Remove-Item $log }
$process = Start-Process -FilePath $exe -ArgumentList '--selftest' -Wait -PassThru
if ($process.ExitCode -ne 0) {
    if (Test-Path $log) { Get-Content $log }
    throw "Self-test failed with exit code $($process.ExitCode)"
}
Get-Content $log

Write-Host '==> Forbidden API scan'
$python = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $python) { $python = Get-Command python3 -ErrorAction Stop }
Invoke-NativeCommand 'security scan' { & $python.Source scripts/security_scan.py }
Invoke-NativeCommand 'security scan fixture tests' { & $python.Source scripts/security_scan_test.py }

Write-Host 'Windows build, tests, self-test and security scan passed'
