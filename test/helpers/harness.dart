import 'dart:async';

import 'package:event_tracker_analytics/event_tracker_analytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records batches instead of sending them; the next outcome can be chosen per test.
/// Set [gate] to hold the next send until the test completes it (to act mid-request).
class FakeTransport extends EventTransport {
  FakeTransport() : super(const TrackerConfig(apiKey: 'pk_test', host: 'http://test'), http.Client());

  final List<List<TrackedEvent>> batches = [];
  SendOutcome nextOutcome = SendOutcome.success;
  Completer<void>? gate;
  Object? throwOnSend;

  List<TrackedEvent> get sent => batches.expand((b) => b).toList();

  @override
  Future<SendResult> send(DeviceContext context, List<TrackedEvent> events) async {
    final error = throwOnSend;
    if (error != null) throw error;
    batches.add(events);
    final wait = gate;
    if (wait != null) await wait.future;
    return SendResult(nextOutcome, message: nextOutcome == SendOutcome.success ? null : 'fake ${nextOutcome.name}');
  }
}

/// Small batches and no automatic sending, so tests decide when events go out.
const testConfig = TrackerConfig(
  apiKey: 'pk_test',
  host: 'http://test',
  flushAt: 3,
  flushInterval: Duration(hours: 1), // only explicit flushes in tests
  trackAppLifecycle: false,
);

late FakeTransport transport;

/// `EventTracker.init` with [FakeTransport] in place of real HTTP.
Future<void> start({TrackerConfig config = testConfig}) async {
  transport = FakeTransport();
  final container = ProviderContainer(overrides: [eventTransportProvider.overrideWithValue(transport)]);
  await EventTracker.init(config, container: container);
}

QueueState get queue => EventTracker.container.read(eventQueueProvider);

List<String> get pendingNames => queue.pending.map((e) => e.event).toList();

/// Fresh device storage and app info before each test.
void resetDevice([Map<String, Object> stored = const {}]) {
  SharedPreferences.setMockInitialValues(stored);
  PackageInfo.setMockInitialValues(
    appName: 'Car App', packageName: 'com.example.car', version: '2.3.1', buildNumber: '45', buildSignature: '',
  );
}
