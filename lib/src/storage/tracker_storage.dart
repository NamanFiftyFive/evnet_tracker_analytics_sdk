import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/tracked_event.dart';

/// Everything the SDK keeps on the device between app launches: who the user is, whether
/// they opted out, and events not sent yet (so nothing is lost offline or when the app is killed).
class TrackerStorage {
  TrackerStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _anonymousIdKey = 'event_tracker.anonymous_id';
  static const _userIdKey = 'event_tracker.user_id';
  static const _optOutKey = 'event_tracker.opt_out';
  static const _queueKey = 'event_tracker.queue';

  static Future<TrackerStorage> open() async => TrackerStorage(await SharedPreferences.getInstance());

  String? get anonymousId => _prefs.getString(_anonymousIdKey);
  Future<void> setAnonymousId(String value) => _prefs.setString(_anonymousIdKey, value);

  String? get userId => _prefs.getString(_userIdKey);
  Future<void> setUserId(String? value) =>
      value == null ? _prefs.remove(_userIdKey) : _prefs.setString(_userIdKey, value);

  bool get optedOut => _prefs.getBool(_optOutKey) ?? false;
  Future<void> setOptedOut(bool value) => _prefs.setBool(_optOutKey, value);

  List<TrackedEvent> loadQueue() {
    final raw = _prefs.getString(_queueKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((item) => TrackedEvent.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (_) {
      return []; // corrupted data shouldn't break the host app
    }
  }

  Future<void> saveQueue(List<TrackedEvent> events) =>
      _prefs.setString(_queueKey, jsonEncode(events.map((e) => e.toJson()).toList()));
}
