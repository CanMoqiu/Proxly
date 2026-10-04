class NumericVersion {
  const NumericVersion._(this.parts);

  final List<int> parts;

  static NumericVersion? tryParse(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    if (value.isEmpty || !RegExp(r'^\d+(?:\.\d+)*$').hasMatch(value)) {
      return null;
    }
    final parts = <int>[];
    for (final segment in value.split('.')) {
      final part = int.tryParse(segment);
      if (part == null) return null;
      parts.add(part);
    }
    return NumericVersion._(parts);
  }

  int compareTo(NumericVersion other) {
    final length =
        parts.length > other.parts.length ? parts.length : other.parts.length;
    for (var index = 0; index < length; index++) {
      final left = index < parts.length ? parts[index] : 0;
      final right = index < other.parts.length ? other.parts[index] : 0;
      final result = left.compareTo(right);
      if (result != 0) return result;
    }
    return 0;
  }
}

int? compareNumericVersions(String left, String right) {
  final leftVersion = NumericVersion.tryParse(left);
  final rightVersion = NumericVersion.tryParse(right);
  if (leftVersion == null || rightVersion == null) return null;
  return leftVersion.compareTo(rightVersion);
}
