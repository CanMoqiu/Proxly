import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/native_connections_page.dart';
import 'package:proxly/services/clash_data_hub.dart';
import 'package:proxly/services/clash_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('close waits for confirmation, keeps failures and allows retry',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
    await AppLocaleController.instance.load();
    var completion = Completer<void>();
    var calls = 0;
    var closed = false;
    var sequence = 0;
    final connection = ConnectionEntry(
        id: 'test-id',
        sourceIp: '192.168.1.2',
        sourcePort: '1234',
        host: 'example.com',
        sniffHost: '',
        destinationIp: '',
        destinationPort: '443',
        remoteDestination: '',
        network: 'tcp',
        type: '',
        chain: 'DIRECT',
        chainList: ['DIRECT'],
        providerChains: [],
        rule: '',
        inboundName: '',
        inboundIp: '',
        inboundPort: '',
        process: '',
        dnsMode: '',
        startTime: _testStartTime,
        upload: 0,
        download: 0,
        apiUpSpeed: 0,
        apiDownSpeed: 0);
    await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
            home: NativeConnectionsPage(
                loadSnapshot: () async => ClashRealtimeSnapshot(
                    sequence: ++sequence,
                    updatedAt: DateTime.now(),
                    downloadTotal: 0,
                    uploadTotal: 0,
                    activeConnections: closed ? 0 : 1,
                    downloadSpeed: 0,
                    uploadSpeed: 0,
                    connections: closed ? [] : [connection],
                    providers: []),
                closeConnection: (id) async {
                  expect(id, 'test-id');
                  calls++;
                  await completion.future;
                  closed = true;
                }))));
    await tester.pumpAndSettle();
    final close = find.byKey(const ValueKey('close_connection_test-id'));
    await tester.tap(close);
    await tester.pump();
    expect(find.text('example.com'), findsOneWidget);
    await tester.tap(close);
    await tester.pump();
    expect(calls, 1);
    completion.completeError(const ClashControllerException(
        ClashControllerFailureKind.unauthorized,
        statusCode: 401));
    await tester.pumpAndSettle();
    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('关闭连接失败，请检查网络和 Token 后重试'), findsOneWidget);
    completion = Completer<void>();
    await tester.tap(close);
    await tester.pump();
    expect(calls, 2);
    completion.complete();
    await tester.pumpAndSettle();
    expect(find.text('example.com'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 7));
  },
      variant:
          TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));
  testWidgets(
      'native connections error state stays retryable without pull refresh',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
    await AppLocaleController.instance.load();

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: const MaterialApp(home: NativeConnectionsPage()),
      ),
    );
    await tester.pump();

    expect(find.text('请先在设置页填写 Clash 地址'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'AdaptivePullRefresh',
      ),
      findsNothing,
    );
    expect(find.byType(RefreshIndicator), findsNothing);

    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.physics, isA<ClampingScrollPhysics>());
  });
}

final _testStartTime = DateTime(2026);
