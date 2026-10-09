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
    Future<ClashActiveConfig> Function()? loadActiveConfig,
    Future<List<ClashConfigFile>> Function()? listFiles,
  }) async {
    SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
    await AppLocaleController.instance.load();
    await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                        body: TextButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => ClashConfigEditorPage(
                                  file: fileA,
                                  loadActiveConfig:
                                      loadActiveConfig ??
                                          () async => const ClashActiveConfig(
                                              file: fileA),
                                  readFile: read,
                                  writeFile: write,
                                  fileActions: actions,
                                  listFiles: listFiles ??
                                      () async => [fileA, fileB]))),
                      child: const Text('Open editor'),
                    ))))));
    await tester.tap(find.text('Open editor'));
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

  for (final operation in [
    'save-other',
    'upload-other',
    'save-active',
    'upload-active',
    'save-active-switch-away',
    'active-changes',
    'same-name-other-directory',
    'lookup-fails'
  ]) {
    testWidgets(
        'restart reminder follows the modified running file: $operation',
        (tester) async {
      var active = fileA;
      final expectRestart = [
        'save-active',
        'upload-active',
        'save-active-switch-away',
        'active-changes'
      ].contains(operation);
      final actions = _FileActions(
          uploadTarget: operation == 'upload-active' ? fileA : fileB);
      await pumpEditor(tester,
          read: (_) async => 'mode: rule',
          write: (_, __) async {},
          actions: actions,
          loadActiveConfig: () async {
            if (operation == 'lookup-fails') throw Exception('offline');
            return ClashActiveConfig(file: active);
          });
      if (operation.startsWith('upload-')) {
        await tester
            .tap(find.byKey(const ValueKey('yaml_editor_file_actions')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('上传新配置'));
        await tester.pumpAndSettle();
      } else {
        if (operation == 'save-other' || operation == 'active-changes') {
          await chooseB(tester);
        }
        tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!.text =
            'mode: global';
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('yaml_editor_save')));
        await tester.pumpAndSettle();
        if (operation == 'save-active-switch-away') await chooseB(tester);
        if (operation == 'active-changes') active = fileB;
        if (operation == 'same-name-other-directory') {
          active = const ClashConfigFile(path: '/etc/clash/config/a.yaml');
        }
      }
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.text('立即重启'), expectRestart ? findsOneWidget : findsNothing);
      if (expectRestart) {
        await tester.tap(find.text('稍后'));
        await tester.pumpAndSettle();
      }
      expect(find.byType(ClashConfigEditorPage), findsNothing);
      if (operation == 'lookup-fails') {
        expect(find.textContaining('无法确认当前配置'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    },
        variant: TargetPlatformVariant(
            {TargetPlatform.android, TargetPlatform.iOS}));
  }

  testWidgets(
      'deletion confirms unsaved loss, preserves failures and reloads the picker',
      (tester) async {
    var fail = true;
    var deleteCount = 0;
    var listCount = 0;
    final files = [fileA, fileB];
    await pumpEditor(tester,
        read: (_) async => 'mode: rule',
        write: (_, __) async {},
        listFiles: () async {
          listCount++;
          return List.of(files);
        },
        loadActiveConfig: () async => const ClashActiveConfig(file: fileB),
        actions: YamlFileActions(deleteFile: (path) async {
          deleteCount++;
          if (fail) throw Exception('delete failed');
          files.removeWhere((file) => file.path == path);
        }));
    final controller =
        tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!;
    controller.text = 'mode: global';
    await tester.pump();
    Future<void> openDelete() async {
      await tester.tap(find.byKey(const ValueKey('yaml_editor_file_actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除配置'));
      await tester.pumpAndSettle();
      expect(find.text('删除配置文件？'), findsOneWidget);
      expect(find.textContaining('未保存的修改也会丢弃'), findsOneWidget);
    }

    await openDelete();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(deleteCount, 0);
    expect(controller.text, 'mode: global');
    await openDelete();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(deleteCount, 1);
    expect(find.textContaining('delete failed'), findsOneWidget);
    expect(controller.text, 'mode: global');
    expect(
        tester.widget<CodeEditor>(find.byType(CodeEditor)).readOnly, isFalse);
    fail = false;
    await openDelete();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(deleteCount, 2);
    expect(controller.text, isEmpty);
    expect(tester.widget<CodeEditor>(find.byType(CodeEditor)).readOnly, isTrue);
    expect(find.text('选择 YAML 或上传新配置开始编辑'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('yaml_editor_save')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('yaml_editor_file_picker')));
    await tester.pumpAndSettle();
    expect(listCount, 1);
    expect(find.text('a.yaml'), findsNothing);
    expect(find.text('b.yaml'), findsOneWidget);
    await tester.tap(find.text('b.yaml'));
    await tester.pumpAndSettle();
    expect(controller.text, 'mode: rule');
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('立即重启'), findsNothing);
    expect(find.byType(ClashConfigEditorPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  },
      variant:
          TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));
}

class _FileActions extends YamlFileActions {
  final ClashConfigFile uploadTarget;
  _FileActions(
      {this.uploadTarget =
          const ClashConfigFile(path: '/etc/openclash/config/uploaded.yaml')});
  int uploads = 0;
  String? exported;
  @override
  Future<ClashConfigFile?> upload(BuildContext context) async {
    uploads++;
    return uploadTarget;
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
