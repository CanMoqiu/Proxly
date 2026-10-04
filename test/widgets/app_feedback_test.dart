import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/theme/app_theme.dart';
import 'package:proxly/widgets/app_feedback.dart';

class _FeedbackHarness extends StatefulWidget {
  const _FeedbackHarness();

  @override
  State<_FeedbackHarness> createState() => _FeedbackHarnessState();
}

class _FeedbackHarnessState extends State<_FeedbackHarness>
    with TransientFeedbackStateMixin<_FeedbackHarness> {
  String? message;

  void show(String value, {required bool error}) {
    setState(() => message = value);
    scheduleFeedbackClear(
      'status',
      isError: error,
      clear: () => setState(() => message = null),
    );
  }

  @override
  void dispose() {
    disposeTransientFeedback();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          FilledButton(
            onPressed: () => show('success', error: false),
            child: const Text('success button'),
          ),
          FilledButton(
            onPressed: () => show('error', error: true),
            child: const Text('error button'),
          ),
          if (message != null) Text(message!),
        ],
      ),
    );
  }
}

class _RouteFeedbackPage extends StatelessWidget {
  const _RouteFeedbackPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () => AppFeedback.showSnackBar(context, 'route notice'),
            child: const Text('show route notice'),
          ),
          TextButton(
            onPressed: () {
              AppFeedback.showSnackBar(context, 'first');
              AppFeedback.showSnackBar(context, 'second');
            },
            child: const Text('replace notice'),
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('transient feedback uses 3 and 6 second lifetimes',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const _FeedbackHarness()),
    );

    await tester.tap(find.text('success button'));
    await tester.pump();
    expect(find.text('success'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2999));
    expect(find.text('success'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('success'), findsNothing);

    await tester.tap(find.text('error button'));
    await tester.pump();
    expect(find.text('error'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 5999));
    expect(find.text('error'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('error'), findsNothing);
  });

  testWidgets('a replaced feedback timer cannot clear the new message',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const _FeedbackHarness()),
    );

    await tester.tap(find.text('success button'));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('error button'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('error'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 4900));
    expect(find.text('error'), findsNothing);
  });

  testWidgets('error feedback slides in from the right above the screen edge',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => AppFeedback.showSnackBar(
                context,
                'failed',
                tone: AppFeedbackTone.error,
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();
    final banner = find.byKey(const ValueKey('app_feedback_banner'));
    final slide = tester.widget<SlideTransition>(
      find.ancestor(of: banner, matching: find.byType(SlideTransition)),
    );
    expect(slide.position.value.dx, greaterThan(0));
    expect(find.text('failed'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 220));
    expect(slide.position.value.dx, 0);
    expect(
      tester.getBottomRight(banner).dy,
      lessThan(
        tester.view.physicalSize.height / tester.view.devicePixelRatio - 40,
      ),
    );
    await tester.pump(const Duration(milliseconds: 5779));
    expect(banner, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
  });

  testWidgets('a feedback banner is removed as its source page exits',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _RouteFeedbackPage()),
              ),
              child: const Text('open route'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open route'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('show route notice'));
    await tester.pump();
    expect(find.text('route notice'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    expect(find.text('route notice'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app_feedback_banner')), findsNothing);
  });

  testWidgets('a new feedback banner immediately replaces the previous one',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const _RouteFeedbackPage()),
    );
    await tester.tap(find.text('replace notice'));
    await tester.pump();
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('app_feedback_banner')),
      findsOneWidget,
    );
  });

  testWidgets('feedback stays within the right three quarters and lower half',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final message = List.filled(160, 'multiline feedback').join(' ');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => AppFeedback.showSnackBar(context, message),
              child: const Text('show long feedback'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show long feedback'));
    await tester.pump(const Duration(milliseconds: 220));

    final banner = find.byKey(const ValueKey('app_feedback_banner'));
    final bounds = tester.getRect(banner);
    expect(bounds.left, greaterThanOrEqualTo(100));
    expect(bounds.width, lessThanOrEqualTo(300));
    expect(bounds.top, greaterThanOrEqualTo(400));
    expect(bounds.bottom, lessThanOrEqualTo(800));
    expect(
      find.descendant(
        of: banner,
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(tester.widget<Text>(find.text(message)).maxLines, isNull);
  });

  testWidgets('long feedback keeps its bottom edge and grows upward',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => AppFeedback.showSnackBar(context, 'short'),
                  child: const Text('show short'),
                ),
                TextButton(
                  onPressed: () => AppFeedback.showSnackBar(
                    context,
                    List.filled(80, 'long feedback').join(' '),
                  ),
                  child: const Text('show long'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show short'));
    await tester.pump(const Duration(milliseconds: 220));
    final banner = find.byKey(const ValueKey('app_feedback_banner'));
    final shortBounds = tester.getRect(banner);

    await tester.tap(find.text('show long'));
    await tester.pump(const Duration(milliseconds: 220));
    final longBounds = tester.getRect(banner);

    expect(longBounds.bottom, closeTo(shortBounds.bottom, 0.01));
    expect(longBounds.top, lessThan(shortBounds.top));
    expect(longBounds.top, greaterThanOrEqualTo(400));
  });
}
