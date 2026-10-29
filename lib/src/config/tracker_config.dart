/// Settings passed once to `EventTracker.init`.
class TrackerConfig {
  const TrackerConfig({
    required this.apiKey,
    required this.host,
    this.flushInterval = const Duration(seconds: 10),
    this.flushAt = 20,
    this.maxBatchSize = 100,
    this.maxQueueSize = 1000,
    this.sessionTimeout = const Duration(minutes: 30),
    this.trackAppLifecycle = true,
    this.debug = false,
    this.ingestPath = '/api/v1/ingest/batch',
  });

  /// The project's API key from the dashboard, e.g. `pk_live_...`.
  final String apiKey;

  /// Base URL of the analytics server, e.g. `https://analytics.example.com`.
  final String host;

  /// Queued events are sent at least this often.
  final Duration flushInterval;

  /// Send immediately once this many events are waiting.
  final int flushAt;

  /// Most events per request (the server accepts at most 100).
  final int maxBatchSize;

  /// Most events kept on the device while offline; the oldest are dropped beyond this.
  final int maxQueueSize;

  /// A new session starts after this long without any event.
  final Duration sessionTimeout;

  /// Track `$app_open`, `$app_foreground` and `$app_background` automatically.
  final bool trackAppLifecycle;

  /// Print what the SDK does to the debug console.
  final bool debug;

  final String ingestPath;

  Uri get ingestUri => Uri.parse(host.replaceAll(RegExp(r'/+$'), '') + ingestPath);
}
