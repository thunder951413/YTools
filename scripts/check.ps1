#!/usr/bin/env pwsh
# Strict build, unit tests, console self-test and forbidden-API scan.
# Mirrors the macOS scripts/check.sh contract on Windows.
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host '==> dotnet build (warnings as errors)'
dotnet build YTools.Windows.sln -c Debug -warnaserror

Write-Host '==> dotnet test'
dotnet test YTools.Windows.sln -c Debug --no-build

Write-Host '==> Release self-test'
$exe = Join-Path $root 'src\YTools.Windows\bin\Debug\net8.0-windows\YTools.exe'
$log = Join-Path $env:TEMP 'ytools-selftest.log'
if (Test-Path $log) { Remove-Item $log }
$process = Start-Process -FilePath $exe -ArgumentList '--selftest' -Wait -PassThru
if ($process.ExitCode -ne 0) {
    if (Test-Path $log) { Get-Content $log }
    throw "Self-test failed with exit code $($process.ExitCode)"
}
Get-Content $log

Write-Host '==> Forbidden API scan'
$patterns = @(
    'HttpClient',
    'WebClient',
    'TcpClient',
    'UdpClient',
    'NetworkStream',
    'Socket\(',
    'Assembly\.Load',
    'Assembly\.LoadFrom',
    'Assembly\.LoadFile',
    'Activator\.CreateInstance',
    'AppDomain',
    'cmd\.exe',
    'powershell\.exe',
    '/bin/(sh|bash|zsh)'
)
$hits = Get-ChildItem -Path src\YTools.Windows -Recurse -Filter *.cs |
    Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' } |
    Select-String -Pattern $patterns
if ($hits) {
    $hits | ForEach-Object { Write-Host "FORBIDDEN: $($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
    throw 'Forbidden network, web, dynamic-code or shell API found in runtime sources'
}

Write-Host 'Windows build, tests, self-test and security scan passed'
