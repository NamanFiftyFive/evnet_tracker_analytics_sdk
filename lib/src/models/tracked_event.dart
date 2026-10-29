/// One event, as stored in the on-device queue and sent to the server.
class TrackedEvent {
  const TrackedEvent({
    required this.id,
    required this.event,
    required this.distinctId,
    required this.timestamp,
    this.sessionId,
    this.screenName,
    this.path,
    this.properties = const {},
  });

  /// Generated on the device; the server stores an id only once, so retries are safe.
  final String id;
  final String event;
  final String distinctId;
  final DateTime timestamp;
  final String? sessionId;
  final String? screenName;
  final String? path;
  final Map<String, Object?> properties;

  /// Matches the server's ingest format.
  Map<String, Object?> toJson() => {
        'id': id,
        'event': event,
        'distinct_id': distinctId,
        'timestamp': timestamp.toUtc().toIso8601String(),
        if (sessionId != null) 'session_id': sessionId,
        if (screenName != null) 'screen_name': screenName,
        if (path != null) 'path': path,
        if (properties.isNotEmpty) 'properties': properties,
      };

  factory TrackedEvent.fromJson(Map<String, dynamic> json) => TrackedEvent(
        id: json['id'] as String,
        event: json['event'] as String,
        distinctId: json['distinct_id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        sessionId: json['session_id'] as String?,
        screenName: json['screen_name'] as String?,
        path: json['path'] as String?,
        properties: Map<String, Object?>.from(json['properties'] as Map? ?? const {}),
      );

  /// Makes app-supplied properties safe to send as JSON: dates become ISO strings, nested
  /// maps/lists are cleaned too, and anything else unknown becomes its `toString()`.
  static Map<String, Object?> sanitize(Map<String, Object?> properties) =>
      properties.map((key, value) => MapEntry(key, _sanitizeValue(value)));

  static Object? _sanitizeValue(Object? value) {
    if (value == null || value is String || value is num || value is bool) return value;
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map) return value.map((k, v) => MapEntry(k.toString(), _sanitizeValue(v)));
    if (value is Iterable) return value.map(_sanitizeValue).toList();
    return value.toString();
  }
}
