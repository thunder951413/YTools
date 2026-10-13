#!/usr/bin/env pwsh
# Publishes the portable single-file Release build into dist/YTools.Windows/.
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# Release tags (v1.2.3) set YTOOLS_VERSION so both platforms ship the same
# version; local builds keep the csproj default.
$versionArgs = @()
if ($env:YTOOLS_VERSION -match '^v?\d+\.\d+\.\d+([-+][0-9A-Za-z.-]+)?$') {
    $versionArgs = @("-p:Version=$($env:YTOOLS_VERSION.TrimStart('v'))")
}

dotnet publish src\YTools.Windows\YTools.Windows.csproj `
        -c Release `
        -r win-x64 `
        --self-contained true `
        -p:PublishSingleFile=true `
        -p:IncludeNativeLibrariesForSelfExtract=true `
        -p:EnableCompressionInSingleFile=true `
        -p:DebugType=None `
        -p:DebugSymbols=false `
        @versionArgs `
        -o dist\YTools.Windows
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE"
}

Write-Host "Published $(Resolve-Path dist\YTools.Windows)"
