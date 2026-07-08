# 013-GitHub发布v1.1.3完成

## 已完成内容

- 已提交功能与发布材料：
  - commit：`a9bb810 Add TUN adapter cleanup setting for v1.1.3`
- 已推送分支：
  - `codex/auto-clean-tun-adapters-v1.1.3`
- 已创建 GitHub Release：
  - `https://github.com/luojiang419/VNTC-2.0-client/releases/tag/v1.1.3`
- 已上传并核验 Release 资产：
  - `VNTC-2.0-client-v1.1.3-setup.exe`
  - `VNTC-2.0-client-v1.1.3-win-x64.zip`
- 已创建 draft PR：
  - `https://github.com/luojiang419/VNTC-2.0-client/pull/2`

## 当前修改到哪个模块

模块 3：提交、推送和 GitHub Release 发布完成。

## 具体修改的代码前后对比

本模块没有继续修改业务源码，新增本发布完成快照用于记录线上结果。

线上 Release 核验结果：

```text
tag: v1.1.3
targetCommitish: codex/auto-clean-tun-adapters-v1.1.3
publishedAt: 2026-07-08T08:06:45Z

VNTC-2.0-client-v1.1.3-setup.exe
size=12649047
digest=sha256:f288dfbb13d7872dcb61cc0fe1af39a97674e51bf029467f7f52c3ed568d9fdb

VNTC-2.0-client-v1.1.3-win-x64.zip
size=15373458
digest=sha256:52939cb1772df525c0e20b3701f3c2b9dd029c50c73994be5361d3c40c2ce427
```

## 验证结果

- `gh release view v1.1.3`：通过。
- `gh api repos/luojiang419/VNTC-2.0-client/releases/tags/v1.1.3`：资产 digest 与本地 SHA256 一致。
- `gh pr create --draft`：通过，PR `#2` 已创建。

## 待办清单（未完成）

- 如需让源码进入默认分支，后续合并 draft PR `#2`。
- 当前工作区仍存在本次任务外的历史未提交改动，未纳入本次发布。

## 下一步要做什么

本次 `v1.1.3` 编译、GitHub Release 发布和 PR 创建已完成。
