import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_navigator.dart';
import '../l10n/app_locale.dart';
import 'app_secure_storage.dart';

class SshHostTrustService {
  SshHostTrustService._();

  static final instance = SshHostTrustService._();
  static const _storageKey = 'ssh_host_fingerprints';

  final Map<String, Future<bool>> _pendingPrompts = {};

  Future<bool> verify(
    String host,
    int port,
    String algorithm,
    Uint8List fingerprintBytes,
  ) async {
    final fingerprint = _standardSha256Fingerprint(fingerprintBytes);
    final normalizedHost = host.trim().toLowerCase().replaceAll(
          RegExp(r'^\[|\]$'),
          '',
        );
    final endpoint = normalizedHost.contains(':')
        ? '[$normalizedHost]:$port'
        : '$normalizedHost:$port';
    final trusted = await _readTrusted();
    final previous = trusted[endpoint];
    if (previous != null &&
        previous['algorithm'] == algorithm &&
        previous['fingerprint'] == fingerprint) {
      return true;
    }

    final promptKey = '$endpoint|$algorithm|$fingerprint';
    final existing = _pendingPrompts[promptKey];
    if (existing != null) return existing;

    final prompt = _promptAndStore(
      endpoint: endpoint,
      algorithm: algorithm,
      fingerprint: fingerprint,
      previous: previous,
    );
    _pendingPrompts[promptKey] = prompt;
    try {
      return await prompt;
    } finally {
      _pendingPrompts.remove(promptKey);
    }
  }

  Future<int> trustedHostCount() async => (await _readTrusted()).length;

  Future<void> clearAll() async {
    await AppSecureStorage.delete(_storageKey);
  }

  Future<bool> _promptAndStore({
    required String endpoint,
    required String algorithm,
    required String fingerprint,
    required Map<String, dynamic>? previous,
  }) async {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return false;
    final changed = previous != null;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(changed ? 'SSH 身份指纹已变化' : '确认 SSH 设备身份')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(changed
                    ? '设备指纹与此前记录不一致。可能是路由器重装或更新，也可能存在冒充风险。请确认后再继续。'
                    : '首次连接此 SSH 设备。请确认该指纹属于你的路由器，确认前不会发送 SSH 密码。'),
              ),
              const SizedBox(height: 14),
              _TrustDetail(label: tr('设备'), value: endpoint),
              _TrustDetail(label: tr('算法'), value: algorithm),
              if (changed)
                _TrustDetail(
                  label: tr('旧指纹'),
                  value: previous['fingerprint']?.toString() ?? '',
                  warning: true,
                ),
              _TrustDetail(
                label: tr(changed ? '新指纹' : 'SHA-256 指纹'),
                value: fingerprint,
                warning: changed,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(tr(changed ? '信任新指纹并继续' : '信任并继续')),
          ),
        ],
      ),
    );
    if (accepted != true) return false;

    final trusted = await _readTrusted();
    trusted[endpoint] = {
      'algorithm': algorithm,
      'fingerprint': fingerprint,
    };
    await AppSecureStorage.write(_storageKey, jsonEncode(trusted));
    return true;
  }

  Future<Map<String, Map<String, dynamic>>> _readTrusted() async {
    final raw = await AppSecureStorage.read(_storageKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((key, value) {
        final entry = value is Map
            ? Map<String, dynamic>.from(value)
            : <String, dynamic>{};
        return MapEntry(key.toString(), entry);
      });
    } catch (_) {
      return {};
    }
  }

  static String _standardSha256Fingerprint(Uint8List bytes) {
    final decoded = utf8.decode(bytes, allowMalformed: true).trim();
    if (RegExp(r'^SHA256:[A-Za-z0-9+/_=-]+$').hasMatch(decoded)) {
      return decoded;
    }
    if (RegExp(r'^[A-Za-z0-9+/_-]{40,}={0,2}$').hasMatch(decoded)) {
      return 'SHA256:$decoded';
    }
    return 'SHA256:${base64Encode(bytes).replaceAll('=', '')}';
  }
}

class _TrustDetail extends StatelessWidget {
  const _TrustDetail({
    required this.label,
    required this.value,
    this.warning = false,
  });

  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: warning ? colors.error : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            value,
            style: TextStyle(
              fontSize: 12,
              color: warning ? colors.error : colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
