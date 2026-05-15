# VNTC 2.0 Client

VNTC 2.0 Client is a Windows desktop GUI for VNT 2.0 built on top of `Flutter Windows + Rust Manager + vnt2_cli`.

The project is designed for daily use and now includes a bilingual interface so users can switch between Simplified Chinese and English directly in the settings page.

## Highlights

- Multi-profile management in one desktop app
- Automatic allocation of a dedicated `tun_name`, `ctrl_port`, and `device_id` for every profile
- Batch connect / disconnect for selected profiles
- Aggregated online / offline peer view
- Advanced profile editor for vnt2 options
- System tray support with minimize-to-tray behavior
- Windows auto-start and silent startup
- Simplified Chinese / English UI switching

## Screenshots

![VNTC 2.0 Home](软件截图/软件首页.png)

| Profiles and Status | Online / Offline Peers |
| --- | --- |
| ![Screenshot 1](软件截图/2026-05-15_12-39-10.png) | ![Screenshot 2](软件截图/2026-05-15_12-39-23.png) |

| Advanced Settings |
| --- |
| ![Screenshot 3](软件截图/2026-05-15_12-39-31.png) |

## Project Structure

- `vntc2_flutter/`: Flutter Windows frontend
- `vnt-2.0.0/vntc-manager/`: Rust Manager for multi-profile orchestration and aggregated APIs
- `vnt-2.0.0/`: VNT 2.0 sources plus `vnt2_cli` / `vnt2_ctrl`
- `软件截图/`: screenshot assets

## Build

### Flutter Windows

```bash
cd vntc2_flutter
flutter pub get
flutter build windows
```

### Rust Binaries

```bash
cd vnt-2.0.0
cargo build --release --features vnt-ipc -p vnt2 -p vntc_manager
```

## Runtime Files

The release package expects the following files in the same directory:

- `vntc2_flutter.exe`
- `vntc_manager.exe`
- `vnt2_cli.exe`
- `vnt2_ctrl.exe`
- `wintun.dll`
- `data/`

## Thanks

- VNT 2.0
- Flutter
- Rust
