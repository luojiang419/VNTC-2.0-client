# VNTC 2.0 Client v1.1.1

This patch release fixes the default language behavior so the UI follows the operating system language on first launch and for upgraded settings files that do not yet contain an explicit language value.

## What’s New

- Added a language selector in the settings page
- Added full Simplified Chinese / English UI switching
- Translated the main dashboard, tray menu, dialogs, profile editor, and settings page into English
- Kept Windows auto-start and silent startup behavior compatible with the new language settings
- Fixed default language detection:
  - Chinese systems default to Simplified Chinese
  - Non-Chinese systems default to English
  - Upgraded settings files without a saved `language` field now follow the system language automatically

## Included Capabilities

- Flutter Windows + Rust Manager + vnt2_cli architecture
- Multi-profile management with batch connect / disconnect
- Automatic unique `tun_name`, `ctrl_port`, and `device_id` allocation per profile
- Aggregated online / offline peer view
- Advanced vnt2 profile editing
- Tray minimize, close behavior selection, and tray shortcut menu
- Windows auto-start and silent startup

## Release Assets

- `VNTC-2.0-client-v1.1.1-setup.exe`: Windows installer
- `VNTC-2.0-client-v1.1.1-win-x64.zip`: portable Windows package
