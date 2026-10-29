import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/queue_state.dart';
import '../models/tracked_event.dart';
import '../transport/event_transport.dart';
import 'tracker_setup_provider.dart';

/// Override in tests (`eventTransportProvider.overrideWithValue(fake)`) to avoid real HTTP.
final eventTransportProvider = Provider<EventTransport>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return EventTransport(requireSetup(ref).config, client);
});

/// The on-device event queue: saves events first, sends them in batches, retries on failure.
class EventQueueNotifier extends Notifier<QueueState> {
  Timer? _flushTimer;
  Timer? _retryTimer;

  static const _maxRetryDelay = Duration(minutes: 5);

  @override
  QueueState build() {
    final setup = requireSetup(ref);
    _flushTimer = Timer.periodic(setup.config.flushInterval, (_) => flush());
    ref.onDispose(() {
      _flushTimer?.cancel();
      _retryTimer?.cancel();
    });
    // Events left over from the last launch are sent on the next flush.
    return QueueState(pending: setup.storage.loadQueue());
  }

  void add(TrackedEvent event) {
    final setup = requireSetup(ref);
    final config = setup.config;
    if (config.devServerUri != null) {
      unawaited(ref.read(eventTransportProvider).sendToDevServer(setup.context, [event]));
    }
    var pending = [...state.pending, event];
    if (pending.length > config.maxQueueSize) {
      pending = pending.sublist(pending.length - config.maxQueueSize); // drop the oldest
    }
    state = state.copyWith(pending: pending);
    _persist();
    if (pending.length >= config.flushAt) unawaited(flush());
  }

  /// Sends everything waiting, in batches. While a retry is scheduled after a failure, timer
  /// calls are skipped; `force` (EventTracker.flush) sends anyway.
  Future<void> flush({bool force = false}) async {
    if (state.isFlushing || state.pending.isEmpty) return;
    if (!force && (_retryTimer?.isActive ?? false)) return;
    _retryTimer?.cancel();

    final setup = requireSetup(ref);
    final transport = ref.read(eventTransportProvider);
    state = state.copyWith(isFlushing: true);
    try {
      while (state.pending.isNotEmpty) {
        final batch = state.pending.take(setup.config.maxBatchSize).toList();
        final result = await transport.send(setup.context, batch);
        if (!ref.mounted) return;

        if (result.outcome == SendOutcome.retryLater) {
          _scheduleRetry(state.failedAttempts + 1);
          state = state.copyWith(failedAttempts: state.failedAttempts + 1, lastError: result.message);
          return;
        }

        // Sent or refused for good: either way these events leave the queue. Events added
        // while the request was running stay.
        final ids = batch.map((e) => e.id).toSet();
        final delivered = result.outcome == SendOutcome.success;
        state = state.copyWith(
          pending: state.pending.where((e) => !ids.contains(e.id)).toList(),
          sentCount: delivered ? state.sentCount + batch.length : null,
          droppedCount: delivered ? null : state.droppedCount + batch.length,
          failedAttempts: 0,
          lastError: delivered ? null : result.message,
          clearError: delivered,
        );
        _persist();
      }
    } finally {
      if (ref.mounted) state = state.copyWith(isFlushing: false);
    }
  }

  /// Removes everything waiting (used when the user opts out).
  void clear() {
    state = state.copyWith(pending: const []);
    _persist();
  }

  /// 2 s, 4 s, 8 s, ... up to 5 minutes between attempts.
  void _scheduleRetry(int attempt) {
    final seconds = min(pow(2, attempt).toInt(), _maxRetryDelay.inSeconds);
    _retryTimer = Timer(Duration(seconds: seconds), () => flush(force: true));
  }

  void _persist() => unawaited(requireSetup(ref).storage.saveQueue(state.pending));
}

final eventQueueProvider = NotifierProvider<EventQueueNotifier, QueueState>(EventQueueNotifier.new);
