/// Event tracking SDK for the Analytics platform.
///
/// ```dart
/// await EventTracker.init(const TrackerConfig(apiKey: 'pk_live_...', host: 'https://analytics.example.com'));
/// MaterialApp(navigatorObservers: [EventTracker.screenObserver()]);
/// EventTracker.track('test_drive_booked', {'model': 'Nexon EV'});
/// ```
library;

export 'src/config/tracker_config.dart';
export 'src/event_tracker.dart';
export 'src/models/device_context.dart';
export 'src/models/identity.dart';
export 'src/models/queue_state.dart';
export 'src/models/session.dart';
export 'src/models/tracked_event.dart';
export 'src/observers/screen_observer.dart';
export 'src/providers/event_queue_provider.dart' show eventQueueProvider, eventTransportProvider, EventQueueNotifier;
export 'src/providers/identity_provider.dart' show identityProvider, IdentityNotifier;
export 'src/providers/session_provider.dart'
    show sessionProvider, currentScreenProvider, SessionNotifier, CurrentScreenNotifier;
export 'src/providers/tracker_client_provider.dart' show eventTrackerClientProvider, EventTrackerClient;
export 'src/transport/event_transport.dart';
