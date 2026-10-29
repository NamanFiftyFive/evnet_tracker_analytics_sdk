import 'dart:async';

import 'package:event_tracker_analytics/event_tracker_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/harness.dart';

/// The on-device queue's timing and limits, plus the "never crash the app" promises.
/// testWidgets runs on fake time, so retry delays of seconds or minutes pass instantly.
void main() {
  setUp(resetDevice);
  tearDown(() => EventTracker.dispose());

  /// Starts the SDK, then rebuilds the queue on the test's fake clock so its timers follow
  /// tester.pump(duration). (Startup itself needs real time: device plugins answer asynchronously.)
  Future<void> startOnFakeTime(WidgetTester tester, TrackerConfig config) async {
    await tester.runAsync(() => start(config: config));
    EventTracker.container.invalidate(eventQueueProvider); // cancels the real-time timers
    EventTracker.container.read(eventQueueProvider); // new timers, on fake time
  }

  group('limits', () {
    test('when offline for long, only the newest maxQueueSize events are kept', () async {
      await start(config: const TrackerConfig(
        apiKey: 'k', host: 'http://test', flushAt: 1000, maxQueueSize: 3,
        flushInterval: Duration(hours: 1), trackAppLifecycle: false,
      ));
      for (var i = 0; i < 5; i++) {
        EventTracker.track('e$i');
      }
      expect(pendingNames, ['e2', 'e3', 'e4']);
    });

    test('empty event names and user ids are ignored', () async {
      await start();
      EventTracker.track('');
      await EventTracker.identify('');
      expect(queue.pending, isEmpty);
      expect(EventTracker.container.read(identityProvider).userId, isNull);
    });

    test('opt-out is remembered after a restart', () async {
      await start();
      await EventTracker.setOptOut(true);
      await EventTracker.dispose();
      await start();
      EventTracker.track('after_restart');
      expect(queue.pending, isEmpty);
    });
  });

  /// testWidgets on fake time; the SDK is stopped before Flutter checks for leftover timers.
  void fakeTimeTest(String description, Future<void> Function(WidgetTester tester) body) =>
      testWidgets(description, (tester) async {
        await body(tester);
        await EventTracker.dispose();
      });

  group('timing', () {
    fakeTimeTest('events are sent every flushInterval without reaching flushAt', (tester) async {
      await startOnFakeTime(tester, const TrackerConfig(
        apiKey: 'k', host: 'http://test', flushAt: 100, flushInterval: Duration(seconds: 10), trackAppLifecycle: false,
      ));
      EventTracker.track('lonely_event');
      await tester.pump(const Duration(seconds: 9));
      expect(transport.batches, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(transport.sent.map((e) => e.event), ['lonely_event']);
    });

    fakeTimeTest('after a failure, retries wait 2 s, then 4 s, then 8 s', (tester) async {
      await startOnFakeTime(tester, testConfig);
      transport.nextOutcome = SendOutcome.retryLater;
      EventTracker.track('a');
      await EventTracker.flush(); // attempt 1 fails
      expect(transport.batches, hasLength(1));

      await tester.pump(const Duration(milliseconds: 1999));
      expect(transport.batches, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1)); // 2 s: attempt 2 fails
      expect(transport.batches, hasLength(2));
      await tester.pump(const Duration(seconds: 4)); // attempt 3 fails
      expect(transport.batches, hasLength(3));
      expect(queue.failedAttempts, 3);

      transport.nextOutcome = SendOutcome.success;
      await tester.pump(const Duration(seconds: 8)); // attempt 4 succeeds
      expect(queue.pending, isEmpty);
      expect(queue.failedAttempts, 0);
    });

    fakeTimeTest('the regular timer waits while a retry is scheduled', (tester) async {
      await startOnFakeTime(tester, const TrackerConfig(
        apiKey: 'k', host: 'http://test', flushAt: 100, flushInterval: Duration(seconds: 1), trackAppLifecycle: false,
      ));
      transport.nextOutcome = SendOutcome.retryLater;
      EventTracker.track('a');
      await tester.pump(const Duration(seconds: 1)); // timer flush fails, retry in 2 s
      expect(transport.batches, hasLength(1));
      await tester.pump(const Duration(seconds: 1)); // timer tick: skipped (no hammering a down server)
      expect(transport.batches, hasLength(1));
      await tester.pump(const Duration(seconds: 1)); // the retry
      expect(transport.batches, hasLength(2));
    });

    fakeTimeTest('retry delay stops growing at 5 minutes', (tester) async {
      await startOnFakeTime(tester, testConfig);
      transport.nextOutcome = SendOutcome.retryLater;
      EventTracker.track('a');
      await EventTracker.flush();
      for (final seconds in [2, 4, 8, 16, 32, 64, 128, 256]) {
        await tester.pump(Duration(seconds: seconds));
      }
      final attempts = transport.batches.length;
      await tester.pump(const Duration(seconds: 299));
      expect(transport.batches, hasLength(attempts));
      await tester.pump(const Duration(seconds: 1)); // 300 s, not 512 s
      expect(transport.batches, hasLength(attempts + 1));
    });
  });

  group('sending', () {
    test('events added while a batch is being sent stay for the next one', () async {
      await start();
      transport.gate = Completer<void>();
      EventTracker.track('first');
      final flushing = EventTracker.flush();
      await pumpEventQueue();
      expect(queue.isFlushing, isTrue);

      EventTracker.track('during_send');
      transport.gate!.complete();
      await flushing;
      expect(transport.batches.first.map((e) => e.event), ['first']);
      expect(pendingNames, isEmpty, reason: 'the loop sends the newcomer too');
      expect(transport.batches.last.map((e) => e.event), ['during_send']);
    });

    test('a second flush while one is running does nothing', () async {
      await start();
      transport.gate = Completer<void>();
      EventTracker.track('a');
      final first = EventTracker.flush();
      await pumpEventQueue();
      await EventTracker.flush();
      transport.gate!.complete();
      await first;
      expect(transport.batches, hasLength(1));
    });

    test('flushing an empty queue sends nothing', () async {
      await start();
      await EventTracker.flush();
      expect(transport.batches, isEmpty);
    });
  });

  group('never crashes the app', () {
    test('a failing transport is caught', () async {
      await start();
      transport.throwOnSend = StateError('bug inside the SDK');
      EventTracker.track('a');
      await expectLater(EventTracker.flush(), completes);
      expect(queue.isFlushing, isFalse);
      expect(pendingNames, ['a'], reason: 'kept for a later attempt');
    });

    test('a second init is ignored', () async {
      await start(config: const TrackerConfig(apiKey: 'k', host: 'http://test', debug: true, trackAppLifecycle: false));
      final container = EventTracker.container;
      await EventTracker.init(const TrackerConfig(apiKey: 'other', host: 'http://other'));
      expect(EventTracker.container, same(container));
    });

    test('container before init explains what to do', () {
      expect(() => EventTracker.container, throwsA(isA<StateError>()));
    });
  });
}
