import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/identity.dart';
import 'tracker_setup_provider.dart';

class IdentityNotifier extends Notifier<Identity> {
  @override
  Identity build() {
    final storage = requireSetup(ref).storage;
    var anonymousId = storage.anonymousId;
    if (anonymousId == null) {
      // First launch on this device.
      anonymousId = const Uuid().v4();
      unawaited(storage.setAnonymousId(anonymousId));
    }
    return Identity(anonymousId: anonymousId, userId: storage.userId);
  }

  Future<void> identify(String userId) async {
    state = Identity(anonymousId: state.anonymousId, userId: userId);
    await requireSetup(ref).storage.setUserId(userId);
  }

  /// On logout: forget the user and start as a new anonymous visitor.
  Future<void> reset() async {
    final storage = requireSetup(ref).storage;
    final anonymousId = const Uuid().v4();
    state = Identity(anonymousId: anonymousId);
    await storage.setAnonymousId(anonymousId);
    await storage.setUserId(null);
  }
}

final identityProvider = NotifierProvider<IdentityNotifier, Identity>(IdentityNotifier.new);
