/// Who the events belong to: an anonymous id created on first launch, replaced by the app's
/// own user id after `identify`.
class Identity {
  const Identity({required this.anonymousId, this.userId});

  final String anonymousId;
  final String? userId;

  /// Sent with every event.
  String get distinctId => userId ?? anonymousId;

  bool get isIdentified => userId != null;
}
