import 'tracked_event.dart';

/// What the on-device queue is doing. Watch `eventQueueProvider` to show it in a debug screen.
class QueueState {
  const QueueState({
    this.pending = const [],
    this.isFlushing = false,
    this.sentCount = 0,
    this.droppedCount = 0,
    this.failedAttempts = 0,
    this.lastError,
  });

  /// Events waiting to be sent (also saved on the device).
  final List<TrackedEvent> pending;
  final bool isFlushing;

  /// Events delivered since the app started.
  final int sentCount;

  /// Events the server refused for good (e.g. revoked key); they are not retried.
  final int droppedCount;

  /// Failed send attempts in a row; drives the retry delay.
  final int failedAttempts;
  final String? lastError;

  QueueState copyWith({
    List<TrackedEvent>? pending,
    bool? isFlushing,
    int? sentCount,
    int? droppedCount,
    int? failedAttempts,
    String? lastError,
    bool clearError = false,
  }) =>
      QueueState(
        pending: pending ?? this.pending,
        isFlushing: isFlushing ?? this.isFlushing,
        sentCount: sentCount ?? this.sentCount,
        droppedCount: droppedCount ?? this.droppedCount,
        failedAttempts: failedAttempts ?? this.failedAttempts,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}
