# event_tracker_analytics

Flutter SDK for the Analytics platform. Add it to any Flutter app (Android, iOS, web, desktop):
it records screens, sessions, app open/background and your own business events, keeps them on
the device, and sends them in batches to the backend's `POST /api/v1/ingest/batch`.

- Flutter **3.47.0** via FVM (`.fvmrc`) · state with **Riverpod 3**
- Never crashes or blocks the host app: every SDK error is caught; calls before `init` are ignored.

## How it works

```
EventTracker.track(...)        your code (or automatic: screens, app lifecycle)
   │  adds id, time, user, session, current screen
   ▼
eventQueueProvider             saved on the device first (survives offline / app kill)
   │  sent when 20 events wait, every 10 s, or when the app goes to the background
   ▼
EventTransport                 POST /api/v1/ingest/batch   X-API-Key: pk_live_…
   │  success → removed from the queue
   │  network error / 5xx / 429 → kept, retried after 2 s, 4 s, 8 s … (max 5 min)
   │  401 / 403 / 413 / 422 → dropped (retrying won't help), shown in lastError
   ▼
Backend → events, persons, sessions, event_definitions
```

## Use it in an app

**1. Add the dependency** (`pubspec.yaml` of the app):

```yaml
dependencies:
  event_tracker_analytics:
    path: ../event_tracker_analytics        # local, e.g. this repo's test app
  # or from git:
  #   git: { url: https://github.com/<you>/<repo>.git, path: event_tracker_analytics }
```

**2. Initialize once** with the project's API key (dashboard → project → API keys):

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EventTracker.init(const TrackerConfig(
    apiKey: 'pk_live_…',
    host: 'http://localhost:8000',   // Android emulator: http://10.0.2.2:8000
    debug: true,                     // log to the console while developing
  ));
  runApp(const CarApp());
}
```

**3. Track screens automatically** (named routes or `RouteSettings(name: ...)`):

```dart
MaterialApp(navigatorObservers: [EventTracker.screenObserver()], ...)
```

**4. Identify the user after login, reset on logout:**

```dart
await EventTracker.identify('customer_1042', {'city': 'Pune', 'plan': 'premium'});
await EventTracker.reset();
```

**5. Track business events:**

```dart
EventTracker.track('car_viewed', {'model': 'Nexon EV', 'price': 1450000});
EventTracker.track('test_drive_booked', {'model': 'Nexon EV', 'showroom': 'Baner'});
```

## API

| Call | What it does |
|---|---|
| `EventTracker.init(config, {container})` | Set up once; loads saved user + unsent events, reads device info |
| `EventTracker.track(name, [properties])` | Business event; current screen is attached |
| `EventTracker.screen(name, [properties])` | `$screen` event + sets the current screen |
| `EventTracker.identify(userId, [traits])` | Later events use `userId`; traits are stored on the user |
| `EventTracker.reset()` | Logout: sends what's waiting, new anonymous id, new session |
| `EventTracker.flush()` | Send now |
| `EventTracker.setOptOut(bool)` | Stop/resume tracking on this device (remembered) |
| `EventTracker.screenObserver({screenName})` | `NavigatorObserver` for automatic screen tracking |

Automatic events: `$app_open`, `$app_foreground`, `$app_background` (turn off with
`trackAppLifecycle: false`), `$screen` (with the observer), `$identify`.

`TrackerConfig` options: `flushInterval` (10 s), `flushAt` (20), `maxBatchSize` (100),
`maxQueueSize` (1000), `sessionTimeout` (30 min), `trackAppLifecycle` (true), `debug` (false).

## Riverpod

The SDK's state lives in Riverpod providers. Apps using Riverpod can share one container and
watch the SDK, e.g. for a debug panel:

```dart
final container = ProviderContainer();
await EventTracker.init(config, container: container);
runApp(UncontrolledProviderScope(container: container, child: const CarApp()));

// in a ConsumerWidget
final queue = ref.watch(eventQueueProvider);      // pending, isFlushing, sentCount, lastError
final identity = ref.watch(identityProvider);     // anonymousId, userId
final session = ref.watch(sessionProvider);       // id, startedAt
```

| Provider | State |
|---|---|
| `eventQueueProvider` | `QueueState`: pending events, isFlushing, sentCount, droppedCount, failedAttempts, lastError |
| `identityProvider` | `Identity`: anonymousId, userId, distinctId |
| `sessionProvider` | `Session?`: id, startedAt, lastActivityAt |
| `currentScreenProvider` | `String?`: current screen name |
| `eventTrackerClientProvider` | `EventTrackerClient`: same methods as `EventTracker` |
| `eventTransportProvider` | `EventTransport`: override in tests with a fake |

Apps without Riverpod just use `EventTracker`; no setup needed.

## Code layout

```
lib/
├── event_tracker_analytics.dart     public exports
└── src/
    ├── event_tracker.dart           EventTracker: static API + safety wrappers
    ├── config/tracker_config.dart
    ├── models/                      TrackedEvent, DeviceContext, Identity, Session, QueueState
    ├── providers/                   Riverpod notifiers: setup, identity, session, queue, client
    ├── storage/tracker_storage.dart shared_preferences: ids, opt-out, unsent events
    ├── transport/event_transport.dart  HTTP to /ingest/batch, success / retry / drop
    └── observers/                   screen (NavigatorObserver) + app lifecycle
test/
├── helpers/harness.dart             FakeTransport, start(), resetDevice()
├── event_tracker_test.dart          track / identify / reset / sessions / restart / opt-out / build phase
├── transport_test.dart              HTTP request shape; which answers retry (429, 5xx, offline, timeout) or drop
├── queue_test.dart                  queue limit, flush timer, retry back-off 2 s → 5 min, sends during a send, never crashes
├── observers_test.dart              screen views (push / pop / replace / dialogs / custom names), app lifecycle
└── models_test.dart                 JSON round trip, sanitize, identity, device context, storage
```

## Development

```bash
cd event_tracker_analytics
fvm flutter pub get
fvm flutter analyze
fvm flutter test                 # 59 tests, no network or device needed
fvm flutter test --coverage      # ~94%; the rest is Android/iOS device details that need a real device
```

Timer tests use Flutter's fake clock, so a 5-minute retry delay takes no real time.

## Notes

- Calls made while Flutter is building widgets (e.g. the first route push, `initState`) are run right
  after the build, because Riverpod doesn't allow state changes during a build. Order is kept.

- Before `identify`, events use an anonymous id; `$identify` stores `$anon_distinct_id` so the two can
  be linked later on the server.
- Web: events are sent when 20 are waiting, every 10 s, and when the tab is hidden. Events from the last
  few seconds before a tab is closed may be lost (a `sendBeacon` path is planned).
