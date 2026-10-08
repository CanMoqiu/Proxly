import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/clash_config_editor_page.dart';
import 'package:proxly/widgets/yaml_file_dialogs.dart';
import 'package:proxly/services/clash_config_file_service.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Widget localized(Widget child) => AppLocaleScope(
        controller: AppLocaleController.instance,
        child: child,
      );

  test('upload file names always resolve inside the fixed config directory',
      () {
    expect(
      ClashConfigFileService.uploadPathForFileName('custom.yaml'),
      '/etc/openclash/config/custom.yaml',
    );
    expect(
      ClashConfigFileService.uploadPathForFileName(' custom.yml '),
      '/etc/openclash/config/custom.yml',
    );

    for (final invalid in [
      '',
      '.',
      '..',
      '../escape.yaml',
      r'folder\escape.yaml',
      'bad\u0000.yaml',
      'config.txt',
    ]) {
      expect(
        () => ClashConfigFileService.uploadPathForFileName(invalid),
        throwsArgumentError,
        reason: invalid,
      );
    }
  });

  test('rename paths stay in place and active files match conservatively', () {
    expect(
      ClashConfigFileService.renamePathForFileName(
        '/etc/openclash/config/old.yaml',
        'new.yml',
      ),
      '/etc/openclash/config/new.yml',
    );
    expect(
      () => ClashConfigFileService.renamePathForFileName(
        '/etc/openclash/config/old.yaml',
        '../new.yaml',
      ),
      throwsArgumentError,
    );

    const exact = ClashConfigFile(path: '/etc/openclash/config/exact.yaml');
    const alias = ClashConfigFile(path: '/etc/openclash/config/alias.yaml');
    final files = [exact, alias];
    expect(
      ClashConfigFileService.matchActiveConfigPath(
        files,
        const ClashActiveConfig(file: exact, subscriptionMode: false),
      ),
      exact.path,
    );
    expect(
      ClashConfigFileService.matchActiveConfigPath(
        files,
        const ClashActiveConfig(
          file: ClashConfigFile(path: '/openclash/config/alias.yaml'),
          subscriptionMode: false,
        ),
      ),
      alias.path,
    );
    expect(
      ClashConfigFileService.matchActiveConfigPath(
        [
          ...files,
          const ClashConfigFile(path: '/etc/clash/config/alias.yaml'),
        ],
        const ClashActiveConfig(
          file: ClashConfigFile(path: '/openclash/config/alias.yaml'),
          subscriptionMode: false,
        ),
      ),
      isNull,
    );
    expect(
      ClashConfigFileService.matchActiveConfigPath(
        files,
        const ClashActiveConfig(file: exact, subscriptionMode: true),
      ),
      isNull,
    );
  });

  test('active config parser matches only the subscription that owns the yaml',
      () {
    final active = ClashConfigFileService.parseActiveConfigOutput('''
openclash.config.config_path='/etc/openclash/config/home.yaml'
openclash.@config_subscribe[0]=config_subscribe
openclash.@config_subscribe[0].enabled='1'
openclash.@config_subscribe[0].address='https://example.com/sub'
openclash.@config_subscribe[0].name='home'
openclash.@config_subscribe[1]=config_subscribe
openclash.@config_subscribe[1].enabled='1'
openclash.@config_subscribe[1].address='https://example.com/other'
openclash.@config_subscribe[1].name='other'
''');

    expect(active.source, ClashActiveConfigSource.subscription);
    expect(active.file, isNull);
    expect(active.subscription?.name, 'home');
    expect(
        active.subscription?.generatedPath, '/etc/openclash/config/home.yaml');
  });

  test('subscription names that already include YAML suffix are not doubled',
      () {
    final active = ClashConfigFileService.parseActiveConfigOutput('''
openclash.config.config_path='/openclash/config/home.yml'
openclash.@config_subscribe[0]=config_subscribe
openclash.@config_subscribe[0].enabled='1'
openclash.@config_subscribe[0].address='https://example.com/sub'
openclash.@config_subscribe[0].name='home.yml'
''');

    expect(active.source, ClashActiveConfigSource.subscription);
    expect(
        active.subscription?.generatedPath, '/etc/openclash/config/home.yml');
  });

  test('stale, disabled and unrelated subscription urls keep local yaml active',
      () {
    final active = ClashConfigFileService.parseActiveConfigOutput('''
openclash.config.config_path='/etc/openclash/config/local.yaml'
openclash.config.config_url='https://example.com/legacy'
openclash.@config_subscribe[0]=config_subscribe
openclash.@config_subscribe[0].enabled='0'
openclash.@config_subscribe[0].address='https://example.com/local'
openclash.@config_subscribe[0].name='local'
openclash.@config_subscribe[1]=config_subscribe
openclash.@config_subscribe[1].enabled='1'
openclash.@config_subscribe[1].address='https://example.com/other'
openclash.@config_subscribe[1].name='other'
''');

    expect(active.source, ClashActiveConfigSource.localYaml);
    expect(active.file?.path, '/etc/openclash/config/local.yaml');
  });

  test('legacy top-level subscription url remains supported', () {
    final active = ClashConfigFileService.parseActiveConfigOutput(
      "openclash.config.config_url='https://example.com/legacy'",
    );

    expect(active.source, ClashActiveConfigSource.subscription);
    expect(active.file, isNull);
  });

  test('line-number gutter grows only when the digit count grows', () {
    final widths = <int, double>{
      for (final lines in [9, 10, 99, 100, 999, 1000])
        lines: YamlEditorLayoutMetrics.forLineCount(lines).gutterWidth,
    };

    expect(widths[10], greaterThan(widths[9]!));
    expect(widths[99], closeTo(widths[10]!, 0.001));
    expect(widths[100], greaterThan(widths[99]!));
    expect(widths[999], closeTo(widths[100]!, 0.001));
    expect(widths[1000], greaterThan(widths[999]!));

    for (final lines in widths.keys) {
      final metrics = YamlEditorLayoutMetrics.forLineCount(lines);
      expect(
        metrics.codeLeftPadding - metrics.gutterWidth,
        YamlEditorLayoutMetrics.codeGap,
      );
    }
  });

  test('indent guide model normalizes spaces, tabs, blanks and depth limits',
      () {
    final yaml = [
      '',
      'root:',
      '  child:',
      '',
      '    grandchild: true',
      '   odd-space: true',
      '\ttabbed: true',
      '${List.filled(130, ' ').join()}deep: true',
      '',
    ].join('\n');
    final model = YamlIndentGuideModel.fromText(yaml);

    expect(model.depths, [0, 0, 1, 1, 2, 1, 1, 64, 0]);
    expect(model.depthForLine(-1), 0);
    expect(model.depthForLine(model.lines.length), 0);
    expect(model.blocksAtLevel(64).single.guideColumn, 128);
  });

  test('indent guide model creates continuous blocks across inner blank lines',
      () {
    final model = YamlIndentGuideModel.fromText('''root:
  child:
    first: true

    # second item
  sibling: true
tail: true''');

    final levelOne = model.blocksAtLevel(1);
    final levelTwo = model.blocksAtLevel(2);
    expect(levelOne, hasLength(1));
    expect(levelOne.single.startLine, 1);
    expect(levelOne.single.endLine, 6);
    expect(levelTwo, hasLength(1));
    expect(levelTwo.single.startLine, 2);
    expect(levelTwo.single.endLine, 5);

    expect(
      model.visibleBlocks(3, 4).map((block) => block.level),
      [1, 2],
    );
    expect(
      model.visibleBlocks(5, 6).map((block) => block.level),
      [1],
    );
  });

  test('indent guides sit on the leading edge of each indentation unit', () {
    expect(
      YamlIndentGuidePainter.guideX(
        guideColumn: 2,
        codeLeftPadding: 40,
        characterWidth: 8,
      ),
      40,
    );
    expect(
      YamlIndentGuidePainter.guideX(
        guideColumn: 4,
        codeLeftPadding: 40,
        characterWidth: 8,
        horizontalOffset: 5,
      ),
      51,
    );
  });

  test('cursor information uses the active Re-Editor selection endpoint', () {
    expect(
      yamlCursorPosition(
        const CodeLineSelection(
          baseIndex: 0,
          baseOffset: 1,
          extentIndex: 3,
          extentOffset: 7,
        ),
      ),
      (line: 4, column: 8),
    );
    expect(
      yamlCursorPosition(
        const CodeLineSelection(
          baseIndex: 4,
          baseOffset: 9,
          extentIndex: 1,
          extentOffset: 0,
        ),
      ),
      (line: 2, column: 1),
    );
  });

  test('document metrics splice only the lines around an edit', () {
    final original = List.generate(2000, (index) => 'line-$index').join('\n');
    final metrics = YamlDocumentMetricsController(original);
    final changed = original.replaceFirst('line-1000', 'line-1000-edited');

    final change = metrics.updateText(changed);

    expect(change, isNotNull);
    expect(metrics.lines, changed.split('\n'));
    expect(metrics.debugLastChangedLineCount, lessThanOrEqualTo(2));

    final inserted = changed.replaceFirst('line-1500', 'inserted\nline-1500');
    metrics.updateText(inserted);
    expect(metrics.lines, inserted.split('\n'));
    expect(metrics.debugLastChangedLineCount, lessThanOrEqualTo(3));
  });

  test('document metrics preserve exact lines across boundary edits', () {
    final metrics = YamlDocumentMetricsController('a\nb\nc');
    for (final next in <String>[
      'a\ninserted\nb\nc',
      'a\ninserted\nc',
      'a\ninserted\nc\n',
      'single line',
      '',
      '\n',
      'first\n\nlast',
    ]) {
      metrics.updateText(next);
      expect(metrics.text, next);
      expect(metrics.lines, next.split('\n'), reason: next);
    }
  });

  testWidgets('whole-document width keeps off-screen longest lines reachable',
      (tester) async {
    final widthCache = YamlDocumentWidthCache();
    const style = TextStyle(fontSize: 13, fontFamily: 'monospace');
    const scaler = TextScaler.noScaling;
    final shortWidth = widthCache.update(
      text: 'short\nline',
      style: style,
      textScaler: scaler,
      horizontalPadding: 40,
    );
    final longWidth = widthCache.update(
      text: 'short\n${List.filled(120, 'x').join()}\nline',
      style: style,
      textScaler: scaler,
      horizontalPadding: 40,
    );
    expect(longWidth, greaterThan(shortWidth));
    expect(widthCache.debugLastMeasuredLineCount, lessThanOrEqualTo(3));

    final controller = YamlDocumentHorizontalScrollController();
    addTearDown(controller.dispose);
    Widget scrollHarness(double childWidth) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: childWidth, height: 20),
              ),
            ),
          ),
        );
    await tester.pumpWidget(scrollHarness(80));
    controller.updateDocumentWidth(longWidth);
    await tester.pumpWidget(scrollHarness(80.001));
    expect(
      controller.position.maxScrollExtent,
      closeTo(longWidth - 200, 0.1),
    );
    controller.jumpTo(controller.position.maxScrollExtent);
    expect(controller.offset, closeTo(longWidth - 200, 0.1));

    controller.updateDocumentWidth(shortWidth);
    await tester.pumpWidget(scrollHarness(80));
    expect(
      controller.position.maxScrollExtent,
      closeTo(math.max(0, shortWidth - 200), 0.1),
    );
    expect(controller.offset,
        lessThanOrEqualTo(controller.position.maxScrollExtent));
  });

  testWidgets('near-limit YAML edits only recalculate the affected lines',
      (tester) async {
    final line = 'key: ${List.filled(512, 'x').join()}';
    final text = List.filled(10100, line).join('\n');
    expect(text.length, lessThan(ClashConfigFileService.maxConfigBytes));
    expect(
      text.length,
      greaterThan(ClashConfigFileService.maxConfigBytes - 20 * 1024),
    );

    final document = YamlDocumentMetricsController(text);
    final widthCache = YamlDocumentWidthCache(document: document);
    const style = TextStyle(fontSize: 13, fontFamily: 'monospace');
    const scaler = TextScaler.noScaling;
    widthCache.update(
      text: text,
      style: style,
      textScaler: scaler,
      horizontalPadding: 40,
    );

    final edited = text.replaceFirst('key:', 'edited-key:');
    widthCache.update(
      text: edited,
      style: style,
      textScaler: scaler,
      horizontalPadding: 40,
    );

    expect(document.lines, hasLength(10100));
    expect(document.lines.first, startsWith('edited-key:'));
    expect(document.debugLastChangedLineCount, lessThanOrEqualTo(2));
    expect(widthCache.debugLastMeasuredLineCount, lessThanOrEqualTo(2));
  });

  testWidgets('indent guide layer never intercepts editor gestures',
      (tester) async {
    final horizontal = ScrollController();
    final vertical = ScrollController();
    final scrollController = CodeScrollController(
      horizontalScroller: horizontal,
      verticalScroller: vertical,
    );
    final controller = CodeLineEditingController.fromText('root:\n  child: 1');
    addTearDown(() {
      controller.dispose();
      scrollController.dispose();
      horizontal.dispose();
      vertical.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 200,
            child: YamlIndentGuideLayer(
              controller: controller,
              scrollController: scrollController,
              metrics: YamlEditorLayoutMetrics.forLineCount(2),
              document: YamlDocumentMetricsController(controller.text),
            ),
          ),
        ),
      ),
    );

    final ignorePointers = tester.widgetList<IgnorePointer>(
      find.ancestor(
        of: find.byKey(const ValueKey('yaml_indent_guides')),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(ignorePointers.any((widget) => widget.ignoring), isTrue);
    var painter = tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey('yaml_indent_guides')),
        )
        .painter! as YamlIndentGuidePainter;
    expect(painter.model.depths, [0, 1]);
    expect(painter.activeLine, 0);

    final initialModel = painter.model;
    controller.selection = const CodeLineSelection.collapsed(
      index: 1,
      offset: 2,
    );
    await tester.pump();
    painter = tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey('yaml_indent_guides')),
        )
        .painter! as YamlIndentGuidePainter;
    expect(painter.model, same(initialModel));
    expect(painter.activeLine, 1);

    controller.text = 'root:\n  child:\n    grandchild: true';
    await tester.pump(const Duration(milliseconds: 80));
    painter = tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey('yaml_indent_guides')),
        )
        .painter! as YamlIndentGuidePainter;
    expect(painter.model, isNot(same(initialModel)));
    expect(painter.model.depths, [0, 1, 2]);
  });

  testWidgets('YAML naming dialog is centered and edits only the file name',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    tester.view.physicalSize = const Size(320, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(320, 520),
            viewInsets: EdgeInsets.only(bottom: 180),
          ),
          child: Scaffold(
            body: YamlUploadFileNameDialog(initialValue: 'local.yaml'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('yaml_upload_file_name')),
    );
    expect(field.controller!.text, 'local.yaml');
    expect(
        find.text('Upload directory: /etc/openclash/config'), findsOneWidget);
    expect(field.controller!.text, isNot(contains('/etc/openclash/config')));

    final dialogRect = tester.getRect(
      find.byKey(const ValueKey('yaml_upload_dialog_content')),
    );
    expect(dialogRect.width, lessThanOrEqualTo(360));
    expect(dialogRect.left, greaterThanOrEqualTo(24));
    expect(dialogRect.right, lessThanOrEqualTo(320 - 24));
    expect(dialogRect.center.dx, closeTo(160, 1));
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byKey(const ValueKey('yaml_upload_file_name')),
      '../escape.yaml',
    );
    await tester.ensureVisible(find.text('Upload'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload'));
    await tester.pump();
    expect(
      find.text(
          'File name cannot contain path separators or control characters'),
      findsOneWidget,
    );
  });

  testWidgets('rename dialog uses concise labels without a field heading',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: const MaterialApp(
          home: Scaffold(
            body: YamlFileNameDialog(
              title: '重命名',
              confirmText: '确认',
              description: '所在目录：/etc/openclash/config',
              initialValue: 'current.yaml',
              fieldKey: ValueKey('yaml_rename_file_name'),
              showFieldTitle: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('File name'), findsNothing);
    expect(find.text('Directory: /etc/openclash/config'), findsOneWidget);
  });

  for (final entry in {
    'LF': 'mode: rule\n# 中文\n',
    'CRLF': 'mode: rule\r\n# 中文\r\n',
    'CR': 'mode: rule\r# 中文\r',
    'empty': '',
  }.entries) {
    testWidgets('unchanged ${entry.key} YAML exits without a save prompt',
        (tester) async {
      SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
      await AppLocaleController.instance.load();
      var writes = 0;
      bool? editorResult;
      await tester.pumpWidget(localized(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      editorResult = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                            builder: (_) => ClashConfigEditorPage(
                                  file: const ClashConfigFile(
                                      path: '/etc/openclash/config/test.yaml'),
                                  readFile: (_) async => entry.value,
                                  writeFile: (_, content) async {
                                    writes++;
                                  },
                                )),
                      );
                    },
                    child: const Text('Open editor'),
                  ),
                )),
      )));
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
      editor.focusNode!.requestFocus();
      editor.controller!.selectAll();
      await tester.pump();
      editor.focusNode!.unfocus();
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('yaml_editor_save')),
              )
              .onPressed,
          isNull);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.text('保存修改？'), findsNothing);
      expect(find.byType(ClashConfigEditorPage), findsNothing);
      expect(editorResult, isFalse);
      expect(writes, 0);
    },
        variant: TargetPlatformVariant(
            {TargetPlatform.android, TargetPlatform.iOS}));
  }

  testWidgets('real YAML edits prompt, and undo returns to the clean baseline',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
    await AppLocaleController.instance.load();
    await tester.pumpWidget(localized(MaterialApp(
        home: ClashConfigEditorPage(
      file: const ClashConfigFile(path: '/etc/openclash/config/test.yaml'),
      readFile: (_) async => 'mode: rule\r\n',
    ))));
    await tester.pumpAndSettle();
    final controller =
        tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!;
    // Whitespace matters in YAML: it must not be trimmed out of dirty checks.
    controller.replaceSelection(' ');
    await tester.pump();
    expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('yaml_editor_save')),
            )
            .onPressed,
        isNotNull);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('保存修改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    controller.undo();
    await tester.pump();
    expect(controller.text, 'mode: rule\n');
    expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('yaml_editor_save')),
            )
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  },
      variant:
          TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));

  testWidgets('failed YAML reads stay read-only until retry succeeds',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
    await AppLocaleController.instance.load();
    var reads = 0;
    await tester.pumpWidget(localized(MaterialApp(
        home: ClashConfigEditorPage(
      file: const ClashConfigFile(path: '/etc/openclash/config/test.yaml'),
      readFile: (_) async {
        if (++reads == 1) throw StateError('SFTP unavailable');
        return 'mode: rule\n';
      },
    ))));
    await tester.pumpAndSettle();
    expect(tester.widget<CodeEditor>(find.byType(CodeEditor)).readOnly, isTrue);
    expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('yaml_editor_save')),
            )
            .onPressed,
        isNull);
    await tester.pump(const Duration(seconds: 10));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    expect(editor.readOnly, isFalse);
    expect(editor.controller!.text, 'mode: rule\n');
    expect(reads, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('restart reminder appears only after leaving a saved editor',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
    await AppLocaleController.instance.load();
    String? written;
    bool? editorResult;

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  editorResult = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => ClashConfigEditorPage(
                        file: const ClashConfigFile(
                          path: '/etc/openclash/config/test.yaml',
                        ),
                        readFile: (_) async => 'mode: rule',
                        writeFile: (_, content) async => written = content,
                      ),
                    ),
                  );
                },
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.controller!.text = 'mode: global';
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('yaml_editor_save')));
    await tester.pump();
    await tester.pump();
    expect(written, 'mode: global');
    expect(find.text('已保存 test.yaml'), findsOneWidget);
    expect(find.text('立即重启'), findsNothing);
    expect(find.textContaining('重启 OpenClash 后生效'), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('立即重启'), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(editorResult, isTrue);
  });

  testWidgets('saved configuration reminder lets the user restart later',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
    await AppLocaleController.instance.load();
    bool? choice;

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  choice = await showDialog<bool>(
                    context: context,
                    builder: (_) => const YamlRestartAfterSaveDialog(),
                  );
                },
                child: const Text('Show reminder'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show reminder'));
    await tester.pumpAndSettle();
    expect(find.text('确认重启 OpenClash'), findsOneWidget);
    expect(find.text('配置已保存，是否立即重启 OpenClash 使修改生效？'), findsOneWidget);
    expect(find.text('稍后'), findsOneWidget);
    expect(find.text('立即重启'), findsOneWidget);

    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(choice, isFalse);
  });

  testWidgets('YAML shortcut bar edits with spaces, symbols and cursor keys',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    final controller = CodeLineEditingController.fromText(
      'key',
      const CodeLineOptions(indentSize: 1),
    );
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    final textInputCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (call) async {
        textInputCalls.add(call.method);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        null,
      );
    });

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Focus(
                focusNode: focusNode,
                child: YamlEditorShortcutBar(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    textInputCalls.clear();

    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 0,
    );
    await tester.tap(find.byKey(const ValueKey('yaml_key_tab')));
    await tester.pump();
    expect(controller.text, '  key');
    expect(controller.text, isNot(contains('\t')));
    expect(focusNode.hasFocus, isTrue);
    expect(textInputCalls, isNot(contains('TextInput.show')));
    expect(textInputCalls, isNot(contains('TextInput.hide')));

    controller.deleteBackward();
    expect(controller.text, ' key');
    controller.deleteBackward();
    expect(controller.text, 'key');

    controller.text = '  key';
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 2,
    );
    controller.deleteBackward();
    expect(controller.text, ' key');

    for (final symbol in const [
      '-',
      ':',
      '"',
      "'",
      '[',
      ']',
      '#',
      '|',
    ]) {
      controller.text = '';
      controller.selection = const CodeLineSelection.zero();
      final finder = find.byKey(ValueKey('yaml_key_$symbol'));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump();
      expect(controller.text, symbol, reason: symbol);
    }

    controller.text = 'abcd';
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 1,
    );
    final right = find.byKey(const ValueKey('yaml_key_right'));
    final left = find.byKey(const ValueKey('yaml_key_left'));
    final down = find.byKey(const ValueKey('yaml_key_down'));
    final up = find.byKey(const ValueKey('yaml_key_up'));
    final tab = find.byKey(const ValueKey('yaml_key_tab'));
    final shortcutBar = find.byKey(
      const ValueKey('yaml_editor_shortcut_bar'),
    );
    await tester.ensureVisible(right);
    expect(
      find.descendant(
        of: shortcutBar,
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('yaml_key_outdent')), findsNothing);
    expect(
      find.descendant(of: tab, matching: find.text('TAB')),
      findsOneWidget,
    );
    expect(tester.getCenter(up).dy, lessThan(tester.getCenter(down).dy));
    expect(tester.getCenter(left).dx, lessThan(tester.getCenter(down).dx));
    expect(tester.getCenter(down).dx, lessThan(tester.getCenter(right).dx));
    await tester.tap(right);
    await tester.pump();
    expect(controller.selection.extentOffset, 2);

    controller.text = 'abcdefghijklmnop';
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 0,
    );
    final gesture = await tester.startGesture(tester.getCenter(right));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump(const Duration(milliseconds: 225));
    await gesture.up();
    await tester.pump();
    expect(controller.selection.extentOffset, greaterThan(2));

    focusNode.unfocus();
    await tester.pump();
    textInputCalls.clear();
    controller.text = '';
    controller.selection = const CodeLineSelection.zero();
    await tester.tap(find.byKey(const ValueKey('yaml_key_#')));
    await tester.pump();
    expect(controller.text, '#');
    expect(focusNode.hasFocus, isFalse);
    expect(textInputCalls, isNot(contains('TextInput.show')));
    expect(textInputCalls, isNot(contains('TextInput.hide')));
  });

  testWidgets('header information and save button reflect editor state',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    var saves = 0;

    Widget build({
      required bool dirty,
      bool loading = false,
      bool saving = false,
    }) {
      return AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                YamlEditorSaveButton(
                  dirty: dirty,
                  loading: loading,
                  saving: saving,
                  enabled: true,
                  onSave: () => saves++,
                ),
              ],
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(31),
                child: YamlEditorHeaderInfo(
                  lineCount: 18,
                  cursorLine: 4,
                  cursorColumn: 7,
                ),
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(build(dirty: false));
    expect(find.text('Lines: 18'), findsOneWidget);
    expect(find.text('Line 4, column 7'), findsOneWidget);
    expect(find.text('Encoding: UTF-8'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('yaml_editor_save')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<Icon>(find.byKey(const ValueKey('yaml_editor_save_icon')))
          .color,
      const Color(0xFF858585),
    );

    await tester.pumpWidget(build(dirty: true));
    expect(
      tester
          .widget<Icon>(find.byKey(const ValueKey('yaml_editor_save_icon')))
          .color,
      Colors.white,
    );
    await tester.tap(find.byKey(const ValueKey('yaml_editor_save')));
    expect(saves, 1);

    await tester.pumpWidget(build(dirty: true, saving: true));
    expect(find.byKey(const ValueKey('yaml_editor_saving')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('yaml_editor_save')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('line numbers follow the editor scroll controllers',
      (tester) async {
    final horizontal = ScrollController();
    final vertical = ScrollController();
    final scrollController = CodeScrollController(
      horizontalScroller: horizontal,
      verticalScroller: vertical,
    );
    final controller = CodeLineEditingController.fromText(
      List.generate(30, (index) => 'line $index').join('\n'),
    );
    addTearDown(() {
      controller.dispose();
      scrollController.dispose();
      horizontal.dispose();
      vertical.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              SingleChildScrollView(
                controller: horizontal,
                scrollDirection: Axis.horizontal,
                child: const SizedBox(width: 1000, height: 20),
              ),
              SingleChildScrollView(
                controller: vertical,
                child: const SizedBox(width: 20, height: 1000),
              ),
              Positioned(
                left: 0,
                top: 40,
                width: 54,
                height: 180,
                child: YamlLineNumberLayer(
                  controller: controller,
                  scrollController: scrollController,
                  cursorLine: 6,
                  gutterWidth:
                      YamlEditorLayoutMetrics.forLineCount(6).gutterWidth,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    horizontal.jumpTo(64);
    vertical.jumpTo(38);
    await tester.pump();

    final transform = tester.widget<Transform>(
      find.byKey(const ValueKey('yaml_line_numbers_horizontal_offset')),
    );
    expect(transform.transform.getTranslation().x, closeTo(-64, 0.1));
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(
          const ValueKey('yaml_line_numbers_horizontal_offset'),
        ),
        matching: find.byType(CustomPaint),
      ),
    );
    final painter = paint.painter! as YamlLineNumberPainter;
    expect(painter.verticalOffset, closeTo(38, 0.1));
    expect(painter.cursorLine, 6);
  });

  testWidgets('mobile selection toolbar exposes native editing actions',
      (tester) async {
    final controller = CodeLineEditingController.fromText('hello world');
    final focusNode = FocusNode();
    var dismissed = false;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    controller.selection = const CodeLineSelection(
      baseIndex: 0,
      baseOffset: 0,
      extentIndex: 0,
      extentOffset: 5,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: Focus(
            focusNode: focusNode,
            child: YamlEditorSelectionToolbar(
              anchors: const TextSelectionToolbarAnchors(
                primaryAnchor: Offset(180, 220),
              ),
              controller: controller,
              editable: true,
              focusNode: focusNode,
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cut'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    expect(find.textContaining(RegExp(r'Select [Aa]ll')), findsOneWidget);

    await tester.tap(find.text('Cut'));
    await tester.pump();
    expect(controller.text, ' world');
    expect(dismissed, isTrue);
    expect(focusNode.hasFocus, isTrue);
  },
      variant:
          TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));

  testWidgets(
      'iOS YAML editor accepts Chinese composing input without losing text',
      (tester) async {
    const storage =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, null));
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    await tester.pumpWidget(AppLocaleScope(
      controller: AppLocaleController.instance,
      child: MaterialApp(
          home: ClashConfigEditorPage(
        readFile: (_) async => '',
        file: const ClashConfigFile(path: '/etc/openclash/config/test.yaml'),
      )),
    ));
    await tester.pumpAndSettle();
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.focusNode!.requestFocus();
    await tester.pump();
    expect(tester.testTextInput.setClientArgs!['enableDeltaModel'], isTrue);
    final clientId = (tester.testTextInput.log
            .lastWhere((call) => call.method == 'TextInput.setClient')
            .arguments as List)
        .first;
    final prefix = tester.testTextInput.editingState!['text'] as String;
    Future<void> sendDelta(Map<String, Object> delta) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.textInput.name,
        SystemChannels.textInput.codec.encodeMethodCall(MethodCall(
          'TextInputClient.updateEditingStateWithDeltas',
          [
            clientId,
            {
              'deltas': [delta]
            }
          ],
        )),
        (_) {},
      );
    }

    await sendDelta({
      'oldText': prefix,
      'deltaText': 'name: zhong',
      'deltaStart': prefix.length,
      'deltaEnd': prefix.length,
      'selectionBase': prefix.length + 11,
      'selectionExtent': prefix.length + 11,
      'composingBase': prefix.length + 6,
      'composingExtent': prefix.length + 11,
    });
    await tester.pump();
    await sendDelta({
      'oldText': '${prefix}name: zhong',
      'deltaText': '中文',
      'deltaStart': prefix.length + 6,
      'deltaEnd': prefix.length + 11,
      'selectionBase': prefix.length + 8,
      'selectionExtent': prefix.length + 8,
      'composingBase': -1,
      'composingExtent': -1,
    });
    await tester.pump();
    expect(editor.controller!.text, 'name: 中文');
    expect(
        tester
            .widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope))
            .canPop,
        isFalse);
    expect(tester.takeException(), isNull);
    editor.focusNode!.unfocus();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('full-screen editor dock follows the mobile keyboard',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Widget editor(double keyboardInset, {double systemBottomInset = 0}) {
      return AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 800),
              viewInsets: EdgeInsets.only(bottom: keyboardInset),
              padding: EdgeInsets.only(bottom: systemBottomInset),
            ),
            child: ClashConfigEditorPage(
              readFile: (_) async => '',
              file: const ClashConfigFile(
                  path: '/etc/openclash/config/test.yaml'),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(editor(0, systemBottomInset: 24));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final surface = find.byKey(
      const ValueKey('yaml_editor_fullscreen_surface'),
    );
    final shortcutBar = find.byKey(
      const ValueKey('yaml_editor_shortcut_bar'),
    );
    expect(tester.getRect(surface).left, 0);
    expect(tester.getRect(surface).right, 360);
    expect(tester.getRect(shortcutBar).bottom, closeTo(776, 1));

    await tester.pumpWidget(editor(240, systemBottomInset: 24));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getRect(shortcutBar).bottom, closeTo(560, 1));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  },
      variant:
          TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));
}
