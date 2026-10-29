import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/tracker_config.dart';
import 'models/device_context.dart';
import 'observers/lifecycle_observer.dart';
import 'observers/screen_observer.dart';
import 'providers/event_queue_provider.dart';
import 'providers/tracker_client_provider.dart';
import 'providers/tracker_setup_provider.dart';
import 'storage/tracker_storage.dart';

/// The SDK's entry point. Call `init` once, then `track`, `screen`, `identify` anywhere.
///
/// Every method is safe to call at any time: before `init` it does nothing, and errors inside
/// the SDK are caught and logged, never thrown into the app.
abstract final class EventTracker {
  static ProviderContainer? _container;
  static TrackerLifecycleObserver? _lifecycleObserver;
  static bool _debug = false;

  static bool get isInitialized => _container != null;

  /// The Riverpod container holding the SDK's state. Riverpod apps can pass their own to
  /// `init` and watch `eventQueueProvider`, `identityProvider`, `sessionProvider`, ...
  static ProviderContainer get container {
    final container = _container;
    if (container == null) {
      throw StateError('EventTracker is not initialized. Call EventTracker.init(...) first.');
    }
    return container;
  }

  /// Sets up the SDK: loads the saved user and unsent events, reads device details, starts
  /// the send timer and (by default) app lifecycle tracking.
  static Future<void> init(TrackerConfig config, {ProviderContainer? container}) async {
    if (_container != null) {
      _log('init called twice; ignoring the second call');
      return;
    }
    _debug = config.debug;
    WidgetsFlutterBinding.ensureInitialized();

    final setup = TrackerSetup(
      config: config,
      storage: await TrackerStorage.open(),
      context: await DeviceContext.collect(),
    );
    final c = container ?? ProviderContainer();
    c.read(trackerSetupProvider.notifier).set(setup);
    c.read(eventQueueProvider); // loads unsent events and starts the flush timer
    _container = c;
    _log('initialized for ${config.ingestUri} (${setup.context.toJson()})');

    if (config.trackAppLifecycle) {
      _lifecycleObserver = TrackerLifecycleObserver();
      WidgetsBinding.instance.addObserver(_lifecycleObserver!);
      track(r'$app_open');
    }
  }

  /// A business event, e.g. `track('test_drive_booked', {'model': 'Nexon EV'})`.
  static void track(String event, [Map<String, Object?> properties = const {}]) =>
      _run('track', (client) => client.track(event, properties: properties));

  /// A screen view (done automatically by [screenObserver] for named routes).
  static void screen(String name, [Map<String, Object?> properties = const {}]) =>
      _run('screen', (client) => client.screen(name, properties: properties));

  /// After login. Traits are stored on the user, e.g. `{'city': 'Pune', 'plan': 'premium'}`.
  static Future<void> identify(String userId, [Map<String, Object?> traits = const {}]) =>
      _runAsync('identify', (client) => client.identify(userId, traits: traits));

  /// On logout.
  static Future<void> reset() => _runAsync('reset', (client) => client.reset());

  /// Send everything waiting now (it's also sent automatically).
  static Future<void> flush() => _runAsync('flush', (client) => client.flush());

  /// Stop (true) or resume (false) tracking for this device. Remembered across launches.
  static Future<void> setOptOut(bool value) => _runAsync('setOptOut', (client) => client.setOptOut(value));

  /// `MaterialApp(navigatorObservers: [EventTracker.screenObserver()])`
  static NavigatorObserver screenObserver({String? Function(RouteSettings settings)? screenName}) =>
      TrackerScreenObserver(screenName: screenName);

  /// Stops the SDK. Mainly for tests; apps normally keep it running.
  static Future<void> dispose({bool disposeContainer = true}) async {
    final observer = _lifecycleObserver;
    if (observer != null) WidgetsBinding.instance.removeObserver(observer);
    _lifecycleObserver = null;
    if (disposeContainer) _container?.dispose();
    _container = null;
  }

  // ── Safety wrappers: the SDK must never crash or block the host app ────────

  static void _run(String action, void Function(EventTrackerClient client) body) {
    final container = _container;
    if (container == null) {
      _log('$action ignored: call EventTracker.init first');
      return;
    }
    if (_isBuilding) {
      // e.g. the Navigator pushing the first screen, or track() in initState/build.
      scheduleMicrotask(() => _run(action, body));
      return;
    }
    try {
      body(container.read(eventTrackerClientProvider));
    } catch (error, stack) {
      _log('$action failed: $error\n$stack');
    }
  }

  static Future<void> _runAsync(String action, Future<void> Function(EventTrackerClient client) body) async {
    final container = _container;
    if (container == null) {
      _log('$action ignored: call EventTracker.init first');
      return;
    }
    if (_isBuilding) await Future<void>.microtask(() {});
    try {
      await body(container.read(eventTrackerClientProvider));
    } catch (error, stack) {
      _log('$action failed: $error\n$stack');
    }
  }

  /// True while Flutter is building/laying out widgets. Riverpod doesn't allow state changes
  /// then, so calls made at that moment are run right after (in a microtask, same order).
  static bool get _isBuilding =>
      SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks;

  static void _log(String message) {
    if (_debug) debugPrint('[EventTracker] $message');
  }
}
