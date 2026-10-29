import 'package:event_tracker_analytics/event_tracker_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/harness.dart';

/// A tiny app with named routes, using the SDK's screen observer.
class _App extends StatelessWidget {
  const _App({this.observer});

  final NavigatorObserver? observer;

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorObservers: [observer ?? EventTracker.screenObserver()],
        initialRoute: '/home',
        routes: {
          '/home': (_) => const _Page('Home'),
          '/cars': (_) => const _Page('Cars'),
          '/cars/42': (_) => const _Page('Car 42'),
          '/profile': (_) => const _Page('Profile'),
        },
      );
}

class _Page extends StatelessWidget {
  const _Page(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(title));
}

NavigatorState navigator(WidgetTester tester) => tester.state<NavigatorState>(find.byType(Navigator));

/// Screen views in order, whether already sent (flushAt is 3 in tests) or still waiting.
List<String?> screenViews() => [...transport.sent, ...queue.pending]
    .where((e) => e.event == r'$screen')
    .map((e) => e.screenName)
    .toList();

void main() {
  setUp(resetDevice);
  tearDown(() => EventTracker.dispose());

  group('screen observer', () {
    testWidgets('records the first screen, pushes, pops and replacements', (tester) async {
      await tester.runAsync(() => start());
      await tester.pumpWidget(const _App());
      await tester.pump();

      navigator(tester).pushNamed('/cars');
      await tester.pumpAndSettle();
      navigator(tester).pushReplacementNamed('/profile');
      await tester.pumpAndSettle();
      navigator(tester).pop(); // back to Home
      await tester.pumpAndSettle();

      expect(screenViews(), ['/home', '/cars', '/profile', '/home']);
      expect(EventTracker.container.read(currentScreenProvider), '/home');
    });

    testWidgets('later events carry the current screen', (tester) async {
      await tester.runAsync(() => start());
      await tester.pumpWidget(const _App());
      navigator(tester).pushNamed('/cars');
      await tester.pumpAndSettle();

      EventTracker.track('filter_used');
      expect(queue.pending.last.screenName, '/cars');
    });

    testWidgets('dialogs, sheets and unnamed routes are ignored', (tester) async {
      await tester.runAsync(() => start());
      await tester.pumpWidget(const _App());
      await tester.pump();
      final context = tester.element(find.text('Home'));

      showDialog<void>(context: context, builder: (_) => const Text('dialog'));
      await tester.pumpAndSettle();
      navigator(tester).pop();
      await tester.pumpAndSettle();
      navigator(tester).push(MaterialPageRoute<void>(builder: (_) => const _Page('No name')));
      await tester.pumpAndSettle();

      // Closing the dialog returns to Home, which counts as a view of Home again.
      expect(screenViews(), ['/home', '/home']);
    });

    testWidgets('custom names, e.g. to drop ids from the route', (tester) async {
      await tester.runAsync(() => start());
      final observer = EventTracker.screenObserver(
        screenName: (settings) => settings.name == '/cars/42' ? 'CarDetail' : settings.name,
      );
      await tester.pumpWidget(_App(observer: observer));
      navigator(tester).pushNamed('/cars/42');
      await tester.pumpAndSettle();
      expect(screenViews(), ['/home', 'CarDetail']);
    });
  });

  group('app lifecycle', () {
    const lifecycleConfig = TrackerConfig(
      apiKey: 'pk_test', host: 'http://test', flushAt: 100, flushInterval: Duration(hours: 1),
    );

    testWidgets('app open, background (sends the queue) and foreground', (tester) async {
      await tester.runAsync(() => start(config: lifecycleConfig));
      expect(pendingNames, [r'$app_open']);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(transport.sent.map((e) => e.event), [r'$app_open', r'$app_background'],
          reason: 'queued events go out before the app may be killed');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(pendingNames, [r'$app_foreground']);
    });

    testWidgets('a short interruption (e.g. notification shade) is not a background', (tester) async {
      await tester.runAsync(() => start(config: lifecycleConfig));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(pendingNames, [r'$app_open']);
    });

    testWidgets('can be turned off', (tester) async {
      await tester.runAsync(() => start()); // testConfig: trackAppLifecycle false
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(pendingNames, isEmpty);
    });
  });
}
