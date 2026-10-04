class TrafficFormatter {
  TrafficFormatter._();

  static const int _base = 1024;
  static const List<String> _units = ['B', 'KB', 'MB', 'GB', 'TB'];

  static String formatBytes(num bytes) {
    if (!bytes.isFinite || bytes <= 0) {
      return '0B';
    }

    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= _base && unitIndex < _units.length - 1) {
      value /= _base;
      unitIndex++;
    }

    if (unitIndex == 0) {
      return '${value.toStringAsFixed(0)}${_units[unitIndex]}';
    }

    final decimals = unitIndex >= 3 ? 2 : 1;
    return '${value.toStringAsFixed(decimals)}${_units[unitIndex]}';
  }

  static String formatSpeed(num bytesPerSecond) {
    return '${formatBytes(bytesPerSecond)}/s';
  }
}
