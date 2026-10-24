# Sound Recorder

A small macOS app (SwiftUI, macOS 15+) that records system audio, a microphone, or both mixed, to WAV
with ScreenCaptureKit. No virtual audio driver needed. English and Vietnamese UI with an in-app switch.

The `sysaudio-record` CLI uses the same capture engine (`Sources/Engine/CaptureEngine.swift`).

## Build and install

Needs only the Xcode Command Line Tools.

```sh
make install       # builds, signs and installs ~/Applications/Sound Recorder.app
make install-cli   # builds and installs ~/.local/bin/sysaudio-record
```

The app is signed with the stable self-signed identity `Que Huong Studio Signing` (override with
`make install IDENTITY=...`), so macOS keeps its permissions across rebuilds. Without that identity it
falls back to ad-hoc signing and the permissions must be granted again after each build.

## Permissions

Turn on **Sound Recorder** in System Settings → Privacy & Security → **Screen & System Audio Recording**
(needed for every source), and under **Microphone** to record the mic. The app shows a notice with a
button to the right settings pane when one is missing.

## Output

48 kHz stereo WAV, straight from ScreenCaptureKit with no resampling or processing. Formats: 32-bit float
(default, keeps headroom), 24-bit or 16-bit PCM (samples above full scale are clipped and counted).
Files go to `~/Music/Sound Recorder/` as `Sound Recorder 2026-10-24 23-30-05.wav`; the folder, format,
source, microphone, language and an optional "stop after" duration are remembered.

## CLI

```sh
sysaudio-record out.wav [--duration SECONDS] [--app BUNDLE_ID] [--source system|mic|both] [--format 16|24|f32]
```

Defaults: all system audio, 16-bit PCM, until Ctrl-C. `--app` records one app and its helper processes.
