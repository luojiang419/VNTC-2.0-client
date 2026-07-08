# VNTC 2.0 Client v1.1.3

This patch release adds a safer maintenance option for cleaning unused VNTC virtual TUN adapters and rebuilds the Windows distributable package.

## What’s New

- Added a Settings switch for automatically cleaning unused TUN virtual adapters on launch
- Runs a one-time cleanup immediately when the switch is first enabled and saved
- Limits cleanup to VNTC-managed `vntc-*` adapters that are no longer referenced by saved profiles
- Keeps adapters referenced by current profiles and skips adapters that are currently `Up`
- Rebuilt the Windows x64 portable package and installer for this update

## Included Capabilities

- Flutter Windows + Rust Manager + vnt2_cli architecture
- Multi-profile management with batch connect / disconnect
- Automatic unique `tun_name`, `ctrl_port`, and `device_id` allocation per profile
- Automatic cleanup option for unused VNTC-managed TUN adapters
- Aggregated online / offline peer view
- Advanced vnt2 profile editing
- Tray minimize, close behavior selection, and tray shortcut menu
- Windows auto-start and silent startup

## Release Assets

- `VNTC-2.0-client-v1.1.3-setup.exe`: Windows installer
- `VNTC-2.0-client-v1.1.3-win-x64.zip`: portable Windows package
