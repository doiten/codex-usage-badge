# Isolated Store identity/activation regression; no installed client or GUI actions.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$version=(Get-Content -LiteralPath (Join-Path $root 'package.json') -Raw | ConvertFrom-Json).windowsVersion
. (Join-Path $root ('dist/CodexUsageBadge-Windows-'+$version+'/manage-windows.ps1')) -Action Functions
function Assert($Condition,[string]$Message) { if(!$Condition){throw $Message} }
function Throws([scriptblock]$Body,[string]$Pattern) {
    $failure=$null
    try {& $Body} catch {$failure=$_.Exception.Message}
    Assert ($failure -and $failure -match $Pattern) ('Expected '+$Pattern+', got '+$failure)
}
# Match the existing native helper's reflection contract without activating any app.
Add-Type -TypeDefinition @'
using System;
namespace CodexUsageBadge.Startup {
    public class LaunchResult { public string AppPath; public string ApplicationId; }
    public static class Native {
        static string appPath = null, applicationId = null;
        public static bool Fail = false;
        public static int Calls = 0;
        static LaunchResult StartApplication() {
            Calls++;
            if (Fail) throw new InvalidOperationException("Synthetic Store activation failure");
            return new LaunchResult { AppPath = appPath, ApplicationId = applicationId };
        }
    }
}
'@
$temp=Join-Path ([IO.Path]::GetTempPath()) ('badge-launch-'+[guid]::NewGuid().ToString('N'))
function New-FixtureDesktop([string]$Directory) {
    [void][IO.Directory]::CreateDirectory((Join-Path $Directory 'resources'))
    Write-Utf8 (Join-Path $Directory 'resources/app.asar') 'synthetic fixture'
    $exe=Join-Path $Directory 'ChatGPT.exe';Write-Utf8 $exe 'synthetic fixture';return $exe
}
try {
    $install=Join-Path $temp 'WindowsApps/Codex fixture'
    $app=New-FixtureDesktop (Join-Path $install 'app')
    $script:packages=@([pscustomobject]@{Name='OpenAI.Codex';InstallLocation=$install;PackageFullName='OpenAI.Codex_fixture';PackageFamilyName='OpenAI.Codex_fixturefamily'})
    $script:manifest=[xml]'<Package><Applications><Application Id="Helper" Executable="app/helper.exe"/><Application Id="Desktop" Executable="app/ChatGPT.exe"/></Applications></Package>'
    $script:desktopLaunches=@()
    function Get-AppxPackage { $script:packages }
    function Get-AppxPackageManifest([string]$Package) {
        Assert ($Package -eq 'OpenAI.Codex_fixture') 'Manifest must belong to the exact matching package'
        return $script:manifest
    }
    function Start-Process([string]$FilePath,[string]$ArgumentList,[switch]$PassThru) {
        $script:desktopLaunches+=@{Path=$FilePath;Arguments=$ArgumentList;PassThru=$PassThru}
    }
    $result=Start-DesktopWithConnection ([pscustomobject]@{AppExe=$app})
    Assert ($result.AppPath -eq [IO.Path]::GetFullPath($app)) 'Exact executable passed to native helper'
    Assert ($result.ApplicationId -eq 'OpenAI.Codex_fixturefamily!Desktop') 'Application ID resolved from exact manifest executable'
    Assert ([CodexUsageBadge.Startup.Native]::Calls -eq 1 -and $script:desktopLaunches.Count -eq 0) 'Store launch uses native helper without direct execution'
    $script:manifest=[xml]'<Package><Applications><Application Id="Helper" Executable="app/helper.exe"/></Applications></Package>'
    Throws {Start-DesktopWithConnection ([pscustomobject]@{AppExe=$app})} '激活标识'
    Assert ([CodexUsageBadge.Startup.Native]::Calls -eq 1 -and $script:desktopLaunches.Count -eq 0) 'Unresolved identity must fail closed'
    $script:manifest=[xml]'<Package><Applications><Application Id="Desktop" Executable="app/ChatGPT.exe"/></Applications></Package>'
    [CodexUsageBadge.Startup.Native]::Fail=$true
    Throws {Start-DesktopWithConnection ([pscustomobject]@{AppExe=$app})} 'Synthetic Store activation failure'
    Assert ($script:desktopLaunches.Count -eq 0) 'Activation failure must not fall back to direct execution'
    [CodexUsageBadge.Startup.Native]::Fail=$false
    $sibling=New-FixtureDesktop (Join-Path $temp 'WindowsApps/Codex fixture-other/app')
    Throws {Start-DesktopWithConnection ([pscustomobject]@{AppExe=$sibling})} '激活标识'
    $script:packages=@()
    Throws {Start-DesktopWithConnection ([pscustomobject]@{AppExe=$app})} '激活标识'
    Assert ($script:desktopLaunches.Count -eq 0) 'Missing/sibling Store packages must not execute directly'
    $desktop=New-FixtureDesktop (Join-Path $temp 'Ordinary desktop')
    Start-DesktopWithConnection ([pscustomobject]@{AppExe=$desktop}) | Out-Null
    Assert ($script:desktopLaunches.Count -eq 1 -and $script:desktopLaunches[0].Path -eq $desktop) 'Ordinary desktop launch retained'
    Assert ($script:desktopLaunches[0].Arguments -eq '--remote-debugging-address=127.0.0.1 --remote-debugging-port=39222') 'Desktop flags stay loopback only'
    Throws {Start-DesktopWithConnection ([pscustomobject]@{AppExe=(Join-Path $temp 'missing.exe')})} '路径无效'
    Assert ($script:desktopLaunches.Count -eq 1) 'Invalid executables must not launch'
    Write-Host 'PASS Store manifest identity, native helper contract, fail-closed resolution/activation, ordinary desktop launch and loopback flags (OS actions mocked)'
} finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
