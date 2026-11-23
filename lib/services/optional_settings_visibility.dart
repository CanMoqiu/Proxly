import 'package:shared_preferences/shared_preferences.dart';

abstract final class OptionalSettingsVisibility {
  static const preferenceKey = 'optional_settings_visible';

  static bool read(SharedPreferences prefs) =>
      prefs.getBool(preferenceKey) ?? false;

  static Future<bool> toggle() async {
    final prefs = await SharedPreferences.getInstance();
    final visible = !read(prefs);
    try {
      if (!await prefs.setBool(preferenceKey, visible)) {
        throw StateError('Could not save optional settings visibility');
      }
    } catch (_) {
      await prefs.reload();
      rethrow;
    }
    return visible;
  }
}
