import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/tracker_config.dart';
import '../models/device_context.dart';
import '../storage/tracker_storage.dart';

/// Everything fixed at `EventTracker.init`: settings, on-device storage and device details.
class TrackerSetup {
  const TrackerSetup({required this.config, required this.storage, required this.context});

  final TrackerConfig config;
  final TrackerStorage storage;
  final DeviceContext context;
}

class TrackerSetupNotifier extends Notifier<TrackerSetup?> {
  @override
  TrackerSetup? build() => null;

  void set(TrackerSetup setup) => state = setup;
}

/// Null until `EventTracker.init` has run.
final trackerSetupProvider = NotifierProvider<TrackerSetupNotifier, TrackerSetup?>(TrackerSetupNotifier.new);

/// For providers that only work after init.
TrackerSetup requireSetup(Ref ref) {
  final setup = ref.watch(trackerSetupProvider);
  if (setup == null) {
    throw StateError('EventTracker is not initialized. Call EventTracker.init(...) first.');
  }
  return setup;
}
