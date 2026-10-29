import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/tracker_config.dart';
import '../models/device_context.dart';
import '../models/tracked_event.dart';

enum SendOutcome {
  /// Server accepted the batch: remove it from the queue.
  success,

  /// Network problem, timeout, 429 or 5xx: keep the batch and try again later.
  retryLater,

  /// 401/403/413/422: sending the same batch again won't help, so drop it.
  dropBatch,
}

class SendResult {
  const SendResult(this.outcome, {this.statusCode, this.message});

  final SendOutcome outcome;
  final int? statusCode;
  final String? message;
}

/// Sends one batch to `POST /api/v1/ingest/batch` with the project's API key.
class EventTransport {
  EventTransport(this.config, this.client);

  final TrackerConfig config;
  final http.Client client;

  static const _timeout = Duration(seconds: 15);

  Future<SendResult> send(DeviceContext context, List<TrackedEvent> events) async {
    try {
      final response = await client
          .post(
            config.ingestUri,
            headers: {'Content-Type': 'application/json', 'X-API-Key': config.apiKey},
            body: jsonEncode({
              'context': context.toJson(),
              'events': events.map((e) => e.toJson()).toList(),
            }),
          )
          .timeout(_timeout);

      final code = response.statusCode;
      if (code >= 200 && code < 300) return SendResult(SendOutcome.success, statusCode: code);
      final message = _errorMessage(response.body) ?? 'HTTP $code';
      if (code == 429 || code >= 500) {
        return SendResult(SendOutcome.retryLater, statusCode: code, message: message);
      }
      return SendResult(SendOutcome.dropBatch, statusCode: code, message: message);
    } on TimeoutException {
      return const SendResult(SendOutcome.retryLater, message: 'Request timed out');
    } catch (error) {
      return SendResult(SendOutcome.retryLater, message: 'Network error: $error');
    }
  }

  /// The server answers errors as {"status": ..., "error": "..."}.
  static String? _errorMessage(String body) {
    try {
      final json = jsonDecode(body);
      return json is Map ? json['error']?.toString() : null;
    } catch (_) {
      return null;
    }
  }
}
