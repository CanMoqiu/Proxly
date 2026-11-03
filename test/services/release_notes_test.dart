import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/release_notes.dart';

void main() {
  const chinese = '## 更新内容\n\n- 优化性能。';
  const english = '## Updates\n\n- Improve performance.';
  const bilingual =
      '$chinese\n\n<details>\n<summary>English</summary>\n\n$english\n\n</details>';

  test('selects Chinese or English without the translation wrapper', () {
    expect(localizedReleaseNotes(bilingual, languageCode: 'zh'), chinese);
    expect(localizedReleaseNotes(bilingual, languageCode: 'en'), english);
  });

  test('preserves single-language releases for either app language', () {
    for (final code in ['zh', 'en']) {
      expect(localizedReleaseNotes(chinese, languageCode: code), chinese);
      expect(localizedReleaseNotes(english, languageCode: code), english);
      expect(localizedReleaseNotes(null, languageCode: code), '');
      expect(localizedReleaseNotes(' \n ', languageCode: code), '');
    }
  });

  test('accepts HTML attributes, casing and CRLF', () {
    const notes = '$chinese\r\n<DETAILS open>\r\n'
        '<SUMMARY lang="en"> English </SUMMARY>\r\n$english\r\n</DETAILS>';
    expect(localizedReleaseNotes(notes, languageCode: 'en'), english);
    expect(localizedReleaseNotes(notes, languageCode: 'zh'), chinese);
  });

  test('falls back when the selected translation is missing or empty', () {
    const empty = '$chinese\n<details><summary>English</summary></details>';
    expect(localizedReleaseNotes(empty, languageCode: 'en'), chinese);
    const onlyEnglish = '<details><summary>English</summary>$english</details>';
    expect(localizedReleaseNotes(onlyEnglish, languageCode: 'zh'), english);
    const incomplete = '$chinese\n<details><summary>English</summary>$english';
    expect(localizedReleaseNotes(incomplete, languageCode: 'en'), incomplete);
  });

  test('retains nested content and unrelated details blocks', () {
    const extra = '<details><summary>Changes</summary>More notes</details>';
    const nested = '$english\n$extra';
    const notes = '$chinese\n$extra\n'
        '<details><summary>English</summary>$nested</details>';
    expect(localizedReleaseNotes(notes, languageCode: 'en'), nested);
    expect(
        localizedReleaseNotes(notes, languageCode: 'zh'), '$chinese\n$extra');
  });

  test('keeps Markdown, version information and checksums intact', () {
    const englishNotes = '$english\n\n## Important notes\n\n- ARM64 only.\n\n'
        '## Version information\n\n- Version: 26.9\n- SHA-256: `abc123`';
    const notes = '$chinese\n<details><summary>English</summary>'
        '$englishNotes</details>';
    expect(localizedReleaseNotes(notes, languageCode: 'en'), englishNotes);
  });
}
