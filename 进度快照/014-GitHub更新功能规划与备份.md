# 014-GitHub更新功能规划与备份

## 已完成内容

- 已读取上一轮最新快照：`013-GitHub发布v1.1.3完成.md`。
- 已定位“故事板”项目更新功能实现：
  - `lib/features/updater/domain/app_update_config.dart`
  - `lib/features/updater/domain/update_models.dart`
  - `lib/features/updater/data/updater_service.dart`
  - `lib/features/updater/application/updater_controller.dart`
  - `lib/app/app_shell.dart`
- 已确认当前项目接入点：
  - `vntc2_flutter/lib/main.dart`
  - `vntc2_flutter/lib/core/models.dart`
  - `vntc2_flutter/lib/core/repository.dart`
  - `release-artifacts/vntc_setup.iss`
- 已新增阶段备份：
  - `backup/004-GitHub更新功能开发前备份.md`

## 当前修改到哪个模块

模块 2：阶段备份完成，准备进入更新模块开发。

## 具体修改的代码前后对比

本模块未修改业务源码，只新增备份文档。

新增：

```text
backup/004-GitHub更新功能开发前备份.md
```

## 待办清单（未完成）

- 新增 updater 配置、状态、服务、控制器。
- 将更新状态持久化到现有 JSON 设置。
- 启动后自动检查 GitHub 最新 Release。
- UI 中新增手动检查入口和发现新版弹窗。
- 先编译本地低版本测试包。
- 再提升版本号并编译线上 Release 包。
- 创建 GitHub Release 并上传资产。
- 核验线上资产与更新检测链路。

## 下一步要做什么

进入模块 3：移植 GitHub Release 更新检查、下载和安装控制器。
