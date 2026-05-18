# Settings Open Profiling (Time Profiler + Points of Interest)

This workflow captures all three diagnostics together:

1. Time Profiler call tree for Settings open.
2. Signpost timing for `SettingsOpen`, `VideoSettingsTabOpened`, and `MicrophoneEnumeration`.
3. Exported `xctrace` data you can share in text form.

## 1) Preferred: run the script

```bash
cd /Users/jamesmontemagno/Projects/tiny-clips-mac
./scripts/profile-settings-open.sh
```

This script builds `TinyClips`, records a Time Profiler session, triggers Settings with `Cmd+,`, and exports:
- `tinyclips-settings-<timestamp>.timeprof.trace`
- `tinyclips-settings-<timestamp>.toc.xml`
- `tinyclips-settings-<timestamp>.signposts.xml`

## 2) Manual build + record (if you prefer CLI steps)

```bash
cd /Users/jamesmontemagno/Projects/tiny-clips-mac
xcodebuild build -project TinyClips.xcodeproj -scheme TinyClips -configuration Debug
```

## 3) Record trace from CLI

Resolve a single built app path first, then pass that concrete path to `xctrace`.

```bash
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path '*/Build/Products/Debug/TinyClips.app' -print -quit)
xcrun xctrace record --template "Time Profiler" --time-limit 25s --output ~/Desktop/tinyclips-settings.timeprof.trace --launch -- "$APP_PATH"
```

During each run:
- Open Settings.
- Wait until it settles.
- Click the Video tab once.

## 4) Export trace output

Export available runs and instrument metadata.

```bash
xcrun xctrace export --input ~/Desktop/tinyclips-settings.timeprof.trace --toc
```

Export table metadata including signpost schema details.

```bash
xcrun xctrace export --input ~/Desktop/tinyclips-settings.timeprof.trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]' > ~/Desktop/tinyclips-settings.signposts.xml
```

Optional: quickly check for your signpost names.

```bash
grep -n "SettingsOpen\|VideoSettingsTabOpened\|MicrophoneEnumeration" ~/Desktop/tinyclips-settings.signposts.xml
```
