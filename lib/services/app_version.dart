/// Display the release number without the internal build counter or final .0.
String displayAppVersion(String raw) {
  final version =
      raw.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
  final parts = version.split('.');
  if (parts.length == 3 && parts.last == '0') return parts.take(2).join('.');
  return version;
}

bool isTestAppVersion(String raw) {
  final parts = raw.split('+').first.split('.');
  return parts.length == 3 && (int.tryParse(parts.last) ?? 0) > 0;
}
