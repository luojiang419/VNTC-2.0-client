# 008-Flutter设置模型接入自动清理

## 已完成内容

- `AppSettings` 新增 `cleanupUnusedTunOnLaunch` 持久化字段，默认关闭。
- 新增 `TunAdapterCleanupResult` / `TunAdapterCleanupSkipped` Dart 模型，用于解析 Rust Manager 清理结果。
- `VntRuntime` 新增 `cleanupUnusedTunAdapters()`，调用 `/adapters/cleanup-unused`。
- `DashboardController` 启动流程中在 Manager 启动后、自动连接配置前执行静默清理。
- `DashboardController` 新增可复用的 `cleanupUnusedTunAdapters({silent})` 方法，供设置页首次开启后立即执行一次。

## 当前修改到哪个模块

模块 2：Flutter 设置持久化与启动自动清理流程。

## 具体修改的代码前后对比

### 设置字段

修改前：

```dart
final bool autoStart;
final bool silentAutoStart;
final bool connectDefaultOnLaunch;
```

修改后：

```dart
final bool autoStart;
final bool silentAutoStart;
final bool connectDefaultOnLaunch;
final bool cleanupUnusedTunOnLaunch;
```

### 启动流程

修改前：

```dart
await runtime!.start();
await refreshAll();
```

修改后：

```dart
await runtime!.start();
if (settings.cleanupUnusedTunOnLaunch) {
  await cleanupUnusedTunAdapters(silent: true);
}
await refreshAll();
```

### 运行时接口

新增：

```dart
Future<TunAdapterCleanupResult> cleanupUnusedTunAdapters() async {
  final data = await _postForDataMap(
    '/adapters/cleanup-unused',
    const <String, dynamic>{},
  );
  return TunAdapterCleanupResult.fromJson(data);
}
```

## 验证结果

- 已执行：`D:\flutter\bin\dart.bat format lib\core\models.dart lib\core\vnt_runtime.dart lib\core\dashboard_controller.dart`
- 已执行：`D:\flutter\bin\flutter.bat analyze`
- 结果：通过，`No issues found!`
- 说明：`dart format` 阶段出现 `flutter_lints` 包解析提示，但 `flutter analyze` 已完成依赖解析并通过。

## 待办清单（未完成）

- 在设置弹窗中增加自动清理开关。
- 设置页首次开启后立即执行一次清理，并显示清理结果。
- 完成全局格式化、构建验证、临时缓存清理。
- 更新备份文档中的最终前后对比。

## 下一步要做什么

进入模块 3：设置页入口与清理结果提示。
