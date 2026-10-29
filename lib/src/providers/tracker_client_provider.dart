import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/tracked_event.dart';
import 'event_queue_provider.dart';
import 'identity_provider.dart';
import 'session_provider.dart';
import 'tracker_setup_provider.dart';

/// Builds events (id, time, user, session, screen) and hands them to the queue.
/// `EventTracker` calls this; Riverpod apps can also use it via `eventTrackerClientProvider`.
class EventTrackerClient {
  EventTrackerClient(this._ref);

  final Ref _ref;

  bool get optedOut => requireSetup(_ref).storage.optedOut;

  void track(
    String event, {
    Map<String, Object?> properties = const {},
    String? screenName,
    String? path,
  }) {
    if (optedOut || event.isEmpty) return;
    final now = DateTime.now().toUtc();
    final sessionId = _ref.read(sessionProvider.notifier).touch(now);
    _ref.read(eventQueueProvider.notifier).add(
          TrackedEvent(
            id: const Uuid().v4(),
            event: event,
            distinctId: _ref.read(identityProvider).distinctId,
            timestamp: now,
            sessionId: sessionId,
            screenName: screenName ?? _ref.read(currentScreenProvider),
            path: path,
            properties: TrackedEvent.sanitize(properties),
          ),
        );
  }

  /// Records a screen view and remembers it as the current screen.
  void screen(String name, {Map<String, Object?> properties = const {}}) {
    _ref.read(currentScreenProvider.notifier).set(name);
    track(r'$screen', properties: properties, screenName: name);
  }

  /// After login: later events use `userId`; `traits` are saved on the user (e.g. city, plan).
  Future<void> identify(String userId, {Map<String, Object?> traits = const {}}) async {
    if (optedOut || userId.isEmpty) return;
    final previousAnonymousId = _ref.read(identityProvider).anonymousId;
    await _ref.read(identityProvider.notifier).identify(userId);
    track(r'$identify', properties: {...traits, r'$anon_distinct_id': previousAnonymousId});
  }

  /// On logout: sends what's waiting, then continues as a new anonymous visitor.
  Future<void> reset() async {
    await flush();
    await _ref.read(identityProvider.notifier).reset();
    _ref.read(sessionProvider.notifier).end();
    _ref.read(currentScreenProvider.notifier).set(null);
  }

  Future<void> flush() => _ref.read(eventQueueProvider.notifier).flush(force: true);

  /// Opting out stops tracking and deletes events not sent yet.
  Future<void> setOptOut(bool value) async {
    await requireSetup(_ref).storage.setOptedOut(value);
    if (value) _ref.read(eventQueueProvider.notifier).clear();
  }
}

final eventTrackerClientProvider = Provider<EventTrackerClient>(EventTrackerClient.new);
