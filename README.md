<p align="center">
  <img src="Resources/AppIcon.png" alt="materialTun logo" width="128" />
</p>

<h1 align="center">materialTun</h1>

<p align="center">
  <img src="https://img.shields.io/badge/lang-Swift-purple?style=for-the-badge" alt="Swift">
  <img src="https://img.shields.io/badge/for--purple?style=for-the-badge" alt="macOS">
  <img src="https://img.shields.io/badge/lang-RU | ENG-purple?style=for-the-badge" alt="Languages">
</p>

## What It Does

- Imports proxy profiles from links, files, clipboard text, subscriptions, and QR images.
- Supports VLESS, VMess, Trojan, Shadowsocks, SOCKS, HTTP, Hysteria2, TUIC, WireGuard, AnyTLS, and raw Xray JSON.
- Runs Xray for classic proxy protocols.
- Runs sing-box for TUN mode and sing-box-backed protocols.
- Provides System Proxy and TUN connection modes.
- Includes routing, DNS, Geo file, subscription refresh, backup/restore, diagnostics, and workspace controls.
- Includes a menu bar controller for quick connect/disconnect and profile switching.

## Requirements

- macOS 14 or newer.
- Swift 6 / Xcode command line tools.
- Xray, sing-box, `geoip.dat`, and `geosite.dat` available in the expected build layout.
- Administrator permission for first-time TUN helper installation.

The build script copies runtime assets from:

```text
/tmp/happ-dmg/Happ.app/Contents/MacOS/core/xray
/tmp/happ-dmg/Happ.app/Contents/MacOS/tun/sing-box
/tmp/happ-dmg/Happ.app/Contents/Resources/geoip.dat
/tmp/happ-dmg/Happ.app/Contents/Resources/geosite.dat
```

## Project Layout

```text
.
├── App/
│   └── Info.plist
├── Resources/
│   └── AppIcon.svg
├── Sources/
│   ├── materialTun/
│   │   ├── CompactUI.swift
│   │   ├── FeatureModels.swift
│   │   └── MaterialTun.swift
│   └── materialTunHelper/
│       └── main.swift
├── Package.swift
├── README.md
└── build.sh
```

## Main Files

- `Sources/materialTun/CompactUI.swift`: active `@main` app, compact UI, onboarding, profile screens, settings, import sheets, and menu bar extra.
- `Sources/materialTun/MaterialTun.swift`: app store, connection lifecycle, profile parser, Xray config builder, system proxy handling, TUN helper installation, and traffic stats.
- `Sources/materialTun/FeatureModels.swift`: workspaces, backup/restore, QR import/export, subscriptions, latency checks, sing-box config generation, and Geo file updates.
- `Sources/materialTunHelper/main.swift`: privileged TUN helper that watches command files and starts/stops sing-box.
- `App/Info.plist`: metadata for the single compact app bundle.
- `build.sh`: the only packaging script.

## Build

Build the Swift package:

```bash
swift build
```

Build the app bundle:

```bash
./build.sh
```

The packaged app is written to:

```text
dist/Here/materialTun.app
```

The script builds universal `arm64` + `x86_64` binaries, copies Xray/sing-box/geodata into the app bundle, generates `AppIcon.icns`, clears quarantine attributes, and ad-hoc signs the app.

## App Bundle

- App path: `dist/Here/materialTun.app`
- Display name: `materialTun`
- Executable: `materialTun`
- Bundle identifier: `local.materialtun`
- Helper executable: `Contents/Library/HelperTools/materialTunHelper`
- URL schemes: `materialtun`, `vless`, `vmess`, `trojan`, `hysteria2`, `tuic`, `anytls`

## Runtime Data

User data is stored in:

```text
~/Library/Application Support/materialTun/
```

Important files:

- `servers.json`: imported server profiles.
- `subscriptions.json`: subscription definitions.
- `settings.json`: app and routing settings.
- `workspaces.json`: user workspaces.
- `runtime-xray.json`: generated Xray config.
- `runtime-singbox.json`: generated sing-box config for sing-box protocols.
- `runtime-tun.json`: generated sing-box TUN config.
- `proxy-backup.json`: temporary macOS proxy backup.
- `helper-command.json` / `helper-status.json`: app-helper command channel.
- `tun.pid` / `tun.log`: TUN process tracking and logs.

## TUN Helper

TUN mode installs these system files:

```text
/Library/PrivilegedHelperTools/local.materialtun.helper
/Library/PrivilegedHelperTools/local.materialtun.sing-box
/Library/LaunchDaemons/local.materialtun.helper.plist
```

The helper runs as `local.materialtun.helper`, reads commands from the app support directory, starts sing-box with `runtime-tun.json`, and reports status back to the main app.

## Notes

- This repository intentionally keeps only the compact build path.
- Distribution output is kept in `dist/Here`.
- The older experimental UI in `MaterialTun.swift` remains behind `#if false` and is not compiled.
- There is no automated test suite yet; use `swift build` and `./build.sh` as the current verification path.
