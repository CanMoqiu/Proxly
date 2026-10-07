import '../l10n/app_locale.dart';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'github_download_accelerator.dart';
import 'app_platform.dart';
import 'version_comparator.dart';

class UpdateInfo {
  final String tag;
  final String apkUrl;
  final String? sha256;
  final String? body;

  const UpdateInfo({
    required this.tag,
    this.apkUrl = '',
    this.sha256,
    this.body,
  });

  Uri get releasePage => UpdateService.releasePage(tag);
}

class ApkDownloadSizeGuard {
  final int maxBytes;
  int receivedBytes = 0;

  ApkDownloadSizeGuard({required this.maxBytes});

  void validateContentLength(int? contentLength) {
    if (contentLength != null && contentLength > maxBytes) {
      throw Exception(tr('APK 文件超过 250 MB 限制'));
    }
  }

  void addChunk(int length) {
    receivedBytes += length;
    if (receivedBytes > maxBytes) {
      throw Exception(tr('APK 文件超过 250 MB 限制'));
    }
  }
}

class UpdateService {
  UpdateService._();
  static final instance = UpdateService._();

  static const int maxApkBytes = 250 * 1024 * 1024;

  static const _repo = 'CanMoqiu/proxly';
  static Uri releasePage(String tag) => Uri(
        scheme: 'https',
        host: 'github.com',
        pathSegments: [..._repo.split('/'), 'releases', 'tag', tag],
      );
  static const _prefKey = 'last_update_check';
  static const _autoCheckKey = 'automatic_update_check_enabled';
  static const _skipKey = 'skipped_update_version';
  static const _cachedTagKey = 'cached_apk_tag';

  final ValueNotifier<UpdateInfo?> availableUpdate = ValueNotifier(null);

  /// Checks the latest release while applying automatic-check throttling.
  ///
  /// Silent checks return null on failure; manual checks rethrow failures.
  Future<UpdateInfo?> checkForUpdate({required bool silent}) async {
    if (!AppPlatform.supportsUpdateChecks) return null;
    final prefs = await SharedPreferences.getInstance();

    if (silent) {
      if (!(prefs.getBool(_autoCheckKey) ?? true)) return null;
      // Automatic checks are limited to once every 24 hours.
      final last = prefs.getInt(_prefKey) ?? 0;
      final elapsed = DateTime.now().millisecondsSinceEpoch - last;
      if (elapsed < const Duration(hours: 24).inMilliseconds) return null;
    }

    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 403) {
        throw Exception(tr('GitHub API 请求频率超限，请稍后再试'));
      }
      if (res.statusCode != HttpStatus.ok) {
        throw Exception(tr('GitHub API 请求失败 (${res.statusCode})'));
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception(tr('GitHub API 返回格式异常'));
      }
      final json = decoded;
      final tag = (json['tag_name'] as String? ?? '').trim();
      final info = await PackageInfo.fromPlatform();
      final localTag = 'v${info.version}';

      // Record the check time even when no newer release is available.
      await prefs.setInt(_prefKey, DateTime.now().millisecondsSinceEpoch);

      if (tag.isEmpty) return null;
      final comparison = compareNumericVersions(tag, localTag);
      if (comparison == null) {
        throw FormatException(tr('版本格式异常'));
      }
      if (comparison <= 0) return null;

      // Do not show a release the user explicitly skipped.
      if (prefs.getString(_skipKey) == tag) return null;

      // iOS checks release metadata only; installation happens in the browser.
      final assets =
          (json['assets'] as List? ?? []).cast<Map<String, dynamic>>();
      final extension = AppPlatform.isIOS ? '.ipa' : '.apk';
      final asset = assets.firstWhere(
        (a) => (a['name'] as String? ?? '').endsWith(extension),
        orElse: () => {},
      );
      if (asset.isEmpty) return null;
      final apkUrl = AppPlatform.supportsApkUpdates
          ? asset['browser_download_url'] as String? ?? ''
          : '';
      if (AppPlatform.supportsApkUpdates && apkUrl.isEmpty) return null;
      final sha256 = AppPlatform.supportsApkUpdates
          ? _parseSha256Digest(asset['digest'] as String?)
          : null;

      final update = UpdateInfo(
        tag: tag,
        apkUrl: apkUrl,
        sha256: sha256,
        body: json['body'] as String?,
      );
      availableUpdate.value = update;
      return update;
    } catch (e) {
      if (silent) {
        await prefs.setInt(_prefKey, DateTime.now().millisecondsSinceEpoch);
        return null;
      }
      rethrow;
    }
  }

  Future<bool> isAutomaticCheckEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoCheckKey) ?? true;
  }

  Future<void> setAutomaticCheckEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoCheckKey, enabled);
  }

  String? _parseSha256Digest(String? digest) {
    if (digest == null) return null;
    final normalized = digest.trim().toLowerCase();
    final match =
        RegExp(r'^(?:sha256:)?([0-9a-f]{64})$').firstMatch(normalized);
    return match?.group(1);
  }

  /// Skips a release so subsequent automatic checks do not show it again.
  Future<void> skipVersion(String tag) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skipKey, tag);
  }

  Future<bool> _isLikelyApk(File file) async {
    if (!await file.exists()) return false;
    final length = await file.length();
    if (length <= 1024 * 1024 || length > maxApkBytes) {
      return false;
    }
    final raf = await file.open();
    try {
      final header = await raf.read(4);
      return header.length == 4 &&
          header[0] == 0x50 &&
          header[1] == 0x4B &&
          ((header[2] == 0x03 && header[3] == 0x04) ||
              (header[2] == 0x05 && header[3] == 0x06) ||
              (header[2] == 0x07 && header[3] == 0x08));
    } finally {
      await raf.close();
    }
  }

  // Return a cached APK only when it still looks like an APK.
  Future<File?> _getCachedApk(String tag, String? expectedSha256) async {
    final prefs = await SharedPreferences.getInstance();
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/proxly_update.apk');
    if (prefs.getString(_cachedTagKey) != tag) {
      if (await file.exists()) await file.delete();
      return null;
    }
    if (await _isLikelyApk(file) &&
        await _matchesExpectedSha256(file, expectedSha256)) {
      return file;
    }
    if (await file.exists()) await file.delete();
    return null;
  }

  Future<String> _fileSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<bool> _matchesExpectedSha256(
    File file,
    String? expectedSha256,
  ) async {
    if (expectedSha256 == null) return true;
    final actual = await _fileSha256(file);
    return actual.toLowerCase() == expectedSha256.toLowerCase();
  }

  /// Streams an APK download, reusing a matching cache when possible.
  ///
  /// [onProgress] receives values from 0.0 to 1.0, or -1 for an unknown size.
  /// Set [cancelled] to true to abort the download and remove its temporary file.
  Future<File> downloadApk(
    String url,
    String tag,
    String? expectedSha256,
    void Function(double) onProgress,
    ValueNotifier<bool> cancelled,
  ) async {
    if (!AppPlatform.supportsApkUpdates) {
      throw UnsupportedError('APK updates are only available on Android');
    }
    // Reuse the cached APK only when it passes the checks in _getCachedApk.
    final cached = await _getCachedApk(tag, expectedSha256);
    if (cached != null) {
      onProgress(1.0);
      return cached;
    }

    Object? lastError;
    final allowMirrors = expectedSha256 != null;
    for (final candidateUrl in GitHubDownloadAccelerator.candidates(
      url,
      includeMirrors: allowMirrors,
    )) {
      if (cancelled.value) throw const _CancelException();
      try {
        final file = await _downloadApkFromUrl(
          candidateUrl,
          expectedSha256,
          onProgress,
          cancelled,
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cachedTagKey, tag);
        return file;
      } catch (e) {
        if (e is _CancelException) rethrow;
        lastError = e;
        onProgress(0);
      }
    }

    throw Exception(tr('下载失败: $lastError'));
  }

  Future<File> _downloadApkFromUrl(
    String url,
    String? expectedSha256,
    void Function(double) onProgress,
    ValueNotifier<bool> cancelled,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/proxly_update.apk');
    if (await file.exists()) await file.delete();
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await httpClient
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != HttpStatus.ok) {
        throw Exception(tr('下载失败 HTTP ${response.statusCode}'));
      }
      final mime = response.headers.contentType?.mimeType.toLowerCase();
      if (mime != null &&
          mime != 'application/vnd.android.package-archive' &&
          mime != 'application/octet-stream' &&
          mime != 'binary/octet-stream' &&
          mime != 'application/zip' &&
          mime != 'application/x-zip-compressed') {
        throw Exception(tr('下载内容类型异常: $mime'));
      }
      final contentLength =
          response.contentLength > 0 ? response.contentLength : null;
      final sizeGuard = ApkDownloadSizeGuard(maxBytes: maxApkBytes)
        ..validateContentLength(contentLength);
      final sink = file.openWrite();

      try {
        await for (final chunk
            in response.timeout(const Duration(seconds: 30))) {
          if (cancelled.value) {
            await sink.close();
            if (await file.exists()) await file.delete();
            throw const _CancelException();
          }
          sizeGuard.addChunk(chunk.length);
          sink.add(chunk);
          if (contentLength != null && contentLength > 0) {
            onProgress(sizeGuard.receivedBytes / contentLength);
          } else {
            onProgress(-1);
          }
        }
        await sink.close();
      } catch (_) {
        await sink.close();
        if (await file.exists()) await file.delete();
        rethrow;
      }

      if (!await _isLikelyApk(file)) {
        if (await file.exists()) await file.delete();
        throw Exception(tr('下载内容不是有效 APK'));
      }
      if (!await _matchesExpectedSha256(file, expectedSha256)) {
        if (await file.exists()) await file.delete();
        throw Exception(tr('下载内容 SHA256 校验失败'));
      }

      // Cache marker is written by the caller after a successful attempt.
      return file;
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      httpClient.close();
    }
  }

  Future<void> installApk(File file) async {
    if (!AppPlatform.supportsApkUpdates) {
      throw UnsupportedError('APK installation is only available on Android');
    }
    final result = await OpenFile.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception(tr('安装失败(${result.type.name}): ${result.message}'));
    }
  }
}

class _CancelException implements Exception {
  const _CancelException();
}
