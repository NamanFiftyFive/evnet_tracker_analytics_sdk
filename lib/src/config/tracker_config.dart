/// Settings passed once to `EventTracker.init`.
class TrackerConfig {
  const TrackerConfig({
    required this.apiKey,
    this.host = defaultHost,
    this.flushInterval = const Duration(seconds: 10),
    this.flushAt = 20,
    this.maxBatchSize = 100,
    this.maxQueueSize = 1000,
    this.sessionTimeout = const Duration(minutes: 30),
    this.trackAppLifecycle = true,
    this.debug = false,
    this.ingestPath = '/api/v1/ingest/batch',
    this.devServer,
  });

  /// The hosted analytics server. Apps only set [host] for a local or self-hosted backend.
  static const defaultHost = 'https://analytics-tracker-backend.fly.dev';

  /// The project's API key from the dashboard, e.g. `pk_live_...`.
  final String apiKey;

  /// Base URL of the analytics server; defaults to [defaultHost].
  /// Local backend: `http://localhost:8000` (Android emulator: `http://10.0.2.2:8000`).
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

  /// The local dev dashboard, e.g. `http://localhost:7777`. In debug builds each event is also
  /// copied there as it is tracked, to watch events live. Ignored in release builds.
  final String? devServer;

  Uri get ingestUri => Uri.parse(_trimSlashes(host) + ingestPath);

  /// Where the dev copy of events goes; null when [devServer] is not set.
  Uri? get devServerUri {
    final server = devServer;
    return server == null || server.isEmpty ? null : Uri.parse('${_trimSlashes(server)}/events');
  }

  static String _trimSlashes(String url) => url.replaceAll(RegExp(r'/+$'), '');
}
