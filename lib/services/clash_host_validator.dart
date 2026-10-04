import '../l10n/app_locale.dart';

class ClashHostValidator {
  ClashHostValidator._();

  static String? validationError(String raw) {
    final host = hostOnly(raw);
    if (host.isEmpty) return tr('请填写 Clash 控制器地址');
    if (!_isLocalOrPrivateHost(host)) {
      return tr('Clash 地址仅支持本机、局域网或本地域名');
    }
    return null;
  }

  static String normalizeAddress(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      final uri = Uri.tryParse(value);
      final host = uri?.host ?? '';
      if (host.isEmpty) return value;
      if (uri?.hasPort == true) return _formatHostPort(host, uri!.port);
      return host;
    }
    return value.split('/').first;
  }

  static ClashControllerEndpoint? parseEndpoint(
    String raw, {
    int defaultPort = 9090,
  }) {
    final value = normalizeAddress(raw);
    if (value.isEmpty) return null;

    var hostname = value;
    var port = defaultPort;

    if (value.startsWith('[')) {
      final end = value.indexOf(']');
      if (end <= 0) return null;
      hostname = value.substring(1, end);
      final rest = value.substring(end + 1);
      if (rest.startsWith(':')) {
        port = int.tryParse(rest.substring(1)) ?? defaultPort;
      }
    } else {
      final firstColon = value.indexOf(':');
      final lastColon = value.lastIndexOf(':');
      if (firstColon > 0 && firstColon == lastColon) {
        hostname = value.substring(0, firstColon);
        port = int.tryParse(value.substring(firstColon + 1)) ?? defaultPort;
      }
    }

    hostname = hostname.trim();
    if (hostname.isEmpty) return null;
    return ClashControllerEndpoint(hostname: hostname, port: port);
  }

  static String hostOnly(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      final uri = Uri.tryParse(value);
      value = uri?.host ?? value;
    } else {
      value = value.split('/').first;
    }
    if (value.startsWith('[')) {
      final end = value.indexOf(']');
      if (end > 0) return value.substring(1, end).toLowerCase();
    }
    final portIndex = value.lastIndexOf(':');
    if (portIndex > 0 && value.indexOf(':') == portIndex) {
      value = value.substring(0, portIndex);
    }
    return value.toLowerCase();
  }

  static String _formatHostPort(String host, int port) {
    if (host.contains(':') && !host.startsWith('[')) {
      return '[$host]:$port';
    }
    return '$host:$port';
  }

  static bool _isLocalOrPrivateHost(String host) {
    if (host == 'localhost' ||
        host.endsWith('.local') ||
        host.endsWith('.lan') ||
        !host.contains('.')) {
      return true;
    }
    if (host == '::1' ||
        host.startsWith('fe80:') ||
        host.startsWith('fc') ||
        host.startsWith('fd')) {
      return true;
    }

    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((part) => part == null || part < 0 || part > 255)) {
      return false;
    }
    final first = octets[0]!;
    final second = octets[1]!;
    return first == 10 ||
        first == 127 ||
        first == 192 && second == 168 ||
        first == 169 && second == 254 ||
        first == 172 && second >= 16 && second <= 31;
  }
}

class ClashControllerEndpoint {
  final String hostname;
  final int port;

  const ClashControllerEndpoint({
    required this.hostname,
    required this.port,
  });

  String get portText => port.toString();
}
