import 'package:flutter/widgets.dart';

import '../event_tracker.dart';

/// Add to `MaterialApp(navigatorObservers: [...])` to record a `$screen` event on every
/// page change. Uses the route name (`RouteSettings(name: ...)` or named routes); routes
/// without a name, dialogs and bottom sheets are ignored.
class TrackerScreenObserver extends NavigatorObserver {
  TrackerScreenObserver({this.screenName});

  /// Optional: turn a route into a screen name, e.g. to drop ids from '/cars/42'.
  final String? Function(RouteSettings settings)? screenName;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _record(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _record(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _record(previousRoute);

  void _record(Route<dynamic>? route) {
    if (route is! PageRoute) return;
    final name = screenName?.call(route.settings) ?? route.settings.name;
    if (name == null || name.isEmpty) return;
    EventTracker.screen(name);
  }
}
