import '../l10n/app_locale.dart';
// lib/services/update_service.dart
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
import 'app_version.dart';
import 'version_comparator.dart';

class UpdateInfo {
  final String tag;
  final String apkUrl;
  final String ipaUrl;
  final String? sha256;
  final String? body;

  const UpdateInfo({
    required this.tag,
    this.apkUrl = '',
    this.ipaUrl = '',
    this.sha256,
    this.body,
  });
}

enum _UpdatePackage { apk, ipa }

class UpdateDownloadSizeGuard {
  final int maxBytes;
  int receivedBytes = 0;

  UpdateDownloadSizeGuard({required this.maxBytes});

  void validateContentLength(int? contentLength) {
    if (contentLength != null && contentLength > maxBytes) {
      throw Exception(tr('安装包超过 250 MB 限制'));
    }
  }

  void addChunk(int length) {
    receivedBytes += length;
    if (receivedBytes > maxBytes) {
      throw Exception(tr('安装包超过 250 MB 限制'));
    }
  }
}

class UpdateService {
  UpdateService._()
      : _temporaryDirectory = getTemporaryDirectory,
        _documentsDirectory = getApplicationDocumentsDirectory;
  @visibleForTesting
  UpdateService.forTesting({
    required Future<Directory> Function() temporaryDirectory,
    Future<Directory> Function() documentsDirectory =
        getApplicationDocumentsDirectory,
  })  : _temporaryDirectory = temporaryDirectory,
        _documentsDirectory = documentsDirectory;
  static final instance = UpdateService._();

  static const _maxPackageBytes = 250 * 1024 * 1024;
  static const _iosDownloadsFolder = 'Downloads';

  static const _repo = 'CanMoqiu/proxly';
  static const _prefKey = 'last_update_check';
  static const _autoCheckKey = 'automatic_update_check_enabled';
  static const _skipKey = 'skipped_update_version';
  static const _cachedTagKey = 'cached_apk_tag';
  static final _placeholderTag = RegExp(r'^untagged-[0-9a-f]+$');
  static final _releaseTitle = RegExp(
    r'^Proxly (\d{2}\.\d+(?:\.\d+)?)(?:（测试版）| \(Test version\))?$',
  );

  final ValueNotifier<UpdateInfo?> availableUpdate = ValueNotifier(null);
  final Future<Directory> Function() _temporaryDirectory;
  final Future<Directory> Function() _documentsDirectory;
  Future<void>? _apkCleanup;

  /// Remove only our obsolete installer, never a newer APK awaiting installation.
  Future<void> cleanupInstalledApk() => _apkCleanup ??= _cleanupInstalledApk();

  Future<void> _cleanupInstalledApk() async {
    if (!AppPlatform.supportsApkUpdates) return;
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 1));
      final cachedTag = prefs.getString(_cachedTagKey);
      if (cachedTag != null) {
        final installed = await PackageInfo.fromPlatform()
            .timeout(const Duration(seconds: 1));
        final comparison = compareNumericVersions(cachedTag, installed.version);
        if (comparison == null || comparison > 0) return;
      }
      final directory =
          await _temporaryDirectory().timeout(const Duration(seconds: 1));
      final path = '${directory.path}/proxly_update.apk';
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.file) {
        File(path).deleteSync();
      } else if (type != FileSystemEntityType.notFound) {
        return;
      }
      await prefs.remove(_cachedTagKey);
    } catch (_) {
      // Cleanup must never prevent startup or remove a retryable update marker.
    }
  }

  /// Silent checks suppress failures and respect automatic-check settings,
  /// 24-hour throttling and skipped versions. Manual checks only honor skips.
  Future<UpdateInfo?> checkForUpdate({required bool silent}) async {
    if (!AppPlatform.supportsUpdateChecks) return null;
    final prefs = await SharedPreferences.getInstance();

    if (silent) {
      if (!(prefs.getBool(_autoCheckKey) ?? true)) return null;
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
      final githubTag = (json['tag_name'] as String? ?? '').trim();
      final info = await PackageInfo.fromPlatform();
      final localTag = 'v${info.version}';

      // Throttle successful checks even when no newer release is available.
      await prefs.setInt(_prefKey, DateTime.now().millisecondsSinceEpoch);

      if (githubTag.isEmpty) return null;
      final hasPlaceholderTag = _placeholderTag.hasMatch(githubTag);
      final tag =
          hasPlaceholderTag ? _tagFromReleaseTitle(json['name']) : githubTag;
      if (tag == null) throw FormatException(tr('版本格式异常'));
      final comparison = compareNumericVersions(tag, localTag);
      if (comparison == null) {
        throw FormatException(tr('版本格式异常'));
      }
      if (comparison <= 0) return null;

      if (prefs.getString(_skipKey) == tag) return null;

      final assets =
          (json['assets'] as List? ?? []).cast<Map<String, dynamic>>();
      final isIOS = AppPlatform.isIOS;
      final extension = isIOS ? '.ipa' : '.apk';
      final platform = isIOS ? 'iOS' : 'Android';
      // A placeholder tag is usable only when the package confirms the title.
      final expectedName =
          'Proxly-$platform-${displayAppVersion(tag)}$extension';
      final asset = assets.firstWhere((asset) {
        final name = asset['name'] as String? ?? '';
        final matchesName =
            hasPlaceholderTag ? name == expectedName : name.endsWith(extension);
        return matchesName &&
            (asset['browser_download_url'] as String? ?? '').trim().isNotEmpty;
      }, orElse: () => {});
      if (asset.isEmpty) return null;
      final downloadUrl = (asset['browser_download_url'] as String).trim();

      final update = UpdateInfo(
        tag: tag,
        apkUrl: isIOS ? '' : downloadUrl,
        ipaUrl: isIOS ? downloadUrl : '',
        sha256: _parseSha256Digest(asset['digest'] as String?),
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

  String? _tagFromReleaseTitle(Object? value) {
    if (value is! String) return null;
    final version = _releaseTitle.firstMatch(value.trim())?.group(1);
    if (version == null) return null;
    return version.split('.').length == 2 ? 'v$version.0' : 'v$version';
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

  /// Skip this version in subsequent automatic and manual checks.
  Future<void> skipVersion(String tag) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skipKey, tag);
  }

  Future<bool> _isLikelyPackage(File file, _UpdatePackage package) async {
    if (!await file.exists()) return false;
    final length = await file.length();
    final minimum = package == _UpdatePackage.apk ? 1024 * 1024 + 1 : 4;
    if (length < minimum || length > _maxPackageBytes) {
      return false;
    }
    final raf = await file.open();
    try {
      final header = await raf.read(4);
      return header.length == 4 &&
          header[0] == 0x50 &&
          header[1] == 0x4B &&
          ((header[2] == 0x03 && header[3] == 0x04) ||
              (package == _UpdatePackage.apk &&
                  ((header[2] == 0x05 && header[3] == 0x06) ||
                      (header[2] == 0x07 && header[3] == 0x08))));
    } finally {
      await raf.close();
    }
  }

  // Return a cached APK only when it still looks like an APK.
  Future<File?> _getCachedApk(String tag, String? expectedSha256) async {
    final prefs = await SharedPreferences.getInstance();
    final tempDir = await _temporaryDirectory();
    final file = File('${tempDir.path}/proxly_update.apk');
    if (prefs.getString(_cachedTagKey) != tag) {
      if (await file.exists()) await file.delete();
      return null;
    }
    if (await _isLikelyPackage(file, _UpdatePackage.apk) &&
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

  /// Stream an APK, reusing a valid cache. [onProgress] reports 0.0 to 1.0,
  /// or -1 for unknown size. [cancelled] aborts with cleanup and an exception.
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
    // Finish startup cleanup before writing into the same installer cache path.
    await cleanupInstalledApk();
    if (cancelled.value) throw const _CancelException();
    final cached = await _getCachedApk(tag, expectedSha256);
    if (cancelled.value) throw const _CancelException();
    if (cached != null) {
      onProgress(1.0);
      return cached;
    }

    final tempDir = await _temporaryDirectory();
    final file = File('${tempDir.path}/proxly_update.apk');
    await _downloadPackage(
      url,
      file,
      _UpdatePackage.apk,
      expectedSha256,
      onProgress,
      cancelled,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedTagKey, tag);
    return file;
  }

  /// Save a checked IPA to the app's Downloads folder in iOS Files.
  Future<File> downloadIpa(
    String url,
    String tag,
    String? expectedSha256,
    void Function(double) onProgress,
    ValueNotifier<bool> cancelled,
  ) async {
    if (!AppPlatform.isIOS) {
      throw UnsupportedError('IPA updates are only available on iOS');
    }
    if (cancelled.value) throw const _CancelException();
    if (NumericVersion.tryParse(tag) == null) {
      throw FormatException(tr('版本格式异常'));
    }

    final documents = await _documentsDirectory();
    final downloads = Directory('${documents.path}/$_iosDownloadsFolder');
    final fileName = 'Proxly-iOS-${displayAppVersion(tag)}.ipa';
    final file = File('${downloads.path}/$fileName');
    if (expectedSha256 != null &&
        await _isLikelyPackage(file, _UpdatePackage.ipa) &&
        await _matchesExpectedSha256(file, expectedSha256)) {
      if (cancelled.value) throw const _CancelException();
      onProgress(1);
      return file;
    }

    // Keep partial files outside the Documents directory exposed in Files.
    final tempDir = await _temporaryDirectory();
    final staging = await tempDir.createTemp('proxly-ipa-');
    final stagedFile = File('${staging.path}/$fileName');
    try {
      await _downloadPackage(
        url,
        stagedFile,
        _UpdatePackage.ipa,
        expectedSha256,
        onProgress,
        cancelled,
      );
      if (cancelled.value) throw const _CancelException();
      await downloads.create(recursive: true);
      if (cancelled.value) throw const _CancelException();
      return await stagedFile.rename(file.path);
    } finally {
      if (await stagedFile.exists()) await stagedFile.delete();
      await staging.delete();
    }
  }

  Future<void> _downloadPackage(
    String url,
    File file,
    _UpdatePackage package,
    String? expectedSha256,
    void Function(double) onProgress,
    ValueNotifier<bool> cancelled,
  ) async {
    Object? lastError;
    for (final candidateUrl in GitHubDownloadAccelerator.candidates(
      url,
      includeMirrors: expectedSha256 != null,
    )) {
      if (cancelled.value) throw const _CancelException();
      try {
        await _downloadFromUrl(
          candidateUrl,
          file,
          package,
          expectedSha256,
          onProgress,
          cancelled,
        );
        return;
      } catch (e) {
        if (e is _CancelException) rethrow;
        lastError = e;
        onProgress(0);
      }
    }

    throw Exception(tr('下载失败: $lastError'));
  }

  Future<void> _downloadFromUrl(
    String url,
    File file,
    _UpdatePackage package,
    String? expectedSha256,
    void Function(double) onProgress,
    ValueNotifier<bool> cancelled,
  ) async {
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    // Abort stalled headers or bodies without waiting for another data chunk.
    void cancelDownload() {
      if (cancelled.value) httpClient.close(force: true);
    }

    cancelled.addListener(cancelDownload);
    try {
      if (cancelled.value) throw const _CancelException();
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
          mime !=
              (package == _UpdatePackage.apk
                  ? 'application/vnd.android.package-archive'
                  : 'application/x-itunes-ipa') &&
          mime != 'application/octet-stream' &&
          mime != 'binary/octet-stream' &&
          mime != 'application/zip' &&
          mime != 'application/x-zip-compressed') {
        throw Exception(tr('下载内容类型异常: $mime'));
      }
      final contentLength =
          response.contentLength > 0 ? response.contentLength : null;
      final sizeGuard = UpdateDownloadSizeGuard(maxBytes: _maxPackageBytes)
        ..validateContentLength(contentLength);
      final output = await file.open(mode: FileMode.write);
      try {
        await for (final chunk
            in response.timeout(const Duration(seconds: 30))) {
          if (cancelled.value) throw const _CancelException();
          sizeGuard.addChunk(chunk.length);
          // Await disk writes so a fast network cannot queue the entire package.
          await output.writeFrom(chunk);
          if (cancelled.value) throw const _CancelException();
          if (contentLength != null && contentLength > 0) {
            onProgress(sizeGuard.receivedBytes / contentLength);
          } else {
            onProgress(-1);
          }
        }
      } finally {
        await output.close();
      }

      if (!await _isLikelyPackage(file, package)) {
        throw Exception(tr(
            package == _UpdatePackage.apk ? '下载内容不是有效 APK' : '下载内容不是有效 IPA'));
      }
      if (!await _matchesExpectedSha256(file, expectedSha256)) {
        throw Exception(tr('下载内容 SHA256 校验失败'));
      }
      if (cancelled.value) throw const _CancelException();
    } catch (_) {
      if (await file.exists()) await file.delete();
      if (cancelled.value) throw const _CancelException();
      rethrow;
    } finally {
      cancelled.removeListener(cancelDownload);
      httpClient.close(force: true);
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
