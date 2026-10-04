import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/openclash_script_safety.dart';

void main() {
  test('redacts quoted JSON, YAML, UCI and whitespace-bearing credentials', () {
    for (final input in [
      '{"password":"audit secret value"}',
      "secret: 'audit secret value'",
      "dashboard_password='audit secret value'",
      'token=audit-secret',
      r'{"password":"audit\"secret value"}',
      '{"authorization":"Bearer audit-secret"}',
    ]) {
      final result = OpenClashScriptSafety.redactCredentials(input);
      expect(result, contains('[redacted]'));
      expect(result, isNot(contains('audit')));
      expect(result, isNot(contains('secret value')));
    }
  });

  test('transaction IDs cannot introduce shell syntax or escape /tmp', () {
    for (final id in ["a'", '../a', 'a\nb', r'$(id)', '']) {
      expect(() => OpenClashScriptSafety.transactionPath('quick', id),
          throwsArgumentError);
    }
    final ids =
        List.generate(100, (_) => OpenClashScriptSafety.transactionId());
    expect(ids.toSet(), hasLength(100));
    expect(ids.every((id) => RegExp(r'^[a-f0-9]{32}$').hasMatch(id)), isTrue);
  });

  test('Ruby keeps aliases but rejects objects even with OpenClash aliases',
      () async {
    final result = await Process.run('ruby', [
      '-ryaml',
      '-rtempfile',
      '-e',
      r'''
class AuditProbe
  def init_with(coder)
    raise "OBJECT_HOOK_EXECUTED"
  end
end
module YAML
  class << self
    alias_method :load, :unsafe_load
  end
end
''' +
          OpenClashScriptSafety.rubyYamlGuard +
          r'''
2.times do |compat|
  if compat == 1
    module YAML
      def self.load_file(path)
        File.open(path) { |file| load(file) }
      end
    end
  end
  Tempfile.create("proxly-test") do |file|
    file.write("base: &base {enable: true}\ncopy: *base\n")
    file.flush
    value = YAML.load_file(file.path)
    raise "aliases lost" unless value["copy"]["enable"] == true
    file.rewind
    file.truncate(0)
    file.write("value: !ruby/object:AuditProbe {}")
    file.flush
    begin
      YAML.load_file(file.path)
      raise "object accepted"
    rescue Psych::DisallowedClass
      puts "objects rejected, aliases retained"
    end
  end
end
''',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('objects rejected, aliases retained'));
  }, skip: Platform.isWindows ? 'Ruby regression runs in Linux CI' : false);

  test('transaction directory blocks other users and pre-existing symlinks',
      () async {
    final root = await Directory.systemTemp.createTemp('proxly-safety-test-');
    addTearDown(() => root.delete(recursive: true));
    final result = await Process.run('sh', [
      '-c',
      r'''
set -eu
tx="$1/new/state"
''' +
          OpenClashScriptSafety.createTransactionDirectory +
          r'''
printf 'test-only-secret' > "$tx.uci"
test "$(stat -c %a "${tx%/*}")" = 700
test "$(stat -c %a "$tx.uci")" = 600
ln -s "$1/new" "$1/linked"
tx="$1/linked/state"
''' +
          OpenClashScriptSafety.createTransactionDirectory,
      'sh',
      root.path,
    ]);
    expect(result.exitCode, 31, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('PROXLY_ERROR=backup_failed'));
  },
      skip: !Platform.isLinux
          ? 'POSIX permission regression runs in Linux CI'
          : false);
}
