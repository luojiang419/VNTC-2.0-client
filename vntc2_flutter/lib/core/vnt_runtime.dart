import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'repository.dart';

class VntRuntime {
  VntRuntime({
    required this.managerExecutablePath,
    required this.cliExecutablePath,
    required this.paths,
  });

  final String managerExecutablePath;
  final String cliExecutablePath;
  final AppPaths paths;

  Process? _process;
  Uri? _baseUri;

  bool get isReady => _baseUri != null;

  Future<void> start() async {
    if (_process != null && _baseUri != null) {
      return;
    }

    if (await paths.managerPortFile.exists()) {
      await paths.managerPortFile.delete();
    }

    _process = await Process.start(
      managerExecutablePath,
      <String>[
        '--data-dir',
        paths.dataDir.path,
        '--cli-executable',
        cliExecutablePath,
        '--port-file',
        paths.managerPortFile.path,
      ],
      workingDirectory: paths.executableDir.path,
      runInShell: false,
      mode: ProcessStartMode.normal,
    );

    unawaited(
      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((_) {})
          .asFuture<void>(),
    );
    unawaited(
      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((_) {})
          .asFuture<void>(),
    );

    _baseUri = await _waitForBaseUri();
  }

  Future<DashboardSummary> fetchDashboardSummary() async {
    final data = await _getDataMap('/dashboard/summary');
    return DashboardSummary.fromJson(data);
  }

  Future<List<ManagedProfileSnapshot>> fetchProfiles() async {
    final data = await _getDataList('/profiles');
    return data.map(ManagedProfileSnapshot.fromJson).toList();
  }

  Future<List<AggregatedPeer>> fetchPeers() async {
    final data = await _getDataList('/peers');
    return data.map(AggregatedPeer.fromJson).toList();
  }

  Future<OperationResult> connectProfiles(List<String> profileIds) async {
    if (profileIds.isEmpty) {
      return OperationResult.empty();
    }
    final data = await _postForDataMap('/profiles/connect', <String, dynamic>{
      'profileIds': profileIds,
    });
    return OperationResult.fromJson(data);
  }

  Future<OperationResult> disconnectProfiles(List<String> profileIds) async {
    if (profileIds.isEmpty) {
      return OperationResult.empty();
    }
    final data = await _postForDataMap(
      '/profiles/disconnect',
      <String, dynamic>{'profileIds': profileIds},
    );
    return OperationResult.fromJson(data);
  }

  Future<TunAdapterCleanupResult> cleanupUnusedTunAdapters() async {
    final data = await _postForDataMap(
      '/adapters/cleanup-unused',
      const <String, dynamic>{},
    );
    return TunAdapterCleanupResult.fromJson(data);
  }

  Future<void> dispose() async {
    try {
      if (_baseUri != null) {
        await _postVoid('/internal/shutdown', const <String, dynamic>{});
      }
    } catch (_) {
      // Manager might already be down.
    }

    final process = _process;
    _process = null;
    _baseUri = null;
    if (process != null) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      try {
        process.kill();
      } catch (_) {}
    }
  }

  Future<Uri> _waitForBaseUri() async {
    for (var attempt = 0; attempt < 40; attempt += 1) {
      if (await paths.managerPortFile.exists()) {
        final content = await paths.managerPortFile.readAsString();
        final port = int.tryParse(content.trim());
        if (port != null) {
          final uri = Uri.parse('http://127.0.0.1:$port');
          try {
            await _ping(uri);
            return uri;
          } catch (_) {}
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError('manager_start_timeout');
  }

  Future<void> _ping(Uri baseUri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final response = await (await client.getUrl(
        baseUri.resolve('/health'),
      )).close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Health check failed',
          uri: baseUri.resolve('/health'),
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _getDataMap(String path) async {
    final body = await _request('GET', path);
    return (body['data'] as Map<String, dynamic>? ?? const <String, dynamic>{});
  }

  Future<List<Map<String, dynamic>>> _getDataList(String path) async {
    final body = await _request('GET', path);
    return (body['data'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> _postForDataMap(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final body = await _request('POST', path, payload: payload);
    return (body['data'] as Map<String, dynamic>? ?? const <String, dynamic>{});
  }

  Future<void> _postVoid(String path, Map<String, dynamic> payload) async {
    await _request('POST', path, payload: payload);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? payload,
  }) async {
    final baseUri = _baseUri;
    if (baseUri == null) {
      throw StateError('manager_not_ready');
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = switch (method) {
        'GET' => await client.getUrl(baseUri.resolve(path)),
        'POST' => await client.postUrl(baseUri.resolve(path)),
        _ => throw UnsupportedError('Unsupported method: $method'),
      };

      if (payload != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(payload));
      }

      final response = await request.close();
      final body = await utf8.decodeStream(response);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}: $body');
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final code = decoded['code'] as int? ?? -1;
      if (code != 0) {
        throw StateError(decoded['msg'] as String? ?? 'request_failed');
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }
}
