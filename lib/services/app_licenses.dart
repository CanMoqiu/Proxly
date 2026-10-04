import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Pub dependencies are registered by Flutter; these bundled assets are not.
class AppLicenses {
  static bool _registered = false;

  static void register() {
    if (_registered) return;
    _registered = true;
    LicenseRegistry.addLicense(() async* {
      for (final entry in const {
        'Zashboard': 'assets/web_panel/LICENSE',
        'Zashboard assets': 'assets/web_panel/THIRD_PARTY_NOTICES.md',
        'JetBrains Mono': 'assets/fonts/JetBrainsMono-OFL.txt',
        'Twemoji / Mozilla': 'assets/fonts/Twemoji-LICENSE.md',
      }.entries) {
        yield LicenseEntryWithLineBreaks(
          [entry.key],
          await rootBundle.loadString(entry.value),
        );
      }
    });
  }
}
