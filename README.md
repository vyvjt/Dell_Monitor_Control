# Alienware monitor Control

A tray-resident control panel for the Dell Alienware monitor on Windows. It talks to the monitor over the native DDC/CI interface (the same Monitor Configuration API that ControlMyMonitor and Twinkle Tray use) and mirrors the look of the Windows 11 brightness flyout.

<img width="380" height="205" alt="image" src="https://github.com/user-attachments/assets/6a31fbcd-7a2a-477f-8e8f-e17744216cbe" />

## Run it

Double-click `Start-AW2521HFL-Control.cmd`. No install, no administrator rights.

A monitor icon appears in the system tray:

- **Left-click** opens the panel (click again, press Esc, or click elsewhere to dismiss it).
- **Right-click** gives Open, Standard, ComfortView, Toggle and Quit.

Windows 11 hides new tray icons in the overflow flyout by default. To pin it to the taskbar, click the chevron (`^`) and drag the icon out, or go to Settings → Personalization → Taskbar → Other system tray icons and switch it on.

Starting a second copy re-opens the panel of the one already running instead of launching another process.

DDC/CI must be enabled in the monitor's OSD menu. Some docks, KVM switches, capture devices and remote-desktop sessions block it.

## Shortcut key

The default is **Ctrl+Alt+F9**, and it flips between Standard and ComfortView from anywhere, including while the panel is hidden. It shows a brief tray balloon so you know which mode you landed in.

To change it, open the panel, click the gear, click the shortcut box, and press the combination you want. It needs at least one of Ctrl, Alt, Shift or Win, or a bare function key. If another program already owns the combination, the panel says so instead of failing silently. The checkbox beside it turns the shortcut off.

## Controls

- Brightness uses VCP code `0x10` and scales to whatever maximum the monitor reports.
- The mouse wheel changes brightness by 3% per notch. The hit area is a padded transparent strip around the slider, not just the 20px control, so the wheel is easy to catch.
- Standard sends `0x14=5` plus `F0=0, E3=0, E2=0`.
- ComfortView sends `F0=12, E3=29, E2=29`.

The highlighted mode is the last one applied, saved across restarts. The panel does not read `0xF0` back — that extra DDC transaction is not needed and the working core does not do it.

All five register values stay editable under the gear, in decimal or `0x` hex, for different monitor firmware.

Settings (shortcut, register values, last display) live in `%APPDATA%\AW2521HFL-Control\settings.json`. Delete that file to go back to defaults.

## Start with Windows

The gear panel has a **Start with Windows** checkbox. It writes a normal shortcut into your Startup folder — no registry keys, no scheduled task, no service — and launches to the tray without opening the panel. Unchecking it deletes the shortcut. **Create desktop shortcut** puts one on the desktop that opens the panel directly; you can pin that to the taskbar or Start.

## Memory use

Everything runs in a single `powershell.exe` process. There are no polling timers: the panel only talks to the monitor when you open it or change something, and the one timer in the script runs for 120 ms after a slider move to coalesce writes. When the panel hides, the script collects and asks Windows to trim the working set, which typically drops it to roughly 10–25 MB resident. Committed memory stays higher because of the .NET and WPF runtime — that is the floor for any WPF-based tool, and the only way materially below it is a compiled C# tray app with no WPF.

## Troubleshooting

`Start-AW2521HFL-Control.cmd debug` runs it in a visible console so errors are readable. Unhandled failures are also written to `%APPDATA%\AW2521HFL-Control\last-error.log`.

## A note on the DDC/CI core

The block marked `DDC/CI CORE` is copied verbatim from the version that works. An earlier rewrite added handle-validity guards to `TryGet`/`TrySet` and re-enumerated the monitors every time the panel opened; the guards then rejected calls before they reached `dxva2.dll`, which produced "did not respond to the brightness query" and "could not be applied to all requested registers" while nothing was actually wrong with the monitor. Physical monitor handles are now acquired once at startup and released only at exit. If you change anything in that block, expect those errors back.

## Notes

This is a focused utility for one monitor, not a replacement for ControlMyMonitor. It makes no permanent monitor configuration changes beyond the values you choose, and no permanent Windows changes beyond the optional startup shortcut and its settings file.
