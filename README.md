# Garmin Sample — Connect IQ watch-app

Two-page data app for Connect IQ. Page 1: steps, distance, calories, step-goal bar.
Page 2: heart rate, battery, memory. Clock in the header, 1 Hz redraw while visible.
UP / DOWN / START change pages.

## Layout

```
manifest.xml                        app id, type, target products, min API level
monkey.jungle                       build config
source/GarminSampleApp.mc           AppBase entry point
source/GarminSampleView.mc          rendering + refresh timer
source/GarminSampleDelegate.mc      button/swipe handling
resources/strings.xml               localized strings
resources/drawables/                launcher icon
```

## Build

```bash
export CIQ_SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"

# Compile (-l 3 = strict type check)
"$CIQ_SDK/bin/monkeyc" -d fenix6pro -f monkey.jungle -o GarminSample.prg -y developer_key.der -l 3
```

## Run

```bash
# 1. Start the simulator (leave it running)
"$CIQ_SDK/bin/connectiq"

# 2. Side-load the built app into it
"$CIQ_SDK/bin/monkeydo" GarminSample.prg fenix6pro
```

## Package for the store

```bash
"$CIQ_SDK/bin/monkeyc" -e -f monkey.jungle -o GarminSample.iq -y developer_key.der -l 3
```

`-e` builds for every product listed in `manifest.xml`.

## Notes

- `developer_key.der` is the signing key. Keep it out of version control.
- Targets installed in the simulator: `ls "$HOME/Library/Application Support/Garmin/ConnectIQ/Devices"`.
- `main.mc.bak` is the original stub, superseded by `source/`. Safe to delete.
