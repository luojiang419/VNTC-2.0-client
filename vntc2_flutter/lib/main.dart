import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'core/dashboard_controller.dart';
import 'core/localization.dart';
import 'core/models.dart';
import 'core/startup_manager.dart';
import 'features/updater/application/updater_controller.dart';
import 'features/updater/data/updater_service.dart';
import 'features/updater/domain/update_models.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final controller = await DashboardController.create();
  final launchContext = LaunchContext.fromArgs(args);

  windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(800, 800),
      minimumSize: Size(800, 800),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    ),
    () async {
      if (launchContext.shouldStartHidden(controller.settings)) {
        await windowManager.hide();
        await windowManager.setSkipTaskbar(true);
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    },
  );

  runApp(VntcApp(controller: controller));
}

enum PeerTab { online, offline }

class VntcApp extends StatefulWidget {
  const VntcApp({super.key, required this.controller});

  final DashboardController controller;

  @override
  State<VntcApp> createState() => _VntcAppState();
}

class _VntcAppState extends State<VntcApp> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: appTitleForLanguage(widget.controller.settings.language),
          locale: localeForLanguage(widget.controller.settings.language),
          supportedLocales: supportedAppLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          themeMode: widget.controller.settings.darkMode
              ? ThemeMode.dark
              : ThemeMode.light,
          home: DesktopShell(controller: widget.controller),
        );
      },
    );
  }
}

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, required this.controller});

  final DashboardController controller;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell>
    with WindowListener, TrayListener {
  CloseAction? _lastCloseAction;
  AppLanguage? _lastLanguage;
  late final UpdaterController _updaterController;
  String? _lastUpdatePromptKey;
  bool _isQuitting = false;
  bool _trayInitialized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    _updaterController = UpdaterController(
      dashboardController: widget.controller,
      service: UpdaterService(paths: widget.controller.repository.paths),
    );
    _updaterController.addListener(_handleUpdaterChanged);
    unawaited(_updaterController.beginStartupFlow());
    unawaited(_initDesktopShell());
  }

  @override
  void dispose() {
    _updaterController.removeListener(_handleUpdaterChanged);
    _updaterController.dispose();
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  Future<void> _initDesktopShell() async {
    await _syncCloseBehavior();
    await _syncWindowTitle();
    await _initTray();
  }

  Future<void> _syncCloseBehavior() async {
    _lastCloseAction = widget.controller.settings.closeAction;
    await windowManager.setPreventClose(true);
  }

  Future<void> _initTray() async {
    if (_trayInitialized) {
      return;
    }
    final iconPath = await _resolveTrayIconPath();
    if (iconPath != null) {
      await trayManager.setIcon(iconPath);
    }
    await _syncTrayPresentation();
    _trayInitialized = true;
  }

  Future<void> _syncTrayPresentation() async {
    final language = widget.controller.settings.language;
    await trayManager.setToolTip(appTitleForLanguage(language));
    await trayManager.setContextMenu(_buildTrayMenu());
  }

  Future<void> _syncWindowTitle() async {
    await windowManager.setTitle(
      appTitleForLanguage(widget.controller.settings.language),
    );
  }

  Menu _buildTrayMenu() {
    final language = widget.controller.settings.language;
    return Menu(
      items: [
        MenuItem(
          key: 'show_window',
          label: trByLanguage(language, '显示主窗口', 'Show window'),
        ),
        MenuItem(
          key: 'connect_checked',
          label: trByLanguage(language, '连接勾选配置', 'Connect selected'),
        ),
        MenuItem(
          key: 'disconnect_checked',
          label: trByLanguage(language, '断开勾选配置', 'Disconnect selected'),
        ),
        MenuItem(
          key: 'open_settings',
          label: trByLanguage(language, '打开设置', 'Open settings'),
        ),
        MenuItem(
          key: 'check_updates',
          label: trByLanguage(language, '检查更新', 'Check for updates'),
        ),
        MenuItem(
          key: 'toggle_theme',
          label: trByLanguage(language, '切换深浅主题', 'Toggle theme'),
        ),
        MenuItem(
          key: 'connect_default',
          label: trByLanguage(language, '连接默认配置', 'Connect default'),
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit_app',
          label: trByLanguage(language, '退出程序', 'Exit app'),
        ),
      ],
    );
  }

  Future<String?> _resolveTrayIconPath() async {
    final executableDir = widget.controller.repository.paths.executableDir.path;
    final candidates = <String>[
      '$executableDir${Platform.pathSeparator}app_icon.ico',
    ];

    var current = Directory.current.absolute;
    while (true) {
      candidates.add(
        '${current.path}${Platform.pathSeparator}windows${Platform.pathSeparator}runner${Platform.pathSeparator}resources${Platform.pathSeparator}app_icon.ico',
      );
      final parent = current.parent;
      if (parent.path == current.path) {
        break;
      }
      current = parent;
    }

    for (final candidate in candidates) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }
    return null;
  }

  Future<void> _hideToTray() async {
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }

  Future<void> _restoreWindow() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _exitApplication() async {
    if (_isQuitting) {
      return;
    }
    _isQuitting = true;
    await trayManager.destroy();
    await widget.controller.shutdownApp();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  Future<void> _showInfoMessage(String message) async {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _handleUpdaterChanged() {
    final state = _updaterController.value;
    if (!mounted || !state.hasReadyUpdate) {
      return;
    }
    final promptKey = '${state.readyVersionTag}|${state.readyInstallerPath}';
    if (_lastUpdatePromptKey == promptKey) {
      return;
    }
    _lastUpdatePromptKey = promptKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _showUpdateReadyDialog(_updaterController);
    });
  }

  Future<void> _showUpdateReadyDialog(UpdaterController controller) async {
    final state = controller.value;
    if (!state.hasReadyUpdate) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            tr(
              context,
              '发现新版本 ${state.readyVersionTag}',
              'New version ${state.readyVersionTag}',
            ),
          ),
          content: SelectableText(
            tr(
              context,
              '更新包已准备好：\n${state.readyInstallerPath}',
              'The update installer is ready:\n${state.readyInstallerPath}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await controller.dismissReadyPrompt();
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: Text(tr(context, '下次启动更新', 'Update next time')),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                final launched = await controller.installPendingUpdateNow(
                  quitApp: _exitApplication,
                );
                if (!launched && mounted) {
                  await _showInfoMessage(controller.value.statusMessage);
                }
              },
              icon: const Icon(Icons.system_update_alt_rounded),
              label: Text(tr(context, '立即更新', 'Update now')),
            ),
          ],
        );
      },
    );
  }

  Future<CloseAction?> _askCloseAction() async {
    if (!mounted) {
      return null;
    }
    return showDialog<CloseAction>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(tr(context, '关闭窗口', 'Close window')),
          content: Text(
            tr(
              context,
              '请选择本次关闭窗口时的操作。',
              'Choose what should happen when closing the window.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: Text(tr(context, '取消', 'Cancel')),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(CloseAction.tray),
              child: Text(tr(context, '最小化到托盘', 'Minimize to tray')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(CloseAction.close),
              child: Text(tr(context, '关闭程序', 'Close app')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleCloseRequest() async {
    final action = widget.controller.settings.closeAction;
    switch (action) {
      case CloseAction.close:
        await _exitApplication();
        return;
      case CloseAction.tray:
        await _hideToTray();
        return;
      case CloseAction.ask:
        final selected = await _askCloseAction();
        if (selected == CloseAction.close) {
          await _exitApplication();
        } else if (selected == CloseAction.tray) {
          await _hideToTray();
        }
        return;
    }
  }

  Future<void> _handleTrayMenuClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show_window':
        await _restoreWindow();
        return;
      case 'connect_checked':
        await widget.controller.connectCheckedProfiles();
        return;
      case 'disconnect_checked':
        await widget.controller.disconnectCheckedProfiles();
        return;
      case 'open_settings':
        await _restoreWindow();
        if (mounted) {
          await _showSettings(context, widget.controller);
        }
        return;
      case 'check_updates':
        await _restoreWindow();
        await _updaterController.checkForUpdates();
        if (mounted && _updaterController.value.statusMessage.isNotEmpty) {
          await _showInfoMessage(_updaterController.value.statusMessage);
        }
        return;
      case 'toggle_theme':
        await widget.controller.toggleTheme();
        return;
      case 'connect_default':
        final defaultProfileId = widget.controller.settings.defaultProfileId;
        if (defaultProfileId == null) {
          await _restoreWindow();
          if (!mounted) {
            return;
          }
          await _showInfoMessage(
            tr(context, '当前未设置默认配置', 'No default profile is configured'),
          );
          return;
        }
        await widget.controller.connectProfiles(<String>[defaultProfileId]);
        return;
      case 'exit_app':
        await _exitApplication();
        return;
      default:
        return;
    }
  }

  @override
  void onWindowClose() {
    if (_isQuitting) {
      return;
    }
    unawaited(_handleCloseRequest());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_restoreWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    unawaited(_handleTrayMenuClick(menuItem));
  }

  @override
  Widget build(BuildContext context) {
    final closeAction = widget.controller.settings.closeAction;
    final language = widget.controller.settings.language;
    if (_lastCloseAction != closeAction) {
      _lastCloseAction = closeAction;
      unawaited(_syncCloseBehavior());
    }
    if (_lastLanguage != language) {
      _lastLanguage = language;
      unawaited(_syncWindowTitle());
      if (_trayInitialized) {
        unawaited(_syncTrayPresentation());
      }
    }
    return DashboardPage(
      controller: widget.controller,
      updaterController: _updaterController,
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: isDark ? const Color(0xFF63A7FF) : const Color(0xFF1E4C85),
    onPrimary: Colors.white,
    secondary: isDark ? const Color(0xFF5BC0BE) : const Color(0xFF0E7490),
    onSecondary: Colors.white,
    error: const Color(0xFFE35D6A),
    onError: Colors.white,
    surface: isDark ? const Color(0xFF172230) : const Color(0xFFF1F6FB),
    onSurface: isDark ? const Color(0xFFF3F7FB) : const Color(0xFF152232),
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: 'Bahnschrift',
    textTheme: Typography.whiteMountainView.apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary;
        }
        return colorScheme.onSurface.withValues(alpha: 0.15);
      }),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
  );
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.controller,
    required this.updaterController,
  });

  final DashboardController controller;
  final UpdaterController updaterController;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  PeerTab selectedPeerTab = PeerTab.online;

  Future<void> _checkForUpdates(BuildContext context) async {
    await widget.updaterController.checkForUpdates();
    if (!mounted || !context.mounted) {
      return;
    }
    final message = widget.updaterController.value.statusMessage;
    if (message.isEmpty) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    String t(String zhHans, String en) => tr(context, zhHans, en);
    final selectedProfile = controller.selectedProfile;
    final onlinePeers = controller.peers.where((peer) => peer.online).toList();
    final offlinePeers = controller.peers
        .where((peer) => !peer.online)
        .toList();
    final displayedPeers = selectedPeerTab == PeerTab.online
        ? onlinePeers
        : offlinePeers;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const <Color>[
                        Color(0xFF09111B),
                        Color(0xFF111C2B),
                        Color(0xFF0F2E4A),
                      ]
                    : const <Color>[
                        Color(0xFFF7FBFF),
                        Color(0xFFE8F1FA),
                        Color(0xFFDDEAF7),
                      ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                child: Column(
                  children: [
                    SizedBox(
                      height: 68,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            t('VNT虚拟组网2.0', 'VNTC 2.0 Client'),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              fontSize: 24,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            controller.vntExecutablePath == null
                                ? t(
                                    '未发现 vnt2_cli.exe',
                                    'vnt2_cli.exe not found',
                                  )
                                : t(
                                    'Rust Manager + 唯一虚拟网卡绑定配置',
                                    'Rust Manager + dedicated adapter per profile',
                                  ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.70,
                              ),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (controller.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      _ErrorBanner(message: controller.errorMessage!),
                    ],
                    const SizedBox(height: 12),
                    _GlassPanel(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: _MetricTile(
                                label: t('已连接配置', 'Connected Profiles'),
                                value:
                                    '${controller.summary.connectedProfileCount}/${controller.summary.checkedProfileCount}',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MetricTile(
                                label: t('在线/离线', 'Online/Offline'),
                                value:
                                    '${controller.summary.totalOnlineCount}/${controller.summary.totalOfflineCount}',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MetricTile(
                                label: t('汇总网速', 'Aggregate Speed'),
                                value:
                                    '↑ ${formatSpeed(controller.summary.aggregateUploadBytesPerSecond)}  ↓ ${formatSpeed(controller.summary.aggregateDownloadBytesPerSecond)}',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MetricTile(
                                label: t('汇总流量', 'Aggregate Traffic'),
                                value:
                                    '↑ ${formatBytes(controller.summary.aggregateTotalTxBytes)}  ↓ ${formatBytes(controller.summary.aggregateTotalRxBytes)}',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MetricTile(
                                label: t('整体状态', 'Overall Status'),
                                value: formatOverallStatus(
                                  context,
                                  controller.summary.overallStatus,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _GlassPanel(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text(
                                  t('配置列表', 'Profiles'),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  t(
                                    '保存配置时自动分配唯一虚拟网卡',
                                    'A dedicated virtual adapter is assigned on save',
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.65,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (controller.profileSnapshots.isEmpty)
                              Text(
                                t(
                                  '还没有配置，点击右下角 + 创建',
                                  'No profiles yet. Click + to create one.',
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.65,
                                  ),
                                ),
                              )
                            else
                              ...controller.profileSnapshots.map(
                                (snapshot) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _ProfileCard(
                                    snapshot: snapshot,
                                    selected:
                                        snapshot.profile.id ==
                                        selectedProfile?.id,
                                    onTap: () => controller.selectProfile(
                                      snapshot.profile.id,
                                    ),
                                    onChecked: (checked) =>
                                        controller.toggleProfileChecked(
                                          snapshot.profile.id,
                                          checked,
                                        ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    selectedProfile == null
                                        ? t('当前没有焦点配置', 'No profile selected')
                                        : t(
                                            '焦点配置 ${selectedProfile.name} · 网卡 ${selectedProfile.tunName} · 控制端口 ${selectedProfile.ctrlPort}',
                                            'Selected ${selectedProfile.name} · Adapter ${selectedProfile.tunName} · Ctrl Port ${selectedProfile.ctrlPort}',
                                          ),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurface.withValues(
                                        alpha: 0.70,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                TextButton(
                                  onPressed: () => _showProfileEditor(
                                    context,
                                    controller,
                                    null,
                                  ),
                                  child: Text(t('添加配置', 'Add Profile')),
                                ),
                                TextButton(
                                  onPressed: selectedProfile == null
                                      ? null
                                      : () => _showProfileEditor(
                                          context,
                                          controller,
                                          selectedProfile,
                                        ),
                                  child: Text(t('编辑配置', 'Edit Profile')),
                                ),
                                TextButton(
                                  onPressed: selectedProfile == null
                                      ? null
                                      : controller.deleteSelectedProfile,
                                  child: Text(t('删除配置', 'Delete Profile')),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: _GlassPanel(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    t('在线 / 离线用户', 'Online / Offline Peers'),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const Spacer(),
                                  _PeerTabButton(
                                    label: t('在线', 'Online'),
                                    count: onlinePeers.length,
                                    selected: selectedPeerTab == PeerTab.online,
                                    activeColor: const Color(0xFF1DAA7A),
                                    onTap: () => setState(
                                      () => selectedPeerTab = PeerTab.online,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _PeerTabButton(
                                    label: t('离线', 'Offline'),
                                    count: offlinePeers.length,
                                    selected:
                                        selectedPeerTab == PeerTab.offline,
                                    activeColor: const Color(0xFF6D7D91),
                                    onTap: () => setState(
                                      () => selectedPeerTab = PeerTab.offline,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: ListView(
                                  children: [
                                    _PeerSection(
                                      title: selectedPeerTab == PeerTab.online
                                          ? t('在线用户', 'Online Peers')
                                          : t('离线用户', 'Offline Peers'),
                                      emptyHint:
                                          selectedPeerTab == PeerTab.online
                                          ? t(
                                              '当前没有在线节点',
                                              'No online peers right now',
                                            )
                                          : t(
                                              '当前没有离线节点',
                                              'No offline peers right now',
                                            ),
                                      peers: displayedPeers,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 54,
                      child: Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _StatusBadge(
                                    label: t(
                                      '运行 ${controller.summary.runningProfileCount}',
                                      'Running ${controller.summary.runningProfileCount}',
                                    ),
                                    color:
                                        controller.summary.runningProfileCount >
                                            0
                                        ? colorScheme.secondary
                                        : colorScheme.primary.withValues(
                                            alpha: 0.25,
                                          ),
                                  ),
                                  const SizedBox(width: 8),
                                  _IconCircleButton(
                                    icon: controller.settings.darkMode
                                        ? Icons.light_mode_rounded
                                        : Icons.dark_mode_rounded,
                                    onPressed: controller.toggleTheme,
                                    size: 44,
                                    iconSize: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Center(
                              child: FilledButton(
                                onPressed:
                                    controller.isBusy ||
                                        !controller.hasCheckedProfiles
                                    ? null
                                    : controller.allCheckedProfilesRunning
                                    ? controller.disconnectCheckedProfiles
                                    : controller.connectCheckedProfiles,
                                style: FilledButton.styleFrom(
                                  backgroundColor: isDark
                                      ? const Color(0xFF233041)
                                      : const Color(0xFF284564),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 36,
                                    vertical: 14,
                                  ),
                                  textStyle: theme.textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4,
                                        fontSize: 15,
                                      ),
                                ),
                                child: Text(controller.connectButtonLabel),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _IconCircleButton(
                                    icon: Icons.add_rounded,
                                    onPressed: () => _showProfileEditor(
                                      context,
                                      controller,
                                      null,
                                    ),
                                    size: 52,
                                    iconSize: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  ValueListenableBuilder<UpdaterState>(
                                    valueListenable: widget.updaterController,
                                    builder: (context, updateState, _) {
                                      final hasReadyUpdate =
                                          updateState.hasReadyUpdate;
                                      return _IconCircleButton(
                                        icon: updateState.isBusy
                                            ? Icons.downloading_rounded
                                            : hasReadyUpdate
                                            ? Icons.system_update_alt_rounded
                                            : Icons.update_rounded,
                                        tooltip:
                                            updateState.statusMessage
                                                .trim()
                                                .isEmpty
                                            ? t('检查更新', 'Check for updates')
                                            : updateState.statusMessage,
                                        onPressed: updateState.isBusy
                                            ? null
                                            : () => _checkForUpdates(context),
                                        size: 52,
                                        iconSize: 22,
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 10),
                                  _IconCircleButton(
                                    icon: Icons.settings_rounded,
                                    onPressed: () =>
                                        _showSettings(context, controller),
                                    tooltip: t('设置', 'Settings'),
                                    size: 52,
                                    iconSize: 22,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.snapshot,
    required this.selected,
    required this.onTap,
    required this.onChecked,
  });

  final ManagedProfileSnapshot snapshot;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<bool> onChecked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    String t(String zhHans, String en) => tr(context, zhHans, en);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.12)
              : colorScheme.onSurface.withValues(alpha: 0.04),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.35)
                : colorScheme.onSurface.withValues(alpha: 0.06),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          child: Row(
            children: [
              Checkbox(
                value: snapshot.profile.checked,
                onChanged: (value) => onChecked(value ?? false),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            snapshot.profile.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _StatusBadge(
                          label: formatProfileStatus(
                            context,
                            snapshot.runtime.status,
                          ),
                          color: snapshot.runtime.running
                              ? const Color(0xFF1DAA7A)
                              : const Color(0xFF6D7D91),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t(
                        '${snapshot.profile.server}  ·  网卡 ${snapshot.profile.tunName}',
                        '${snapshot.profile.server}  ·  Adapter ${snapshot.profile.tunName}',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _InlineFact(
                      label: t('虚拟IP', 'Virtual IP'),
                      value: snapshot.runtime.virtualIp ?? '--',
                    ),
                    _InlineFact(
                      label: t('在线/离线', 'Online/Offline'),
                      value:
                          '${snapshot.runtime.onlineCount}/${snapshot.runtime.offlineCount}',
                    ),
                    _InlineFact(
                      label: t('网速', 'Speed'),
                      value:
                          '↑ ${formatSpeed(snapshot.runtime.uploadBytesPerSecond)} ↓ ${formatSpeed(snapshot.runtime.downloadBytesPerSecond)}',
                    ),
                    _InlineFact(
                      label: t('流量', 'Traffic'),
                      value:
                          '↑ ${formatBytes(snapshot.runtime.totalTxBytes)} ↓ ${formatBytes(snapshot.runtime.totalRxBytes)}',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineFact extends StatelessWidget {
  const _InlineFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: colorScheme.primary.withValues(alpha: 0.08),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.92),
            ),
            children: [
              TextSpan(
                text: '$label ',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              TextSpan(
                text: value,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: isDark ? const Color(0xB2212D3B) : const Color(0xCCFFFFFF),
        border: Border.all(
          color: colorScheme.onSurface.withValues(alpha: isDark ? 0.10 : 0.08),
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 24,
            offset: const Offset(0, 10),
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.primary.withValues(alpha: 0.10),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.70),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _PeerTabButton extends StatelessWidget {
  const _PeerTabButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = selected
        ? activeColor.withValues(alpha: 0.18)
        : colorScheme.onSurface.withValues(alpha: 0.06);
    final foreground = selected
        ? activeColor
        : colorScheme.onSurface.withValues(alpha: 0.68);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? activeColor.withValues(alpha: 0.18)
                : Colors.transparent,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            '$label $count',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _PeerSection extends StatelessWidget {
  const _PeerSection({
    required this.title,
    required this.emptyHint,
    required this.peers,
  });

  final String title;
  final String emptyHint;
  final List<AggregatedPeer> peers;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final language = appLanguageOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (peers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              emptyHint,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.60),
              ),
            ),
          )
        else
          ...peers.map(
            (peer) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: peer.online
                              ? const Color(0xFF1DAA7A)
                              : const Color(0xFF778699),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              peer.peerName.isEmpty
                                  ? defaultPeerName(language)
                                  : peer.peerName,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  peer.peerVirtualIp.isEmpty
                                      ? '--'
                                      : peer.peerVirtualIp,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.82,
                                        ),
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(width: 6),
                                _CopyPeerIpButton(
                                  ip: peer.peerVirtualIp.isEmpty
                                      ? '--'
                                      : peer.peerVirtualIp,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tr(
                                context,
                                '配置 ${peer.sourceProfileName}  ·  本机虚拟IP ${peer.sourceProfileVirtualIp ?? '--'}',
                                'Profile ${peer.sourceProfileName}  ·  Local Virtual IP ${peer.sourceProfileVirtualIp ?? '--'}',
                              ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.65,
                                    ),
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        peer.online
                            ? (peer.latencyMs == null
                                  ? tr(context, '在线', 'Online')
                                  : '${peer.latencyMs} ms')
                            : tr(context, '离线', 'Offline'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: peer.online
                              ? const Color(0xFF1DAA7A)
                              : colorScheme.onSurface.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE35D6A).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFE35D6A)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFE35D6A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyPeerIpButton extends StatelessWidget {
  const _CopyPeerIpButton({required this.ip});

  final String ip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: ip));
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context, '已复制虚拟IP $ip', 'Copied virtual IP $ip')),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          Icons.copy_rounded,
          size: 15,
          color: colorScheme.primary.withValues(alpha: 0.92),
        ),
      ),
    );
  }
}

class _IconCircleButton extends StatelessWidget {
  const _IconCircleButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 56,
    this.iconSize = 24,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isDark ? const Color(0xCC202B39) : const Color(0xE8FFFFFF),
        border: Border.all(
          color: colorScheme.onSurface.withValues(alpha: isDark ? 0.12 : 0.08),
        ),
      ),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon),
        color: onPressed == null
            ? colorScheme.onSurface.withValues(alpha: 0.38)
            : colorScheme.onSurface,
        iconSize: iconSize,
        padding: EdgeInsets.all((size - iconSize) / 2),
        constraints: BoxConstraints.tightFor(width: size, height: size),
      ),
    );
  }
}

InputDecoration _inputDecoration(
  BuildContext context, {
  required String hintText,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return InputDecoration(
    hintText: hintText,
    filled: true,
    fillColor: colorScheme.onSurface.withValues(alpha: 0.04),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(
        color: colorScheme.onSurface.withValues(alpha: 0.08),
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(
        color: colorScheme.onSurface.withValues(alpha: 0.08),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: colorScheme.primary.withValues(alpha: 0.9)),
    ),
  );
}

Future<void> _showProfileEditor(
  BuildContext context,
  DashboardController controller,
  VntProfile? profile,
) async {
  final result = await showDialog<_ProfileDraft>(
    context: context,
    builder: (context) => _ProfileEditorDialog(profile: profile),
  );
  if (result == null) {
    return;
  }
  await controller.saveProfile(
    profileId: profile?.id,
    name: result.name,
    server: result.server,
    networkCode: result.networkCode,
    deviceName: result.deviceName,
    rtx: result.rtx,
    customIp: result.customIp,
    password: result.password,
    certMode: result.certMode,
    compress: result.compress,
    fec: result.fec,
    noPunch: result.noPunch,
    noNat: result.noNat,
    mtu: result.mtu,
    allowMapping: result.allowMapping,
    inputRoutes: result.inputRoutes,
    outputRoutes: result.outputRoutes,
    portMappings: result.portMappings,
    udpStunServers: result.udpStunServers,
    tcpStunServers: result.tcpStunServers,
  );
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        tr(context, '已保存配置 ${result.name}', 'Saved profile ${result.name}'),
      ),
    ),
  );
}

Future<void> _showSettings(
  BuildContext context,
  DashboardController controller,
) async {
  final cleanupWasEnabled = controller.settings.cleanupUnusedTunOnLaunch;
  final result = await showDialog<AppSettings>(
    context: context,
    builder: (context) => _SettingsDialog(
      settings: controller.settings,
      profiles: controller.profiles,
    ),
  );
  if (result == null) {
    return;
  }
  await controller.saveSettings(result);
  final shouldRunCleanup =
      result.cleanupUnusedTunOnLaunch &&
      !cleanupWasEnabled &&
      controller.settings.cleanupUnusedTunOnLaunch;
  if (!shouldRunCleanup) {
    return;
  }

  final cleanupResult = await controller.cleanupUnusedTunAdapters();
  if (!context.mounted || cleanupResult == null) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(formatTunAdapterCleanupResult(context, cleanupResult)),
    ),
  );
}

String formatOverallStatus(BuildContext context, String raw) {
  switch (raw) {
    case 'running':
      return tr(context, '运行中', 'Running');
    case 'partial':
      return tr(context, '部分运行', 'Partially Running');
    case 'starting':
      return tr(context, '启动中', 'Starting');
    case 'stopped':
      return tr(context, '已停止', 'Stopped');
    default:
      return '--';
  }
}

String formatProfileStatus(BuildContext context, String raw) {
  switch (raw) {
    case 'running':
      return tr(context, '运行', 'Running');
    case 'starting':
      return tr(context, '启动中', 'Starting');
    case 'stopped':
      return tr(context, '停止', 'Stopped');
    default:
      return '--';
  }
}

String formatBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  final fractionDigits = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
  return '${value.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
}

String formatSpeed(int bytesPerSecond) {
  return '${formatBytes(bytesPerSecond)}/s';
}

String formatTunAdapterCleanupResult(
  BuildContext context,
  TunAdapterCleanupResult result,
) {
  if (result.unsupported) {
    return tr(
      context,
      '当前系统不支持自动清理 TUN 虚拟网卡',
      'Automatic TUN adapter cleanup is not supported on this system',
    );
  }
  if (result.cleanedCount == 0 && result.skippedCount == 0) {
    return tr(
      context,
      '未发现需要清理的无用 TUN 虚拟网卡',
      'No unused TUN adapters were found',
    );
  }
  if (result.cleanedCount == 0) {
    return tr(
      context,
      '未删除网卡，已跳过 ${result.skippedCount} 个正在使用或无法删除的网卡',
      'No adapters were deleted. Skipped ${result.skippedCount} active or protected adapters',
    );
  }
  return tr(
    context,
    '已清理 ${result.cleanedCount} 个无用 TUN 虚拟网卡，保留 ${result.keptCount} 个配置网卡',
    'Cleaned ${result.cleanedCount} unused TUN adapters and kept ${result.keptCount} configured adapters',
  );
}

class _ProfileDraft {
  const _ProfileDraft({
    required this.name,
    required this.server,
    required this.networkCode,
    required this.deviceName,
    required this.rtx,
    required this.customIp,
    required this.password,
    required this.certMode,
    required this.compress,
    required this.fec,
    required this.noPunch,
    required this.noNat,
    required this.mtu,
    required this.allowMapping,
    required this.inputRoutes,
    required this.outputRoutes,
    required this.portMappings,
    required this.udpStunServers,
    required this.tcpStunServers,
  });

  final String name;
  final String server;
  final String networkCode;
  final String deviceName;
  final bool rtx;
  final String? customIp;
  final String? password;
  final String? certMode;
  final bool compress;
  final bool fec;
  final bool noPunch;
  final bool noNat;
  final String? mtu;
  final bool allowMapping;
  final List<String> inputRoutes;
  final List<String> outputRoutes;
  final List<String> portMappings;
  final List<String> udpStunServers;
  final List<String> tcpStunServers;
}

class _ProfileEditorDialog extends StatefulWidget {
  const _ProfileEditorDialog({this.profile});

  final VntProfile? profile;

  @override
  State<_ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<_ProfileEditorDialog> {
  late final TextEditingController nameController;
  late final TextEditingController serverController;
  late final TextEditingController networkCodeController;
  late final TextEditingController deviceNameController;
  late final TextEditingController customIpController;
  late final TextEditingController passwordController;
  late final TextEditingController certModeController;
  late final TextEditingController mtuController;
  late final TextEditingController inputRoutesController;
  late final TextEditingController outputRoutesController;
  late final TextEditingController portMappingsController;
  late final TextEditingController udpStunController;
  late final TextEditingController tcpStunController;
  late bool rtx;
  late bool compress;
  late bool fec;
  late bool noPunch;
  late bool noNat;
  late bool allowMapping;
  bool advancedExpanded = false;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.profile?.name ?? '');
    serverController = TextEditingController(
      text: widget.profile?.server ?? 'quic://115.231.35.105:2225',
    );
    networkCodeController = TextEditingController(
      text: widget.profile?.networkCode ?? 'a',
    );
    deviceNameController = TextEditingController(
      text: widget.profile?.deviceName ?? 'vntc-live-a',
    );
    customIpController = TextEditingController(
      text: widget.profile?.customIp ?? '',
    );
    passwordController = TextEditingController(
      text: widget.profile?.password ?? '',
    );
    certModeController = TextEditingController(
      text: widget.profile?.certMode ?? '',
    );
    mtuController = TextEditingController(text: widget.profile?.mtu ?? '');
    inputRoutesController = TextEditingController(
      text: widget.profile == null
          ? ''
          : widget.profile!.inputRoutes.join('\n'),
    );
    outputRoutesController = TextEditingController(
      text: widget.profile == null
          ? ''
          : widget.profile!.outputRoutes.join('\n'),
    );
    portMappingsController = TextEditingController(
      text: widget.profile == null
          ? ''
          : widget.profile!.portMappings.join('\n'),
    );
    udpStunController = TextEditingController(
      text: widget.profile == null
          ? ''
          : widget.profile!.udpStunServers.join('\n'),
    );
    tcpStunController = TextEditingController(
      text: widget.profile == null
          ? ''
          : widget.profile!.tcpStunServers.join('\n'),
    );
    rtx = widget.profile?.rtx ?? true;
    compress = widget.profile?.compress ?? false;
    fec = widget.profile?.fec ?? false;
    noPunch = widget.profile?.noPunch ?? false;
    noNat = widget.profile?.noNat ?? false;
    allowMapping = widget.profile?.allowMapping ?? false;
  }

  @override
  void dispose() {
    nameController.dispose();
    serverController.dispose();
    networkCodeController.dispose();
    deviceNameController.dispose();
    customIpController.dispose();
    passwordController.dispose();
    certModeController.dispose();
    mtuController.dispose();
    inputRoutesController.dispose();
    outputRoutesController.dispose();
    portMappingsController.dispose();
    udpStunController.dispose();
    tcpStunController.dispose();
    super.dispose();
  }

  String? _normalizeDraftText(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  List<String> _splitMultiline(String value) {
    return value
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    String t(String zhHans, String en) => tr(context, zhHans, en);
    return AlertDialog(
      title: Text(
        widget.profile == null
            ? t('新建配置', 'New Profile')
            : t('编辑配置', 'Edit Profile'),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: _inputDecoration(
                  context,
                  hintText: t('显示名称', 'Display name'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: serverController,
                decoration: _inputDecoration(
                  context,
                  hintText: t(
                    '服务端地址，如 quic://115.231.35.105:2225',
                    'Server address, e.g. quic://115.231.35.105:2225',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: networkCodeController,
                decoration: _inputDecoration(
                  context,
                  hintText: t('组网编号', 'Network code'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: deviceNameController,
                decoration: _inputDecoration(
                  context,
                  hintText: t('设备名称', 'Device name'),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: rtx,
                title: Text(t('启用 QUIC 优化传输', 'Enable QUIC acceleration')),
                onChanged: (value) => setState(() => rtx = value),
              ),
              const SizedBox(height: 8),
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 4),
                  initiallyExpanded: advancedExpanded,
                  onExpansionChanged: (value) =>
                      setState(() => advancedExpanded = value),
                  title: Text(
                    t('高级配置', 'Advanced Settings'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    widget.profile == null
                        ? t(
                            '默认折叠，展开后可配置全部 vnt2 进阶参数',
                            'Collapsed by default. Expand to edit advanced vnt2 options.',
                          )
                        : t(
                            '可查看并调整进阶参数，唯一网卡/端口仍自动管理',
                            'Review and adjust advanced options while keeping adapter and port allocation automatic.',
                          ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.profile == null
                            ? t(
                                '保存后自动生成唯一 device_id / tun_name / ctrl_port',
                                'A unique device_id / tun_name / ctrl_port will be generated after saving.',
                              )
                            : 'device_id: ${widget.profile!.deviceId}\ntun_name: ${widget.profile!.tunName}\nctrl_port: ${widget.profile!.ctrlPort}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: customIpController,
                      decoration: _inputDecoration(
                        context,
                        hintText: t(
                          '自定义虚拟IP，例如 10.10.0.2',
                          'Custom virtual IP, e.g. 10.10.0.2',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      decoration: _inputDecoration(
                        context,
                        hintText: t('加密密码，可选', 'Encryption password, optional'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: certModeController,
                      decoration: _inputDecoration(
                        context,
                        hintText: t(
                          '证书模式，例如 skip / standard / finger:xxxx',
                          'Certificate mode, e.g. skip / standard / finger:xxxx',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: mtuController,
                      decoration: _inputDecoration(
                        context,
                        hintText: t('MTU，例如 1400', 'MTU, e.g. 1400'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: compress,
                      title: Text(t('启用压缩', 'Enable compression')),
                      onChanged: (value) => setState(() => compress = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: fec,
                      title: Text(t('启用 FEC', 'Enable FEC')),
                      onChanged: (value) => setState(() => fec = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: noPunch,
                      title: Text(t('关闭 P2P 打洞', 'Disable P2P hole punching')),
                      onChanged: (value) => setState(() => noPunch = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: noNat,
                      title: Text(
                        t('关闭内置子网 NAT', 'Disable built-in subnet NAT'),
                      ),
                      onChanged: (value) => setState(() => noNat = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: allowMapping,
                      title: Text(
                        t('允许作为端口映射出口', 'Allow as port-mapping egress'),
                      ),
                      onChanged: (value) =>
                          setState(() => allowMapping = value),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: inputRoutesController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: _inputDecoration(
                        context,
                        hintText: t(
                          '入栈监听网段，每行一条\n例如 192.168.0.0/24,10.26.0.2',
                          'Inbound routes, one per line\nFor example 192.168.0.0/24,10.26.0.2',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: outputRoutesController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: _inputDecoration(
                        context,
                        hintText: t(
                          '出栈允许网段，每行一条\n例如 0.0.0.0/0',
                          'Outbound routes, one per line\nFor example 0.0.0.0/0',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: portMappingsController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: _inputDecoration(
                        context,
                        hintText: t(
                          '端口映射，每行一条\n例如 tcp://0.0.0.0:81-10.0.0.2-10.0.0.2:80',
                          'Port mappings, one per line\nFor example tcp://0.0.0.0:81-10.0.0.2-10.0.0.2:80',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: udpStunController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: _inputDecoration(
                        context,
                        hintText: t(
                          'UDP STUN 地址，每行一条',
                          'UDP STUN servers, one per line',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tcpStunController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: _inputDecoration(
                        context,
                        hintText: t(
                          'TCP STUN 地址，每行一条',
                          'TCP STUN servers, one per line',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('取消', 'Cancel')),
        ),
        FilledButton(
          onPressed: () {
            final name = nameController.text.trim();
            final server = serverController.text.trim();
            final networkCode = networkCodeController.text.trim();
            final deviceName = deviceNameController.text.trim();
            if (name.isEmpty || server.isEmpty || networkCode.isEmpty) {
              return;
            }
            Navigator.of(context).pop(
              _ProfileDraft(
                name: name,
                server: server,
                networkCode: networkCode,
                deviceName: deviceName.isEmpty ? name : deviceName,
                rtx: rtx,
                customIp: _normalizeDraftText(customIpController.text),
                password: _normalizeDraftText(passwordController.text),
                certMode: _normalizeDraftText(certModeController.text),
                compress: compress,
                fec: fec,
                noPunch: noPunch,
                noNat: noNat,
                mtu: _normalizeDraftText(mtuController.text),
                allowMapping: allowMapping,
                inputRoutes: _splitMultiline(inputRoutesController.text),
                outputRoutes: _splitMultiline(outputRoutesController.text),
                portMappings: _splitMultiline(portMappingsController.text),
                udpStunServers: _splitMultiline(udpStunController.text),
                tcpStunServers: _splitMultiline(tcpStunController.text),
              ),
            );
          },
          child: Text(t('保存', 'Save')),
        ),
      ],
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.settings, required this.profiles});

  final AppSettings settings;
  final List<VntProfile> profiles;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late AppLanguage language;
  late CloseAction closeAction;
  late bool autoStart;
  late bool silentAutoStart;
  late bool connectDefaultOnLaunch;
  late bool cleanupUnusedTunOnLaunch;
  String? defaultProfileId;

  @override
  void initState() {
    super.initState();
    language = widget.settings.language;
    closeAction = widget.settings.closeAction;
    autoStart = widget.settings.autoStart;
    silentAutoStart = widget.settings.silentAutoStart;
    connectDefaultOnLaunch = widget.settings.connectDefaultOnLaunch;
    cleanupUnusedTunOnLaunch = widget.settings.cleanupUnusedTunOnLaunch;
    defaultProfileId = widget.settings.defaultProfileId;
  }

  @override
  Widget build(BuildContext context) {
    String t(String zhHans, String en) {
      return trByLanguage(language, zhHans, en);
    }

    return AlertDialog(
      title: Text(t('设置', 'Settings')),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<AppLanguage>(
                initialValue: language,
                decoration: _inputDecoration(
                  context,
                  hintText: t('界面语言', 'Language'),
                ),
                items: AppLanguage.values
                    .map(
                      (item) => DropdownMenuItem<AppLanguage>(
                        value: item,
                        child: Text(languageDisplayName(item)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() => language = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CloseAction>(
                initialValue: closeAction,
                decoration: _inputDecoration(
                  context,
                  hintText: t('关闭动作', 'Close behavior'),
                ),
                items: CloseAction.values
                    .map(
                      (item) => DropdownMenuItem<CloseAction>(
                        value: item,
                        child: Text(formatCloseActionLabel(item, language)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() => closeAction = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: defaultProfileId,
                decoration: _inputDecoration(
                  context,
                  hintText: t('默认配置', 'Default profile'),
                ),
                items: widget.profiles
                    .map(
                      (profile) => DropdownMenuItem<String>(
                        value: profile.id,
                        child: Text(profile.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => defaultProfileId = value),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: autoStart,
                title: Text(t('开机自启', 'Auto-start with Windows')),
                onChanged: (value) => setState(() => autoStart = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: silentAutoStart,
                title: Text(t('静默自启', 'Start silently')),
                onChanged: (value) => setState(() => silentAutoStart = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: connectDefaultOnLaunch,
                title: Text(
                  t(
                    '启动后连接默认配置或勾选配置',
                    'Connect default or selected profiles on launch',
                  ),
                ),
                onChanged: (value) =>
                    setState(() => connectDefaultOnLaunch = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: cleanupUnusedTunOnLaunch,
                title: Text(
                  t(
                    '自动清理无用 TUN 虚拟网卡',
                    'Automatically clean unused TUN adapters',
                  ),
                ),
                onChanged: (value) =>
                    setState(() => cleanupUnusedTunOnLaunch = value),
              ),
              const SizedBox(height: 10),
              Text(
                t(
                  '开启“开机自启”后会写入当前 Windows 用户启动项；“静默自启”仅在系统自动拉起时隐藏主窗口，手动启动仍会正常显示。“自动清理”只处理本客户端生成且未被配置引用的 vntc-* 网卡。',
                  'Enabling auto-start writes a Run entry for the current Windows user. "Start silently" hides the main window only when the app is started by the system; manual launches still open normally. Automatic cleanup only handles vntc-* adapters created by this client and no longer referenced by profiles.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('取消', 'Cancel')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              widget.settings.copyWith(
                language: language,
                closeAction: closeAction,
                autoStart: autoStart,
                silentAutoStart: silentAutoStart,
                connectDefaultOnLaunch: connectDefaultOnLaunch,
                cleanupUnusedTunOnLaunch: cleanupUnusedTunOnLaunch,
                defaultProfileId: defaultProfileId,
              ),
            );
          },
          child: Text(t('保存', 'Save')),
        ),
      ],
    );
  }
}
