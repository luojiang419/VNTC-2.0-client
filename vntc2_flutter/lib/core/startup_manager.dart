import 'dart:io';

import 'localization.dart';
import 'models.dart';

class LaunchContext {
  const LaunchContext({required this.fromAutoStart});

  factory LaunchContext.fromArgs(List<String> args) {
    return LaunchContext(
      fromAutoStart: args.any((arg) => arg.trim() == '--startup'),
    );
  }

  final bool fromAutoStart;

  bool shouldStartHidden(AppSettings settings) {
    return fromAutoStart && settings.autoStart && settings.silentAutoStart;
  }
}

class WindowsAutoStartManager {
  WindowsAutoStartManager({required this.executablePath});

  static const String _registryKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _valueName = 'VNTC2Client';

  final String executablePath;

  Future<void> sync(AppSettings settings) async {
    if (!Platform.isWindows) {
      return;
    }

    if (settings.autoStart) {
      await _setAutoStartValue(settings.language);
      return;
    }

    await _removeAutoStartValue(settings.language);
  }

  Future<void> _setAutoStartValue(AppLanguage language) async {
    final result = await Process.run('reg.exe', <String>[
      'add',
      _registryKey,
      '/v',
      _valueName,
      '/t',
      'REG_SZ',
      '/d',
      _buildCommandLine(),
      '/f',
    ], runInShell: false);

    if (result.exitCode != 0) {
      throw StateError(
        _buildFailureMessage(
          result,
          trByLanguage(language, '写入开机自启启动项失败', 'Failed to enable auto-start'),
        ),
      );
    }
  }

  Future<void> _removeAutoStartValue(AppLanguage language) async {
    final result = await Process.run('reg.exe', <String>[
      'delete',
      _registryKey,
      '/v',
      _valueName,
      '/f',
    ], runInShell: false);

    if (result.exitCode == 0) {
      return;
    }

    final outputText = [
      _extractText(result.stderr),
      _extractText(result.stdout),
    ].join('\n').toLowerCase();
    if (outputText.contains('unable to find') ||
        outputText.contains('无法找到') ||
        outputText.contains('找不到')) {
      return;
    }

    throw StateError(
      _buildFailureMessage(
        result,
        trByLanguage(language, '移除开机自启启动项失败', 'Failed to disable auto-start'),
      ),
    );
  }

  String _buildCommandLine() {
    return '${_quoteWindowsArgument(executablePath)} --startup';
  }

  String _quoteWindowsArgument(String value) {
    if (!RegExp(r'\s').hasMatch(value)) {
      return value;
    }
    return '"${value.replaceAll('"', r'\"')}"';
  }

  String _buildFailureMessage(ProcessResult result, String prefix) {
    final stderrText = _extractText(result.stderr);
    final stdoutText = _extractText(result.stdout);
    final detail = stderrText.isNotEmpty ? stderrText : stdoutText;
    if (detail.isEmpty) {
      return '$prefix，退出码 ${result.exitCode}';
    }
    return '$prefix：$detail';
  }

  String _extractText(Object? value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }
}
