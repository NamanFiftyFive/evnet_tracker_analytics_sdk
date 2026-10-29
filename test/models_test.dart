import 'dart:convert';

import 'package:event_tracker_analytics/event_tracker_analytics.dart';
import 'package:event_tracker_analytics/src/storage/tracker_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/harness.dart';

class _Car {
  @override
  String toString() => 'Car(Nexon EV)';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrackedEvent', () {
    test('survives a save and load (JSON round trip)', () {
      final event = TrackedEvent(
        id: 'e1',
        event: r'$screen',
        distinctId: 'u1',
        timestamp: DateTime.utc(2026, 10, 20, 10, 30),
        sessionId: 's1',
        screenName: 'Home',
        path: '/home',
        properties: const {'a': 1},
      );
      final loaded = TrackedEvent.fromJson(jsonDecode(jsonEncode(event.toJson())) as Map<String, dynamic>);
      expect(loaded.toJson(), event.toJson());
    });

    test('optional fields are left out of the JSON', () {
      final json = TrackedEvent(id: 'e1', event: 'a', distinctId: 'u1', timestamp: DateTime.utc(2026)).toJson();
      expect(json.keys, ['id', 'event', 'distinct_id', 'timestamp']);
    });

    test('local times are sent as UTC', () {
      final local = DateTime(2026, 10, 20, 10);
      final json = TrackedEvent(id: 'e1', event: 'a', distinctId: 'u1', timestamp: local).toJson();
      expect(json['timestamp'], local.toUtc().toIso8601String());
      expect(json['timestamp'] as String, endsWith('Z'));
    });

    test('sanitize makes any property JSON-safe', () {
      final clean = TrackedEvent.sanitize({
        'text': 'x', 'number': 1.5, 'flag': true, 'nothing': null,
        'when': DateTime.utc(2026, 10, 20),
        'nested': {1: DateTime.utc(2026), 'list': [_Car()]},
        'set': {'a', 'b'},
        'object': _Car(),
      });
      expect(clean, {
        'text': 'x', 'number': 1.5, 'flag': true, 'nothing': null,
        'when': '2026-10-20T00:00:00.000Z',
        'nested': {'1': '2026-01-01T00:00:00.000Z', 'list': ['Car(Nexon EV)']},
        'set': ['a', 'b'],
        'object': 'Car(Nexon EV)',
      });
      expect(() => jsonEncode(clean), returnsNormally);
    });
  });

  group('Identity', () {
    test('uses the user id once known, the anonymous id before', () {
      expect(const Identity(anonymousId: 'anon').distinctId, 'anon');
      expect(const Identity(anonymousId: 'anon').isIdentified, isFalse);
      expect(const Identity(anonymousId: 'anon', userId: 'u1').distinctId, 'u1');
      expect(const Identity(anonymousId: 'anon', userId: 'u1').isIdentified, isTrue);
    });
  });

  group('DeviceContext', () {
    test('leaves unknown details out of the JSON', () {
      expect(const DeviceContext().toJson(), {'platform': 'flutter'});
    });

    for (final (platform, os, type) in [
      (TargetPlatform.macOS, 'macOS', 'desktop'),
      (TargetPlatform.windows, 'windows', 'desktop'),
      (TargetPlatform.linux, 'linux', 'desktop'),
      (TargetPlatform.fuchsia, 'fuchsia', 'other'),
    ]) {
      test('collect on ${platform.name}', () async {
        resetDevice();
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final context = await DeviceContext.collect();
        expect((context.os, context.deviceType, context.appVersion), (os, type, '2.3.1+45'));
      });
    }

    test('collect never throws and still sends the app version', () async {
      // Device plugins aren't available in tests, which is the "plugin missing" path.
      resetDevice();
      final context = await DeviceContext.collect();
      expect(context.appVersion, '2.3.1+45');
      expect(context.os, isNotNull);
    });
  });

  group('QueueState.copyWith', () {
    test('keeps unchanged fields and can clear the error', () {
      const state = QueueState(sentCount: 3, failedAttempts: 2, lastError: 'boom');
      expect(state.copyWith(isFlushing: true).lastError, 'boom');
      expect(state.copyWith(isFlushing: true).sentCount, 3);
      expect(state.copyWith(clearError: true).lastError, isNull);
    });
  });

  group('TrackerStorage', () {
    test('corrupted saved queue loads as empty instead of crashing', () async {
      SharedPreferences.setMockInitialValues({'event_tracker.queue': 'not json ['});
      final storage = await TrackerStorage.open();
      expect(storage.loadQueue(), isEmpty);
    });

    test('remembers user, opt-out and queue', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await TrackerStorage.open();
      await storage.setUserId('u1');
      await storage.setOptedOut(true);
      await storage.saveQueue([TrackedEvent(id: 'e1', event: 'a', distinctId: 'u1', timestamp: DateTime.utc(2026))]);

      final reopened = await TrackerStorage.open();
      expect((reopened.userId, reopened.optedOut), ('u1', true));
      expect(reopened.loadQueue().single.id, 'e1');
      await reopened.setUserId(null);
      expect(reopened.userId, isNull);
    });
  });
}
