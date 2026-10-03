# Pomodoro v1.0.0 — macOS & Windows

## Download / 下載

- **Apple Silicon Mac**: `Pomodoro-v1.0.0-macOS-arm64.zip` — macOS 26 or newer.
- **Intel Mac**: `Pomodoro-v1.0.0-macOS-x64.zip` — macOS 26 or newer.
- **Windows**: `Pomodoro-v1.0.0-Windows-x64.zip` — Windows 11 x64; extract and run `Pomodoro.exe`. No separate .NET install needed.
- `SHA256SUMS.txt` contains checksums for all three packages. GitHub's automatic source archives are source code, not installed apps.

## macOS

The full native Mac app: thirteen dial styles, floating compact mode over full-screen study apps,
pomodoro/countdown/stopwatch, history/statistics, sounds, hotkeys, and break overlay.
New: recover unfinished progress on relaunch, and small/medium/large compact sizes.
App identity stays `local.pomodoro.timer`; existing settings and history are preserved.

## Windows 實用版

Three timer modes, customizable durations, auto-continue, task labels, history/today totals,
classic floating dial, draggable small/medium/large compact window, sound and persistent visual alerts,
and unfinished-progress recovery. Only one dial style; no global hotkeys, break mask, or weekly charts.
User data is stored in `%LOCALAPPDATA%\PomodoroTimer`, independently of the program files.
Closing the app freezes progress; recovery never creates duplicate completed sessions.

## Installation and security

**Mac**: Extract the ZIP, drag `番茄鐘.app` to Applications and open it. The app is ad-hoc signed,
not Developer ID signed/notarized, so macOS may block its first launch. After verifying the download,
use System Settings → Privacy & Security → Open Anyway if available. Do not disable Gatekeeper.

**Windows**: Extract the entire ZIP and launch `Pomodoro.exe`. It is not Authenticode signed;
SmartScreen may warn. After checking the official source/checksum, use More info → Run anyway
if your system policy permits. Do not disable SmartScreen or Defender.

No personal settings, history, credentials, or smoke-test data are included in these packages.

## Verification boundaries

Built from one tagged commit on native Apple Silicon/Intel macOS and Windows runners.
Mac tests use isolated preferences and cover recovery, all thirteen dial styles at three sizes,
and synthetic drag events. Windows core tests cover timer transitions, persistence, recovery,
history, and corrupt/write-failed data; the packaged executable runs native WPF UI probes
for input, buttons, scaled layouts, synthetic DPI-aware drag, and settings scrolling.
These automated checks are not physical mouse testing on every user's computer.
Windows 11 x64 is the target; Windows hosted CI runs on Windows Server 2025.
Windows exclusive full-screen games, ARM, and older Windows versions are not certified.
Unexpected termination can lose the last approximately ten seconds since a checkpoint.
