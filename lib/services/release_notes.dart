final _detailsTag = RegExp(r'<(/?)details\b[^>]*>', caseSensitive: false);
final _englishSummary = RegExp(
  r'^\s*<summary\b[^>]*>\s*(?:English|英文)\s*</summary\s*>',
  caseSensitive: false,
);

/// Selects the translation from Proxly's bilingual GitHub release format.
/// Releases without a complete translation retain their original notes.
String localizedReleaseNotes(String? body, {required String languageCode}) {
  final source = body?.trim() ?? '';
  if (source.isEmpty) return source;

  var depth = 0;
  RegExpMatch? opening;
  for (final tag in _detailsTag.allMatches(source)) {
    if (tag.group(1)!.isEmpty) {
      if (depth == 0) opening = tag;
      depth++;
      continue;
    }
    if (depth == 0) continue;
    depth--;
    if (depth != 0 || opening == null) continue;

    final content = source.substring(opening.end, tag.start);
    final summary = _englishSummary.firstMatch(content);
    if (summary == null) continue;

    final english = content.substring(summary.end).trim();
    final primary =
        '${source.substring(0, opening.start)}${source.substring(tag.end)}'
            .trim();
    // Choose at display time so cached update metadata survives language changes.
    if (languageCode == 'en' && english.isNotEmpty) return english;
    if (primary.isNotEmpty) return primary;
    return english;
  }
  return source;
}
