param(
    [ValidateSet('run','install','uninstall','once','diagnose')]
    [string]$Action = 'run'
)

$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $base 'wallpapers.json'
$startup = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startup 'Auto Wallpaper.lnk'
$taskName = 'Auto Wallpaper'
$programs = [Environment]::GetFolderPath('Programs')
$hotkeyDir = Join-Path $programs 'Auto Wallpaper Hotkeys'

if ($Action -eq 'install') {
    $shell = New-Object -ComObject WScript.Shell
    Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue

    New-Item -ItemType Directory -Path $hotkeyDir -Force | Out-Null
    $displaySwitch = Join-Path $env:WINDIR 'System32\DisplaySwitch.exe'
    $hotkeys = @(
        @{ Name = '1 - PC screen only.lnk'; Arguments = '/internal'; Hotkey = 'CTRL+ALT+1' },
        @{ Name = '2 - Extend screens.lnk'; Arguments = '/extend'; Hotkey = 'CTRL+ALT+2' },
        @{ Name = '3 - Second screen only.lnk'; Arguments = '/external'; Hotkey = 'CTRL+ALT+3' }
    )
    foreach ($item in $hotkeys) {
        $hotkeyShortcut = $shell.CreateShortcut((Join-Path $hotkeyDir $item.Name))
        $hotkeyShortcut.TargetPath = $displaySwitch
        $hotkeyShortcut.Arguments = $item.Arguments
        $hotkeyShortcut.Hotkey = $item.Hotkey
        $hotkeyShortcut.WindowStyle = 7
        $hotkeyShortcut.Save()
    }
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*AutoWallpaper.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $powershell = (Get-Command powershell.exe).Source
    $arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" -Action run"
    $taskAction = New-ScheduledTaskAction -Execute $powershell -Argument $arguments -WorkingDirectory $base
    $taskTrigger = New-ScheduledTaskTrigger -AtLogOn -User ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
    $taskTrigger.Delay = 'PT20S'
    $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -MultipleInstances IgnoreNew
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -Principal $taskPrincipal -Description 'Automatic wallpaper switcher for one or two active monitors.' -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Write-Host "Scheduled task enabled: $taskName"
    exit
}

if ($Action -eq 'uninstall') {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $hotkeyDir -Recurse -Force -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*AutoWallpaper.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Write-Host 'Autostart disabled.'
    exit
}

if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Config file not found: $configPath"
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public enum DesktopWallpaperPosition { Center, Tile, Stretch, Fit, Fill, Span }

[ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDesktopWallpaper {
    void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID, [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
    [return: MarshalAs(UnmanagedType.LPWStr)] string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
    [return: MarshalAs(UnmanagedType.LPWStr)] string GetMonitorDevicePathAt(uint monitorIndex);
    uint GetMonitorDevicePathCount();
    void GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorID, out RECT displayRect);
    void SetBackgroundColor(uint color);
    uint GetBackgroundColor();
    void SetPosition(DesktopWallpaperPosition position);
    DesktopWallpaperPosition GetPosition();
    void SetSlideshow(IntPtr items);
    IntPtr GetSlideshow();
    void SetSlideshowOptions(uint options, uint slideshowTick);
    void GetSlideshowOptions(out uint options, out uint slideshowTick);
    void AdvanceSlideshow([MarshalAs(UnmanagedType.LPWStr)] string monitorID, uint direction);
    uint GetStatus();
    bool Enable(bool enable);
}

[StructLayout(LayoutKind.Sequential)]
public struct RECT { public int Left, Top, Right, Bottom; }

public static class WallpaperApi {
    private delegate bool MonitorEnumProc(IntPtr monitor, IntPtr dc, IntPtr rect, IntPtr data);

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonitorEnumProc callback, IntPtr data);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SystemParametersInfo(uint action, uint param, string value, uint flags);

    private const uint SPI_SETDESKWALLPAPER = 0x0014;
    private const uint SPIF_UPDATEINIFILE = 0x0001;
    private const uint SPIF_SENDCHANGE = 0x0002;

    private static List<RECT> GetActiveMonitorRects() {
        var rects = new List<RECT>();
        MonitorEnumProc callback = delegate(IntPtr monitor, IntPtr dc, IntPtr rect, IntPtr data) {
            rects.Add((RECT)Marshal.PtrToStructure(rect, typeof(RECT)));
            return true;
        };
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero);
        return rects;
    }

    private static int GetActiveMonitorCount() {
        return GetActiveMonitorRects().Count;
    }

    public static string GetActiveState() {
        var rects = GetActiveMonitorRects();
        if (rects.Count <= 1)
            return "1|global";

        rects.Sort((a, b) => {
            int byLeft = a.Left.CompareTo(b.Left);
            if (byLeft != 0) return byLeft;
            return a.Top.CompareTo(b.Top);
        });

        var signature = new System.Text.StringBuilder(rects.Count.ToString());
        foreach (var rect in rects)
            signature.Append("|")
                .Append(rect.Left).Append(",")
                .Append(rect.Top).Append(",")
                .Append(rect.Right).Append(",")
                .Append(rect.Bottom);
        return signature.ToString();
    }

    private static IDesktopWallpaper Create() {
        var type = Type.GetTypeFromCLSID(new Guid("C2CF3110-460E-4FC1-B9D0-8A1C0C9CC4BD"));
        return (IDesktopWallpaper)Activator.CreateInstance(type);
    }

    public static string Apply(string single, string left, string right) {
        int activeCount = GetActiveMonitorCount();
        if (activeCount <= 1) {
            if (!SystemParametersInfo(SPI_SETDESKWALLPAPER, 0, single,
                SPIF_UPDATEINIFILE | SPIF_SENDCHANGE))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            return "1|global";
        }

        IDesktopWallpaper desktop = Create();
        try {
            uint count = desktop.GetMonitorDevicePathCount();
            var monitors = new List<MonitorInfo>();
            for (uint i = 0; i < count; i++) {
                string id = desktop.GetMonitorDevicePathAt(i);
                RECT rect;
                desktop.GetMonitorRECT(id, out rect);
                monitors.Add(new MonitorInfo { Id = id, Left = rect.Left });
            }
            monitors.Sort((a, b) => a.Left.CompareTo(b.Left));

            if (monitors.Count >= 2) {
                desktop.SetWallpaper(monitors[0].Id, left);
                desktop.SetWallpaper(monitors[monitors.Count - 1].Id, right);
                for (int i = 1; i < monitors.Count - 1; i++)
                    desktop.SetWallpaper(monitors[i].Id, right);
            }

            var signature = new System.Text.StringBuilder(activeCount.ToString());
            foreach (var monitor in monitors)
                signature.Append("|").Append(monitor.Id).Append("@").Append(monitor.Left);
            return signature.ToString();
        }
        finally {
            Marshal.ReleaseComObject(desktop);
        }
    }

    private class MonitorInfo {
        public string Id;
        public int Left;
    }
}
'@

function Resolve-Image([string]$path) {
    if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $base $path }
    $resolved = (Resolve-Path -LiteralPath $path).Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Image not found: $resolved" }
    return $resolved
}

$single = Resolve-Image $config.single
$leftImage = Resolve-Image $config.dual.left
$rightImage = Resolve-Image $config.dual.right
$lastSignature = ''

function Set-ForCurrentMonitors {
    $signature = [WallpaperApi]::GetActiveState()
    if ($signature -ne $script:lastSignature) {
        [WallpaperApi]::Apply($single, $leftImage, $rightImage) | Out-Null
        $script:lastSignature = $signature
        return "$signature applied"
    }
    return "$signature unchanged"
}

if ($Action -eq 'once') {
    Set-ForCurrentMonitors | Out-Null
    exit
}

# Keep retrying because Explorer and the desktop COM service may not be ready
# yet when Windows starts this script from the Startup folder.
while ($true) {
    try {
        $currentSignature = Set-ForCurrentMonitors
        if ($Action -eq 'diagnose') {
            Write-Host "$(Get-Date -Format T) active state: $currentSignature"
        }
    }
    catch {
        Add-Content -LiteralPath (Join-Path $base 'AutoWallpaper.log') -Value "$(Get-Date -Format s) $($_.Exception.Message)"
        if ($Action -eq 'diagnose') {
            Write-Host "$(Get-Date -Format T) ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Start-Sleep -Seconds ([Math]::Max(2, [int]$config.checkEverySeconds))
}
