# cc3x3 - tile Windows Terminal windows into a screen grid and launch Claude Code in each.
#
# Dot-source this from your PowerShell $PROFILE:  . "C:\path\to\cc3x3\cc.ps1"
# Then in any Terminal window type `cc` to snap it into a free grid cell and start Claude.
#
# Functions: cc (tile this window + launch), ccgrid (re-tile every window),
#            cczoom (set the base font size), ccsnap (the 2x2 Windows-snap dance).

# --- config: edit to taste ---------------------------------------------------
# 3-column grids (3x2, 3x3) span this fraction of the work area, centered, so strips
# stay free on both sides for a browser or notes. 2x2 uses the full width (the four corners).
$CcWidth  = @{ 3 = 0.92; 2 = 1 }

# What each new cc window runs. Change it to your own command if you are not using Claude Code.
$CcLaunch = 'claude --dangerously-skip-permissions'

# Base Terminal font size (the zoom new windows open at). Laptops get the larger size so a
# 3x3 cell stays readable on a small screen; desktops get the smaller one. cczoom detects a
# laptop by the presence of a battery, so it just works on any machine; tweak the numbers here.
$CcFont   = @{ laptop = 10; desktop = 7 }
# -----------------------------------------------------------------------------

$CcSource = @'
using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;

public static class CcTile {
    struct RECT { public int L, T, R, B; }
    struct MONITORINFO { public int cbSize; public RECT rcMonitor, rcWork; public int dwFlags; }
    delegate bool EnumProc(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr p);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hgt, uint flags);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr m, ref MONITORINFO mi);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint flags);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT r, int size);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int v, int size);
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int v, int size);

    static bool IsTerminal(IntPtr h) { var s = new StringBuilder(64); GetClassName(h, s, 64); return s.ToString() == "CASCADIA_HOSTING_WINDOW_CLASS"; }
    // Visible frame, without the invisible resize borders GetWindowRect includes.
    static RECT Frame(IntPtr h) { RECT r; if (DwmGetWindowAttribute(h, 9, out r, 16) != 0) GetWindowRect(h, out r); return r; }
    static RECT Work(IntPtr h) {
        var mi = new MONITORINFO { cbSize = Marshal.SizeOf(typeof(MONITORINFO)) };
        GetMonitorInfo(MonitorFromWindow(h, 2), ref mi);
        return mi.rcWork;
    }
    // Per-monitor v2 for the call, so all numbers are physical pixels.
    static T Dpi<T>(Func<T> f) {
        IntPtr old = SetThreadDpiAwarenessContext((IntPtr)(-4));
        try { return f(); } finally { SetThreadDpiAwarenessContext(old); }
    }

    // Terminal 1.24 makes its window the owner of the hidden console window.
    public static IntPtr Self() { return GetAncestor(GetConsoleWindow(), 3); }

    static void Key(byte vk, bool up) { keybd_event(vk, 0, up ? 2u : 0u, UIntPtr.Zero); }
    public static void Escape() { Key(0x1B, false); Key(0x1B, true); }
    // Opens Windows' Snap Layouts menu (Win+Z) on h. The Alt tap lets a background process take focus.
    public static void SnapMenu(IntPtr h) {
        Key(0x12, false); Key(0x12, true); SetForegroundWindow(h);
        System.Threading.Thread.Sleep(200);
        Key(0x5B, false); Key(0x5A, false); Key(0x5A, true); Key(0x5B, true);
    }

    // Terminal windows on this virtual desktop that can sit in the grid: visible, not minimized or maximized.
    // One monitor is assumed; terminals on a second screen would be pulled into this grid.
    static List<IntPtr> Others(IntPtr self) {
        var l = new List<IntPtr>();
        EnumWindows((w, p) => {
            int cloaked; // cloaked = on another virtual desktop
            if (w != self && IsWindowVisible(w) && !IsIconic(w) && !IsZoomed(w) && IsTerminal(w)
                && (DwmGetWindowAttribute(w, 14, out cloaked, 4) != 0 || cloaked == 0)) l.Add(w);
            return true;
        }, IntPtr.Zero);
        return l;
    }

    class Grid {
        int x, y, w, h, cols, rows;
        public Grid(RECT wa, int cols, int rows, double widthFrac) {
            this.cols = cols; this.rows = rows;
            w = (int)((wa.R - wa.L) * widthFrac) / cols; h = (wa.B - wa.T) / rows;
            x = wa.L + (wa.R - wa.L - w * cols) / 2; y = wa.T;
        }
        public int CellOf(RECT r) {
            int cx = (r.L + r.R) / 2 - x, cy = (r.T + r.B) / 2 - y;
            return cx < 0 || cy < 0 || cx >= w * cols || cy >= h * rows ? -1 : cy / h * cols + cx / w;
        }
        public void Place(IntPtr win, int cell) {
            RECT wr, fr = Frame(win);
            GetWindowRect(win, out wr);
            int px = x + cell % cols * w, py = y + cell / cols * h;
            SetWindowPos(win, IntPtr.Zero, px - (fr.L - wr.L), py - (fr.T - wr.T),
                w + (fr.L - wr.L) + (wr.R - fr.R), h + (fr.T - wr.T) + (wr.B - fr.B), 0x14); // NOZORDER | NOACTIVATE
            // Square corners, like a snapped window. A plain move leaves Windows 11's rounded corners, so force
            // DWMWCP_DONOTROUND; without this the 3x2/3x3 grids look rounded while the 2x2 snap looks square.
            int square = 1; DwmSetWindowAttribute(win, 33, ref square, 4); // DWMWA_WINDOW_CORNER_PREFERENCE = DONOTROUND
        }
    }

    // Layout on screen: 2x2 when another terminal fills a screen quarter, 3x3 when one is a 3-row cell tall, else 3x2.
    public static string Layout(IntPtr self) {
        return Dpi(() => {
            var fw = Others(self).Select(o => new { f = Frame(o), wa = Work(o) }).ToList();
            if (fw.Any(x => Math.Abs((x.f.R - x.f.L) * 2 - (x.wa.R - x.wa.L)) < 8
                         && Math.Abs((x.f.B - x.f.T) * 2 - (x.wa.B - x.wa.T)) < 8)) return "2x2";
            return fw.Any(x => (x.f.B - x.f.T) * 12 < (x.wa.B - x.wa.T) * 5) ? "3x3" : "3x2";
        });
    }

    // Moves the other terminals into a cols x rows grid in reading order, leaving `reserve` cells free after them.
    // Returns how many terminals must close first when they do not fit, else 0 (nothing moves in that case).
    // Placed holds the moved windows in cell order, for ccsnap.
    public static IntPtr[] Placed = new IntPtr[0];
    public static int Relayout(IntPtr self, int cols, int rows, double widthFrac, int reserve) {
        Placed = new IntPtr[0];
        return Dpi(() => {
            var ws = Others(self);
            int extra = ws.Count + reserve - cols * rows;
            if (extra > 0) return extra;
            if (ws.Count == 0) return 0;
            RECT wa = Work(self == IntPtr.Zero ? ws[0] : self);
            var g = new Grid(wa, cols, rows, widthFrac);
            int band = (wa.B - wa.T) / 3; // thirds of the screen fit both layouts, so rows keep their order
            var order = ws.OrderBy(o => { RECT f = Frame(o); return ((f.T + f.B) / 2 - wa.T) / band; })
                          .ThenBy(o => { RECT f = Frame(o); return f.L + f.R; }).ToList();
            for (int i = 0; i < order.Count; i++) g.Place(order[i], i);
            Placed = order.ToArray();
            return 0;
        });
    }

    // Keeps h in the cell under its center if that cell is free, else moves it to the first free cell.
    // Returns the cell index, -1 when the grid is full, -2 when h is not a Terminal window.
    public static int Tile(IntPtr h, int cols, int rows, double widthFrac) {
        if (!IsTerminal(h)) return -2;
        return Dpi(() => {
            var g = new Grid(Work(h), cols, rows, widthFrac);
            var taken = new bool[cols * rows];
            foreach (var o in Others(h)) { int c = g.CellOf(Frame(o)); if (c >= 0) taken[c] = true; }
            if (IsZoomed(h)) ShowWindow(h, 9);
            int cell = g.CellOf(Frame(h));
            if (cell < 0 || taken[cell]) cell = Array.IndexOf(taken, false);
            if (cell < 0) return -1;
            g.Place(h, cell);
            return cell;
        });
    }
}
'@

# Moves every terminal except $Self into $Layout (default: the layout on screen), keeping $Reserve cells free.
# Returns how many must close first, else 0.
function ccgrid([ValidatePattern('^(3x[23]|2x2)$')][string]$Layout, [int]$Reserve = 0, [IntPtr]$Self = [IntPtr]::Zero) {
    if (-not ('CcTile' -as [type])) { Add-Type -TypeDefinition $CcSource }
    if (-not $Layout) { $Layout = [CcTile]::Layout($Self) }
    $cols = [int]"$($Layout[0])"
    $close = [CcTile]::Relayout($Self, $cols, [int]"$($Layout[-1])", $CcWidth[$cols], $Reserve)
    # cc snaps the moved windows together with its own; from anywhere else snap them here.
    if (-not $close -and $cols -eq 2 -and $Self -eq [IntPtr]::Zero -and [CcTile]::Placed.Count) { ccsnap ([CcTile]::Placed) }
    $close
}

# 2x2 uses Windows' own snap, so the windows get square corners and form a snap group: Win+Z puts the first of
# $Wins in quarter $Cell (0 top left .. 3 bottom right), then Snap Assist is handed each next window by title.
function ccsnap([IntPtr[]]$Wins, [int]$Cell = 0) {
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
    $A = [Windows.Automation.AutomationElement]; $in = [Windows.Automation.TreeScope]; $all = [Windows.Automation.Condition]::TrueCondition
    $named = { param($n) [Windows.Automation.PropertyCondition]::new($A::NameProperty, $n) }
    $listItem = [Windows.Automation.PropertyCondition]::new($A::ControlTypeProperty, [Windows.Automation.ControlType]::ListItem)
    $assist = { $A::RootElement.FindFirst($in::Children, (& $named 'Snap Assist')) }
    $wait = { param($f) for ($t = 0; $t -lt 20; $t++) { $r = & $f; if ($r) { return $r }; Start-Sleep -Milliseconds 100 } }
    $invoke = { param($e) $e.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke() }
    $zones = 'Top left quarter', 'Top right quarter', 'Bottom left quarter', 'Bottom right quarter'
    for ($i = 0; $i -lt $Wins.Count; $i++, $Cell++) {
        $sa = if ($i) { & $wait $assist } else { & $assist }
        $title = $A::FromHandle($Wins[$i]).Current.Name -replace '^\W\s'   # Claude prefixes a spinner that keeps changing
        $item = if ($sa) { $sa.FindAll($in::Descendants, $listItem) | Where-Object { $_.Current.Name.EndsWith($title) } | Select-Object -First 1 }
        if ($item) { & $invoke $item; continue }
        if ($sa) { [CcTile]::Escape(); Start-Sleep -Milliseconds 200 }
        [CcTile]::SnapMenu($Wins[$i])
        $menu = & $wait { $f = $A::FocusedElement; if ($f.Current.Name -eq 'Snap Layouts Menu') { $f } }
        if (-not $menu) { Write-Host 'cc: Snap Layouts menu did not open'; return }
        $grid = $menu.FindFirst($in::Descendants, (& $named '4 window grid layout'))
        & $invoke ($grid.FindAll($in::Children, $all) | Where-Object { $_.Current.Name.StartsWith($zones[$Cell]) })
    }
    # Snap Assist stays up while quarters are empty.
    if ($Cell -lt 4 -and (& $wait $assist)) { [CcTile]::Escape() }
}

# Sets the Windows Terminal profile's base font size (the zoom new windows open at) to this machine's default
# plus $Delta, one step per press of Ctrl + + or Ctrl + -. The default is $CcFont.laptop on a machine with a
# battery, else $CcFont.desktop. Open windows keep their own Ctrl +/- until Ctrl+0 drops them to the new base.
function cczoom([int]$Delta = 0) {
    $isLaptop = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    $default  = if ($isLaptop) { $CcFont.laptop } else { $CcFont.desktop }
    $size = [Math]::Max(1, $default + $Delta)
    $f = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (-not (Test-Path $f)) { Write-Host "cc: Terminal settings.json not found at $f"; return }
    $raw = Get-Content $f -Raw
    # Replace the PowerShell profile's font size in place when it is the only explicit size in the file, so the
    # rest stays byte-for-byte. Fall back to a JSON edit of the PowerShell Core profile otherwise.
    if (([regex]::Matches($raw, '"size"\s*:')).Count -eq 1) {
        $raw = [regex]::Replace($raw, '("size"\s*:\s*)\d+', "`${1}$size")
        Set-Content $f -Value $raw -NoNewline -Encoding utf8
    } else {
        $j = $raw | ConvertFrom-Json
        $p = $j.profiles.list | Where-Object source -eq 'Windows.Terminal.PowershellCore' | Select-Object -First 1
        if (-not $p) { Write-Host 'cc: no PowerShell Core profile in settings.json'; return }
        if (-not $p.font) { $p | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{}) -Force }
        $p.font | Add-Member -NotePropertyName size -NotePropertyValue $size -Force
        $j | ConvertTo-Json -Depth 32 | Set-Content $f -Encoding utf8
    }
    "cc zoom: font size $size (default $default, $(if ($isLaptop) { 'laptop' } else { 'desktop' })). Ctrl+0 in open windows to pick it up."
}

# Typed in a Terminal window: snap this window into the grid, then run $CcLaunch.
#   cc              tile into the layout on screen and launch
#   cc 3x3 | 3x2 | 2x2   move every terminal into that layout first, then tile and launch
#   cc z-2 | z0 | z2     set the zoom (default -/+ N); `cc z-2` alone only zooms, no new window
# Trailing arguments pass through to $CcLaunch, e.g. `cc 3x3 --model opus`.
function cc {
    if (-not ('CcTile' -as [type])) { Add-Type -TypeDefinition $CcSource }
    $a = @($args)
    if ($a.Count -and $a[0] -match '^z(-?\d+)$') {
        cczoom ([int]$Matches[1]); $a = @($a | Select-Object -Skip 1)
        if (-not $a.Count) { return }   # zoom only, no new window
    }
    $self = [CcTile]::Self(); $rest = $a; $moved = @()
    if ($a.Count -and $a[0] -match '^(3x[23]|2x2)$') {
        $layout = $a[0]; $rest = @($a | Select-Object -Skip 1)
        $close = ccgrid $layout 1 $self
        if ($close) { Write-Host "cc: too many terminals for $layout, close $close first"; return }
        $moved = [CcTile]::Placed
    } else { $layout = [CcTile]::Layout($self) }
    $cols = [int]"$($layout[0])"
    $cell = [CcTile]::Tile($self, $cols, [int]"$($layout[-1])", $CcWidth[$cols])
    if ($cell -eq -1) { Write-Host 'cc: grid full, window left where it is' }
    elseif ($cols -eq 2) { if ($moved.Count) { ccsnap (@($moved) + $self) } else { ccsnap $self $cell } }
    $exe, $cargs = -split $CcLaunch
    & $exe @cargs @rest
}
