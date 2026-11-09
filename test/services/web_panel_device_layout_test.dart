import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/web_panel_device_layout.dart';

const _jsc =
    '/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc';
const _environment = r'''
const window = globalThis;
let width = 768;
const other = {matches: true};
window.matchMedia = query => query === '(prefers-color-scheme: dark)'
  ? other : {matches: width <= 768};
const values = new Map();
const localStorage = {setItem: (k, v) => values.set(k, v)};
const classes = new Set();
const styles = [];
const document = {
  documentElement: {classList: {add: name => classes.add(name)}},
  head: {appendChild: style => styles.push(style)},
  createElement: () => ({}),
  getElementById: id => styles.find(style => style.id === id),
};
function check(value, message) { if (!value) throw new Error(message); }
''';
const _checks = r'''
for (const size of [600, 768, 1024, 1366, 400]) {
  width = size;
  check(!window.matchMedia('(max-width: 768px)').matches, 'tablet stays desktop');
}
check(window.matchMedia('(prefers-color-scheme: dark)') === other, 'theme query unchanged');
check(classes.has('__proxly_tablet'), 'tablet CSS marker');
check(styles.length === 1, 'script idempotent');
check(styles[0].textContent.includes('div:has(> .sidebar) { display: none'), 'sidebar and its width removed');
print('Tablet panel script checks passed');
''';

void main() {
  test(
      'tablet scripts preserve desktop signals without the overview sidebar across widths',
      () {
    final script = WebPanelDeviceLayout.tablet();
    final result = Process.runSync(
        _jsc, ['-e', '$_environment\n$script\n$script\n$_checks']);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }, skip: !File(_jsc).existsSync());

  test('standalone console retains its web navigation and saved view choice',
      () {
    final script = WebPanelDeviceLayout.tablet(embedded: false);
    expect(script, isNot(contains('display: none')));
    expect(script, isNot(contains('connection-display-style')));
  });
}
