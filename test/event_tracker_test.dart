import 'package:event_tracker_analytics/event_tracker_analytics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetDevice);

  tearDown(() => EventTracker.dispose());

  test('calls before init do nothing and never throw', () async {
    EventTracker.track('early');
    EventTracker.screen('Home');
    await EventTracker.identify('u1');
    await EventTracker.flush();
    expect(EventTracker.isInitialized, isFalse);
  });

  test('track builds a full event and queues it', () async {
    await start();
    EventTracker.screen('CarDetail');
    EventTracker.track('car_viewed', {'model': 'Nexon EV', 'at': DateTime.utc(2026, 10, 20)});

    expect(queue.pending, hasLength(2));
    final event = queue.pending.last;
    expect(event.event, 'car_viewed');
    expect(event.screenName, 'CarDetail', reason: 'current screen is attached');
    expect(event.sessionId, queue.pending.first.sessionId, reason: 'same session');
    expect(event.distinctId, EventTracker.container.read(identityProvider).anonymousId);
    expect(event.properties['at'], '2026-10-20T00:00:00.000Z', reason: 'dates become ISO strings');
    expect(event.toJson()['distinct_id'], event.distinctId, reason: 'server field names');
  });

  test('reaching flushAt sends a batch and empties the queue', () async {
    await start();
    for (var i = 0; i < 3; i++) {
      EventTracker.track('e$i');
    }
    await pumpEventQueue();
    expect(transport.batches, hasLength(1));
    expect(transport.sent.map((e) => e.event), ['e0', 'e1', 'e2']);
    expect(queue.pending, isEmpty);
    expect(queue.sentCount, 3);
  });

  test('network failure keeps events for a retry', () async {
    await start();
    transport.nextOutcome = SendOutcome.retryLater;
    EventTracker.track('a');
    await EventTracker.flush();
    expect(queue.pending, hasLength(1));
    expect(queue.failedAttempts, 1);
    expect(queue.lastError, 'fake retryLater');

    transport.nextOutcome = SendOutcome.success;
    await EventTracker.flush();
    expect(queue.pending, isEmpty);
    expect(queue.failedAttempts, 0);
    expect(queue.lastError, isNull);
  });

  test('a batch the server refuses for good is dropped, not retried forever', () async {
    await start();
    transport.nextOutcome = SendOutcome.dropBatch;
    EventTracker.track('a');
    await EventTracker.flush();
    expect(queue.pending, isEmpty);
    expect(queue.droppedCount, 1);
  });

  test('large queues are sent in batches of maxBatchSize', () async {
    await start(config: const TrackerConfig(
      apiKey: 'k', host: 'http://test', flushAt: 1000, maxBatchSize: 4,
      flushInterval: Duration(hours: 1), trackAppLifecycle: false,
    ));
    for (var i = 0; i < 10; i++) {
      EventTracker.track('e$i');
    }
    await EventTracker.flush();
    expect(transport.batches.map((b) => b.length), [4, 4, 2]);
  });

  test('identify switches the user and stores traits; reset starts fresh', () async {
    await start();
    final anonymous = EventTracker.container.read(identityProvider).anonymousId;
    await EventTracker.identify('customer_1042', {'city': 'Pune'});
    EventTracker.track('test_drive_booked');

    final identifyEvent = queue.pending.firstWhere((e) => e.event == r'$identify');
    expect(identifyEvent.distinctId, 'customer_1042');
    expect(identifyEvent.properties, {'city': 'Pune', r'$anon_distinct_id': anonymous});
    expect(queue.pending.last.distinctId, 'customer_1042');

    await EventTracker.reset();
    final identity = EventTracker.container.read(identityProvider);
    expect(identity.userId, isNull);
    expect(identity.anonymousId, isNot(anonymous));
    expect(transport.sent.map((e) => e.event), contains('test_drive_booked'), reason: 'reset flushes first');
  });

  test('a new session starts after the timeout', () async {
    await start();
    final sessions = EventTracker.container.read(sessionProvider.notifier);
    final t0 = DateTime.utc(2026, 10, 20, 10);
    final first = sessions.touch(t0);
    expect(sessions.touch(t0.add(const Duration(minutes: 29))), first);
    expect(sessions.touch(t0.add(const Duration(minutes: 70))), isNot(first));
  });

  test('unsent events and the user survive an app restart', () async {
    await start();
    transport.nextOutcome = SendOutcome.retryLater;
    await EventTracker.identify('customer_7');
    EventTracker.track('offline_event');
    await EventTracker.flush();
    await pumpEventQueue();
    await EventTracker.dispose();

    await start(); // same SharedPreferences, new container = app relaunch
    expect(EventTracker.container.read(identityProvider).userId, 'customer_7');
    expect(queue.pending.map((e) => e.event), [r'$identify', 'offline_event']);
    await EventTracker.flush();
    expect(transport.sent.map((e) => e.event), [r'$identify', 'offline_event']);
  });

  test('opt-out stops tracking and clears the queue', () async {
    await start();
    EventTracker.track('a');
    await EventTracker.setOptOut(true);
    EventTracker.track('b');
    expect(queue.pending, isEmpty);
    await EventTracker.setOptOut(false);
    EventTracker.track('c');
    expect(queue.pending.map((e) => e.event), ['c']);
  });

  testWidgets('events tracked while widgets build are kept (first screen, initState)', (tester) async {
    await tester.runAsync(() => start());
    await tester.pumpWidget(UncontrolledProviderScope(
      container: EventTracker.container,
      child: const _TracksInInitState(),
    ));
    await tester.pump();
    expect(queue.pending.map((e) => e.event), ['opened_during_build']);
  });
}

class _TracksInInitState extends StatefulWidget {
  const _TracksInInitState();

  @override
  State<_TracksInInitState> createState() => _TracksInInitStateState();
}

class _TracksInInitStateState extends State<_TracksInInitState> {
  @override
  void initState() {
    super.initState();
    EventTracker.track('opened_during_build');
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
