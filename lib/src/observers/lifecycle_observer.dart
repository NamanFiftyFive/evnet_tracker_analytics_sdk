import 'package:flutter/widgets.dart';

import '../event_tracker.dart';

/// Tracks the app going to the background and coming back, and sends queued events when
/// the app is hidden (it may be killed afterwards).
class TrackerLifecycleObserver with WidgetsBindingObserver {
  bool _wasHidden = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
        if (_wasHidden) return;
        _wasHidden = true;
        EventTracker.track(r'$app_background');
        EventTracker.flush();
      case AppLifecycleState.resumed:
        // Only after a real background, not after e.g. pulling down the notification shade.
        if (!_wasHidden) return;
        _wasHidden = false;
        EventTracker.track(r'$app_foreground');
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        break;
    }
  }
}
