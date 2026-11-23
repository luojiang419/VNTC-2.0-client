# Mac 端开发文档

## 1. 文档目的

本文档用于完整记录本项目从 Windows 导向代码迁移到 macOS 可构建版本的过程，重点总结：

- Mac 端开发中遇到的关键问题
- 每个问题的定位方法
- 实际采用的解决方案
- 当前版本的已完成状态
- 仍需在真实用户机器上继续验证的点

文档面向后续维护者、交接人员以及准备推送到 GitHub 的发布整理工作。

---

## 2. 当前项目结论

截至本文档整理时，项目已经具备以下能力：

- 可在 macOS 上完成 Flutter + Rust 的完整构建
- 可输出 mac 版应用包到 `dist/vntc2_flutter.app`
- 前端已具备 `macos/` 平台工程
- Rust 二进制可打入 `.app/Contents/Resources/runtime/`
- 应用数据目录已迁移到 macOS 标准的 `~/Library/Application Support/...`
- macOS 下已支持管理员授权启动核心组网进程
- 历史无 TUN 配置会自动迁回 TUN 模式
- macOS 下 `tun_name` 已自动规范为 `utunN`
- 仓库中已移除预置测试服务器地址和测试配置

需要强调的一点：

- 管理员授权链路已经接通，并且已定位并修复 `nohup` 后台化问题与 `utun` 命名问题。
- 但“最终提权后的真实 TUN 连通”仍需要用户在本机再次输入管理员密码后完成最后一轮实机确认，因为该步骤必须依赖本机交互授权，无法由自动化完全代替。

---

## 3. 项目结构与 mac 端相关模块

本次改造主要涉及以下目录：

- `vntc2_flutter/`
  Flutter 桌面前端，现已支持 macOS 构建。

- `vnt-2.0.0/`
  Rust 主工程，包含：
  - `vnt2_cli`
  - `vnt2_ctrl`
  - `vntc_manager`
  - `vnt-core`

- `build_macos_dist.sh`
  Mac 端统一打包脚本，用于重新构建并将 Rust 运行时复制到 `dist/`。

- `dist/vntc2_flutter.app`
  最终 macOS 发布产物。

---

## 4. 最初遇到的总体问题

项目最初实际上不是一个真正可用的 mac 项目，而是一个明显以 Windows 为中心的代码库，主要问题包括：

- Flutter 工程只有 `windows/`，没有 `macos/`
- Dart 代码中大量写死 `.exe`
- 运行时文件查找逻辑按 Windows 路径组织
- 前端默认数据目录放在程序可执行目录旁边
- Rust 工具链未安装
- Rust 依赖下载依赖 GitHub 和 crates.io，网络不稳定
- `protoc` 缺失导致 `vnt-core` 无法编译
- macOS 下运行时权限模型与 Windows 明显不同
- TUN 创建逻辑在 macOS 下需要管理员授权
- TUN 设备名格式与 Windows 风格不兼容
- 仓库里混入测试服务器和本地日志，不适合直接推 GitHub

---

## 5. 目录层级问题

### 问题现象

外层目录和内层目录同名，真正仓库内容位于：

`/Users/qy/Documents/app/VNT2X-source-for-mac-20260516/VNT2X-source-for-mac-20260516`

这在初次构建时容易误判工作目录。

### 解决方法

- 所有构建、搜索、打包操作都统一切换到内层真实目录。
- 后续脚本与文档均以该目录作为仓库根目录。

---

## 6. Flutter 缺失 macOS 平台工程

### 问题现象

项目最开始只有：

- `windows/`

没有：

- `macos/`

因此 `flutter build macos` 无法直接执行。

### 解决方法

使用 Flutter 自动生成 macOS 平台骨架：

```bash
cd vntc2_flutter
flutter create --platforms=macos .
```

### 结果

已补齐：

- `vntc2_flutter/macos/Runner`
- `vntc2_flutter/macos/Flutter`
- `vntc2_flutter/macos/Runner.xcodeproj`
- `vntc2_flutter/macos/Runner.xcworkspace`

---

## 7. Dart 层写死 Windows 可执行文件名

### 问题现象

多个位置只查找：

- `vntc_manager.exe`
- `vnt2_cli.exe`

在 macOS 上实际应为无扩展名 Mach-O 二进制。

### 解决方法

增加平台化可执行文件名解析逻辑：

- Windows 返回 `xxx.exe`
- macOS / Linux 返回 `xxx`

同时补齐查找路径：

- 开发目录下 `target/release/`
- `.app/Contents/Resources/runtime/`
- 程序当前目录附近

### 结果

Flutter 应用在开发态和打包态都能定位到 Rust 二进制。

---

## 8. 程序数据目录不能再放在 `.app` 包旁边

### 问题现象

Windows 代码默认把：

- `settings/`
- `profiles/`
- `runtime/`
- `logs/`

放在可执行文件目录旁边。

macOS 下 `.app` 是 Bundle，运行时不适合把动态数据写进应用包内部。

### 解决方法

通过 `path_provider` 使用 macOS 标准应用支持目录：

```dart
getApplicationSupportDirectory()
```

最终运行时数据落在：

`~/Library/Application Support/com.example.vntc2Flutter/data`

### 结果

应用数据与程序包彻底分离，符合 macOS 桌面应用习惯。

---

## 9. Rust 工具链缺失

### 问题现象

本机初始没有：

- `cargo`
- `rustc`
- `rustup`

### 解决方法

安装 Rust：

```bash
curl https://sh.rustup.rs -sSf | sh -s -- -y
source "$HOME/.cargo/env"
```

### 结果

后续可正常编译：

- `vnt2_cli`
- `vnt2_ctrl`
- `vntc_manager`

---

## 10. Rust 依赖下载困难

### 问题现象

构建过程中同时遇到了两个网络问题：

- crates.io 索引和包下载不稳定
- `tcp_ip` 是 GitHub git 依赖，`git fetch` 极慢甚至失败

### 解决方法一：切换 crates 镜像

在：

`vnt-2.0.0/.cargo/config.toml`

加入：

```toml
[source.crates-io]
replace-with = "rsproxy-sparse"

[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"
```

### 解决方法二：使用本地代理

开发时使用：

- `HTTP_PROXY=http://127.0.0.1:7890`
- `HTTPS_PROXY=http://127.0.0.1:7890`
- `ALL_PROXY=socks5://127.0.0.1:7890`

### 解决方法三：vendor GitHub 依赖

`tcp_ip` 无法稳定通过 git 拉取，于是将固定 commit 的源码直接下载并落地到：

`vnt-2.0.0/vendor/tcp_ip`

同时在：

`vnt-2.0.0/Cargo.toml`

增加：

```toml
[patch."https://github.com/rustp2p/tcp_ip"]
tcp_ip = { path = "vendor/tcp_ip" }
```

### 结果

Rust 编译链路脱离实时 GitHub 拉取，构建稳定性大幅提升。

---

## 11. `protoc` 缺失导致 `vnt-core` 编译失败

### 问题现象

Rust 编译推进到 `vnt-core` 时，`build.rs` 会调用 `prost_build`，缺少 `protoc` 会报错。

### 解决方法

安装 protobuf：

```bash
brew install protobuf
```

### 结果

`vnt-core` 和 `vnt-ipc` 均可顺利编译。

---

## 12. 打包脚本缺失

### 问题现象

项目最开始没有统一的 mac 端打包入口，手工步骤多且容易漏掉 Rust 二进制复制。

### 解决方法

新增：

`build_macos_dist.sh`

脚本流程：

1. `flutter pub get`
2. `cargo build --release --features vnt-ipc -p vnt2 -p vntc_manager`
3. `flutter build macos --release`
4. 将 `.app` 复制到 `dist/`
5. 将 Rust 二进制复制到 `.app/Contents/Resources/runtime/`

### 结果

现在可以通过一条命令统一重打包：

```bash
./build_macos_dist.sh
```

---

## 13. macOS 原始 ICMP 权限问题

### 问题现象

最早直接运行 `vnt2_cli` 时，在 `create_network` 阶段就失败：

- `new Socket RAW ICMPV4 failed`
- `Operation not permitted`

根因是 macOS 下原始 ICMP socket 受权限限制。

### 问题定位

问题位于：

- `vnt-core/src/nat/internal_nat/icmp_nat.rs`

其中显式创建了：

- `socket2::Type::RAW`
- `socket2::Protocol::ICMPV4`

### 解决方法

修改：

- `vnt-core/src/nat/internal_nat/mod.rs`

当 macOS 上 ICMP NAT 因权限失败时：

- 不再整体退出
- 记录 warning
- 继续初始化 TCP/UDP NAT

### 结果

应用不再因为 ICMP raw socket 权限直接启动失败。

注意：

- 这只是让网络核心可继续启动
- 并不等于 macOS 已具备真正的 TUN 通信能力

---

## 14. 有 TUN 模式下的管理员权限问题

### 问题现象

修掉 ICMP 问题后，`vnt2_cli` 已经可以完成注册并拿到虚拟 IP，例如：

- `Registration completed, IP: 10.10.10.x`

但随后会在：

- `start tun`

阶段失败：

- `Operation not permitted`

### 根因

macOS 下创建 TUN、设置接口、配置路由，需要更高权限。

普通用户双击 GUI 启动时，`vnt2_cli` 不是 root，因此会失败。

### 解决方案方向

不能依赖普通系统弹窗权限，必须实现真正的管理员提权启动。

---

## 15. 最早的临时兼容方案：无 TUN 模式

### 目的

为了先把“能连接服务器、能拉在线离线用户列表”这条链路打通，曾一度在 macOS 上把配置自动改成：

- `no_tun = true`

### 效果

无 TUN 模式下可以：

- 注册成功
- 获取虚拟 IP
- 获取在线/离线用户列表

但无法：

- 让系统级网络真正通过虚拟网卡与对端通信

### 后续处理

这是中间过渡方案，后面已经撤回成真正的 TUN + 提权方案。

---

## 16. 管理员提权启动方案

### 需求

在 macOS 上，当配置为正常 TUN 模式时：

- 点击连接
- 触发管理员密码弹窗
- 以提权方式启动 `vnt2_cli`
- 断开时也能正常停掉进程

### 初始实现

在 `vntc_manager` 中增加会话抽象：

- 普通子进程会话
- 提权会话

提权会话通过：

- `osascript`
- `do shell script ... with administrator privileges`

执行组网命令。

### 管理器改造点

`vntc_manager` 增加了：

- 提权会话类型
- PID 文件
- 会话恢复逻辑
- 会话停止逻辑

从而支持：

- manager 重启后识别 root 启动的组网进程
- 点击断开时结束提权进程

---

## 17. `nohup` 后台化失败问题

### 问题现象

提权链路最开始用的是：

```bash
nohup vnt2_cli ... &
```

但在 `osascript do shell script` 环境里，日志报错：

- `nohup: can't detach from console: Inappropriate ioctl for device`

这会导致：

- 提权链路表面执行了
- 但后台进程并未真正脱离成功

### 解决方法

改用：

- `/usr/bin/python3`
- `subprocess.Popen(..., start_new_session=True)`

由 Python 完成真正的 detached spawn，并输出 PID。

### 结果

提权命令不再依赖 `nohup`，后台拉起机制更稳定。

---

## 18. macOS TUN 设备名规则不兼容

### 问题现象

修完提权和后台化后，`vnt2_cli` 又在日志中报出新的错误：

- `device name must start with utun`

这说明：

- 进程已经提权成功
- 注册已完成
- 失败点已经推进到 macOS 专属 TUN 设备创建阶段

### 根因

原项目沿用了 Windows 风格的名称生成方式：

- `vntc-a`
- `vntc-xxx`

而 `tun-rs` 在 macOS 下明确要求：

- TUN 名称必须是 `utunN`

### 解决方法

在 Flutter 配置模型中加入 macOS 专属规则：

- 新建配置时生成 `utunN`
- 旧配置读取时如果不是 `utun数字`，自动迁移
- 写回 `vnt.toml` 时强制落地合法的 `utunN`

### 结果

旧配置已经能够自动从：

- `vntc-a`

迁移为例如：

- `utun414`

---

## 19. 旧配置自动迁移策略

Mac 端配置迁移目前包含两类：

### 1. `noTun` 迁移

历史无 TUN 兼容配置会在当前版本重新规范为：

- `noTun = false`

因为当前目标已经从“仅能取列表”转为“尝试真实 TUN 组网”。

### 2. `tunName` 迁移

历史不合法的 Windows 风格名称会迁移为：

- `utunN`

### 迁移触发时机

发生在：

- 应用启动
- 读取 profile
- 保存 profile

### 结果

旧用户数据无需手工编辑，即可自动向 mac 兼容配置靠拢。

---

## 20. 前端 UI 与文案调整

为了减少用户误解，前端做了如下调整：

- 增加 `macos/` 平台工程
- 托盘图标改为 Flutter asset 方式
- 在 macOS 上显示“连接时将请求管理员权限”的提示
- 连接逻辑不再依赖 Windows 专属 `.exe`
- 表单默认值改成通用占位符，不再带测试服务器

当前默认输入改为：

- 服务器地址：空
- 组网编号：空
- 设备名称：`Vntc2`

---

## 21. 应用包内 Rust 运行时组织方式

最终打包后，Rust 二进制位于：

`dist/vntc2_flutter.app/Contents/Resources/runtime/`

包括：

- `vnt2_cli`
- `vnt2_ctrl`
- `vntc_manager`

Flutter 程序启动后会从该目录定位运行时。

---

## 22. 运行时数据目录

当前应用数据目录位于：

`~/Library/Application Support/com.example.vntc2Flutter/data`

主要内容：

- `settings/app_settings.json`
- `profiles/<profile-id>/meta.json`
- `profiles/<profile-id>/vnt.toml`
- `runtime/<profile-id>/`
- `logs/<profile-id>.log`

管理员提权启动时，日志和 PID 文件也会落到这一套目录下。

---

## 23. 安全清理与 GitHub 推送处理

在准备推 GitHub 前，已经做了以下清理：

- 移除 UI 中的预置服务器 `quic://115.231.35.105:2225`
- 删除顶层测试文件 `test-vnt-a.toml`
- 删除顶层 `logs/` 内本地测试日志
- 确认仓库目录内不再包含该测试服务器地址

### 注意

以下内容虽然不在仓库内，但仍属于本机敏感运行数据：

- `~/Library/Application Support/com.example.vntc2Flutter/data/`

推 GitHub 时不要手动把该目录内容带入仓库。

---

## 24. 当前仍需重点验证的事项

虽然提权链路、后台化、`utun` 命名都已经修正，但最后仍有一个必须依赖真实本机交互完成的验证步骤：

- 用户在 macOS 管理员弹窗中输入密码
- 再次点击连接
- 确认提权后的 `vnt2_cli` 真正完成 `start tun`
- 确认能获取虚拟 IP 并与组网其他成员真实通信

由于管理员密码输入必须由本机用户完成，自动化无法替代该步骤，因此这里必须在用户机器上做最后确认。

---

## 25. 建议的最终实机验证流程

建议使用以下流程做上线前验证：

1. 删除本机历史应用进程
2. 打开新的 `dist/vntc2_flutter.app`
3. 新建或加载一个 profile
4. 确认 `meta.json` 中：
   - `noTun = false`
   - `tunName = utunN`
5. 点击连接
6. 在管理员授权弹窗中输入密码
7. 检查：
   - 是否获得虚拟 IP
   - `/profiles` 是否显示 `running=true`
   - `/peers` 是否返回在线/离线用户
   - 实际 ping / 业务通信是否可达
8. 点击断开
9. 检查 root 启动的 `vnt2_cli` 是否被正常回收

---

## 26. 建议保留的诊断文件

当用户反馈“输入密码后仍然不通”时，优先查看：

- `~/Library/Application Support/com.example.vntc2Flutter/data/logs/<profile>.log`
- `~/Library/Application Support/com.example.vntc2Flutter/data/profiles/<profile>/vnt.toml`
- `~/Library/Application Support/com.example.vntc2Flutter/data/profiles/<profile>/meta.json`

这三者足以判断当前卡在：

- 授权链路
- 进程启动
- TUN 创建
- 路由设置
- 还是组网本身

---

## 27. 本次开发的核心经验

本项目的 mac 适配并不是简单的“加一个 Flutter 平台目录”就能完成，真正的工作量主要集中在以下几类差异：

- 平台工程差异
- 文件路径与打包结构差异
- 依赖拉取与工具链差异
- 权限模型差异
- TUN 设备规则差异
- 本地测试数据与发布安全差异

其中最关键的不是 UI，而是：

- `Rust 运行时 + macOS 权限模型 + TUN 规则`

后续如果继续演进，建议优先把以下方向做成长期方案：

- 更正式的 mac 提权 helper
- 更明确的管理员授权失败提示
- TUN 成功后的最终通信实测自动化
- 更规范的 release 打包与脱敏流程

---

## 28. 当前可复用命令

### 重新构建 mac 包

```bash
./build_macos_dist.sh
```

### Flutter 静态检查

```bash
cd vntc2_flutter
flutter analyze
```

### Rust 构建

```bash
cd vnt-2.0.0
cargo build --release --features vnt-ipc -p vnt2 -p vntc_manager
```

### 使用代理构建

```bash
HTTP_PROXY=http://127.0.0.1:7890 \
HTTPS_PROXY=http://127.0.0.1:7890 \
ALL_PROXY=socks5://127.0.0.1:7890 \
./build_macos_dist.sh
```

---

## 29. 文档结语

本次 mac 端开发的核心任务已经从“完全无法构建”推进到了“可构建、可打包、可触发管理员授权、可自动修正 mac 配置规则”的状态。

剩余最关键的一步不再是代码结构性问题，而是：

- 在真实用户机器上完成管理员授权后的最终 TUN 连通验证

如果这一步通过，mac 端就能从“开发可用”进入“发布可用”阶段。
