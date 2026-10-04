import 'dart:math';

/// Shared by remote read and write scripts. OpenClash's YAML compatibility
/// module may alias YAML.load to unsafe_load, so install the guard AFTER it.
class OpenClashScriptSafety {
  OpenClashScriptSafety._();

  static String transactionId() => List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();

  static String transactionPath(String kind, String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id) ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(kind)) {
      throw ArgumentError('Invalid transaction ID');
    }
    return '/tmp/proxly_${kind}_$id/state';
  }

  // mkdir without -p fails closed on an existing directory or symbolic link.
  // Every file containing UCI/YAML data lives inside this root-only directory.
  static const createTransactionDirectory = r'''
umask 077
mkdir -m 700 "${tx%/*}" || {
  echo 'PROXLY_ERROR=backup_failed' >&2
  echo 'PROXLY_ROLLBACK=not_started' >&2
  exit 31
}
''';

  static const rubyYamlGuard = r'''
require "date"
module YAML
  def self.load(yaml, *args, **kwargs)
    safe_load(yaml, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
  end
end
''';

  static String redactCredentials(String raw) => raw.replaceAllMapped(
        RegExp(
          r'''["']?\b([\w.-]*(?:token|password|passwd|secret|authorization)[\w.-]*)["']?\s*[:=]\s*(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s,}]+)''',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}=[redacted]',
      );
}
