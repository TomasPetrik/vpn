import 'dart:convert';

import 'package:flutter/foundation.dart';

class ApiCallEntry {
  ApiCallEntry({
    required this.id,
    required this.method,
    required this.uri,
    required this.startedAt,
    this.requestHeaders = const {},
    this.requestBody,
    this.statusCode,
    this.responseBody,
    this.errorMessage,
    this.duration,
  });

  final String id;
  final String method;
  final Uri uri;
  final DateTime startedAt;
  final Map<String, String> requestHeaders;
  final String? requestBody;
  int? statusCode;
  String? responseBody;
  String? errorMessage;
  Duration? duration;

  String get pathWithQuery {
    final path = uri.path.isEmpty ? '/' : uri.path;
    if (uri.hasQuery) {
      return '$path?${uri.query}';
    }
    return path;
  }

  bool get isSuccess {
    final code = statusCode;
    return code != null && code >= 200 && code < 400;
  }
}

/// In-memory log of HTTP calls for the current app process (dev mode only).
class ApiTrafficLog extends ChangeNotifier {
  final List<ApiCallEntry> _entries = [];
  int _seq = 0;

  List<ApiCallEntry> get entries => List.unmodifiable(_entries.reversed);

  int get count => _entries.length;

  ApiCallEntry start({
    required String method,
    required Uri uri,
    Map<String, String> requestHeaders = const {},
    Object? requestBody,
  }) {
    _seq += 1;
    final entry = ApiCallEntry(
      id: '$_seq',
      method: method.toUpperCase(),
      uri: uri,
      startedAt: DateTime.now(),
      requestHeaders: _redactHeaders(requestHeaders),
      requestBody: _stringifyBody(requestBody),
    );
    _entries.add(entry);
    notifyListeners();
    return entry;
  }

  void complete(
    ApiCallEntry entry, {
    int? statusCode,
    Object? responseBody,
    String? errorMessage,
  }) {
    entry
      ..statusCode = statusCode
      ..responseBody = _stringifyBody(responseBody)
      ..errorMessage = errorMessage
      ..duration = DateTime.now().difference(entry.startedAt);
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  static Map<String, String> _redactHeaders(Map<String, String> headers) {
    final out = <String, String>{};
    headers.forEach((key, value) {
      if (key.toLowerCase() == 'authorization') {
        out[key] = 'Bearer ***';
      } else {
        out[key] = value;
      }
    });
    return out;
  }

  static String? _stringifyBody(Object? body) {
    if (body == null) {
      return null;
    }
    if (body is String) {
      return _truncate(body);
    }
    try {
      return _truncate(const JsonEncoder.withIndent('  ').convert(body));
    } catch (_) {
      return _truncate(body.toString());
    }
  }

  static String _truncate(String value, {int max = 8000}) {
    if (value.length <= max) {
      return value;
    }
    return '${value.substring(0, max)}…';
  }
}
