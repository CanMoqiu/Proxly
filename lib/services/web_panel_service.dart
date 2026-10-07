import '../l10n/app_locale.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:archive/archive.dart';

import 'version_comparator.dart';
import 'web_panel_flag_font.dart';

class WebPanelVersionInfo {
  final String tag;
  final String downloadUrl;
  final String sha256;

  const WebPanelVersionInfo({
    required this.tag,
    required this.downloadUrl,
    required this.sha256,
  });
}

class WebPanelArchiveEntry {
  const WebPanelArchiveEntry({required this.file, required this.path});

  final ArchiveFile file;
  final String path;
}

class WebPanelService {
  static const builtinVersion = 'v3.29.1';
  static const maxArchiveBytes = 50 * 1024 * 1024;
  static const maxArchiveEntries = 2000;
  static const maxArchiveFileBytes = 20 * 1024 * 1024;
  static const maxArchiveExtractedBytes = 100 * 1024 * 1024;
  static const maxArchiveCompressionRatio = 100;
  static const _prefVersion = 'webpanel_version';
  static const _prefPath = 'webpanel_path';
  static const _prefLastBuiltinVersion = 'webpanel_last_builtin_version';

  static int _compareVersionTags(String? a, String? b) {
    final left = _versionParts(a);
    final right = _versionParts(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  static List<int> _versionParts(String? tag) {
    if (tag == null || tag.isEmpty) return const [0];
    final matches = RegExp(r'\d+').allMatches(tag);
    final parts = matches.map((m) => int.tryParse(m.group(0)!) ?? 0).toList();
    return parts.isEmpty ? const [0] : parts;
  }

  static String? _safeArchivePath(String rawName) {
    if (rawName.isEmpty) return null;
    final name = rawName.replaceAll('\\', '/');
    if (name.startsWith('/') ||
        name.startsWith('//') ||
        RegExp(r'^[A-Za-z]:').hasMatch(name)) {
      return null;
    }

    final parts = <String>[];
    for (final part in name.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') return null;
      parts.add(part);
    }
    if (parts.isEmpty) return null;
    return parts.join('/');
  }

  static List<WebPanelArchiveEntry> validateArchive(Archive archive) {
    if (archive.length > maxArchiveEntries) {
      throw FormatException(tr('发布包文件数量超过 2000 项'));
    }

    final rawEntries = <WebPanelArchiveEntry>[];
    final rawPaths = <String>{};
    for (final file in archive) {
      if (file.name.isEmpty || file.size < 0) {
        throw FormatException(tr('发布包包含异常条目'));
      }
      if (file.isSymbolicLink) {
        throw FormatException(tr('发布包包含不支持的符号链接: ${file.name}'));
      }
      final safeName = _safeArchivePath(file.name);
      if (safeName == null) {
        throw FormatException(tr('发布包包含不安全路径: ${file.name}'));
      }
      if (!rawPaths.add(safeName.toLowerCase())) {
        throw FormatException(tr('发布包包含重复路径: ${file.name}'));
      }
      rawEntries.add(WebPanelArchiveEntry(file: file, path: safeName));
    }

    String? prefix;
    for (final entry in rawEntries) {
      final slash = entry.path.indexOf('/');
      if (slash < 1) continue;
      final candidate = entry.path.substring(0, slash + 1);
      final root = candidate.substring(0, candidate.length - 1);
      if (rawEntries.every(
        (other) => other.path == root || other.path.startsWith(candidate),
      )) {
        prefix = candidate;
      }
      break;
    }

    final validated = <WebPanelArchiveEntry>[];
    final pathKinds = <String, bool>{};
    var extractedBytes = 0;
    for (final entry in rawEntries) {
      final file = entry.file;
      var name = entry.path;
      if (prefix != null && name == prefix.substring(0, prefix.length - 1)) {
        continue;
      }
      if (prefix != null && name.startsWith(prefix)) {
        name = name.substring(prefix.length);
      }
      if (name.isEmpty) continue;
      final safeName = _safeArchivePath(name);
      if (safeName == null) {
        throw FormatException(tr('发布包包含不安全路径: ${file.name}'));
      }

      if (file.isFile) {
        if (file.size > maxArchiveFileBytes) {
          throw FormatException(tr('发布包中的单个文件超过 20 MB: ${file.name}'));
        }
        extractedBytes += file.size;
        if (extractedBytes > maxArchiveExtractedBytes) {
          throw FormatException(tr('发布包解压后的总大小超过 100 MB'));
        }
        final compressedBytes = file.rawContent?.length ?? file.size;
        if (file.size > 0 &&
            (compressedBytes <= 0 ||
                file.size / compressedBytes > maxArchiveCompressionRatio)) {
          throw FormatException(tr('发布包包含异常压缩文件: ${file.name}'));
        }
      }

      final normalized = safeName.toLowerCase();
      if (pathKinds.containsKey(normalized)) {
        throw FormatException(tr('发布包包含重复路径: ${file.name}'));
      }
      final parts = normalized.split('/');
      for (var i = 1; i < parts.length; i++) {
        final parent = parts.take(i).join('/');
        if (pathKinds[parent] == true) {
          throw FormatException(tr('发布包包含冲突路径: ${file.name}'));
        }
      }
      if (file.isFile &&
          pathKinds.keys.any((path) => path.startsWith('$normalized/'))) {
        throw FormatException(tr('发布包包含冲突路径: ${file.name}'));
      }
      pathKinds[normalized] = file.isFile;
      validated.add(WebPanelArchiveEntry(file: file, path: safeName));
    }
    return validated;
  }

  static Future<void> _downloadArchive(
    WebPanelVersionInfo info,
    File zipFile,
    void Function(double progress) onProgress,
  ) async {
    _validateGitHubReleaseDownloadUrl(info.downloadUrl);
    if (zipFile.existsSync()) await zipFile.delete();
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(info.downloadUrl));
      final response =
          await client.send(request).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception(tr('下载失败 (${response.statusCode})'));
      }

      final total = response.contentLength ?? 0;
      if (total > maxArchiveBytes) {
        throw Exception(tr('发布包超过 50 MB，已停止下载'));
      }
      int received = 0;
      final sink = zipFile.openWrite();
      try {
        await for (final chunk
            in response.stream.timeout(const Duration(seconds: 30))) {
          received += chunk.length;
          if (received > maxArchiveBytes) {
            throw Exception(tr('发布包超过 50 MB，已停止下载'));
          }
          sink.add(chunk);
          if (total > 0) onProgress(received / total * 0.75);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      final actualSha256 =
          (await sha256.bind(zipFile.openRead()).first).toString();
      if (actualSha256.toLowerCase() != info.sha256.toLowerCase()) {
        if (zipFile.existsSync()) await zipFile.delete();
        throw Exception(tr('面板发布包校验失败，请稍后重试'));
      }
    } catch (_) {
      if (zipFile.existsSync()) await zipFile.delete();
      onProgress(0);
      rethrow;
    } finally {
      client.close();
    }
  }

  static Future<String?> getInstalledVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefVersion);
  }

  static Future<String?> getInstalledPath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_prefPath);
    final version = prefs.getString(_prefVersion);

    final lastBuiltinVersion = prefs.getString(_prefLastBuiltinVersion);
    if (lastBuiltinVersion != builtinVersion) {
      await _clearInstalledPanel(prefs, path);
      await prefs.setString(_prefLastBuiltinVersion, builtinVersion);
      return null;
    }

    if (path != null && Directory(path).existsSync()) {
      if (_compareVersionTags(version, builtinVersion) >= 0) return path;

      await _clearInstalledPanel(prefs, path);
    }
    return null;
  }

  static Future<void> _clearInstalledPanel(
    SharedPreferences prefs,
    String? path,
  ) async {
    await prefs.remove(_prefPath);
    await prefs.remove(_prefVersion);
    if (path == null) return;
    try {
      await Directory(path).delete(recursive: true);
    } catch (_) {
      // Cache cleanup is best-effort; falling back to bundled assets matters most.
    }
  }

  static Future<String> getActiveVersion() async {
    final installedPath = await getInstalledPath();
    if (installedPath == null) return builtinVersion;
    return await getInstalledVersion() ?? builtinVersion;
  }

  static Future<WebPanelVersionInfo> checkLatest() async {
    Future<WebPanelVersionInfo> doFetch() async {
      final http.Response response;
      try {
        response = await http.get(
          Uri.parse(
              'https://api.github.com/repos/Zephyruso/zashboard/releases/latest'),
          headers: {'Accept': 'application/vnd.github.v3+json'},
        ).timeout(const Duration(seconds: 15));
      } on TimeoutException {
        throw Exception(tr('请求超时，请检查网络连接后重试'));
      }

      if (response.statusCode == 403) {
        throw Exception(tr('GitHub API 请求频率超限，请稍后再试'));
      }
      if (response.statusCode != 200) {
        throw Exception(tr('GitHub API 请求失败 (${response.statusCode})'));
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = data['tag_name'] as String;
      final assets = data['assets'] as List;

      final distAsset = assets.firstWhere(
        (a) => (a['name'] as String).toLowerCase() == 'dist.zip',
        orElse: () => throw Exception(tr('发布包中未找到 dist.zip')),
      );
      final downloadUrl = distAsset['browser_download_url'] as String;
      _validateGitHubReleaseDownloadUrl(downloadUrl);
      final digest = distAsset['digest'] as String?;
      final sha256Digest = _parseSha256Digest(digest);
      if (sha256Digest == null) {
        throw Exception(tr('发布包缺少 SHA256 摘要，已拒绝更新'));
      }

      return WebPanelVersionInfo(
        tag: tag,
        downloadUrl: downloadUrl,
        sha256: sha256Digest,
      );
    }

    try {
      return await doFetch();
    } on TimeoutException {
      await Future.delayed(const Duration(seconds: 2));
      return await doFetch();
    } on SocketException {
      await Future.delayed(const Duration(seconds: 2));
      return await doFetch();
    }
  }

  static Future<void> downloadAndInstall(
    WebPanelVersionInfo info,
    void Function(double progress) onProgress,
  ) async {
    if (NumericVersion.tryParse(info.tag) == null) {
      throw FormatException(tr('版本格式异常'));
    }
    final appDir = await getApplicationSupportDirectory();
    final baseDir = Directory('${appDir.path}/zashboard');
    await baseDir.create(recursive: true);

    final zipFile = File('${baseDir.path}/download.zip');
    final newDir = Directory('${baseDir.path}/${info.tag}');
    final stagingDir = Directory('${newDir.path}.staging');
    final backupDir = Directory('${newDir.path}.backup');
    var switched = false;
    var backedUpExisting = false;

    try {
      await _downloadArchive(info, zipFile, onProgress);
      onProgress(0.80);

      // Validate the complete archive before extracting anything to the staging directory.
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      onProgress(0.85);

      final validated = validateArchive(archive);

      if (stagingDir.existsSync()) await stagingDir.delete(recursive: true);
      await stagingDir.create(recursive: true);
      for (final entry in validated) {
        final file = entry.file;
        final outPath = '${stagingDir.path}/${entry.path}';

        if (file.isFile) {
          final outFile = File(outPath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }

      // Require index.html so an incomplete archive cannot replace the active panel.
      if (!File('${stagingDir.path}/index.html').existsSync()) {
        throw Exception(tr('解压后未找到 index.html，发布包格式有误'));
      }
      onProgress(0.95);

      if (backupDir.existsSync()) await backupDir.delete(recursive: true);
      if (newDir.existsSync()) {
        await newDir.rename(backupDir.path);
        backedUpExisting = true;
      }
      try {
        await stagingDir.rename(newDir.path);
        switched = true;
      } catch (_) {
        if (backedUpExisting && !newDir.existsSync()) {
          await backupDir.rename(newDir.path);
          backedUpExisting = false;
        }
        rethrow;
      }

      // Persist the version and resource path only after activation succeeds.
      final prefs = await SharedPreferences.getInstance();
      final oldPath = prefs.getString(_prefPath);
      await prefs.setString(_prefVersion, info.tag);
      await prefs.setString(_prefPath, newDir.path);

      if (backupDir.existsSync()) await backupDir.delete(recursive: true);
      backedUpExisting = false;
      switched = false;
      if (oldPath != null && oldPath != newDir.path) {
        try {
          final oldDir = Directory(oldPath);
          if (oldDir.existsSync()) await oldDir.delete(recursive: true);
        } catch (_) {
          // The new panel is already active, so old-cache cleanup is best-effort.
        }
      }

      onProgress(1.0);
    } catch (_) {
      // Remove partial files after download or extraction failures so they cannot
      // be reused by a later update attempt.
      if (zipFile.existsSync()) await zipFile.delete();
      if (stagingDir.existsSync()) await stagingDir.delete(recursive: true);
      if (switched) {
        if (newDir.existsSync()) await newDir.delete(recursive: true);
        if (backedUpExisting && backupDir.existsSync()) {
          await backupDir.rename(newDir.path);
        }
      }
      rethrow;
    } finally {
      if (zipFile.existsSync()) await zipFile.delete();
    }
  }

  static String? _parseSha256Digest(String? digest) {
    if (digest == null || digest.trim().isEmpty) return null;
    final value = digest.trim().toLowerCase();
    final match = RegExp(r'^(?:sha256:)?([a-f0-9]{64})$').firstMatch(value);
    return match?.group(1);
  }

  static void _validateGitHubReleaseDownloadUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.pathSegments.length < 5 ||
        uri.pathSegments[2] != 'releases' ||
        uri.pathSegments[3] != 'download') {
      throw Exception(tr('发布包下载地址不可信，已拒绝更新'));
    }
  }
}

class WebPanelControllerBridge {
  static const maxRequestBytes = 8 * 1024 * 1024;
  static const _pathRoot = '/__proxly_clash';

  final String hostname;
  final int port;
  final String _token;
  final HttpClient _client;
  final String _session;
  final Set<WebSocket> _webSockets = <WebSocket>{};
  bool _closed = false;

  WebPanelControllerBridge({
    required this.hostname,
    required this.port,
    required String token,
    HttpClient? client,
    String? session,
  })  : _token = token,
        _client = client ?? HttpClient(),
        _session = session ?? _randomSession() {
    // Forward the original bytes with Content-Encoding. HttpClient otherwise
    // decodes gzip while keeping that header, so WebKit tries to decode twice.
    _client.autoUncompress = false;
    _client.connectionTimeout = const Duration(seconds: 8);
  }

  String get secondaryPath => '$_pathRoot/$_session';

  bool matches(Uri uri) =>
      uri.path == secondaryPath || uri.path.startsWith('$secondaryPath/');

  Future<bool> handle(HttpRequest request) async {
    if (!matches(request.uri)) return false;
    if (request.method == 'OPTIONS') {
      _setCorsHeaders(request.response);
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return true;
    }
    if (!const {'GET', 'POST', 'PUT', 'PATCH', 'DELETE'}
        .contains(request.method)) {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return true;
    }

    final relativePath = request.uri.path.substring(secondaryPath.length);
    final upstreamPath = relativePath.isEmpty ? '/' : relativePath;
    try {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        await _proxyWebSocket(request, upstreamPath);
      } else {
        await _proxyHttp(request, upstreamPath);
      }
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } catch (_) {
        // The downstream socket may already be upgraded or closed.
      }
    }
    return true;
  }

  Future<void> _proxyHttp(HttpRequest request, String upstreamPath) async {
    final upstreamUri = Uri(
      scheme: 'http',
      host: hostname,
      port: port,
      path: upstreamPath,
      query: request.uri.hasQuery ? request.uri.query : null,
    );
    final upstream = await _client
        .openUrl(request.method, upstreamUri)
        .timeout(const Duration(seconds: 10));
    upstream
      ..followRedirects = false
      ..maxRedirects = 0;
    _copyRequestHeaders(request.headers, upstream.headers);
    if (_token.isNotEmpty) {
      upstream.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    }

    var received = 0;
    await for (final chunk in request) {
      received += chunk.length;
      if (received > maxRequestBytes) {
        upstream.abort();
        request.response.statusCode = HttpStatus.requestEntityTooLarge;
        await request.response.close();
        return;
      }
      upstream.add(chunk);
    }

    final response = await upstream.close().timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        upstream.abort();
        throw TimeoutException('Controller response timed out');
      },
    );
    request.response.statusCode = response.statusCode;
    _copyResponseHeaders(response.headers, request.response.headers);
    _setCorsHeaders(request.response);
    await request.response.addStream(response);
    await request.response.close();
  }

  Future<void> _proxyWebSocket(
    HttpRequest request,
    String upstreamPath,
  ) async {
    final upstreamUri = Uri(
      scheme: 'ws',
      host: hostname,
      port: port,
      path: upstreamPath,
      query: request.uri.hasQuery ? request.uri.query : null,
    );
    final headers = _token.isEmpty
        ? null
        : <String, dynamic>{
            HttpHeaders.authorizationHeader: 'Bearer $_token',
          };
    final upstream = await WebSocket.connect(
      upstreamUri.toString(),
      headers: headers,
    );
    if (_closed) {
      await upstream.close();
      throw StateError('Controller bridge is closed');
    }
    late final WebSocket downstream;
    try {
      downstream = await WebSocketTransformer.upgrade(request);
    } catch (_) {
      await upstream.close();
      rethrow;
    }
    _webSockets
      ..add(upstream)
      ..add(downstream);
    downstream.listen(
      upstream.add,
      onError: (_) => _closeSocketPair(downstream, upstream),
      onDone: () => _closeSocketPair(downstream, upstream),
      cancelOnError: true,
    );
    upstream.listen(
      downstream.add,
      onError: (_) => _closeSocketPair(upstream, downstream),
      onDone: () => _closeSocketPair(upstream, downstream),
      cancelOnError: true,
    );
  }

  void _closeSocketPair(WebSocket source, WebSocket target) {
    _webSockets
      ..remove(source)
      ..remove(target);
    unawaited(target.close());
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _client.close(force: true);
    final sockets = List<WebSocket>.of(_webSockets);
    _webSockets.clear();
    for (final socket in sockets) {
      unawaited(socket.close());
    }
  }

  static void _copyRequestHeaders(
    HttpHeaders source,
    HttpHeaders target,
  ) {
    source.forEach((name, values) {
      final lower = name.toLowerCase();
      if (lower == HttpHeaders.hostHeader ||
          lower == HttpHeaders.authorizationHeader ||
          lower == HttpHeaders.contentLengthHeader ||
          lower == HttpHeaders.connectionHeader) {
        return;
      }
      target.set(name, values);
    });
  }

  static void _copyResponseHeaders(
    HttpHeaders source,
    HttpHeaders target,
  ) {
    source.forEach((name, values) {
      final lower = name.toLowerCase();
      if (lower == HttpHeaders.contentLengthHeader ||
          lower == HttpHeaders.transferEncodingHeader ||
          lower == HttpHeaders.connectionHeader ||
          lower == 'access-control-allow-origin') {
        return;
      }
      target.set(name, values);
    });
  }

  static void _setCorsHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type, Authorization',
    );
    response.headers.set(
      'Access-Control-Allow-Methods',
      'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    );
  }

  static String _randomSession() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

/// Serves downloaded panel resources to InAppWebView over localhost.
class FileHttpServer {
  HttpServer? _server;
  final String rootPath;
  final WebPanelControllerBridge? controllerBridge;
  int _port = 0;

  FileHttpServer(this.rootPath, {this.controllerBridge});

  int get port => _port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _server!.listen(_handle);
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
    controllerBridge?.close();
  }

  Future<void> _handle(HttpRequest request) async {
    if (await controllerBridge?.handle(request) == true) return;
    if (await WebPanelFlagFont.handle(request)) return;
    final root = await Directory(rootPath).resolveSymbolicLinks();
    final requestedSegments = request.uri.pathSegments.isEmpty
        ? const ['index.html']
        : request.uri.pathSegments.where((segment) => segment.isNotEmpty);
    final safeSegments = <String>[];
    for (final segment in requestedSegments) {
      if (segment == '.' ||
          segment == '..' ||
          segment.contains('/') ||
          segment.contains('\\') ||
          segment.contains('\u0000')) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      safeSegments.add(segment);
    }
    if (safeSegments.isEmpty) safeSegments.add('index.html');

    final relativePath = safeSegments.join('/');
    final filePath = [root, ...safeSegments].join(Platform.pathSeparator);
    final file = File(filePath);
    if (file.existsSync()) {
      final resolvedFile = await file.resolveSymbolicLinks();
      if (!_isInsideRoot(resolvedFile, root)) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      request.response.headers
          .set(HttpHeaders.contentTypeHeader, _contentType(relativePath));
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      await request.response.addStream(File(resolvedFile).openRead());
    } else {
      // Fall back to index.html for unknown SPA routes.
      final index = File('$root${Platform.pathSeparator}index.html');
      if (index.existsSync()) {
        request.response.headers
            .set(HttpHeaders.contentTypeHeader, 'text/html; charset=utf-8');
        await request.response.addStream(index.openRead());
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
    }
    await request.response.close();
  }

  bool _isInsideRoot(String path, String root) {
    final normalizedRoot = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    if (Platform.isWindows) {
      return path.toLowerCase().startsWith(normalizedRoot.toLowerCase());
    }
    return path.startsWith(normalizedRoot);
  }

  String _contentType(String path) {
    if (path.endsWith('.html')) return 'text/html; charset=utf-8';
    if (path.endsWith('.js') || path.endsWith('.mjs')) {
      return 'application/javascript';
    }
    if (path.endsWith('.css')) return 'text/css';
    if (path.endsWith('.json')) return 'application/json';
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'image/jpeg';
    if (path.endsWith('.webp')) return 'image/webp';
    if (path.endsWith('.svg')) return 'image/svg+xml';
    if (path.endsWith('.ico')) return 'image/x-icon';
    if (path.endsWith('.ttf')) return 'font/ttf';
    if (path.endsWith('.woff2')) return 'font/woff2';
    if (path.endsWith('.woff')) return 'font/woff';
    if (path.endsWith('.webmanifest')) return 'application/manifest+json';
    return 'application/octet-stream';
  }
}

/// Serves bundled Flutter assets from an isolated random localhost port.
class AssetHttpServer {
  HttpServer? _server;
  final String rootPath;
  final WebPanelControllerBridge? controllerBridge;
  int _port = 0;

  AssetHttpServer(this.rootPath, {this.controllerBridge});

  int get port => _port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _server!.listen(_handle);
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
    controllerBridge?.close();
  }

  Future<void> _handle(HttpRequest request) async {
    if (await controllerBridge?.handle(request) == true) return;
    if (await WebPanelFlagFont.handle(request)) return;
    final requestedSegments = request.uri.pathSegments.isEmpty
        ? const ['index.html']
        : request.uri.pathSegments.where((segment) => segment.isNotEmpty);
    final safeSegments = <String>[];
    for (final segment in requestedSegments) {
      if (segment == '.' ||
          segment == '..' ||
          segment.contains('/') ||
          segment.contains('\\') ||
          segment.contains('\u0000')) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      safeSegments.add(segment);
    }
    if (safeSegments.isEmpty) safeSegments.add('index.html');

    final relativePath = safeSegments.join('/');
    final assetPath = '$rootPath/$relativePath';
    final served = await _tryServeAsset(request, assetPath, relativePath);
    if (!served) {
      final fallbackServed =
          await _tryServeAsset(request, '$rootPath/index.html', 'index.html');
      if (!fallbackServed) {
        request.response.statusCode = HttpStatus.notFound;
      }
    }
    await request.response.close();
  }

  Future<bool> _tryServeAsset(
    HttpRequest request,
    String assetPath,
    String relativePath,
  ) async {
    try {
      final data = await rootBundle.load(assetPath);
      request.response.headers
          .set(HttpHeaders.contentTypeHeader, _contentType(relativePath));
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      request.response.add(data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      ));
      return true;
    } catch (_) {
      return false;
    }
  }

  String _contentType(String path) {
    if (path.endsWith('.html')) return 'text/html; charset=utf-8';
    if (path.endsWith('.js') || path.endsWith('.mjs')) {
      return 'application/javascript';
    }
    if (path.endsWith('.css')) return 'text/css';
    if (path.endsWith('.json')) return 'application/json';
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'image/jpeg';
    if (path.endsWith('.webp')) return 'image/webp';
    if (path.endsWith('.svg')) return 'image/svg+xml';
    if (path.endsWith('.ico')) return 'image/x-icon';
    if (path.endsWith('.ttf')) return 'font/ttf';
    if (path.endsWith('.woff2')) return 'font/woff2';
    if (path.endsWith('.woff')) return 'font/woff';
    if (path.endsWith('.webmanifest')) return 'application/manifest+json';
    return 'application/octet-stream';
  }
}

class WebPanelAuthScript {
  WebPanelAuthScript._();

  static String build({
    required String hostname,
    required String port,
    required String secondaryPath,
    bool dispatchEvents = false,
  }) {
    final apiList = jsonEncode([
      {
        'uuid': 'proxly-current',
        'type': 'clash',
        'protocol': 'http',
        'secondaryPath': secondaryPath,
        'host': hostname,
        'port': port,
        'password': '',
        'label': 'Proxly',
        'disableUpgradeCore': false,
      }
    ]);
    final apiListLiteral = jsonEncode(apiList);
    final activeUuidLiteral = jsonEncode('proxly-current');
    final dispatchLiteral = dispatchEvents ? 'true' : 'false';

    return """
      (function(){try{
        const apiList = $apiListLiteral;
        const activeUuid = $activeUuidLiteral;
        localStorage.setItem('setup/api-list', apiList);
        localStorage.setItem('setup/active-uuid', activeUuid);
        if ($dispatchLiteral) {
          [
            ['setup/api-list', apiList],
            ['setup/active-uuid', activeUuid]
          ].forEach(function([key, value]) {
            window.dispatchEvent(new StorageEvent('storage', {
              key: key,
              newValue: value,
              storageArea: window.localStorage
            }));
          });
        }
      }catch(e){}})();
    """;
  }
}

class WebPanelCoreSettingsSyncScript {
  WebPanelCoreSettingsSyncScript._();

  static const pendingStorageKey = '__proxly_core_settings_import_pending_v1';

  static String build() {
    final pendingKey = jsonEncode(pendingStorageKey);
    return """
      (function(){try{
        const stateKey = '__proxlyCoreSettingsSyncV1';
        const pendingKey = $pendingKey;
        if (window[stateKey]) {
          window.__proxlyCoreImportPending =
            sessionStorage.getItem(pendingKey) !== null;
          return;
        }
        window[stateKey] = true;
        window.__proxlyCoreImportPending =
          sessionStorage.getItem(pendingKey) !== null;

        let candidate = null;
        function isCoreSettingsRequest(url, method) {
          if (String(method || 'GET').toUpperCase() !== 'GET') return false;
          try {
            const parsed = new URL(String(url || ''), window.location.href);
            return parsed.pathname.endsWith('/storage/zashboard');
          } catch (_) {
            return false;
          }
        }
        function captureCandidate(value) {
          if (!value || typeof value !== 'object' || Array.isArray(value)) {
            return;
          }
          candidate = value;
        }
        function markConfirmedImport(key, value) {
          if (candidate && key === 'cache/auto-sync-settings-hash') {
            candidate = null;
            return;
          }
          if (!candidate || !String(key || '').startsWith('config/')) return;
          if (!Object.prototype.hasOwnProperty.call(candidate, key)) return;
          if (String(candidate[key]) !== String(value)) return;
          sessionStorage.setItem(pendingKey, JSON.stringify(candidate));
          window.__proxlyCoreImportPending = true;
          candidate = null;
        }

        const originalSetItem = Storage.prototype.setItem;
        Storage.prototype.setItem = function(key, value) {
          const result = originalSetItem.apply(this, arguments);
          if (this === window.localStorage) {
            markConfirmedImport(String(key), String(value));
          }
          return result;
        };

        const originalFetch = window.fetch;
        if (typeof originalFetch === 'function') {
          window.fetch = function(input, init) {
            const url = typeof input === 'string' ? input :
              (input && input.url) || '';
            const method = (init && init.method) ||
              (input && input.method) || 'GET';
            const responsePromise = originalFetch.apply(this, arguments);
            if (!isCoreSettingsRequest(url, method)) return responsePromise;
            return responsePromise.then(async function(response) {
              if (response && response.ok) {
                try { captureCandidate(await response.clone().json()); } catch (_) {}
              }
              return response;
            });
          };
        }

        const originalOpen = XMLHttpRequest.prototype.open;
        const originalSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function(method, url) {
          this.__proxlyCoreSettingsRequest =
            isCoreSettingsRequest(url, method);
          return originalOpen.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function() {
          if (this.__proxlyCoreSettingsRequest) {
            this.addEventListener('load', function() {
              if (this.status < 200 || this.status >= 300) return;
              try {
                const value = this.responseType === 'json'
                  ? this.response
                  : JSON.parse(this.responseText);
                captureCandidate(value);
              } catch (_) {}
            }, { capture: true, once: true });
          }
          return originalSend.apply(this, arguments);
        };
      }catch(e){}})();
    """;
  }

  static String consumePending() {
    final pendingKey = jsonEncode(pendingStorageKey);
    return """
      (function(){try{
        const key = $pendingKey;
        const raw = sessionStorage.getItem(key);
        if (raw !== null) sessionStorage.removeItem(key);
        window.__proxlyCoreImportPending = false;
        return raw;
      }catch(e){ return null; }})();
    """;
  }
}

class WebPanelLayoutScript {
  WebPanelLayoutScript._();

  static String buildDockless({
    bool proxyTab = false,
    bool connectionsTab = false,
  }) {
    assert(
      !(proxyTab && connectionsTab),
      'Proxy and connections scroll modes are mutually exclusive.',
    );
    final markerClass = proxyTab
        ? '__proxly_dockless __proxly_proxy_tab_scroll'
        : connectionsTab
            ? '__proxly_dockless __proxly_connections_tab_scroll'
            : '__proxly_dockless';
    final styleId = proxyTab
        ? '__proxly_dockless_proxy_style'
        : connectionsTab
            ? '__proxly_dockless_connections_style'
            : '__proxly_dockless_layout_style';
    final css = <String>[
      'html.__proxly_dockless { height: var(--app-height, 100dvh) !important; max-height: var(--app-height, 100dvh) !important; overflow: hidden !important; overscroll-behavior: none !important; }',
      'html.__proxly_dockless body, html.__proxly_dockless #app, html.__proxly_dockless #app-content { height: var(--app-height, 100dvh) !important; min-height: 0 !important; max-height: var(--app-height, 100dvh) !important; overflow: hidden !important; overscroll-behavior: none !important; }',
      'html.__proxly_dockless body { margin: 0 !important; }',
      'html.__proxly_dockless .home-page { height: 100% !important; min-height: 0 !important; max-height: 100% !important; overflow: hidden !important; }',
      // Keep an invisible zero-height box at the viewport bottom. Zashboard
      // measures its top to size virtual lists; display:none would add an
      // entire viewport of blank padding to those lists.
      'html.__proxly_dockless .home-page .dock, html.__proxly_dockless .home-page nav.tab-bar { display: flex !important; position: fixed !important; top: 100% !important; bottom: auto !important; height: 0 !important; min-height: 0 !important; padding: 0 !important; margin: 0 !important; border: 0 !important; transform: none !important; overflow: hidden !important; visibility: hidden !important; pointer-events: none !important; }',
      'html.__proxly_dockless .home-page .dock + .fixed.bottom-0, html.__proxly_dockless .home-page nav.tab-bar + .fixed.bottom-0 { display: none !important; }',
      if (proxyTab)
        'html.__proxly_proxy_tab_scroll .home-page > [class~="relative"][class~="flex-1"][class~="overflow-hidden"] > [class~="absolute"][class~="flex"][class~="h-full"][class~="w-full"][class~="flex-col"][class~="overflow-y-auto"]:has([class~="h-full"][class~="min-w-0"][class~="flex-1"][class~="overflow-y-scroll"]) { overflow-y: hidden !important; overscroll-behavior-y: none !important; }',
      if (proxyTab)
        'html.__proxly_proxy_tab_scroll .home-page [class~="h-full"][class~="min-w-0"][class~="flex-1"][class~="overflow-y-scroll"] { height: 100% !important; min-height: 0 !important; max-height: 100% !important; overflow-y: scroll !important; overscroll-behavior-y: none !important; touch-action: pan-y !important; -webkit-overflow-scrolling: touch !important; scroll-padding-bottom: 0 !important; padding-bottom: 0 !important; }',
      if (connectionsTab)
        'html.__proxly_connections_tab_scroll .home-page > [class~="relative"][class~="flex-1"][class~="overflow-hidden"] > [class~="absolute"][class~="flex"][class~="h-full"][class~="w-full"][class~="flex-col"][class~="overflow-y-auto"] { overflow-y: hidden !important; overscroll-behavior-y: none !important; }',
      if (connectionsTab)
        'html.__proxly_connections_tab_scroll .home-page [class~="relative"][class~="flex"][class~="size-full"][class~="flex-col"][class~="overflow-hidden"] { height: 100% !important; min-height: 0 !important; max-height: 100% !important; padding-bottom: 0 !important; }',
      if (connectionsTab)
        'html.__proxly_connections_tab_scroll .home-page [class~="relative"][class~="flex"][class~="size-full"][class~="flex-col"][class~="overflow-hidden"] > [class~="flex"][class~="h-full"][class~="w-full"][class~="flex-col"][class~="overflow-y-auto"] { height: 100% !important; min-height: 0 !important; max-height: 100% !important; flex: 1 1 auto !important; overflow-y: auto !important; overscroll-behavior-y: none !important; touch-action: pan-y !important; -webkit-overflow-scrolling: touch !important; scroll-padding-bottom: 0 !important; padding-bottom: 0 !important; }',
      if (connectionsTab)
        'html.__proxly_connections_tab_scroll .home-page [class~="relative"][class~="flex"][class~="size-full"][class~="flex-col"][class~="overflow-hidden"] > .base-container.m-3.h-full.overflow-auto { height: auto !important; min-height: 0 !important; max-height: none !important; flex: 1 1 auto !important; margin-bottom: 0 !important; overflow: auto !important; overscroll-behavior-y: none !important; touch-action: pan-y !important; -webkit-overflow-scrolling: touch !important; scroll-padding-bottom: 0 !important; padding-bottom: 0 !important; }',
    ].join('\n');

    return """
      (function(){try{
        const stateKey = '__proxlyDocklessLayoutV4';
        const styleId = ${jsonEncode(styleId)};
        const css = ${jsonEncode(css)};
        const markerClasses = ${jsonEncode(markerClass)}.split(' ');
        const state = window[stateKey] || (window[stateKey] = {});

        function viewportHeight() {
          return (window.visualViewport && window.visualViewport.height) ||
            window.innerHeight ||
            document.documentElement.clientHeight ||
            0;
        }

        function applyViewportHeight() {
          const height = viewportHeight();
          if (height > 0) {
            document.documentElement.style.setProperty(
              '--app-height',
              height + 'px'
            );
          }
        }

        function ensureStyle() {
          let style = document.getElementById(styleId);
          if (!style) {
            style = document.createElement('style');
            style.id = styleId;
            (document.head || document.documentElement).appendChild(style);
          }
          if (style.textContent !== css) {
            style.textContent = css;
          }
        }

        function applyDocklessLayout() {
          document.documentElement.classList.add.apply(
            document.documentElement.classList,
            markerClasses
          );
          applyViewportHeight();
          ensureStyle();
        }

        if (state.version === 4 && state.apply) {
          state.apply();
          return;
        }

        state.version = 4;
        state.apply = applyDocklessLayout;

        window.addEventListener('resize', applyViewportHeight);
        window.addEventListener('orientationchange', applyViewportHeight);
        if (window.visualViewport) {
          window.visualViewport.addEventListener(
            'resize',
            applyViewportHeight
          );
        }
        window.addEventListener('load', applyDocklessLayout, { once: true });
        document.addEventListener(
          'DOMContentLoaded',
          applyDocklessLayout,
          { once: true }
        );

        applyDocklessLayout();
      }catch(e){}})();
    """;
  }
}

class WebPanelAppearanceScript {
  WebPanelAppearanceScript._();

  static String build({
    required bool isDark,
    required String language,
    bool dispatchEvents = false,
  }) {
    final themeLiteral = jsonEncode(isDark ? 'dark' : 'light');
    final languageLiteral = jsonEncode(language);
    final dispatchLiteral = dispatchEvents ? 'true' : 'false';

    return """
      (function(){try{
        const theme = $themeLiteral;
        const language = $languageLiteral;
        const shouldDispatch = $dispatchLiteral;
        function setManagedItem(key, value) {
          const oldValue = localStorage.getItem(key);
          localStorage.setItem(key, value);
          if (shouldDispatch) {
            window.dispatchEvent(new StorageEvent('storage', {
              key: key,
              oldValue: oldValue,
              newValue: value,
              url: window.location.href,
              storageArea: window.localStorage
            }));
          }
        }
        function setNavigatorLocale() {
          try {
            Object.defineProperty(navigator, 'language', {
              get: function() { return language; },
              configurable: true
            });
            Object.defineProperty(navigator, 'languages', {
              get: function() { return [language]; },
              configurable: true
            });
          } catch (_) {}
        }
        function applyDom() {
          document.documentElement.lang = language;
          document.documentElement.setAttribute('data-theme', theme);
          document.documentElement.style.colorScheme = theme;
          if (document.body) {
            document.body.setAttribute('data-theme', theme);
            document.body.style.colorScheme = theme;
          }
        }
        setNavigatorLocale();
        setManagedItem('config/auto-theme', 'false');
        setManagedItem('config/default-theme', theme);
        setManagedItem('config/dark-theme', 'dark');
        setManagedItem('config/language', language);
        applyDom();
        document.addEventListener('DOMContentLoaded', applyDom, { once: true });
        requestAnimationFrame(applyDom);
        if (shouldDispatch) {
          window.dispatchEvent(new CustomEvent('proxly:appearance-change', {
            detail: { theme: theme, language: language }
          }));
          window.dispatchEvent(new Event('resize'));
          try { window.dispatchEvent(new Event('visibilitychange')); } catch (_) {}
          try { document.dispatchEvent(new Event('visibilitychange')); } catch (_) {}
          try { window.dispatchEvent(new PopStateEvent('popstate', { state: history.state })); } catch (_) {}
          try { window.dispatchEvent(new HashChangeEvent('hashchange')); } catch (_) {}
        }
      }catch(e){}})();
    """;
  }
}

/// Synchronizes Web panel state between the tab WebViews and pushed console.
class WebPanelSync {
  WebPanelSync._();
  static final instance = WebPanelSync._();

  Future<void> Function()? _save;
  Future<void> Function()? _reload;
  Future<void> Function()? _syncAppearance;
  Future<void> Function()? _reloadConnections;
  Future<void> Function()? _syncConnectionsAppearance;
  final Map<Object, Future<void> Function()> _webViewReloaders = {};
  final Map<Object, Future<void> Function()> _webViewRestarters = {};

  /// Whether the connections tab is currently visible in WebView mode.
  bool connectionsTabActive = false;

  /// Whether the proxy tab is currently active.
  ///
  /// MainShell updates this state when tabs change so ProxyPage can decide
  /// whether lifecycle-triggered reloads should be handled.
  bool proxyTabActive = false;

  void register({
    required Future<void> Function() save,
    required Future<void> Function() reload,
    Future<void> Function()? syncAppearance,
  }) {
    _save = save;
    _reload = reload;
    _syncAppearance = syncAppearance;
  }

  void unregister() {
    _save = null;
    _reload = null;
    _syncAppearance = null;
  }

  void registerConnections({
    required Future<void> Function() reload,
    Future<void> Function()? syncAppearance,
  }) {
    _reloadConnections = reload;
    _syncConnectionsAppearance = syncAppearance;
  }

  void unregisterConnections() {
    _reloadConnections = null;
    _syncConnectionsAppearance = null;
  }

  void registerWebView(
    Object owner,
    Future<void> Function() reload, {
    Future<void> Function()? restartServer,
  }) {
    _webViewReloaders[owner] = reload;
    if (restartServer != null) _webViewRestarters[owner] = restartServer;
  }

  void unregisterWebView(Object owner) {
    _webViewReloaders.remove(owner);
    _webViewRestarters.remove(owner);
  }

  /// Reopens each local server against the newly installed resource directory.
  Future<WebPanelReloadResult> restartAllWebViews({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final callbacks =
        Map<Object, Future<void> Function()>.from(_webViewRestarters);
    final results = <Object, bool>{};
    await Future.wait(callbacks.entries.map((entry) async {
      try {
        await entry.value().timeout(timeout);
        results[entry.key] = true;
      } catch (_) {
        results[entry.key] = false;
      }
    }));
    return WebPanelReloadResult(
      total: callbacks.length,
      failed: results.values.where((succeeded) => !succeeded).length,
      results: Map.unmodifiable(results),
    );
  }

  Future<WebPanelReloadResult> reloadAllWebViews() async {
    final callbacks = List<Future<void> Function()>.from(
      _webViewReloaders.values,
    );
    var failed = 0;
    await Future.wait(callbacks.map((callback) async {
      try {
        await callback();
      } catch (_) {
        failed++;
      }
    }));
    return WebPanelReloadResult(total: callbacks.length, failed: failed);
  }

  Future<void> save() async => _save?.call();
  Future<void> reload() async => _reload?.call();

  Future<void> syncAppearance() async {
    final tasks = <Future<void>>[];
    final proxy = _syncAppearance;
    final connections = _syncConnectionsAppearance;
    if (proxy != null) tasks.add(_runSafely(proxy));
    if (connections != null) tasks.add(_runSafely(connections));
    if (tasks.isEmpty) return;
    await Future.wait(tasks);
  }

  Future<void> _runSafely(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  Future<void> reloadConnections({bool force = false}) async {
    if (!force && !connectionsTabActive) return;
    return _reloadConnections?.call();
  }
}

class WebPanelReloadResult {
  const WebPanelReloadResult({
    required this.total,
    required this.failed,
    this.results = const {},
  });

  final int total;
  final int failed;
  final Map<Object, bool> results;

  bool get succeeded => failed == 0;
}
