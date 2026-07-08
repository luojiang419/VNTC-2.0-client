# 007-Rust管理器新增TUN清理接口

## 已完成内容

- 在 Rust Manager 中新增 `/adapters/cleanup-unused` POST 接口。
- 新增 `TunAdapterCleanupResult` 与 `TunAdapterCleanupSkipped` 返回结构。
- Windows 下通过 PowerShell 枚举 `vntc-*` 网络设备：
  - 当前配置仍引用的网卡加入 `kept`，不删除。
  - 当前状态为 `Up` 的未引用网卡加入 `skipped`，不删除。
  - 未引用且非 `Up` 的网卡通过 `pnputil /remove-device` 删除。
- 非 Windows 平台返回 `unsupported: true`，避免跨平台编译失败。

## 当前修改到哪个模块

模块 1：Rust Manager 清理接口。

## 具体修改的代码前后对比

### 路由注册

修改前：

```rust
.route("/profiles/connect", post(connect_profiles))
.route("/profiles/disconnect", post(disconnect_profiles))
.route("/peers", get(get_peers))
```

修改后：

```rust
.route("/profiles/connect", post(connect_profiles))
.route("/profiles/disconnect", post(disconnect_profiles))
.route(
    "/adapters/cleanup-unused",
    post(cleanup_unused_tun_adapters),
)
.route("/peers", get(get_peers))
```

### 新增清理逻辑

新增：

```rust
fn cleanup_unused_tun_adapters(&self) -> anyhow::Result<TunAdapterCleanupResult> {
    self.cleanup_exited_sessions();
    #[cfg(windows)]
    {
        return self.cleanup_unused_tun_adapters_windows();
    }
    #[cfg(not(windows))]
    {
        Ok(TunAdapterCleanupResult {
            cleaned: Vec::new(),
            kept: Vec::new(),
            skipped: Vec::new(),
            unsupported: true,
        })
    }
}
```

## 验证结果

- 已执行：`cargo fmt -p vntc_manager`
- 已执行：`cargo check -p vntc_manager`
- 结果：通过。

## 待办清单（未完成）

- 在 Flutter `AppSettings` 中增加自动清理开关字段。
- 在 Flutter 运行时客户端中调用 `/adapters/cleanup-unused`。
- 在 `DashboardController` 启动流程中接入自动清理。
- 在设置页增加开关与结果提示。
- 完成全局格式化、构建验证、临时缓存清理。

## 下一步要做什么

进入模块 2：Flutter 设置模型、运行时客户端和启动自动清理流程。
