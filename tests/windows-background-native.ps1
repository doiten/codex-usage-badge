# Kill a disposable installer job; the production Start-Worker must survive it.
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Windows runner required' }
$root = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $root 'package.json') -Raw | ConvertFrom-Json).windowsVersion
$manager = Join-Path $root ('dist/CodexUsageBadge-Windows-' + $version + '/manage-windows.ps1')
. $manager -Action Functions
function Assert($Condition, [string]$Message) { if (!$Condition) { throw $Message } }
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
public sealed class BadgeBackgroundJob : IDisposable {
    [StructLayout(LayoutKind.Sequential)] struct Limits {
        public long processTime, jobTime; public uint flags; public UIntPtr minimum, maximum;
        public uint active; public UIntPtr affinity; public uint priority, scheduling;
    }
    [StructLayout(LayoutKind.Sequential)] struct ExtendedLimits {
        public Limits basic;
        public ulong readOps, writeOps, otherOps, readBytes, writeBytes, otherBytes;
        public UIntPtr processMemory, jobMemory, peakProcess, peakJob;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct StartupInfo {
        public int size; public string reserved, desktop, title;
        public uint x, y, width, height, columns, rows, fill, flags;
        public ushort show, reservedSize;
        public IntPtr reservedData, input, output, error;
    }
    [StructLayout(LayoutKind.Sequential)] struct ProcessInfo { public IntPtr process, thread; public uint pid, tid; }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObjectW(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job, int kind, ref ExtendedLimits limits, uint size);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateProcessW(string app, StringBuilder command, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr environment, string directory, ref StartupInfo startup, out ProcessInfo process);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool IsProcessInJob(IntPtr process, IntPtr job, out bool result);
    [DllImport("kernel32.dll", SetLastError=true)] static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr process, uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    IntPtr job;
    public int ParentId {get; private set;}
    public bool Contains(int pid) {
        using(var process=Process.GetProcessById(pid)) {
            bool result;
            if(!IsProcessInJob(process.Handle,job,out result)) throw new Win32Exception(Marshal.GetLastWin32Error());
            return result;
        }
    }
    public BadgeBackgroundJob(string app, string arguments, string directory) {
        job=CreateJobObjectW(IntPtr.Zero,null);
        if(job==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            var limits=new ExtendedLimits(); limits.basic.flags=0x2800; // kill on close, allow explicit breakaway
            if(!SetInformationJobObject(job,9,ref limits,(uint)Marshal.SizeOf(typeof(ExtendedLimits)))) throw new Win32Exception(Marshal.GetLastWin32Error());
            var startup=new StartupInfo {size=Marshal.SizeOf(typeof(StartupInfo)),flags=1,show=0};
            ProcessInfo process;
            if(!CreateProcessW(app,new StringBuilder("\""+app+"\" "+arguments),IntPtr.Zero,IntPtr.Zero,false,0x09000004,IntPtr.Zero,directory,ref startup,out process)) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                if(!AssignProcessToJobObject(job,process.process)) throw new Win32Exception(Marshal.GetLastWin32Error());
                if(ResumeThread(process.thread)==UInt32.MaxValue) throw new Win32Exception(Marshal.GetLastWin32Error());
                ParentId=checked((int)process.pid);
            } catch {TerminateProcess(process.process,1);throw;}
            finally {CloseHandle(process.thread);CloseHandle(process.process);}
        } catch {Dispose();throw;}
    }
    public void Dispose() {if(job!=IntPtr.Zero){CloseHandle(job);job=IntPtr.Zero;}}
}
'@
$temp = Join-Path ([IO.Path]::GetTempPath()) ('badge-background-中文 空格-' + [guid]::NewGuid().ToString('N'))
$oldMarker = $env:CODEX_BADGE_BACKGROUND_TEST
$job = $null; $child = $null; $parent = $null
try {
    [void][IO.Directory]::CreateDirectory($temp)
    $env:CODEX_BADGE_BACKGROUND_TEST = '中文 inherited value'
    $stop = Join-Path $temp 'stop.request'
    $childScript = Join-Path $temp 'child.ps1'
    $childReceipt = Join-Path $temp 'child.json'
    $parentReceipt = Join-Path $temp 'parent.json'
    $parentScript = Join-Path $temp 'parent.ps1'
    [IO.File]::WriteAllText($childScript, @'
param($Action)
$ErrorActionPreference='Stop'
$Receipt=Join-Path $PSScriptRoot 'child.json'
$Stop=Join-Path $PSScriptRoot 'stop.request'
$state=@{State='running';Pid=$PID;Directory=[Environment]::CurrentDirectory;Marker=$env:CODEX_BADGE_BACKGROUND_TEST}
[IO.File]::WriteAllText($Receipt,($state|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
while (!(Test-Path -LiteralPath $Stop)) {Start-Sleep -Milliseconds 100}
'@, (New-Object Text.UTF8Encoding($true)))
    [IO.File]::WriteAllText($parentScript, @'
param($Manager, $Receipt, $ChildScript, $ChildReceipt, $Stop)
$ErrorActionPreference='Stop'
. $Manager -Action Functions
Initialize-Context
$script:InstallRoot=$PSScriptRoot
$script:ManagerPath=$ChildScript
$script:StatePath=$ChildReceipt
$script:StopPath=$Stop
function Test-Worker {
    $state=Read-Json $script:StatePath
    return $state -and $state.State -eq 'running' -and !!(Get-Process -Id $state.Pid -ErrorAction SilentlyContinue)
}
Start-Worker
$childId=(Read-Json $ChildReceipt).Pid
Write-Json $Receipt @{ChildId=$childId}
while (!(Test-Path -LiteralPath $Stop)) {Start-Sleep -Milliseconds 100}
'@, (New-Object Text.UTF8Encoding($true)))
    $shell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $arguments = Join-NativeArguments @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$parentScript,'-Manager',$manager,'-Receipt',$parentReceipt,'-ChildScript',$childScript,'-ChildReceipt',$childReceipt,'-Stop',$stop)
    $job = New-Object BadgeBackgroundJob($shell, $arguments, $temp)
    $parent = Get-Process -Id $job.ParentId
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ((!(Test-Path -LiteralPath $childReceipt) -or !(Test-Path -LiteralPath $parentReceipt)) -and !$parent.HasExited -and [DateTime]::UtcNow -lt $deadline) {Start-Sleep -Milliseconds 100}
    Assert (Test-Path -LiteralPath $parentReceipt) 'Installer fixture did not start background'
    $child = Get-Process -Id (Read-Json $parentReceipt).ChildId
    Assert (Test-Path -LiteralPath $childReceipt) 'Background fixture did not become ready'
    $state = Read-Json $childReceipt
    Assert ($state.Pid -eq $child.Id -and $state.Marker -eq $env:CODEX_BADGE_BACKGROUND_TEST) 'Background must inherit the installer environment'
    Assert ($state.Directory -eq $temp) 'Background working directory/Unicode arguments changed'
    Assert ($child.MainWindowHandle -eq 0) 'Background must remain hidden'
    Assert ($job.Contains($parent.Id)) 'Installer fixture must be inside a job'
    Assert (!$job.Contains($child.Id)) 'Background inherited the installer job'
    $job.Dispose(); $job = $null
    Assert ($parent.WaitForExit(5000)) 'Closing installer job did not terminate the parent'
    Assert (!$child.HasExited) 'Background died with the installer job'
    Write-Utf8 $stop 'stop'
    Assert ($child.WaitForExit(5000)) 'Independent background did not honor graceful stop'
    Write-Host 'PASS background survives installer job termination, inherits environment/Unicode directory, stays hidden and stops gracefully'
} finally {
    if ($job) { $job.Dispose() }
    if (Test-Path -LiteralPath $temp) {Write-Utf8 (Join-Path $temp 'stop.request') 'stop'}
    # A readiness assertion can fail before the test has read the independent PID.
    if (!$child -and $childScript) {
        $fixture = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {$_.CommandLine -like ('*' + $childScript + '*')} | Select-Object -First 1
        if ($fixture) {$child=Get-Process -Id $fixture.ProcessId -ErrorAction SilentlyContinue}
    }
    if ($child) {if (!$child.WaitForExit(5000)) {$child.Kill();$child.WaitForExit()};$child.Dispose()}
    if ($parent) {[void]$parent.WaitForExit(5000);$parent.Dispose()}
    $env:CODEX_BADGE_BACKGROUND_TEST = $oldMarker
    $resolved = [IO.Path]::GetFullPath($temp)
    Assert ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -like 'badge-background-*') 'cleanup must stay inside fixture root'
    if (Test-Path -LiteralPath $resolved) {Remove-Item -LiteralPath $resolved -Recurse -Force}
}
