import 'dart:async';
import 'dart:convert';

import 'package:event_tracker_analytics/event_tracker_analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// EventTransport against a fake HTTP server (MockClient): what it sends and how it reads
/// each kind of answer.
void main() {
  const config = TrackerConfig(apiKey: 'pk_live_abc', host: 'https://analytics.example.com/');
  const context = DeviceContext(os: 'Android 14', deviceType: 'mobile', appVersion: '2.3.1+45');
  final event = TrackedEvent(
    id: 'e1',
    event: 'car_viewed',
    distinctId: 'anon-1',
    timestamp: DateTime.utc(2026, 10, 20, 10),
    sessionId: 's1',
    properties: const {'model': 'Nexon EV'},
  );

  Future<SendResult> sendWith(http.Client client) => EventTransport(config, client).send(context, [event]);

  MockClient answering(int status, [Object? body]) =>
      MockClient((_) async => http.Response(body == null ? '' : jsonEncode(body), status));

  test('posts the batch with the API key in the server format', () async {
    late http.Request request;
    final result = await sendWith(MockClient((r) async {
      request = r;
      return http.Response('{"status":202,"data":{}}', 202);
    }));

    expect(result.outcome, SendOutcome.success);
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://analytics.example.com/api/v1/ingest/batch');
    expect(request.headers['X-API-Key'], 'pk_live_abc');
    expect(request.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(request.body), {
      'context': {'platform': 'flutter', 'os': 'Android 14', 'device_type': 'mobile', 'app_version': '2.3.1+45'},
      'events': [
        {
          'id': 'e1',
          'event': 'car_viewed',
          'distinct_id': 'anon-1',
          'timestamp': '2026-10-20T10:00:00.000Z',
          'session_id': 's1',
          'properties': {'model': 'Nexon EV'},
        }
      ],
    });
  });

  group('answers that are worth retrying', () {
    for (final status in [429, 500, 502, 503]) {
      test('HTTP $status', () async {
        final result = await sendWith(answering(status, {'status': status, 'error': 'Busy'}));
        expect((result.outcome, result.statusCode, result.message), (SendOutcome.retryLater, status, 'Busy'));
      });
    }

    test('no network', () async {
      final result = await sendWith(MockClient((_) => throw http.ClientException('Failed host lookup')));
      expect(result.outcome, SendOutcome.retryLater);
      expect(result.message, contains('Failed host lookup'));
    });

    testWidgets('no answer within 15 seconds', (tester) async {
      // A server that never answers; fake time lets the timeout pass instantly.
      final result = sendWith(MockClient((_) => Completer<http.Response>().future));
      await tester.pump(const Duration(seconds: 16));
      expect((await result).outcome, SendOutcome.retryLater);
      expect((await result).message, 'Request timed out');
    });
  });

  group('answers where retrying would not help (batch is dropped)', () {
    for (final status in [400, 401, 403, 413, 422]) {
      test('HTTP $status', () async {
        final result = await sendWith(answering(status, {'status': status, 'error': 'Invalid or revoked API key'}));
        expect((result.outcome, result.statusCode), (SendOutcome.dropBatch, status));
        expect(result.message, 'Invalid or revoked API key');
      });
    }

    test('error body that is not JSON', () async {
      final result = await sendWith(MockClient((_) async => http.Response('<html>Bad gateway</html>', 400)));
      expect(result.message, 'HTTP 400');
    });
  });

  test('host with or without a trailing slash gives the same URL', () {
    const withSlash = TrackerConfig(apiKey: 'k', host: 'http://10.0.2.2:8000//');
    const without = TrackerConfig(apiKey: 'k', host: 'http://10.0.2.2:8000');
    expect(withSlash.ingestUri, without.ingestUri);
    expect(without.ingestUri.toString(), 'http://10.0.2.2:8000/api/v1/ingest/batch');
  });
}
