import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/clash_config_editor_page.dart';
import 'package:proxly/services/clash_config_file_service.dart';
import 'package:proxly/widgets/yaml_file_actions.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

const fileA = ClashConfigFile(path: '/etc/openclash/config/a.yaml');
const fileB = ClashConfigFile(path: '/etc/openclash/config/b.yaml');

void main() {
  Future<void> pumpEditor(
    WidgetTester tester, {
    required Future<String> Function(String) read,
    required Future<void> Function(String, String) write,
    YamlFileActions? actions,
  }) async {
    SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
    await AppLocaleController.instance.load();
    await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
            home: ClashConfigEditorPage(
                file: fileA,
                readFile: read,
                writeFile: write,
                fileActions: actions,
                listFiles: () async => [fileA, fileB]))));
    await tester.pumpAndSettle();
  }

  Future<void> chooseB(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('yaml_editor_file_picker')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.text('b.yaml'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'switching files cancels safely or saves the original path before loading the next file',
      (tester) async {
    final writes = <String, String>{};
    await pumpEditor(tester,
        read: (path) async =>
            path == fileA.path ? 'mode: rule' : 'mode: direct',
        write: (path, text) async {
          writes[path] = text;
        });
    final controller =
        tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!;
    controller.text = 'mode: global';
    await tester.pump();
    await chooseB(tester);
    expect(find.text('保存修改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.text, 'mode: global');
    expect(writes, isEmpty);
    expect(find.text('a.yaml'), findsOneWidget);
    await chooseB(tester);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(writes, {fileA.path: 'mode: global'});
    expect(find.text('b.yaml'), findsOneWidget);
    expect(controller.text, 'mode: direct');
    controller.text = 'mode: rule';
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('yaml_editor_save')));
    await tester.pumpAndSettle();
    expect(writes[fileB.path], 'mode: rule');
    await tester.pumpWidget(const SizedBox());
  },
      variant:
          TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));

  testWidgets('failed saves keep the current file and unsaved text',
      (tester) async {
    await pumpEditor(tester,
        read: (_) async => 'mode: rule',
        write: (_, __) async => throw Exception('write failed'));
    final controller =
        tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!;
    controller.text = 'mode: global';
    await tester.pump();
    await chooseB(tester);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('a.yaml'), findsOneWidget);
    expect(controller.text, 'mode: global');
    expect(find.textContaining('write failed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'failed reads after switching cannot save the previous document into the new file',
      (tester) async {
    var writes = 0;
    await pumpEditor(tester, read: (path) async {
      if (path == fileB.path) throw Exception('read failed');
      return 'mode: rule';
    }, write: (_, __) async {
      writes++;
    });
    await chooseB(tester);
    expect(find.text('b.yaml'), findsOneWidget);
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    expect(editor.readOnly, isTrue);
    expect(editor.controller!.text, isEmpty);
    await tester.tap(find.byKey(const ValueKey('yaml_editor_save')));
    await tester.pump();
    expect(writes, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'rename retains unsaved content, export uses the buffer, and upload opens the new file',
      (tester) async {
    final actions = _FileActions();
    final writes = <String, String>{};
    await pumpEditor(tester,
        actions: actions,
        read: (_) async => 'mode: rule',
        write: (path, text) async {
          writes[path] = text;
        });
    final controller =
        tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!;
    controller.text = 'mode: global';
    await tester.pump();
    Future<void> action(String label) async {
      await tester.tap(find.byKey(const ValueKey('yaml_editor_file_actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await action('重命名');
    expect(find.text('renamed.yaml'), findsOneWidget);
    expect(controller.text, 'mode: global');
    await action('导出当前内容');
    expect(actions.exported, 'mode: global');
    expect(writes, isEmpty);
    await tester.tap(find.byKey(const ValueKey('yaml_editor_save')));
    await tester.pumpAndSettle();
    expect(writes, {'/etc/openclash/config/renamed.yaml': 'mode: global'});
    await action('上传新配置');
    expect(find.text('uploaded.yaml'), findsOneWidget);
    expect(controller.text, 'mode: rule');
    expect(actions.uploads, 1);
    await tester.pumpWidget(const SizedBox());
  });
}

class _FileActions extends YamlFileActions {
  int uploads = 0;
  String? exported;
  @override
  Future<ClashConfigFile?> upload(BuildContext context) async {
    uploads++;
    return const ClashConfigFile(path: '/etc/openclash/config/uploaded.yaml');
  }

  @override
  Future<ClashConfigFile?> rename(
          BuildContext context, ClashConfigFile file) async =>
      const ClashConfigFile(path: '/etc/openclash/config/renamed.yaml');
  @override
  Future<bool> export(
      BuildContext context, ClashConfigFile file, String content) async {
    exported = content;
    return true;
  }
}
