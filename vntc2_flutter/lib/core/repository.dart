import 'dart:convert';
import 'dart:io';

import 'models.dart';

class AppPaths {
  AppPaths._({
    required this.executableDir,
    required this.dataDir,
    required this.settingsDir,
    required this.profilesDir,
    required this.runtimeRootDir,
    required this.logsDir,
  });

  final Directory executableDir;
  final Directory dataDir;
  final Directory settingsDir;
  final Directory profilesDir;
  final Directory runtimeRootDir;
  final Directory logsDir;

  static Future<AppPaths> detect() async {
    final executableDir = File(Platform.resolvedExecutable).parent;
    final dataDir = Directory(joinPath(executableDir.path, 'data'));
    final settingsDir = Directory(joinPath(dataDir.path, 'settings'));
    final profilesDir = Directory(joinPath(dataDir.path, 'profiles'));
    final runtimeRootDir = Directory(joinPath(dataDir.path, 'runtime'));
    final logsDir = Directory(joinPath(dataDir.path, 'logs'));

    for (final dir in <Directory>[
      dataDir,
      settingsDir,
      profilesDir,
      runtimeRootDir,
      logsDir,
    ]) {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    return AppPaths._(
      executableDir: executableDir,
      dataDir: dataDir,
      settingsDir: settingsDir,
      profilesDir: profilesDir,
      runtimeRootDir: runtimeRootDir,
      logsDir: logsDir,
    );
  }

  File get settingsFile =>
      File(joinPath(settingsDir.path, 'app_settings.json'));

  Directory profileDir(String profileId) =>
      Directory(joinPath(profilesDir.path, profileId));

  File profileMetaFile(String profileId) =>
      File(joinPath(profileDir(profileId).path, 'meta.json'));

  File profileTomlFile(String profileId) =>
      File(joinPath(profileDir(profileId).path, 'vnt.toml'));

  Directory runtimeDir(String profileId) =>
      Directory(joinPath(runtimeRootDir.path, profileId));

  File logFile(String profileId) =>
      File(joinPath(logsDir.path, '$profileId.log'));

  File get managerPortFile =>
      File(joinPath(runtimeRootDir.path, 'vntc_manager.port'));

  Future<String?> findManagerExecutable() async {
    final candidates = <String>{
      joinPath(executableDir.path, 'vntc_manager.exe'),
      joinPath(Directory.current.path, 'vntc_manager.exe'),
    };
    for (final root in <String>[Directory.current.path, executableDir.path]) {
      for (final ancestor in collectAncestors(root)) {
        candidates.add(
          joinPath(
            ancestor,
            'vnt-2.0.0',
            'target',
            'release',
            'vntc_manager.exe',
          ),
        );
        candidates.add(joinPath(ancestor, 'vntc_manager.exe'));
      }
    }
    return findExistingCandidate(candidates);
  }

  Future<String?> findVntCliExecutable() async {
    final candidates = <String>{
      joinPath(executableDir.path, 'vnt2_cli.exe'),
      joinPath(Directory.current.path, 'vnt2_cli.exe'),
    };
    for (final root in <String>[Directory.current.path, executableDir.path]) {
      for (final ancestor in collectAncestors(root)) {
        candidates.add(
          joinPath(ancestor, 'vnt-2.0.0', 'target', 'release', 'vnt2_cli.exe'),
        );
        candidates.add(joinPath(ancestor, 'vnt2_cli.exe'));
      }
    }
    return findExistingCandidate(candidates);
  }
}

class AppRepository {
  AppRepository._(this.paths);

  final AppPaths paths;

  static Future<AppRepository> open() async {
    final paths = await AppPaths.detect();
    return AppRepository._(paths);
  }

  Future<AppSettings> loadSettings() async {
    if (!await paths.settingsFile.exists()) {
      return AppSettings.defaults();
    }
    final content = await paths.settingsFile.readAsString();
    return AppSettings.fromJson(jsonDecode(content) as Map<String, dynamic>);
  }

  Future<void> saveSettings(AppSettings settings) async {
    await paths.settingsFile.writeAsString(encodePrettyJson(settings.toJson()));
  }

  Future<List<VntProfile>> loadProfiles() async {
    if (!await paths.profilesDir.exists()) {
      return const <VntProfile>[];
    }

    final result = <VntProfile>[];
    final entries = paths.profilesDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final dir in entries) {
      final file = File(joinPath(dir.path, 'meta.json'));
      if (!file.existsSync()) {
        continue;
      }
      final content = await file.readAsString();
      result.add(
        VntProfile.fromJson(jsonDecode(content) as Map<String, dynamic>),
      );
    }

    result.sort((a, b) => a.createdAtIso.compareTo(b.createdAtIso));
    return result;
  }

  Future<void> saveProfile(VntProfile profile) async {
    final dir = paths.profileDir(profile.id);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await paths
        .profileMetaFile(profile.id)
        .writeAsString(encodePrettyJson(profile.toJson()));
    await paths.profileTomlFile(profile.id).writeAsString(buildToml(profile));
  }

  Future<void> deleteProfile(String profileId) async {
    final dir = paths.profileDir(profileId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    final runtimeDir = paths.runtimeDir(profileId);
    if (await runtimeDir.exists()) {
      await runtimeDir.delete(recursive: true);
    }
    final logFile = paths.logFile(profileId);
    if (await logFile.exists()) {
      await logFile.delete();
    }
  }

  Future<void> ensureBootstrapData() async {
    final profiles = await loadProfiles();
    if (profiles.isNotEmpty) {
      for (final profile in profiles) {
        await saveProfile(profile);
      }
      return;
    }

    final current = await loadSettings();
    await saveSettings(
      current.copyWith(
        clearSelectedProfileId: true,
        clearDefaultProfileId: true,
      ),
    );
  }
}

String buildToml(VntProfile profile) {
  final lines = <String>[
    'config_name = ${quoteToml(profile.name)}',
    'server = [${quoteToml(profile.server)}]',
    'network_code = ${quoteToml(profile.networkCode)}',
    'device_id = ${quoteToml(profile.deviceId)}',
    'device_name = ${quoteToml(profile.deviceName)}',
    'tun_name = ${quoteToml(profile.tunName)}',
    'ctrl_port = ${profile.ctrlPort}',
    'no_tun = ${profile.noTun}',
    'rtx = ${profile.rtx}',
    'compress = ${profile.compress}',
    'fec = ${profile.fec}',
    'no_punch = ${profile.noPunch}',
    'no_nat = ${profile.noNat}',
    'allow_mapping = ${profile.allowMapping}',
  ];
  if (_hasText(profile.customIp)) {
    lines.add('ip = ${quoteToml(profile.customIp!.trim())}');
  }
  if (_hasText(profile.password)) {
    lines.add('password = ${quoteToml(profile.password!.trim())}');
  }
  if (_hasText(profile.certMode)) {
    lines.add('cert_mode = ${quoteToml(profile.certMode!.trim())}');
  }
  if (_hasText(profile.mtu)) {
    lines.add('mtu = ${profile.mtu!.trim()}');
  }
  if (profile.inputRoutes.isNotEmpty) {
    lines.add('input = ${quoteTomlList(profile.inputRoutes)}');
  }
  if (profile.outputRoutes.isNotEmpty) {
    lines.add('output = ${quoteTomlList(profile.outputRoutes)}');
  }
  if (profile.portMappings.isNotEmpty) {
    lines.add('port_mapping = ${quoteTomlList(profile.portMappings)}');
  }
  if (profile.udpStunServers.isNotEmpty) {
    lines.add('udp_stun = ${quoteTomlList(profile.udpStunServers)}');
  }
  if (profile.tcpStunServers.isNotEmpty) {
    lines.add('tcp_stun = ${quoteTomlList(profile.tcpStunServers)}');
  }
  return '${lines.join('\n')}\n';
}

String quoteToml(String value) {
  final escaped = value.replaceAll('\\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}

String quoteTomlList(List<String> values) {
  return '[${values.map(quoteToml).join(', ')}]';
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

String joinPath(
  String first, [
  String? second,
  String? third,
  String? fourth,
  String? fifth,
]) {
  final parts = <String?>[
    first,
    second,
    third,
    fourth,
    fifth,
  ].whereType<String>().toList();
  return parts.join(Platform.pathSeparator);
}

List<String> collectAncestors(String start) {
  final results = <String>[];
  var current = Directory(start).absolute;
  while (true) {
    results.add(current.path);
    final parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }
  return results;
}

Future<String?> findExistingCandidate(Iterable<String> candidates) async {
  for (final path in candidates) {
    if (await File(path).exists()) {
      return path;
    }
  }
  return null;
}
