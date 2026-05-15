import 'dart:io';

import 'dart:convert';

enum AppLanguage { zhHans, en }

extension AppLanguageX on AppLanguage {
  String get value => switch (this) {
    AppLanguage.zhHans => 'zh-Hans',
    AppLanguage.en => 'en',
  };

  static AppLanguage fromValue(String? value) {
    return AppLanguage.values.firstWhere(
      (item) => item.value == value,
      orElse: () => AppLanguage.zhHans,
    );
  }

  static AppLanguage detectSystemDefault() {
    final localeName = Platform.localeName.toLowerCase();
    if (localeName.startsWith('en')) {
      return AppLanguage.en;
    }
    return AppLanguage.zhHans;
  }
}

enum CloseAction { close, tray, ask }

extension CloseActionX on CloseAction {
  String get value => switch (this) {
    CloseAction.close => 'close',
    CloseAction.tray => 'tray',
    CloseAction.ask => 'ask',
  };

  String get label => switch (this) {
    CloseAction.close => '直接关闭',
    CloseAction.tray => '最小化到托盘',
    CloseAction.ask => '每次询问',
  };

  static CloseAction fromValue(String? value) {
    return CloseAction.values.firstWhere(
      (item) => item.value == value,
      orElse: () => CloseAction.close,
    );
  }
}

class AppSettings {
  const AppSettings({
    required this.language,
    required this.darkMode,
    required this.closeAction,
    required this.autoStart,
    required this.silentAutoStart,
    required this.connectDefaultOnLaunch,
    this.selectedProfileId,
    this.defaultProfileId,
  });

  final AppLanguage language;
  final bool darkMode;
  final CloseAction closeAction;
  final bool autoStart;
  final bool silentAutoStart;
  final bool connectDefaultOnLaunch;
  final String? selectedProfileId;
  final String? defaultProfileId;

  AppSettings copyWith({
    AppLanguage? language,
    bool? darkMode,
    CloseAction? closeAction,
    bool? autoStart,
    bool? silentAutoStart,
    bool? connectDefaultOnLaunch,
    String? selectedProfileId,
    String? defaultProfileId,
    bool clearSelectedProfileId = false,
    bool clearDefaultProfileId = false,
  }) {
    return AppSettings(
      language: language ?? this.language,
      darkMode: darkMode ?? this.darkMode,
      closeAction: closeAction ?? this.closeAction,
      autoStart: autoStart ?? this.autoStart,
      silentAutoStart: silentAutoStart ?? this.silentAutoStart,
      connectDefaultOnLaunch:
          connectDefaultOnLaunch ?? this.connectDefaultOnLaunch,
      selectedProfileId: clearSelectedProfileId
          ? null
          : selectedProfileId ?? this.selectedProfileId,
      defaultProfileId: clearDefaultProfileId
          ? null
          : defaultProfileId ?? this.defaultProfileId,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'language': language.value,
      'darkMode': darkMode,
      'closeAction': closeAction.value,
      'autoStart': autoStart,
      'silentAutoStart': silentAutoStart,
      'connectDefaultOnLaunch': connectDefaultOnLaunch,
      'selectedProfileId': selectedProfileId,
      'defaultProfileId': defaultProfileId,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      language: AppLanguageX.fromValue(json['language'] as String?),
      darkMode: json['darkMode'] as bool? ?? true,
      closeAction: CloseActionX.fromValue(json['closeAction'] as String?),
      autoStart: json['autoStart'] as bool? ?? false,
      silentAutoStart: json['silentAutoStart'] as bool? ?? false,
      connectDefaultOnLaunch: json['connectDefaultOnLaunch'] as bool? ?? true,
      selectedProfileId: json['selectedProfileId'] as String?,
      defaultProfileId: json['defaultProfileId'] as String?,
    );
  }

  factory AppSettings.defaults() {
    return AppSettings(
      language: AppLanguageX.detectSystemDefault(),
      darkMode: true,
      closeAction: CloseAction.close,
      autoStart: false,
      silentAutoStart: false,
      connectDefaultOnLaunch: true,
    );
  }
}

class VntProfile {
  const VntProfile({
    required this.id,
    required this.name,
    required this.server,
    required this.networkCode,
    required this.deviceId,
    required this.deviceName,
    required this.ctrlPort,
    required this.tunName,
    required this.noTun,
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
    required this.createdAtIso,
    required this.checked,
  });

  final String id;
  final String name;
  final String server;
  final String networkCode;
  final String deviceId;
  final String deviceName;
  final int ctrlPort;
  final String tunName;
  final bool noTun;
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
  final String createdAtIso;
  final bool checked;

  VntProfile copyWith({
    String? id,
    String? name,
    String? server,
    String? networkCode,
    String? deviceId,
    String? deviceName,
    int? ctrlPort,
    String? tunName,
    bool? noTun,
    bool? rtx,
    String? customIp,
    String? password,
    String? certMode,
    bool? compress,
    bool? fec,
    bool? noPunch,
    bool? noNat,
    String? mtu,
    bool? allowMapping,
    List<String>? inputRoutes,
    List<String>? outputRoutes,
    List<String>? portMappings,
    List<String>? udpStunServers,
    List<String>? tcpStunServers,
    String? createdAtIso,
    bool? checked,
  }) {
    return VntProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      server: server ?? this.server,
      networkCode: networkCode ?? this.networkCode,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      ctrlPort: ctrlPort ?? this.ctrlPort,
      tunName: tunName ?? this.tunName,
      noTun: noTun ?? this.noTun,
      rtx: rtx ?? this.rtx,
      customIp: customIp ?? this.customIp,
      password: password ?? this.password,
      certMode: certMode ?? this.certMode,
      compress: compress ?? this.compress,
      fec: fec ?? this.fec,
      noPunch: noPunch ?? this.noPunch,
      noNat: noNat ?? this.noNat,
      mtu: mtu ?? this.mtu,
      allowMapping: allowMapping ?? this.allowMapping,
      inputRoutes: inputRoutes ?? this.inputRoutes,
      outputRoutes: outputRoutes ?? this.outputRoutes,
      portMappings: portMappings ?? this.portMappings,
      udpStunServers: udpStunServers ?? this.udpStunServers,
      tcpStunServers: tcpStunServers ?? this.tcpStunServers,
      createdAtIso: createdAtIso ?? this.createdAtIso,
      checked: checked ?? this.checked,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'server': server,
      'networkCode': networkCode,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'ctrlPort': ctrlPort,
      'tunName': tunName,
      'noTun': noTun,
      'rtx': rtx,
      'customIp': customIp,
      'password': password,
      'certMode': certMode,
      'compress': compress,
      'fec': fec,
      'noPunch': noPunch,
      'noNat': noNat,
      'mtu': mtu,
      'allowMapping': allowMapping,
      'inputRoutes': inputRoutes,
      'outputRoutes': outputRoutes,
      'portMappings': portMappings,
      'udpStunServers': udpStunServers,
      'tcpStunServers': tcpStunServers,
      'createdAtIso': createdAtIso,
      'checked': checked,
    };
  }

  factory VntProfile.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    return VntProfile(
      id: id,
      name: json['name'] as String,
      server: json['server'] as String,
      networkCode: json['networkCode'] as String,
      deviceId: json['deviceId'] as String? ?? buildDeviceId(id),
      deviceName: json['deviceName'] as String? ?? 'Vntc2',
      ctrlPort: (json['ctrlPort'] ?? json['apiPort']) as int,
      tunName: json['tunName'] as String? ?? buildTunName(id),
      noTun: json['noTun'] as bool? ?? false,
      rtx: json['rtx'] as bool? ?? true,
      customIp: json['customIp'] as String?,
      password: json['password'] as String?,
      certMode: json['certMode'] as String?,
      compress: json['compress'] as bool? ?? false,
      fec: json['fec'] as bool? ?? false,
      noPunch: json['noPunch'] as bool? ?? false,
      noNat: json['noNat'] as bool? ?? false,
      mtu: json['mtu'] as String?,
      allowMapping: json['allowMapping'] as bool? ?? false,
      inputRoutes: (json['inputRoutes'] as List<dynamic>? ?? const [])
          .cast<String>(),
      outputRoutes: (json['outputRoutes'] as List<dynamic>? ?? const [])
          .cast<String>(),
      portMappings: (json['portMappings'] as List<dynamic>? ?? const [])
          .cast<String>(),
      udpStunServers: (json['udpStunServers'] as List<dynamic>? ?? const [])
          .cast<String>(),
      tcpStunServers: (json['tcpStunServers'] as List<dynamic>? ?? const [])
          .cast<String>(),
      createdAtIso:
          json['createdAtIso'] as String? ?? DateTime.now().toIso8601String(),
      checked: json['checked'] as bool? ?? false,
    );
  }
}

class ProfileRuntimeSummary {
  const ProfileRuntimeSummary({
    required this.status,
    required this.running,
    required this.virtualIp,
    required this.onlineCount,
    required this.offlineCount,
    required this.uploadBytesPerSecond,
    required this.downloadBytesPerSecond,
    required this.totalTxBytes,
    required this.totalRxBytes,
  });

  final String status;
  final bool running;
  final String? virtualIp;
  final int onlineCount;
  final int offlineCount;
  final int uploadBytesPerSecond;
  final int downloadBytesPerSecond;
  final int totalTxBytes;
  final int totalRxBytes;

  factory ProfileRuntimeSummary.fromJson(Map<String, dynamic> json) {
    return ProfileRuntimeSummary(
      status: json['status'] as String? ?? 'stopped',
      running: json['running'] as bool? ?? false,
      virtualIp: json['virtualIp'] as String?,
      onlineCount: json['onlineCount'] as int? ?? 0,
      offlineCount: json['offlineCount'] as int? ?? 0,
      uploadBytesPerSecond: json['uploadBytesPerSecond'] as int? ?? 0,
      downloadBytesPerSecond: json['downloadBytesPerSecond'] as int? ?? 0,
      totalTxBytes: json['totalTxBytes'] as int? ?? 0,
      totalRxBytes: json['totalRxBytes'] as int? ?? 0,
    );
  }
}

class ManagedProfileSnapshot {
  const ManagedProfileSnapshot({required this.profile, required this.runtime});

  final VntProfile profile;
  final ProfileRuntimeSummary runtime;

  factory ManagedProfileSnapshot.fromJson(Map<String, dynamic> json) {
    return ManagedProfileSnapshot(
      profile: VntProfile.fromJson(json['profile'] as Map<String, dynamic>),
      runtime: ProfileRuntimeSummary.fromJson(
        json['runtime'] as Map<String, dynamic>,
      ),
    );
  }
}

class DashboardSummary {
  const DashboardSummary({
    required this.checkedProfileCount,
    required this.runningProfileCount,
    required this.connectedProfileCount,
    required this.totalOnlineCount,
    required this.totalOfflineCount,
    required this.aggregateUploadBytesPerSecond,
    required this.aggregateDownloadBytesPerSecond,
    required this.aggregateTotalTxBytes,
    required this.aggregateTotalRxBytes,
    required this.overallStatus,
  });

  final int checkedProfileCount;
  final int runningProfileCount;
  final int connectedProfileCount;
  final int totalOnlineCount;
  final int totalOfflineCount;
  final int aggregateUploadBytesPerSecond;
  final int aggregateDownloadBytesPerSecond;
  final int aggregateTotalTxBytes;
  final int aggregateTotalRxBytes;
  final String overallStatus;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      checkedProfileCount: json['checkedProfileCount'] as int? ?? 0,
      runningProfileCount: json['runningProfileCount'] as int? ?? 0,
      connectedProfileCount: json['connectedProfileCount'] as int? ?? 0,
      totalOnlineCount: json['totalOnlineCount'] as int? ?? 0,
      totalOfflineCount: json['totalOfflineCount'] as int? ?? 0,
      aggregateUploadBytesPerSecond:
          json['aggregateUploadBytesPerSecond'] as int? ?? 0,
      aggregateDownloadBytesPerSecond:
          json['aggregateDownloadBytesPerSecond'] as int? ?? 0,
      aggregateTotalTxBytes: json['aggregateTotalTxBytes'] as int? ?? 0,
      aggregateTotalRxBytes: json['aggregateTotalRxBytes'] as int? ?? 0,
      overallStatus: json['overallStatus'] as String? ?? 'stopped',
    );
  }

  factory DashboardSummary.empty() {
    return const DashboardSummary(
      checkedProfileCount: 0,
      runningProfileCount: 0,
      connectedProfileCount: 0,
      totalOnlineCount: 0,
      totalOfflineCount: 0,
      aggregateUploadBytesPerSecond: 0,
      aggregateDownloadBytesPerSecond: 0,
      aggregateTotalTxBytes: 0,
      aggregateTotalRxBytes: 0,
      overallStatus: 'stopped',
    );
  }
}

class AggregatedPeer {
  const AggregatedPeer({
    required this.peerName,
    required this.peerVirtualIp,
    required this.online,
    required this.latencyMs,
    required this.sourceProfileId,
    required this.sourceProfileName,
    required this.sourceProfileVirtualIp,
    required this.version,
  });

  final String peerName;
  final String peerVirtualIp;
  final bool online;
  final int? latencyMs;
  final String sourceProfileId;
  final String sourceProfileName;
  final String? sourceProfileVirtualIp;
  final String version;

  factory AggregatedPeer.fromJson(Map<String, dynamic> json) {
    return AggregatedPeer(
      peerName: json['peerName'] as String? ?? '',
      peerVirtualIp: json['peerVirtualIp'] as String? ?? '',
      online: json['online'] as bool? ?? false,
      latencyMs: json['latencyMs'] as int?,
      sourceProfileId: json['sourceProfileId'] as String? ?? '',
      sourceProfileName: json['sourceProfileName'] as String? ?? '',
      sourceProfileVirtualIp: json['sourceProfileVirtualIp'] as String?,
      version: json['version'] as String? ?? '',
    );
  }
}

class OperationFailure {
  const OperationFailure({required this.profileId, required this.reason});

  final String profileId;
  final String reason;

  factory OperationFailure.fromJson(Map<String, dynamic> json) {
    return OperationFailure(
      profileId: json['profileId'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
    );
  }
}

class OperationResult {
  const OperationResult({
    required this.requestedIds,
    required this.connectedIds,
    required this.disconnectedIds,
    required this.skippedIds,
    required this.failed,
  });

  final List<String> requestedIds;
  final List<String> connectedIds;
  final List<String> disconnectedIds;
  final List<String> skippedIds;
  final List<OperationFailure> failed;

  bool get hasFailure => failed.isNotEmpty;

  factory OperationResult.fromJson(Map<String, dynamic> json) {
    return OperationResult(
      requestedIds: (json['requestedIds'] as List<dynamic>? ?? const [])
          .cast<String>(),
      connectedIds: (json['connectedIds'] as List<dynamic>? ?? const [])
          .cast<String>(),
      disconnectedIds: (json['disconnectedIds'] as List<dynamic>? ?? const [])
          .cast<String>(),
      skippedIds: (json['skippedIds'] as List<dynamic>? ?? const [])
          .cast<String>(),
      failed: (json['failed'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(OperationFailure.fromJson)
          .toList(),
    );
  }

  factory OperationResult.empty() {
    return const OperationResult(
      requestedIds: <String>[],
      connectedIds: <String>[],
      disconnectedIds: <String>[],
      skippedIds: <String>[],
      failed: <OperationFailure>[],
    );
  }
}

String encodePrettyJson(Map<String, dynamic> json) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(json);
}

String buildTunName(String profileId) {
  final suffix = profileId.length > 24 ? profileId.substring(0, 24) : profileId;
  return 'vntc-$suffix';
}

String buildDeviceId(String profileId) {
  final millis = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
  return 'VNTC-${profileId.toUpperCase()}-$millis';
}
