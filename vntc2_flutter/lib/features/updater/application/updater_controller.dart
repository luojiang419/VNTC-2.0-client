import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/dashboard_controller.dart';
import '../../../core/localization.dart';
import '../data/updater_service.dart';
import '../domain/app_update_config.dart';
import '../domain/update_models.dart';

class UpdaterController extends ValueNotifier<UpdaterState> {
  UpdaterController({
    required DashboardController dashboardController,
    required UpdaterService service,
  }) : _dashboardController = dashboardController,
       _service = service,
       super(const UpdaterState.initial());

  final DashboardController _dashboardController;
  final UpdaterService _service;

  bool _startupFlowStarted = false;

  Future<void> beginStartupFlow() async {
    if (_startupFlowStarted) {
      return;
    }
    _startupFlowStarted = true;
    _clearPendingUpdateIfCurrentOrMissing();
    await checkForUpdates(manual: false);
  }

  Future<void> checkForUpdates({bool manual = true}) async {
    if (value.isBusy) {
      _setStatus(_t('正在检查或下载更新，请稍候。', 'Checking or downloading updates.'));
      return;
    }

    _clearPendingUpdateIfCurrentOrMissing();

    value = value.copyWith(
      isBusy: true,
      statusMessage: manual
          ? _t('正在检查最新版本...', 'Checking for updates...')
          : _t('启动后正在检查最新版本...', 'Checking for updates on startup...'),
      readyVersionTag: null,
      readyInstallerPath: null,
      downloadProgress: null,
      readyFromManualCheck: manual,
    );

    try {
      final release = await _service.fetchLatestRelease();
      if (UpdaterService.compareVersionTags(
            release.versionTag,
            AppUpdateConfig.currentVersionTag,
          ) <=
          0) {
        value = value.copyWith(
          isBusy: false,
          statusMessage: _t(
            '当前已是最新版本：${AppUpdateConfig.currentVersionTag}',
            'Already up to date: ${AppUpdateConfig.currentVersionTag}',
          ),
          downloadProgress: null,
        );
        return;
      }

      final pending = _readPendingUpdate();
      if (pending != null) {
        if (_pendingMatchesRelease(pending, release)) {
          await _savePendingUpdate(
            versionTag: release.versionTag,
            installerPath: pending.installerPath,
          );
          if (!manual && _isUpdatePromptDismissed(release.versionTag)) {
            value = value.copyWith(
              isBusy: false,
              statusMessage: _t(
                '已暂缓安装更新：${release.versionTag}',
                'Update postponed: ${release.versionTag}',
              ),
              downloadProgress: null,
              readyVersionTag: null,
              readyInstallerPath: null,
              readyFromManualCheck: false,
            );
            return;
          }
          _setReady(
            versionTag: release.versionTag,
            installerPath: pending.installerPath,
            manual: manual,
            message: _t(
              '已复用已下载更新包：${release.versionTag}',
              'Reusing downloaded update: ${release.versionTag}',
            ),
          );
          return;
        }
        await _clearPendingUpdate();
      }

      final existingInstaller = _existingInstallerFor(release);
      if (existingInstaller != null) {
        await _savePendingUpdate(
          versionTag: release.versionTag,
          installerPath: existingInstaller.path,
        );
        if (!manual && _isUpdatePromptDismissed(release.versionTag)) {
          value = value.copyWith(
            isBusy: false,
            statusMessage: _t(
              '已暂缓安装更新：${release.versionTag}',
              'Update postponed: ${release.versionTag}',
            ),
            downloadProgress: null,
            readyVersionTag: null,
            readyInstallerPath: null,
            readyFromManualCheck: false,
          );
          return;
        }
        _setReady(
          versionTag: release.versionTag,
          installerPath: existingInstaller.path,
          manual: manual,
          message: _t(
            '已复用已下载更新包：${release.versionTag}',
            'Reusing downloaded update: ${release.versionTag}',
          ),
        );
        return;
      }

      value = value.copyWith(
        statusMessage: _t(
          '发现新版本 ${release.versionTag}，正在下载更新包...',
          'New version ${release.versionTag} found. Downloading...',
        ),
        downloadProgress: 0.0,
      );
      final installer = await _service.downloadInstaller(
        release: release,
        onProgress: (progress) {
          value = value.copyWith(downloadProgress: progress);
        },
      );
      await _savePendingUpdate(
        versionTag: release.versionTag,
        installerPath: installer.path,
        clearDismissedPrompt: true,
      );
      _setReady(
        versionTag: release.versionTag,
        installerPath: installer.path,
        manual: manual,
        message: _t(
          '更新包已下载完成：${release.versionTag}',
          'Update downloaded: ${release.versionTag}',
        ),
      );
    } on UpdateException catch (error) {
      if (_emitPendingUpdate(manual: manual)) {
        return;
      }
      value = value.copyWith(
        isBusy: false,
        statusMessage: error.message,
        downloadProgress: null,
      );
    } catch (error) {
      if (_emitPendingUpdate(manual: manual)) {
        return;
      }
      value = value.copyWith(
        isBusy: false,
        statusMessage: _t('检查更新失败：$error', 'Update check failed: $error'),
        downloadProgress: null,
      );
    }
  }

  Future<bool> installPendingUpdateNow({
    Future<void> Function()? quitApp,
  }) async {
    _clearPendingUpdateIfCurrentOrMissing();
    final pending = _readPendingUpdate();
    if (pending == null) {
      _setStatus(_t('当前没有可安装的更新包。', 'No installable update is ready.'));
      return false;
    }

    try {
      final launched = await _service.launchInstaller(
        versionTag: pending.versionTag,
        installerPath: pending.installerPath,
      );
      if (!launched) {
        _setStatus(_t('无法启动更新安装脚本。', 'Failed to start update script.'));
        return false;
      }
      _setStatus(
        _t(
          '正在退出程序并打开更新安装包：${pending.versionTag}',
          'Exiting and opening update installer: ${pending.versionTag}',
        ),
      );
      if (quitApp != null) {
        unawaited(quitApp());
      } else {
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 500), () {
            exit(0);
          }),
        );
      }
      return true;
    } on UpdateException catch (error) {
      _setStatus(error.message);
      return false;
    } catch (error) {
      _setStatus(_t('启动更新安装脚本失败：$error', 'Failed to start update: $error'));
      return false;
    }
  }

  Future<void> dismissReadyPrompt() async {
    final versionTag = value.readyVersionTag;
    if (versionTag != null) {
      await _saveDismissedUpdatePrompt(versionTag);
    }
    value = value.copyWith(readyFromManualCheck: false);
  }

  File? _existingInstallerFor(UpdateReleaseInfo release) {
    final candidates = [_service.installerFileFor(release)];
    for (final file in candidates) {
      if (!file.existsSync()) {
        continue;
      }
      if (release.installerSize > 0 &&
          file.lengthSync() != release.installerSize) {
        continue;
      }
      return file;
    }
    return null;
  }

  bool _pendingMatchesRelease(
    _PendingUpdate pending,
    UpdateReleaseInfo release,
  ) {
    if (UpdaterService.compareVersionTags(
          pending.versionTag,
          release.versionTag,
        ) !=
        0) {
      return false;
    }
    if (release.installerSize <= 0) {
      return true;
    }
    final installer = File(pending.installerPath);
    return installer.existsSync() &&
        installer.lengthSync() == release.installerSize;
  }

  bool _emitPendingUpdate({required bool manual}) {
    final pending = _readPendingUpdate();
    if (pending == null) {
      return false;
    }
    if (!manual && _isUpdatePromptDismissed(pending.versionTag)) {
      value = value.copyWith(
        isBusy: false,
        statusMessage: _t(
          '已暂缓安装更新：${pending.versionTag}',
          'Update postponed: ${pending.versionTag}',
        ),
      );
      return false;
    }
    _setReady(
      versionTag: pending.versionTag,
      installerPath: pending.installerPath,
      manual: manual,
      message: _t(
        '已找到待安装更新：${pending.versionTag}',
        'Ready to install update: ${pending.versionTag}',
      ),
    );
    return true;
  }

  _PendingUpdate? _readPendingUpdate() {
    final settings = _dashboardController.settings;
    final versionTag = UpdaterService.normalizeVersionTag(
      settings.pendingUpdateVersionTag ?? '',
    );
    final installerPath = settings.pendingUpdateInstallerPath ?? '';
    if (versionTag.isEmpty || installerPath.trim().isEmpty) {
      return null;
    }
    final installer = File(installerPath);
    if (!installer.existsSync()) {
      return null;
    }
    if (!UpdaterService.installerNameMatchesExpected(
      _basename(installer.path),
      versionTag,
    )) {
      return null;
    }
    if (UpdaterService.compareVersionTags(
          versionTag,
          AppUpdateConfig.currentVersionTag,
        ) <=
        0) {
      return null;
    }
    return _PendingUpdate(versionTag: versionTag, installerPath: installerPath);
  }

  void _clearPendingUpdateIfCurrentOrMissing() {
    final versionTag = UpdaterService.normalizeVersionTag(
      _dashboardController.settings.pendingUpdateVersionTag ?? '',
    );
    if (versionTag.isEmpty) {
      return;
    }
    if (_readPendingUpdate() == null) {
      unawaited(_clearPendingUpdate());
    }
  }

  bool _isUpdatePromptDismissed(String versionTag) {
    final dismissedVersionTag = UpdaterService.normalizeVersionTag(
      _dashboardController.settings.dismissedUpdatePromptVersion ?? '',
    );
    if (dismissedVersionTag.isEmpty) {
      return false;
    }
    return UpdaterService.compareVersionTags(dismissedVersionTag, versionTag) ==
        0;
  }

  Future<void> _savePendingUpdate({
    required String versionTag,
    required String installerPath,
    bool clearDismissedPrompt = false,
  }) {
    return _dashboardController.saveSettings(
      _dashboardController.settings.copyWith(
        pendingUpdateVersionTag: versionTag,
        pendingUpdateInstallerPath: installerPath,
        clearDismissedUpdatePromptVersion: clearDismissedPrompt,
      ),
    );
  }

  Future<void> _clearPendingUpdate() {
    return _dashboardController.saveSettings(
      _dashboardController.settings.copyWith(
        clearPendingUpdate: true,
        clearDismissedUpdatePromptVersion: true,
      ),
    );
  }

  Future<void> _saveDismissedUpdatePrompt(String versionTag) {
    return _dashboardController.saveSettings(
      _dashboardController.settings.copyWith(
        dismissedUpdatePromptVersion: versionTag,
      ),
    );
  }

  void _setReady({
    required String versionTag,
    required String installerPath,
    required bool manual,
    required String message,
  }) {
    value = value.copyWith(
      isBusy: false,
      statusMessage: message,
      readyVersionTag: versionTag,
      readyInstallerPath: installerPath,
      downloadProgress: 1.0,
      readyFromManualCheck: manual,
    );
  }

  void _setStatus(String message) {
    value = value.copyWith(statusMessage: message);
  }

  String _t(String zhHans, String en) {
    return trByLanguage(_dashboardController.settings.language, zhHans, en);
  }

  String _basename(String path) {
    final separator = Platform.pathSeparator;
    final index = path.lastIndexOf(separator);
    if (index < 0) {
      return path;
    }
    return path.substring(index + 1);
  }
}

class _PendingUpdate {
  const _PendingUpdate({required this.versionTag, required this.installerPath});

  final String versionTag;
  final String installerPath;
}
