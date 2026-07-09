# 017-GitHub发布v1.1.5完成

## 已完成内容

- 已提交更新功能：
  - commit：`8e867ee Add GitHub release updater for v1.1.5`
- 已推送分支：
  - `codex/github-updater-v1.1.5`
- 已创建 GitHub Release：
  - `https://github.com/luojiang419/VNTC-2.0-client/releases/tag/v1.1.5`
- 已上传并核验 Release 资产：
  - `VNTC-2.0-client-v1.1.5-setup.exe`
  - `VNTC-2.0-client-v1.1.5-win-x64.zip`
- 已生成本地低版本测试包，用于测试更新功能：
  - `release-artifacts/VNTC-2.0-client-v1.1.4-setup.exe`
  - `release-artifacts/VNTC-2.0-client-v1.1.4-win-x64.zip`
  - 已同步到 `output/`
- 已清理 Flutter 构建缓存：
  - `D:\flutter\bin\flutter.bat clean`

## 当前修改到哪个模块

模块 6 与模块 7：GitHub Release 发布、线上资产核验和缓存清理完成。

## 具体修改的代码前后对比

本模块没有继续修改业务源码，新增本发布完成快照用于记录线上结果。

线上 Release 核验结果：

```text
tag: v1.1.5
targetCommitish: codex/github-updater-v1.1.5
publishedAt: 2026-07-09T01:33:43Z

VNTC-2.0-client-v1.1.5-setup.exe
size=12679483
digest=sha256:5ed0dee2759e25eb0bda02efc7b0694d1bf41c8fd61a03b0eee8dfe071882f2d

VNTC-2.0-client-v1.1.5-win-x64.zip
size=15418271
digest=sha256:53ffaba8c521cd0fc27c2cfd9bb28a872689daa23201fae9d4080c5fcb3176b1
```

本地 SHA256：

```text
VNTC-2.0-client-v1.1.5-setup.exe
sha256=5ED0DEE2759E25EB0BDA02EFC7B0694D1BF41C8FD61A03B0EEE8DFE071882F2D

VNTC-2.0-client-v1.1.5-win-x64.zip
sha256=53FFABA8C521CD0FC27C2CFD9BB28A872689DAA23201FAE9D4080C5FCB3176B1
```

latest API 验证：

```text
tag_name: v1.1.5
setup_asset: VNTC-2.0-client-v1.1.5-setup.exe
setup_size: 12679483
zip_asset: VNTC-2.0-client-v1.1.5-win-x64.zip
```

## 验证结果

- `D:\flutter\bin\flutter.bat analyze`：通过，`No issues found!`
- `D:\flutter\bin\flutter.bat build windows --release`：`v1.1.4` 与 `v1.1.5` 均通过。
- `ISCC.exe vntc_setup.iss`：`v1.1.4` 与 `v1.1.5` 均通过。
- `gh release create v1.1.5`：通过。
- `gh release view v1.1.5`：通过。
- `gh api repos/luojiang419/VNTC-2.0-client/releases/tags/v1.1.5`：资产 digest 与本地 SHA256 一致。
- `curl.exe` 请求 GitHub latest release：返回 `v1.1.5` 且包含匹配安装包资产。

## 更新功能测试方法

1. 安装本地低版本测试包：
   - `G:\data\app\VNT2.0-极简客户端\release-artifacts\VNTC-2.0-client-v1.1.4-setup.exe`
2. 启动 `v1.1.4` 客户端。
3. 等待启动自动检查，或点击主界面底部“检查更新”按钮。
4. 预期检测到 GitHub 最新版本 `v1.1.5`。
5. 客户端下载：
   - `VNTC-2.0-client-v1.1.5-setup.exe`
6. 弹窗出现后点击“立即更新”，程序退出并拉起安装包。
7. 完成安装后应更新到 `v1.1.5`。

## 待办清单（未完成）

- 如需让源码进入默认分支，后续可以从分支 `codex/github-updater-v1.1.5` 创建或合并 PR。
- 当前工作区仍存在本次任务外的历史未提交/未跟踪改动，未纳入本次发布。

## 下一步要做什么

本次应用内更新功能开发、本地测试包生成、GitHub Release 发布和线上资产核验已完成。
