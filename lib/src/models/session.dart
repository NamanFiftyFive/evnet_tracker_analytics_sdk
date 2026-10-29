/// One visit to the app. Ends after `TrackerConfig.sessionTimeout` without events.
class Session {
  const Session({required this.id, required this.startedAt, required this.lastActivityAt});

  final String id;
  final DateTime startedAt;
  final DateTime lastActivityAt;

  Session touched(DateTime now) => Session(id: id, startedAt: startedAt, lastActivityAt: now);
}
