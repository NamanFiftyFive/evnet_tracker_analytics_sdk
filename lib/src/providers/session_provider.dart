import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/session.dart';
import 'tracker_setup_provider.dart';

class SessionNotifier extends Notifier<Session?> {
  @override
  Session? build() => null;

  /// Called for every event. Returns the session id to put on it, starting a new session
  /// on the first event or after `sessionTimeout` of inactivity.
  String touch(DateTime now) {
    final timeout = requireSetup(ref).config.sessionTimeout;
    final current = state;
    final next = (current == null || now.difference(current.lastActivityAt) > timeout)
        ? Session(id: const Uuid().v4(), startedAt: now, lastActivityAt: now)
        : current.touched(now);
    state = next;
    return next.id;
  }

  /// The next event starts a new session (used on logout).
  void end() => state = null;
}

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);

/// The screen the user is on; attached to events tracked without an explicit screen.
class CurrentScreenNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? name) => state = name;
}

final currentScreenProvider = NotifierProvider<CurrentScreenNotifier, String?>(CurrentScreenNotifier.new);
