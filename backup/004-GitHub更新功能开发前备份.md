# 004-GitHub更新功能开发前备份

## 阶段目标

为当前 VNTC 2.0 极简客户端移植“故事板”项目的 GitHub Release 更新能力，并生成一低一高两个版本用于真实测试更新链路：

- 本地测试版：低于线上发布版本，用来安装后触发更新提示。
- GitHub Release 版：高于本地测试版，用来作为可检测、可下载、可安装的目标版本。

## 修改前状态

- 当前分支：`codex/auto-clean-tun-adapters-v1.1.3`
- 当前已发布版本：`v1.1.3`
- Flutter 应用版本：`1.1.3+5`
- Inno Setup 安装脚本版本：`1.1.3`
- 当前项目尚无应用内更新模块。
- 工作区存在本任务外历史未提交/未跟踪内容，本阶段只处理更新功能和发布必需文件。

## 参考实现

参考项目：`G:\data\app\故事板`

参考模块：

- `lib/features/updater/domain/app_update_config.dart`
- `lib/features/updater/domain/update_models.dart`
- `lib/features/updater/data/updater_service.dart`
- `lib/features/updater/application/updater_controller.dart`
- `lib/app/app_shell.dart`

## 计划修改文件

- `vntc2_flutter/pubspec.yaml`
- `vntc2_flutter/lib/main.dart`
- `vntc2_flutter/lib/core/models.dart`
- `vntc2_flutter/lib/core/repository.dart`
- `vntc2_flutter/lib/features/updater/domain/app_update_config.dart`
- `vntc2_flutter/lib/features/updater/domain/update_models.dart`
- `vntc2_flutter/lib/features/updater/data/updater_service.dart`
- `vntc2_flutter/lib/features/updater/application/updater_controller.dart`
- `release-artifacts/vntc_setup.iss`
- `release-artifacts/RELEASE_NOTES.md`

## 修改前代码摘录

### Flutter 版本

```yaml
version: 1.1.3+5
```

### 安装脚本版本

```iss
#define MyAppVersion "1.1.3"
OutputBaseFilename=VNTC-2.0-client-v1.1.3-setup
```

### 设置模型

修改前 `AppSettings` 只包含语言、主题、关闭行为、自启、默认连接和 TUN 清理等字段，没有更新相关配置或待安装更新状态。

```dart
class AppSettings {
  const AppSettings({
    required this.language,
    required this.darkMode,
    required this.closeAction,
    required this.autoStart,
    required this.silentAutoStart,
    required this.connectDefaultOnLaunch,
    required this.cleanupUnusedTunOnLaunch,
    this.selectedProfileId,
    this.defaultProfileId,
  });
}
```

### 主界面入口

修改前底部操作区只有主题、连接、新建配置和设置入口，没有更新检查入口。

```dart
_IconCircleButton(
  icon: Icons.settings_rounded,
  onPressed: () => _showSettings(context, controller),
  size: 52,
  iconSize: 22,
),
```

## 待办清单

- 新增 updater 配置、状态、服务、控制器。
- 将更新状态持久化到现有 JSON 设置。
- 启动后自动检查 GitHub 最新 Release。
- UI 中新增手动检查入口和发现新版弹窗。
- 先编译本地低版本测试包。
- 再提升版本号并编译线上 Release 包。
- 创建 GitHub Release 并上传资产。
- 核验线上资产与更新检测链路。

## 下一步

进入模块 3：移植 GitHub Release 更新检查、下载和安装控制器。

## 阶段完成后的实际修改

### 新增更新模块

修改前：当前项目没有应用内更新模块。

修改后：

```text
vntc2_flutter/lib/features/updater/domain/app_update_config.dart
vntc2_flutter/lib/features/updater/domain/update_models.dart
vntc2_flutter/lib/features/updater/data/updater_service.dart
vntc2_flutter/lib/features/updater/application/updater_controller.dart
```

关键能力：

- 请求 GitHub latest release API。
- 按当前平台匹配 `VNTC-2.0-client-vX.Y.Z-setup.exe`。
- 比较当前版本和线上版本。
- 自动探测环境代理、本机 `7890` 等代理端口，并失败回退直连。
- 下载更新包到 `data/updates/windows`。
- 通过 PowerShell handoff 脚本等待旧进程退出后启动安装包。

### AppPaths

修改前：

```dart
final Directory logsDir;
```

修改后：

```dart
final Directory logsDir;
final Directory updatesDir;
```

### AppSettings

修改前：

```dart
final String? selectedProfileId;
final String? defaultProfileId;
```

修改后：

```dart
final String? selectedProfileId;
final String? defaultProfileId;
final String? pendingUpdateVersionTag;
final String? pendingUpdateInstallerPath;
final String? dismissedUpdatePromptVersion;
```

### UI 接入

修改前：主界面和托盘菜单没有更新入口。

修改后：

- `DesktopShell` 创建并持有 `UpdaterController`。
- 启动后自动检查最新 GitHub Release。
- 托盘菜单新增“检查更新”。
- 底部工具区新增更新图标按钮。
- 下载完成后弹出“下次启动更新 / 立即更新”对话框。

### 版本与发布文件

修改前：

```yaml
version: 1.1.3+5
```

```iss
#define MyAppVersion "1.1.3"
OutputBaseFilename=VNTC-2.0-client-v1.1.3-setup
```

修改后：

```yaml
version: 1.1.5+7
```

```dart
static const currentVersion = '1.1.5';
```

```iss
#define MyAppVersion "1.1.5"
OutputBaseFilename=VNTC-2.0-client-v1.1.5-setup
```

## 阶段验证结果

- `D:\flutter\bin\flutter.bat pub get`：通过。
- `D:\flutter\bin\flutter.bat analyze`：通过，`No issues found!`
- 本地低版本测试包 `v1.1.4`：构建通过。
- 线上发布包 `v1.1.5`：构建通过。
- `ISCC.exe vntc_setup.iss`：`v1.1.4` 与 `v1.1.5` 均通过。

## 阶段产物核验

```text
VNTC-2.0-client-v1.1.4-setup.exe
size=12679993
sha256=9B327B0F699FF5874EB976DF68AE228713A47C320F7C2FD2123021F718C00012

VNTC-2.0-client-v1.1.4-win-x64.zip
size=15418276
sha256=D83FFAFC45197E47D04CA2563C23C7C2B9EB77EB3CD5D3368AB55DD10445C8EF

VNTC-2.0-client-v1.1.5-setup.exe
size=12679483
sha256=5ED0DEE2759E25EB0BDA02EFC7B0694D1BF41C8FD61A03B0EEE8DFE071882F2D

VNTC-2.0-client-v1.1.5-win-x64.zip
size=15418271
sha256=53FFABA8C521CD0FC27C2CFD9BB28A872689DAA23201FAE9D4080C5FCB3176B1
```
