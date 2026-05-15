# VNTC 2.0 Client

一个基于 `Flutter Windows + Rust Manager + vnt2_cli` 的 VNT 2.0 桌面客户端。

项目目标是提供一个更适合日常使用的 Windows 图形界面，支持：

- 多配置管理
- 每个配置自动绑定唯一虚拟网卡
- 勾选多个配置后批量连接 / 断开
- 在线 / 离线用户列表查看
- 高级配置折叠编辑
- 托盘最小化与快捷菜单

## 软件首页

![VNTC 2.0 软件首页](软件截图/软件首页.png)

## 功能特性

- 单一主程序统一管理多个 VNT 会话，不依赖多开客户端实例
- 保存配置时自动分配唯一 `tun_name`、`ctrl_port`、`device_id`
- 默认支持普通连接模式，不再使用测试专用的 `no_tun` 开关
- 顶部汇总状态栏展示连接数、在线/离线数量、汇总网速和整体状态
- 支持托盘常驻、关闭询问、最小化到托盘和托盘右键菜单

## 软件截图

| 配置与状态 | 在线 / 离线用户 |
| --- | --- |
| ![截图1](软件截图/2026-05-15_12-39-10.png) | ![截图2](软件截图/2026-05-15_12-39-23.png) |

| 高级配置 |
| --- |
| ![截图3](软件截图/2026-05-15_12-39-31.png) |

## 项目结构

- `vntc2_flutter/`：Flutter Windows 前端
- `vnt-2.0.0/vntc-manager/`：Rust Manager，多配置调度与聚合接口
- `vnt-2.0.0/`：VNT 2.0 相关源码与 `vnt2_cli` / `vnt2_ctrl`
- `软件截图/`：项目截图资源

## 构建说明

### Flutter Windows

```bash
cd vntc2_flutter
flutter pub get
flutter build windows
```

### Rust 二进制

```bash
cd vnt-2.0.0
cargo build --release --features vnt-ipc -p vnt2 -p vntc_manager
```

## 运行说明

发布包运行时需要以下文件位于同级目录：

- `vntc2_flutter.exe`
- `vntc_manager.exe`
- `vnt2_cli.exe`
- `vnt2_ctrl.exe`
- `wintun.dll`
- `data/`

## 致谢

- VNT 2.0
- Flutter
- Rust
