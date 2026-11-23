use anyhow::{Context, anyhow};
use axum::{
    Json, Router,
    extract::State,
    routing::{get, post},
};
use clap::Parser;
use futures::{SinkExt, StreamExt};
use parking_lot::Mutex;
use prost::Message;
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    fs::{self, OpenOptions},
    io::Write,
    net::{Ipv4Addr, SocketAddr},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::Arc,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use tokio::{net::TcpListener, net::TcpStream, time::timeout};
use tokio_util::codec::{Framed, LengthDelimitedCodec};
use vnt_ipc::message::ipc_request::IpcCmd;
use vnt_ipc::message::ipc_response::ResponsePayload;
use vnt_ipc::message::{
    AppInfo, AppInfoCmd, ClientInfoList, ClientListCmd, IpcRequest, IpcResponse, TrafficInfoList,
    TrafficListCmd,
};

#[cfg(windows)]
const CLEANUP_UNUSED_TUN_ADAPTERS_PS: &str = r#"
$ErrorActionPreference = 'Stop'
$result = [ordered]@{
    cleaned = @()
    kept = @()
    skipped = @()
    unsupported = $false
}
$keep = @{}
if ($env:VNTC_KEEP_TUN_NAMES) {
    foreach ($name in @($env:VNTC_KEEP_TUN_NAMES | ConvertFrom-Json)) {
        if ($null -ne $name -and $name.ToString().Trim().Length -gt 0) {
            $keep[$name.ToString().ToLowerInvariant()] = $true
        }
    }
}
$netAdapters = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue)
$devices = @(Get-PnpDevice -Class Net -ErrorAction SilentlyContinue | Where-Object {
    $_.FriendlyName -like 'vntc-*'
})
foreach ($device in $devices) {
    $name = [string]$device.FriendlyName
    if ($keep.ContainsKey($name.ToLowerInvariant())) {
        $result.kept += $name
        continue
    }
    $net = $netAdapters | Where-Object { $_.Name -eq $name } | Select-Object -First 1
    if ($null -ne $net -and $net.Status -eq 'Up') {
        $result.skipped += [ordered]@{ name = $name; reason = 'adapter is Up' }
        continue
    }
    $removeOutput = & pnputil /remove-device $device.InstanceId 2>&1
    if ($LASTEXITCODE -eq 0) {
        $result.cleaned += $name
    } else {
        $result.skipped += [ordered]@{
            name = $name
            reason = (($removeOutput | Out-String).Trim())
        }
    }
}
$result | ConvertTo-Json -Depth 5 -Compress
"#;

#[derive(Parser, Debug)]
#[command(author, version, about)]
struct Args {
    #[arg(long)]
    data_dir: PathBuf,
    #[arg(long)]
    cli_executable: PathBuf,
    #[arg(long)]
    port_file: PathBuf,
    #[arg(long, default_value = "127.0.0.1:0")]
    addr: SocketAddr,
}

#[derive(Clone)]
struct AppState {
    inner: Arc<Mutex<ManagerState>>,
    data_dir: PathBuf,
    cli_executable: PathBuf,
}

struct ManagerState {
    sessions: HashMap<String, ManagedSession>,
    traffic_samples: HashMap<String, TrafficSample>,
}

struct ManagedSession {
    child: Child,
}

#[derive(Clone, Copy)]
struct TrafficSample {
    recorded_at: Instant,
    total_tx_bytes: u64,
    total_rx_bytes: u64,
}

#[derive(Serialize)]
struct ApiResponse<T> {
    code: i32,
    msg: String,
    data: Option<T>,
}

impl<T> ApiResponse<T> {
    fn success(data: T) -> Self {
        Self {
            code: 0,
            msg: "success".to_string(),
            data: Some(data),
        }
    }

    fn error(message: impl Into<String>) -> Self {
        Self {
            code: -1,
            msg: message.into(),
            data: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProfileMeta {
    id: String,
    name: String,
    server: String,
    #[serde(rename = "networkCode")]
    network_code: String,
    #[serde(rename = "deviceName")]
    device_name: String,
    #[serde(rename = "ctrlPort", alias = "apiPort")]
    ctrl_port: u16,
    #[serde(default = "default_tun_name", rename = "tunName")]
    tun_name: String,
    #[serde(default, rename = "noTun")]
    no_tun: bool,
    #[serde(default = "default_rtx")]
    rtx: bool,
    #[serde(rename = "createdAtIso")]
    created_at_iso: String,
    #[serde(default)]
    checked: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct ProfileRuntimeSummary {
    status: String,
    running: bool,
    virtual_ip: Option<String>,
    online_count: u32,
    offline_count: u32,
    upload_bytes_per_second: u64,
    download_bytes_per_second: u64,
    total_tx_bytes: u64,
    total_rx_bytes: u64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct ManagedProfileSnapshot {
    profile: ProfileMeta,
    runtime: ProfileRuntimeSummary,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct DashboardSummary {
    checked_profile_count: usize,
    running_profile_count: usize,
    connected_profile_count: usize,
    total_online_count: u64,
    total_offline_count: u64,
    aggregate_upload_bytes_per_second: u64,
    aggregate_download_bytes_per_second: u64,
    aggregate_total_tx_bytes: u64,
    aggregate_total_rx_bytes: u64,
    overall_status: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct PeerListItem {
    peer_name: String,
    peer_virtual_ip: String,
    online: bool,
    latency_ms: Option<u32>,
    source_profile_id: String,
    source_profile_name: String,
    source_profile_virtual_ip: Option<String>,
    version: String,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProfileActionRequest {
    profile_ids: Vec<String>,
}

#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
struct OperationResult {
    requested_ids: Vec<String>,
    connected_ids: Vec<String>,
    disconnected_ids: Vec<String>,
    skipped_ids: Vec<String>,
    failed: Vec<OperationFailure>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct OperationFailure {
    profile_id: String,
    reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TunAdapterCleanupSkipped {
    name: String,
    reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TunAdapterCleanupResult {
    cleaned: Vec<String>,
    kept: Vec<String>,
    skipped: Vec<TunAdapterCleanupSkipped>,
    unsupported: bool,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args = Args::parse();
    ensure_data_dirs(&args.data_dir)?;
    if let Some(parent) = args.port_file.parent() {
        fs::create_dir_all(parent)?;
    }
    if args.port_file.exists() {
        let _ = fs::remove_file(&args.port_file);
    }

    let state = AppState {
        inner: Arc::new(Mutex::new(ManagerState {
            sessions: HashMap::new(),
            traffic_samples: HashMap::new(),
        })),
        data_dir: args.data_dir.clone(),
        cli_executable: args.cli_executable.clone(),
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/dashboard/summary", get(get_dashboard_summary))
        .route("/profiles", get(get_profiles))
        .route("/profiles/connect", post(connect_profiles))
        .route("/profiles/disconnect", post(disconnect_profiles))
        .route(
            "/adapters/cleanup-unused",
            post(cleanup_unused_tun_adapters),
        )
        .route("/peers", get(get_peers))
        .route("/internal/shutdown", post(shutdown_manager))
        .with_state(state.clone());

    let listener = TcpListener::bind(args.addr).await?;
    let actual_addr = listener.local_addr()?;
    fs::write(&args.port_file, actual_addr.port().to_string())?;
    println!("vntc_manager listening on http://{}", actual_addr);

    axum::serve(listener, app)
        .with_graceful_shutdown(async move {
            let _ = tokio::signal::ctrl_c().await;
            state.stop_all();
        })
        .await?;

    Ok(())
}

async fn health() -> Json<ApiResponse<&'static str>> {
    Json(ApiResponse::success("ok"))
}

async fn get_profiles(
    State(state): State<AppState>,
) -> Json<ApiResponse<Vec<ManagedProfileSnapshot>>> {
    match state.build_profile_snapshots().await {
        Ok(data) => Json(ApiResponse::success(data)),
        Err(error) => Json(ApiResponse::error(error.to_string())),
    }
}

async fn get_dashboard_summary(
    State(state): State<AppState>,
) -> Json<ApiResponse<DashboardSummary>> {
    match state.build_profile_snapshots().await {
        Ok(snapshots) => Json(ApiResponse::success(build_dashboard_summary(&snapshots))),
        Err(error) => Json(ApiResponse::error(error.to_string())),
    }
}

async fn get_peers(State(state): State<AppState>) -> Json<ApiResponse<Vec<PeerListItem>>> {
    match state.build_peer_list().await {
        Ok(data) => Json(ApiResponse::success(data)),
        Err(error) => Json(ApiResponse::error(error.to_string())),
    }
}

async fn connect_profiles(
    State(state): State<AppState>,
    Json(req): Json<ProfileActionRequest>,
) -> Json<ApiResponse<OperationResult>> {
    match state.connect_profiles(req.profile_ids) {
        Ok(result) => Json(ApiResponse::success(result)),
        Err(error) => Json(ApiResponse::error(error.to_string())),
    }
}

async fn disconnect_profiles(
    State(state): State<AppState>,
    Json(req): Json<ProfileActionRequest>,
) -> Json<ApiResponse<OperationResult>> {
    match state.disconnect_profiles(req.profile_ids) {
        Ok(result) => Json(ApiResponse::success(result)),
        Err(error) => Json(ApiResponse::error(error.to_string())),
    }
}

async fn cleanup_unused_tun_adapters(
    State(state): State<AppState>,
) -> Json<ApiResponse<TunAdapterCleanupResult>> {
    match state.cleanup_unused_tun_adapters() {
        Ok(result) => Json(ApiResponse::success(result)),
        Err(error) => Json(ApiResponse::error(error.to_string())),
    }
}

async fn shutdown_manager(State(state): State<AppState>) -> Json<ApiResponse<()>> {
    state.stop_all();
    tokio::spawn(async {
        tokio::time::sleep(Duration::from_millis(120)).await;
        std::process::exit(0);
    });
    Json(ApiResponse::success(()))
}

impl AppState {
    fn profile_root(&self) -> PathBuf {
        self.data_dir.join("profiles")
    }

    fn runtime_root(&self) -> PathBuf {
        self.data_dir.join("runtime")
    }

    fn logs_root(&self) -> PathBuf {
        self.data_dir.join("logs")
    }

    fn profile_dir(&self, profile_id: &str) -> PathBuf {
        self.profile_root().join(profile_id)
    }

    fn profile_toml_path(&self, profile_id: &str) -> PathBuf {
        self.profile_dir(profile_id).join("vnt.toml")
    }

    fn profile_runtime_dir(&self, profile_id: &str) -> PathBuf {
        self.runtime_root().join(profile_id)
    }

    fn profile_log_path(&self, profile_id: &str) -> PathBuf {
        self.logs_root().join(format!("{profile_id}.log"))
    }

    fn load_profiles(&self) -> anyhow::Result<Vec<ProfileMeta>> {
        let mut result = Vec::new();
        if !self.profile_root().exists() {
            return Ok(result);
        }

        for entry in fs::read_dir(self.profile_root())? {
            let entry = entry?;
            if !entry.file_type()?.is_dir() {
                continue;
            }
            let meta_path = entry.path().join("meta.json");
            if !meta_path.exists() {
                continue;
            }
            let content = fs::read_to_string(&meta_path)
                .with_context(|| format!("read meta failed: {}", meta_path.display()))?;
            let mut profile: ProfileMeta = serde_json::from_str(&content)
                .with_context(|| format!("parse meta failed: {}", meta_path.display()))?;
            if profile.tun_name.is_empty() {
                profile.tun_name = build_tun_name(&profile.id);
            }
            result.push(profile);
        }

        result.sort_by(|a, b| a.created_at_iso.cmp(&b.created_at_iso));
        Ok(result)
    }

    fn cleanup_exited_sessions(&self) {
        let mut state = self.inner.lock();
        let mut exited_ids = Vec::new();
        for (profile_id, session) in &mut state.sessions {
            match session.child.try_wait() {
                Ok(Some(_)) => exited_ids.push(profile_id.clone()),
                Ok(None) => {}
                Err(_) => exited_ids.push(profile_id.clone()),
            }
        }

        for profile_id in exited_ids {
            state.sessions.remove(&profile_id);
            state.traffic_samples.remove(&profile_id);
        }
    }

    fn session_is_running(&self, profile_id: &str) -> bool {
        self.cleanup_exited_sessions();
        self.inner.lock().sessions.contains_key(profile_id)
    }

    fn connect_profiles(&self, profile_ids: Vec<String>) -> anyhow::Result<OperationResult> {
        self.cleanup_exited_sessions();
        let profiles = self.load_profiles()?;
        let profile_map: HashMap<String, ProfileMeta> = profiles
            .into_iter()
            .map(|profile| (profile.id.clone(), profile))
            .collect();
        let mut result = OperationResult::default();

        for profile_id in profile_ids {
            result.requested_ids.push(profile_id.clone());
            let Some(profile) = profile_map.get(&profile_id) else {
                result.failed.push(OperationFailure {
                    profile_id,
                    reason: "配置不存在".to_string(),
                });
                continue;
            };

            if self.session_is_running(&profile.id) {
                result.skipped_ids.push(profile.id.clone());
                continue;
            }

            let toml_path = self.profile_toml_path(&profile.id);
            if !toml_path.exists() {
                result.failed.push(OperationFailure {
                    profile_id: profile.id.clone(),
                    reason: "缺少 vnt.toml".to_string(),
                });
                continue;
            }

            fs::create_dir_all(self.profile_runtime_dir(&profile.id))?;
            let log_path = self.profile_log_path(&profile.id);
            let mut log_file = OpenOptions::new()
                .create(true)
                .append(true)
                .open(&log_path)
                .with_context(|| format!("open log failed: {}", log_path.display()))?;
            writeln!(
                log_file,
                "[{}] 启动 {} ({})",
                timestamp_string(),
                profile.name,
                profile.server
            )?;
            let stdout = log_file.try_clone()?;
            let stderr = log_file.try_clone()?;

            let child = Command::new(&self.cli_executable)
                .arg("--conf")
                .arg(&toml_path)
                .current_dir(self.profile_runtime_dir(&profile.id))
                .stdout(Stdio::from(stdout))
                .stderr(Stdio::from(stderr))
                .spawn()
                .with_context(|| format!("start cli failed: {}", self.cli_executable.display()));

            match child {
                Ok(child) => {
                    self.inner
                        .lock()
                        .sessions
                        .insert(profile.id.clone(), ManagedSession { child });
                    result.connected_ids.push(profile.id.clone());
                }
                Err(error) => {
                    result.failed.push(OperationFailure {
                        profile_id: profile.id.clone(),
                        reason: error.to_string(),
                    });
                }
            }
        }

        Ok(result)
    }

    fn disconnect_profiles(&self, profile_ids: Vec<String>) -> anyhow::Result<OperationResult> {
        self.cleanup_exited_sessions();
        let mut result = OperationResult::default();
        let mut state = self.inner.lock();

        for profile_id in profile_ids {
            result.requested_ids.push(profile_id.clone());
            let Some(mut session) = state.sessions.remove(&profile_id) else {
                result.skipped_ids.push(profile_id.clone());
                continue;
            };
            state.traffic_samples.remove(&profile_id);
            match session.child.kill() {
                Ok(_) => {
                    let _ = session.child.wait();
                    result.disconnected_ids.push(profile_id);
                }
                Err(error) => {
                    result.failed.push(OperationFailure {
                        profile_id,
                        reason: error.to_string(),
                    });
                }
            }
        }

        Ok(result)
    }

    fn stop_all(&self) {
        let ids = {
            self.cleanup_exited_sessions();
            self.inner
                .lock()
                .sessions
                .keys()
                .cloned()
                .collect::<Vec<String>>()
        };
        let _ = self.disconnect_profiles(ids);
    }

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

    #[cfg(windows)]
    fn cleanup_unused_tun_adapters_windows(&self) -> anyhow::Result<TunAdapterCleanupResult> {
        let keep_names = self
            .load_profiles()?
            .into_iter()
            .filter_map(|profile| {
                let name = profile.tun_name.trim().to_string();
                if name.is_empty() { None } else { Some(name) }
            })
            .collect::<Vec<String>>();
        let keep_names_json =
            serde_json::to_string(&keep_names).context("serialize keep tun names failed")?;

        let output = Command::new("powershell.exe")
            .args([
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                CLEANUP_UNUSED_TUN_ADAPTERS_PS,
            ])
            .env("VNTC_KEEP_TUN_NAMES", keep_names_json)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .context("run adapter cleanup failed")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(anyhow!("adapter cleanup failed: {}", stderr.trim()));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let json_line = stdout
            .lines()
            .rev()
            .map(str::trim)
            .find(|line| line.starts_with('{'))
            .ok_or_else(|| anyhow!("adapter cleanup did not return JSON"))?;
        serde_json::from_str(json_line).context("parse adapter cleanup result failed")
    }

    async fn build_profile_snapshots(&self) -> anyhow::Result<Vec<ManagedProfileSnapshot>> {
        self.cleanup_exited_sessions();
        let profiles = self.load_profiles()?;
        let mut snapshots = Vec::with_capacity(profiles.len());

        for profile in profiles {
            let runtime = self.profile_runtime_summary(&profile).await;
            snapshots.push(ManagedProfileSnapshot { profile, runtime });
        }

        Ok(snapshots)
    }

    async fn build_peer_list(&self) -> anyhow::Result<Vec<PeerListItem>> {
        self.cleanup_exited_sessions();
        let profiles = self.load_profiles()?;
        let mut peers = Vec::new();

        for profile in profiles {
            if !self.session_is_running(&profile.id) {
                continue;
            }

            let app_info = match ipc_app_info(profile.ctrl_port).await {
                Ok(info) => info,
                Err(_) => continue,
            };
            let peer_virtual_ip = app_info.ip.map(|value| Ipv4Addr::from(value).to_string());
            let client_list = match ipc_client_list(profile.ctrl_port).await {
                Ok(list) => list,
                Err(_) => continue,
            };

            peers.extend(client_list.items.into_iter().map(|item| PeerListItem {
                peer_name: item.name,
                peer_virtual_ip: Ipv4Addr::from(item.ip).to_string(),
                online: item.online,
                latency_ms: item.rtt,
                source_profile_id: profile.id.clone(),
                source_profile_name: profile.name.clone(),
                source_profile_virtual_ip: peer_virtual_ip.clone(),
                version: item.version,
            }));
        }

        peers.sort_by(|a, b| {
            if a.online != b.online {
                return b.online.cmp(&a.online);
            }
            a.source_profile_name
                .cmp(&b.source_profile_name)
                .then(a.peer_virtual_ip.cmp(&b.peer_virtual_ip))
        });
        Ok(peers)
    }

    async fn profile_runtime_summary(&self, profile: &ProfileMeta) -> ProfileRuntimeSummary {
        if !self.session_is_running(&profile.id) {
            return ProfileRuntimeSummary {
                status: "stopped".to_string(),
                running: false,
                virtual_ip: None,
                online_count: 0,
                offline_count: 0,
                upload_bytes_per_second: 0,
                download_bytes_per_second: 0,
                total_tx_bytes: 0,
                total_rx_bytes: 0,
            };
        }

        let app_info = match ipc_app_info(profile.ctrl_port).await {
            Ok(info) => info,
            Err(_) => {
                return ProfileRuntimeSummary {
                    status: "starting".to_string(),
                    running: true,
                    virtual_ip: None,
                    online_count: 0,
                    offline_count: 0,
                    upload_bytes_per_second: 0,
                    download_bytes_per_second: 0,
                    total_tx_bytes: 0,
                    total_rx_bytes: 0,
                };
            }
        };

        let traffic_list = ipc_traffic_list(profile.ctrl_port)
            .await
            .unwrap_or_else(|_| TrafficInfoList { items: Vec::new() });
        let total_tx_bytes = traffic_list
            .items
            .iter()
            .map(|item| item.tx_bytes)
            .sum::<u64>();
        let total_rx_bytes = traffic_list
            .items
            .iter()
            .map(|item| item.rx_bytes)
            .sum::<u64>();

        let now = Instant::now();
        let previous = {
            let state = self.inner.lock();
            state.traffic_samples.get(&profile.id).copied()
        };

        let (upload_bytes_per_second, download_bytes_per_second) = if let Some(previous) = previous
        {
            let elapsed_ms = now
                .saturating_duration_since(previous.recorded_at)
                .as_millis()
                .max(1) as u64;
            (
                total_tx_bytes.saturating_sub(previous.total_tx_bytes) * 1000 / elapsed_ms,
                total_rx_bytes.saturating_sub(previous.total_rx_bytes) * 1000 / elapsed_ms,
            )
        } else {
            (0, 0)
        };

        self.inner.lock().traffic_samples.insert(
            profile.id.clone(),
            TrafficSample {
                recorded_at: now,
                total_tx_bytes,
                total_rx_bytes,
            },
        );

        ProfileRuntimeSummary {
            status: "running".to_string(),
            running: true,
            virtual_ip: app_info.ip.map(|value| Ipv4Addr::from(value).to_string()),
            online_count: app_info.online_client_num,
            offline_count: app_info.offline_client_num,
            upload_bytes_per_second,
            download_bytes_per_second,
            total_tx_bytes,
            total_rx_bytes,
        }
    }
}

fn build_dashboard_summary(snapshots: &[ManagedProfileSnapshot]) -> DashboardSummary {
    let checked_profile_count = snapshots.iter().filter(|item| item.profile.checked).count();
    let running_profile_count = snapshots.iter().filter(|item| item.runtime.running).count();
    let total_online_count = snapshots
        .iter()
        .map(|item| u64::from(item.runtime.online_count))
        .sum::<u64>();
    let total_offline_count = snapshots
        .iter()
        .map(|item| u64::from(item.runtime.offline_count))
        .sum::<u64>();
    let aggregate_upload_bytes_per_second = snapshots
        .iter()
        .map(|item| item.runtime.upload_bytes_per_second)
        .sum::<u64>();
    let aggregate_download_bytes_per_second = snapshots
        .iter()
        .map(|item| item.runtime.download_bytes_per_second)
        .sum::<u64>();
    let aggregate_total_tx_bytes = snapshots
        .iter()
        .map(|item| item.runtime.total_tx_bytes)
        .sum::<u64>();
    let aggregate_total_rx_bytes = snapshots
        .iter()
        .map(|item| item.runtime.total_rx_bytes)
        .sum::<u64>();

    let overall_status = if running_profile_count == 0 {
        "stopped"
    } else if snapshots
        .iter()
        .any(|item| item.runtime.status == "starting")
        || (checked_profile_count > 0 && running_profile_count < checked_profile_count)
    {
        "partial"
    } else {
        "running"
    };

    DashboardSummary {
        checked_profile_count,
        running_profile_count,
        connected_profile_count: running_profile_count,
        total_online_count,
        total_offline_count,
        aggregate_upload_bytes_per_second,
        aggregate_download_bytes_per_second,
        aggregate_total_tx_bytes,
        aggregate_total_rx_bytes,
        overall_status: overall_status.to_string(),
    }
}

async fn ipc_app_info(port: u16) -> anyhow::Result<AppInfo> {
    match send_ipc_request(port, IpcCmd::AppInfo(AppInfoCmd {})).await? {
        ResponsePayload::AppInfo(info) => Ok(info),
        _ => Err(anyhow!("unexpected IPC response for AppInfo")),
    }
}

async fn ipc_client_list(port: u16) -> anyhow::Result<ClientInfoList> {
    match send_ipc_request(port, IpcCmd::ClientList(ClientListCmd {})).await? {
        ResponsePayload::ClientList(list) => Ok(list),
        _ => Err(anyhow!("unexpected IPC response for ClientList")),
    }
}

async fn ipc_traffic_list(port: u16) -> anyhow::Result<TrafficInfoList> {
    match send_ipc_request(port, IpcCmd::TrafficList(TrafficListCmd {})).await? {
        ResponsePayload::TrafficList(list) => Ok(list),
        _ => Err(anyhow!("unexpected IPC response for TrafficList")),
    }
}

async fn send_ipc_request(port: u16, cmd: IpcCmd) -> anyhow::Result<ResponsePayload> {
    let addr = format!("127.0.0.1:{port}");
    let stream = timeout(Duration::from_secs(2), TcpStream::connect(addr))
        .await
        .context("IPC connect timeout")??;
    let mut framed = Framed::new(stream, LengthDelimitedCodec::new());

    framed
        .send(IpcRequest { ipc_cmd: Some(cmd) }.encode_to_vec().into())
        .await
        .context("send IPC request failed")?;

    let response = framed.next().await.context("IPC response missing")??;
    let decoded = IpcResponse::decode(response).context("decode IPC response failed")?;
    decoded
        .response_payload
        .context("response payload is empty")
}

fn ensure_data_dirs(data_dir: &Path) -> anyhow::Result<()> {
    fs::create_dir_all(data_dir.join("settings"))?;
    fs::create_dir_all(data_dir.join("profiles"))?;
    fs::create_dir_all(data_dir.join("runtime"))?;
    fs::create_dir_all(data_dir.join("logs"))?;
    Ok(())
}

fn default_rtx() -> bool {
    true
}

fn default_tun_name() -> String {
    "vntc-default".to_string()
}

fn build_tun_name(profile_id: &str) -> String {
    let suffix = if profile_id.len() > 24 {
        &profile_id[..24]
    } else {
        profile_id
    };
    format!("vntc-{suffix}")
}

fn timestamp_string() -> String {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    seconds.to_string()
}
