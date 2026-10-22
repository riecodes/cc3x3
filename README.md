# cc3x3

![License](https://img.shields.io/github/license/riecodes/cc3x3?style=flat-square&color=green) ![Windows 11](https://img.shields.io/badge/Windows-11-0078D6?style=flat-square&logo=windows&logoColor=white) ![PowerShell 7](https://img.shields.io/badge/PowerShell-7-5391FE?style=flat-square&logo=powershell&logoColor=white) ![Claude Code](https://img.shields.io/badge/Claude%20Code-launcher-D97757?style=flat-square&logo=anthropic&logoColor=white)

Tile Windows Terminal windows into a screen grid and launch [Claude Code](https://claude.com/claude-code) in each one with a single command.

Type `cc` in any Terminal window and it snaps itself into a free cell of a grid, then starts Claude. Run it in a few windows and you get a clean 3x2 or 3x3 wall of agents, or the four screen corners (2x2). Corners are squared, side strips are left free for a browser, and a zoom helper keeps the text readable on both a laptop and a desktop.

```
cc            # tile this window into the grid on screen, launch Claude
cc 3x3        # move every terminal into a 3x3 grid first, then tile and launch
cc 3x2        # 3 columns, 2 rows (the default)
cc 2x2        # the four screen corners, snapped by Windows (square corners, one snap group)
cc z-2        # zoom out two steps (base font size); z0 resets, z2 zooms in. Alone, it only zooms.
cc 3x3 --model opus   # trailing args pass through to the launch command
```

## Setup (once)

### One prompt

Open your agent in any folder (for example `claude` in a terminal) and paste:

```text
Set up cc3x3 for me. Clone https://github.com/riecodes/cc3x3.git into my Documents folder
(install Git and PowerShell 7 first if either is missing, after asking me). Then run
pwsh -File cc3x3\install.ps1 to add it to my PowerShell profile. When you finish, tell me to
open a new Windows Terminal window and that typing cc tiles it into the grid and starts Claude
Code, with cc 3x3 / cc 2x2 for layouts and cc z-2 / cc z2 for zoom.
```

### Step by step

1. **Get it.** `git clone https://github.com/riecodes/cc3x3.git`, or use *Code > Download ZIP* on GitHub and unzip it.
2. **Install.** `pwsh -File cc3x3\install.ps1` appends a dot-source line to your `$PROFILE`. Or add it yourself to `$PROFILE` (`~\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`):

   ```powershell
   . "C:\path\to\cc3x3\cc.ps1"
   ```
3. **Use it.** Open a new Terminal window (or run `. $PROFILE`) and type `cc`.

## Requirements

- **Windows 11** (uses the rounded-corner and Snap Layouts APIs)
- **Windows Terminal**
- **PowerShell 7** (`pwsh`)
- **Claude Code** on `PATH` (`claude`), or change the launch command in the config (see below)

## Config

Edit the block at the top of `cc.ps1`:

| Setting | Default | What it does |
| --- | --- | --- |
| `$CcWidth[3]` | `0.92` | Fraction of the work area the 3-column grids span (the rest is side strips). Lower it for wider strips. |
| `$CcLaunch` | `claude --dangerously-skip-permissions` | The command each `cc` window runs. Change it for a different tool or flags. |
| `$CcFont.laptop` / `$CcFont.desktop` | `10` / `7` | Base Terminal font size per machine. `cczoom` detects a laptop by the presence of a battery and picks the right one, so the same config works on every machine. |

> `--dangerously-skip-permissions` is included because the point is unattended parallel agents. Drop it from `$CcLaunch` if you want Claude to ask first.

## Commands

- **`cc [layout] [zN] [args...]`** - tile this window and launch. A leading `3x3`/`3x2`/`2x2` re-tiles every window into that layout first; a leading `zN` sets the zoom; the rest passes through to the launch command.
- **`ccgrid [layout]`** - re-tile every terminal into a layout (defaults to the one on screen, which snaps dragged windows back). Returns how many windows must close first when they do not fit, and then moves nothing. From outside a Terminal: `pwsh -c ". $PROFILE; ccgrid 3x3"`.
- **`cczoom [N]`** - set the Terminal base font size to the machine default + N. Open windows keep their own `Ctrl +`/`Ctrl -` until `Ctrl 0` drops them to the new base; new windows get it at once.

## How it works

The grid math and window moving live in a small C# type (`CcTile`) compiled on first use. It finds Terminal windows by class name, reads their true frames with DWM (so the invisible resize borders do not throw off the math), is per-monitor-DPI aware, and moves windows with `SetWindowPos`. 3x2/3x3 are plain moves with corners forced square (`DWMWA_WINDOW_CORNER_PREFERENCE`); 2x2 drives the real Windows Snap Layouts menu over UI Automation so the windows snap into a group. One monitor is assumed.

## Limitations

- Windows 11 only (the corner and snap APIs).
- Single monitor; terminals on a second screen would be pulled into the grid.
- The 2x2 snap briefly takes focus (it sends `Win+Z` and clicks the menu), about 3 seconds.
- Tuned for Windows Terminal specifically (`CASCADIA_HOSTING_WINDOW_CLASS`).

## License

MIT - see [LICENSE](LICENSE).
