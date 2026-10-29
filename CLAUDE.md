# event_tracker_analytics (Flutter SDK)

SDK that apps add to send analytics events to `../backend` (`POST /api/v1/ingest/batch`, header `X-API-Key`).
Full docs: `README.md`. Backend context: `../backend/CLAUDE.md`.

- Flutter **3.47.0 via FVM**: always run `fvm flutter ...` (`fvm flutter analyze`, `fvm flutter test`). Keep analyze at 0 issues.
- State: **Riverpod 3** (`Notifier`/`NotifierProvider`, no code generation). Providers in `lib/src/providers/`.
- Public API is the static `EventTracker` (lib/src/event_tracker.dart); it must never throw into the host app.
- Event JSON must match the backend's `IngestEvent` (id, event, distinct_id, timestamp, session_id, screen_name, path, properties).
- Tests (59, see README tree): `test/helpers/harness.dart` has `FakeTransport` (via `eventTransportProvider.overrideWithValue(...)`), `start()`, `resetDevice()`. Timers: `startOnFakeTime` in queue_test; flutter_test blocks real HTTP
  (set `HttpOverrides.global = null` for a live-backend check, and delete that test afterwards).
- **Guardrails** (`.claude/settings.json` + `.claude/hooks/guard.py`, changed by people only): blocked = editing/reading `.env` and keys, `pubspec.lock`, destructive shell commands; asks a person = `git push`, `pub add/upgrade`. After code edits, `flutter analyze` + `flutter test` must pass before finishing (Stop hook). If blocked, don't work around it: tell the user.
- User preferences: OOP, explain *why*, one step at a time, update README when changing behaviour.
