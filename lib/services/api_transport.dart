import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'native_bridge.dart';

/// Raw result of an API call made through [sendApiRequest].
class ApiHttpResult {
  const ApiHttpResult({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

/// Thrown when a request never produced an HTTP response (network error,
/// timeout, URL rejected by the host allowlist, outdated host build).
class ApiTransportException implements Exception {
  ApiTransportException(this.message);

  final String message;

  @override
  String toString() => 'ApiTransportException: $message';
}

/// Performs [method] `GET`/`POST` on [url], returning the raw status + body.
///
/// Inside the native host the request goes through the host's `httpRequest`
/// JS bridge handler (native HTTP — immune to CORS; the host allowlists which
/// URLs it will call, see `native_bridge.dart`). In a plain browser it falls
/// back to a regular `http` fetch, which works only against CORS-enabled
/// endpoints.
Future<ApiHttpResult> sendApiRequest(
  String method,
  Uri url, {
  Map<String, String>? headers,
  String? body,
  Duration timeout = const Duration(seconds: 30),
}) async {
  if (NativeCameraBridge.isSupported) {
    final Map<String, dynamic>? res;
    try {
      res = await NativeCameraBridge.sendHttpRequest(
        method: method,
        url: url.toString(),
        headers: headers,
        body: body,
      ).timeout(timeout);
    } on TimeoutException {
      throw ApiTransportException('timeout: $method $url');
    } catch (e) {
      throw ApiTransportException('bridge error: $e');
    }
    if (res == null) {
      throw ApiTransportException(
          'Host app is outdated (no httpRequest bridge handler)');
    }
    final status = (res['status'] as num?)?.toInt() ?? 0;
    if (status == 0) {
      throw ApiTransportException('unreachable: ${res['error']}');
    }
    return ApiHttpResult(
        statusCode: status, body: (res['body'] ?? '').toString());
  }

  final http.Response res;
  try {
    res = method == 'POST'
        ? await http.post(url, headers: headers, body: body).timeout(timeout)
        : await http.get(url, headers: headers).timeout(timeout);
  } on TimeoutException {
    throw ApiTransportException('timeout: $method $url');
  } catch (e) {
    throw ApiTransportException('unreachable: $e');
  }
  return ApiHttpResult(
      statusCode: res.statusCode, body: utf8.decode(res.bodyBytes));
}
