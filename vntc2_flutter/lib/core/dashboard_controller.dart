import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'localization.dart';
import 'models.dart';
import 'repository.dart';
import 'startup_manager.dart';
import 'vnt_runtime.dart';

class DashboardController extends ChangeNotifier {
  DashboardController._({
    required this.repository,
    required this.settings,
    required this.vntExecutablePath,
    required this.managerExecutablePath,
    required this.autoStartManager,
  }) {
    if (managerExecutablePath != null && vntExecutablePath != null) {
      runtime = VntRuntime(
        managerExecutablePath: managerExecutablePath!,
        cliExecutablePath: vntExecutablePath!,
        paths: repository.paths,
      );
    }
  }

  final AppRepository repository;
  final String? vntExecutablePath;
  final String? managerExecutablePath;
  final WindowsAutoStartManager autoStartManager;
  VntRuntime? runtime;

  AppSettings settings;
  bool isLoading = true;
  bool isBusy = false;
  String? errorMessage;
  String? selectedProfileId;
  DashboardSummary summary = DashboardSummary.empty();
  List<ManagedProfileSnapshot> profileSnapshots =
      const <ManagedProfileSnapshot>[];
  List<AggregatedPeer> peers = const <AggregatedPeer>[];

  Timer? _pollingTimer;
  bool _shutdownInvoked = false;

  static Future<DashboardController> create() async {
    final repository = await AppRepository.open();
    await repository.ensureBootstrapData();
    final settings = await repository.loadSettings();
    final controller = DashboardController._(
      repository: repository,
      settings: settings,
      vntExecutablePath: await repository.paths.findVntCliExecutable(),
      managerExecutablePath: await repository.paths.findManagerExecutable(),
      autoStartManager: WindowsAutoStartManager(
        executablePath: Platform.resolvedExecutable,
      ),
    );
    await controller._bootstrap();
    return controller;
  }

  List<VntProfile> get profiles =>
      profileSnapshots.map((item) => item.profile).toList(growable: false);

  VntProfile? get selectedProfile {
    final selectedId = selectedProfileId;
    if (selectedId == null) {
      return null;
    }
    for (final snapshot in profileSnapshots) {
      if (snapshot.profile.id == selectedId) {
        return snapshot.profile;
      }
    }
    return null;
  }

  ManagedProfileSnapshot? get selectedProfileSnapshot {
    final selectedId = selectedProfileId;
    if (selectedId == null) {
      return null;
    }
    for (final snapshot in profileSnapshots) {
      if (snapshot.profile.id == selectedId) {
        return snapshot;
      }
    }
    return null;
  }

  int get checkedProfileCount =>
      profileSnapshots.where((item) => item.profile.checked).length;

  bool get hasCheckedProfiles => checkedProfileCount > 0;

  bool get allCheckedProfilesRunning {
    final checked = profileSnapshots
        .where((item) => item.profile.checked)
        .toList();
    if (checked.isEmpty) {
      return false;
    }
    return checked.every((item) => item.runtime.running);
  }

  String get connectButtonLabel {
    if (!hasCheckedProfiles) {
      return _t('勾选后连接', 'Select profiles to connect');
    }
    return allCheckedProfilesRunning
        ? _t('断开勾选配置', 'Disconnect selected')
        : _t('连接勾选配置', 'Connect selected');
  }

  Future<void> _bootstrap() async {
    try {
      await autoStartManager.sync(settings);
    } catch (error) {
      errorMessage = _describeError(error);
    }

    final initialProfiles = await repository.loadProfiles();
    selectedProfileId =
        settings.selectedProfileId ??
        settings.defaultProfileId ??
        (initialProfiles.isEmpty ? null : initialProfiles.first.id);

    if (runtime == null) {
      isLoading = false;
      errorMessage = _t(
        '未找到 vntc_manager.exe 或 vnt2_cli.exe。',
        'vntc_manager.exe or vnt2_cli.exe was not found.',
      );
      notifyListeners();
      return;
    }

    await runtime!.start();
    if (settings.cleanupUnusedTunOnLaunch) {
      await cleanupUnusedTunAdapters(silent: true);
    }
    await refreshAll();

    if (settings.connectDefaultOnLaunch) {
      final checkedIds = profiles
          .where((profile) => profile.checked)
          .map((profile) => profile.id)
          .toList();
      if (checkedIds.isNotEmpty) {
        await connectProfiles(checkedIds, silent: true);
      } else if (settings.defaultProfileId != null) {
        await connectProfiles(<String>[
          settings.defaultProfileId!,
        ], silent: true);
      }
    }

    isLoading = false;
    notifyListeners();

    _pollingTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(refreshAll()),
    );
  }

  Future<void> refreshAll() async {
    final runtime = this.runtime;
    if (runtime == null) {
      return;
    }

    try {
      final nextProfiles = await runtime.fetchProfiles();
      final nextSummary = await runtime.fetchDashboardSummary();
      final nextPeers = await runtime.fetchPeers();

      profileSnapshots = nextProfiles;
      summary = nextSummary;
      peers = nextPeers;

      final stillExists = profileSnapshots.any(
        (item) => item.profile.id == selectedProfileId,
      );
      if (!stillExists) {
        selectedProfileId = profileSnapshots.isEmpty
            ? null
            : profileSnapshots.first.profile.id;
      }
      errorMessage = null;
      notifyListeners();
    } catch (error) {
      errorMessage =
          '${_t('刷新状态失败', 'Failed to refresh status')}: ${_describeError(error)}';
      notifyListeners();
    }
  }

  Future<void> toggleTheme() async {
    settings = settings.copyWith(darkMode: !settings.darkMode);
    await repository.saveSettings(settings);
    notifyListeners();
  }

  Future<void> saveSettings(AppSettings updated) async {
    try {
      await autoStartManager.sync(updated);
      await repository.saveSettings(updated);
      settings = updated;
      errorMessage = null;
    } catch (error) {
      errorMessage =
          '${_t('保存设置失败', 'Failed to save settings')}: ${_describeError(error)}';
    }
    notifyListeners();
  }

  Future<void> selectProfile(String profileId) async {
    selectedProfileId = profileId;
    settings = settings.copyWith(selectedProfileId: profileId);
    await repository.saveSettings(settings);
    notifyListeners();
  }

  Future<void> toggleProfileChecked(String profileId, bool checked) async {
    final target = profileSnapshots
        .firstWhere((item) => item.profile.id == profileId)
        .profile;
    await repository.saveProfile(target.copyWith(checked: checked));
    await refreshAll();
  }

  Future<void> connectCheckedProfiles() async {
    final ids = profiles
        .where((profile) => profile.checked)
        .map((profile) => profile.id)
        .toList();
    await connectProfiles(ids);
  }

  Future<void> connectProfiles(
    List<String> profileIds, {
    bool silent = false,
  }) async {
    final runtime = this.runtime;
    if (runtime == null) {
      errorMessage = _t('Rust Manager 未就绪', 'Rust Manager is not ready');
      notifyListeners();
      return;
    }
    if (profileIds.isEmpty) {
      if (!silent) {
        errorMessage = _t('请先勾选至少一个配置', 'Select at least one profile first');
        notifyListeners();
      }
      return;
    }

    isBusy = true;
    if (!silent) {
      errorMessage = null;
    }
    notifyListeners();

    try {
      final result = await runtime.connectProfiles(profileIds);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await refreshAll();
      if (result.hasFailure) {
        errorMessage = result.failed
            .map(
              (item) =>
                  '${item.profileId}: ${item.reason.isEmpty ? defaultOperationReason(settings.language) : item.reason}',
            )
            .join('; ');
      }
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> disconnectCheckedProfiles() async {
    final runtime = this.runtime;
    if (runtime == null) {
      return;
    }
    final ids = profiles
        .where((profile) => profile.checked)
        .map((profile) => profile.id)
        .toList();
    if (ids.isEmpty) {
      errorMessage = _t('请先勾选至少一个配置', 'Select at least one profile first');
      notifyListeners();
      return;
    }

    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await runtime.disconnectProfiles(ids);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await refreshAll();
      if (result.hasFailure) {
        errorMessage = result.failed
            .map(
              (item) =>
                  '${item.profileId}: ${item.reason.isEmpty ? defaultOperationReason(settings.language) : item.reason}',
            )
            .join('; ');
      }
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<TunAdapterCleanupResult?> cleanupUnusedTunAdapters({
    bool silent = false,
  }) async {
    final runtime = this.runtime;
    if (runtime == null) {
      if (!silent) {
        errorMessage = _t('Rust Manager 未就绪', 'Rust Manager is not ready');
        notifyListeners();
      }
      return null;
    }

    if (!silent) {
      isBusy = true;
      errorMessage = null;
      notifyListeners();
    }

    try {
      final result = await runtime.cleanupUnusedTunAdapters();
      if (result.unsupported && !silent) {
        errorMessage = _t(
          '当前系统不支持自动清理 TUN 虚拟网卡',
          'Automatic TUN adapter cleanup is not supported on this system',
        );
      }
      return result;
    } catch (error) {
      if (!silent) {
        errorMessage =
            '${_t('清理 TUN 网卡失败', 'Failed to clean TUN adapters')}: ${_describeError(error)}';
      }
      return null;
    } finally {
      if (!silent) {
        isBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> saveProfile({
    String? profileId,
    required String name,
    required String server,
    required String networkCode,
    required String deviceName,
    required bool rtx,
    required String? customIp,
    required String? password,
    required String? certMode,
    required bool compress,
    required bool fec,
    required bool noPunch,
    required bool noNat,
    required String? mtu,
    required bool allowMapping,
    required List<String> inputRoutes,
    required List<String> outputRoutes,
    required List<String> portMappings,
    required List<String> udpStunServers,
    required List<String> tcpStunServers,
  }) async {
    final existing = profiles.where((item) => item.id == profileId).toList();
    final resolvedId = profileId ?? _buildProfileId(name);
    final profile = VntProfile(
      id: resolvedId,
      name: name,
      server: server,
      networkCode: networkCode,
      deviceId: existing.isNotEmpty
          ? existing.first.deviceId
          : buildDeviceId(resolvedId),
      deviceName: deviceName,
      ctrlPort: existing.isNotEmpty
          ? existing.first.ctrlPort
          : _allocateNextCtrlPort(),
      tunName: existing.isNotEmpty
          ? existing.first.tunName
          : _allocateTunName(resolvedId),
      noTun: false,
      rtx: rtx,
      customIp: _normalizeText(customIp),
      password: _normalizeText(password),
      certMode: _normalizeText(certMode),
      compress: compress,
      fec: fec,
      noPunch: noPunch,
      noNat: noNat,
      mtu: _normalizeText(mtu),
      allowMapping: allowMapping,
      inputRoutes: inputRoutes,
      outputRoutes: outputRoutes,
      portMappings: portMappings,
      udpStunServers: udpStunServers,
      tcpStunServers: tcpStunServers,
      createdAtIso: existing.isNotEmpty
          ? existing.first.createdAtIso
          : DateTime.now().toIso8601String(),
      checked: existing.isNotEmpty ? existing.first.checked : false,
    );
    await repository.saveProfile(profile);

    if (selectedProfileId == null) {
      selectedProfileId = profile.id;
      settings = settings.copyWith(selectedProfileId: profile.id);
      await repository.saveSettings(settings);
    }

    await refreshAll();
  }

  Future<void> deleteSelectedProfile() async {
    final profile = selectedProfile;
    if (profile == null) {
      return;
    }

    if (selectedProfileSnapshot?.runtime.running ?? false) {
      await runtime?.disconnectProfiles(<String>[profile.id]);
    }
    await repository.deleteProfile(profile.id);

    if (settings.defaultProfileId == profile.id) {
      settings = settings.copyWith(clearDefaultProfileId: true);
    }
    if (selectedProfileId == profile.id) {
      selectedProfileId = null;
      settings = settings.copyWith(clearSelectedProfileId: true);
    }
    await repository.saveSettings(settings);
    await refreshAll();
  }

  int _allocateNextCtrlPort() {
    final used = profiles.map((item) => item.ctrlPort).toSet();
    var port = 11241;
    while (used.contains(port)) {
      port += 1;
    }
    return port;
  }

  String _allocateTunName(String profileId) {
    final used = profiles.map((item) => item.tunName).toSet();
    var candidate = buildTunName(profileId);
    var suffix = 1;
    while (used.contains(candidate)) {
      candidate = '${buildTunName(profileId)}-$suffix';
      suffix += 1;
    }
    return candidate;
  }

  String _buildProfileId(String name) {
    final base = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (base.isEmpty) {
      return 'profile-${DateTime.now().millisecondsSinceEpoch}';
    }
    var candidate = base;
    var suffix = 1;
    while (profiles.any((item) => item.id == candidate)) {
      candidate = '$base-$suffix';
      suffix += 1;
    }
    return candidate;
  }

  String? _normalizeText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String _t(String zhHans, String en) {
    return trByLanguage(settings.language, zhHans, en);
  }

  String _describeError(Object error) {
    final detail = _extractErrorDetail(error);
    return switch (detail) {
      'manager_start_timeout' => _t(
        'Rust Manager 启动超时',
        'Rust Manager startup timed out',
      ),
      'manager_not_ready' => _t(
        'Rust Manager 尚未就绪',
        'Rust Manager is not ready',
      ),
      'request_failed' => _t('请求失败', 'Request failed'),
      _ => detail,
    };
  }

  String _extractErrorDetail(Object error) {
    if (error is StateError) {
      return error.message.toString().trim();
    }
    if (error is HttpException) {
      return error.message.trim();
    }
    return error.toString().trim();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    unawaited(runtime?.dispose());
    super.dispose();
  }

  Future<void> shutdownApp() async {
    if (_shutdownInvoked) {
      return;
    }
    _shutdownInvoked = true;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    await runtime?.dispose();
  }
}
