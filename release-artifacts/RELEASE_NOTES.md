# VNTC 2.0 Client v1.1.5

This release adds in-app GitHub Release updates and rebuilds the Windows distributable package so users can test updating from the local v1.1.4 build to v1.1.5.

## What’s New

- Added automatic startup checks against the latest GitHub Release
- Added a manual "Check for updates" action in the main toolbar and tray menu
- Downloads the matching Windows installer asset and keeps it under `data/updates/windows`
- Prompts users to update immediately or defer the prompt until the next launch
- Launches the downloaded installer through a small PowerShell handoff script after the app exits
- Rebuilt the Windows x64 portable package and installer for the update test flow

## Included Capabilities

- Flutter Windows + Rust Manager + vnt2_cli architecture
- Multi-profile management with batch connect / disconnect
- Automatic unique `tun_name`, `ctrl_port`, and `device_id` allocation per profile
- Automatic cleanup option for unused VNTC-managed TUN adapters
- In-app GitHub Release update checks and installer handoff
- Aggregated online / offline peer view
- Advanced vnt2 profile editing
- Tray minimize, close behavior selection, and tray shortcut menu
- Windows auto-start and silent startup

## Release Assets

- `VNTC-2.0-client-v1.1.5-setup.exe`: Windows installer
- `VNTC-2.0-client-v1.1.5-win-x64.zip`: portable Windows package
