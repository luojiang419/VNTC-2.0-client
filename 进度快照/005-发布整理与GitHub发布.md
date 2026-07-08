# 005-发布整理与GitHub发布

## 已完成内容

- 已清理本次构建产生的 Flutter 缓存：
  - `vntc2_flutter/.dart_tool`
  - `vntc2_flutter/build`
  - `vntc2_flutter/windows/flutter/ephemeral`
  - `vntc2_flutter/flutter_01.log`
- 已清理 ASCII 临时构建目录：
  - `G:\codex_build\vntc2_flutter_icon_release`
- 已创建 Git 分支：
  - `codex/update-app-icon-v1.1.2`
- 已确认当前工作区存在任务外历史改动，发布提交只纳入本次任务文件。
- 已准备 GitHub Release：
  - tag：`v1.1.2`
  - 预计地址：`https://github.com/luojiang419/VNTC-2.0-client/releases/tag/v1.1.2`

## 当前修改到哪个模块

模块 5：清理缓存、整理 Git 变更并发布到 GitHub。

## 具体修改的代码前后对比

本模块没有继续修改业务源码，主要是清理缓存、整理发布范围和记录发布状态。

暂存范围应仅包含：

```text
backup/001-程序图标更新前备份.md
release-artifacts/RELEASE_NOTES.md
release-artifacts/vntc_setup.iss
vntc2_flutter/pubspec.yaml
vntc2_flutter/windows/runner/Runner.rc
vntc2_flutter/windows/runner/resources/app_icon.ico
进度快照/001-启动检查与发布规划.md
进度快照/002-生成并应用简约程序图标.md
进度快照/003-更新版本与发布说明.md
进度快照/004-编译并生成发布资产.md
进度快照/005-发布整理与GitHub发布.md
```

任务外改动保持未暂存：

```text
README.md
README_EN.md
开发进度快照.md
doc/
output/
vntcAPP-WEB/
公钥/
```

## 待办清单（未完成）

- 提交本次变更。
- 推送 `codex/update-app-icon-v1.1.2`。
- 创建 GitHub Release `v1.1.2` 并上传 zip/installer。
- 验证线上 Release 资产可见。

## 下一步要做什么

执行 commit、push 和 GitHub Release 发布。
