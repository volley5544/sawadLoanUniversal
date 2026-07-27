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

/// Uploads [fileBytes] as a single `multipart/form-data` file part.
///
/// Unlike [sendApiRequest] this always uses `package:http` directly, even
/// inside the native host: the host's `httpRequest` bridge carries the body as
/// a **JS string**, which cannot round-trip arbitrary binary. That is safe for
/// the srisawad mobile API specifically because it answers with
/// `access-control-allow-origin: *`, so the browser fetch isn't blocked. Do
/// **not** reuse this for the NDID gateway, which sends no CORS headers.
Future<ApiHttpResult> sendMultipartApiRequest(
  Uri url, {
  required String fileField,
  required String fileName,
  required List<int> fileBytes,
  Map<String, String>? headers,
  Map<String, String> fields = const {},
  Duration timeout = const Duration(seconds: 60),
}) async {
  final request = http.MultipartRequest('POST', url)
    ..fields.addAll(fields)
    ..files.add(http.MultipartFile.fromBytes(
      fileField,
      fileBytes,
      filename: fileName,
    ));
  // Let MultipartRequest set Content-Type itself — it has to append the
  // boundary, so a caller-supplied value would break the request.
  if (headers != null) {
    request.headers.addAll(
      Map.of(headers)..removeWhere((k, _) => k.toLowerCase() == 'content-type'),
    );
  }

  final http.Response res;
  try {
    final streamed = await request.send().timeout(timeout);
    res = await http.Response.fromStream(streamed);
  } on TimeoutException {
    throw ApiTransportException('timeout: POST $url');
  } catch (e) {
    throw ApiTransportException('unreachable: $e');
  }
  return ApiHttpResult(
      statusCode: res.statusCode, body: utf8.decode(res.bodyBytes));
}

/// One file part of a [sendMultipartGroupsApiRequest] upload.
class MultipartFilePart {
  const MultipartFilePart({
    required this.field,
    required this.filename,
    required this.bytes,
    this.contentType = 'image/jpeg',
  });

  /// Form field name, including the `[]` when the API expects repeats
  /// (e.g. `carImage[]`).
  final String field;
  final String filename;
  final List<int> bytes;
  final String contentType;
}

/// Posts `multipart/form-data` with any number of fields and repeated file
/// parts, preferring the native host over the browser.
///
/// Unlike [sendMultipartApiRequest] — which always uses `package:http` because
/// its one caller talks to an endpoint that sends
/// `access-control-allow-origin: *` — this routes through the host's
/// `httpMultipart` bridge handler when running inside the host. It exists for
/// the P-Loan save API, which sends **no** CORS headers and 401s the preflight,
/// so a browser upload is blocked outright.
///
/// File bytes reach the handler as base64 inside its JSON envelope; the host
/// rebuilds the real multipart body natively (see `native_bridge.dart`).
///
/// If the host is too old to have the handler, this falls back to a direct
/// browser upload rather than failing immediately — some WebView configurations
/// allow it. When that fails too, the thrown message names the missing handler,
/// because adding it is the actual fix.
Future<ApiHttpResult> sendMultipartGroupsApiRequest(
  Uri url, {
  Map<String, String>? headers,
  Map<String, String> fields = const {},
  List<MultipartFilePart> files = const [],
  Duration timeout = const Duration(seconds: 120),
}) async {
  if (NativeCameraBridge.isSupported) {
    Map<String, dynamic>? res;
    try {
      res = await NativeCameraBridge.sendHttpMultipart(
        url: url.toString(),
        headers: headers,
        fields: fields,
        files: [
          for (final f in files)
            {
              'field': f.field,
              'filename': f.filename,
              'contentType': f.contentType,
              'base64': base64Encode(f.bytes),
            },
        ],
      ).timeout(timeout);
    } on TimeoutException {
      throw ApiTransportException('timeout: POST $url');
    } catch (e) {
      throw ApiTransportException('bridge error: $e');
    }
    if (res != null) {
      final status = (res['status'] as num?)?.toInt() ?? 0;
      if (status == 0) {
        throw ApiTransportException('unreachable: ${res['error']}');
      }
      return ApiHttpResult(
          statusCode: status, body: (res['body'] ?? '').toString());
    }
    // Handler missing -> try the browser, and say what to add if it fails.
    try {
      return await _postMultipartDirect(url, headers, fields, files, timeout);
    } on ApiTransportException catch (e) {
      throw ApiTransportException(
        '${e.message} (host app has no httpMultipart bridge handler, which is '
        'what this upload needs — see native_bridge.dart)',
      );
    }
  }

  return _postMultipartDirect(url, headers, fields, files, timeout);
}

Future<ApiHttpResult> _postMultipartDirect(
  Uri url,
  Map<String, String>? headers,
  Map<String, String> fields,
  List<MultipartFilePart> files,
  Duration timeout,
) async {
  final request = http.MultipartRequest('POST', url)..fields.addAll(fields);
  for (final f in files) {
    request.files.add(http.MultipartFile.fromBytes(
      f.field,
      f.bytes,
      filename: f.filename,
    ));
  }
  if (headers != null) {
    // MultipartRequest has to append its own boundary, so never let a caller
    // set Content-Type.
    request.headers.addAll(
      Map.of(headers)..removeWhere((k, _) => k.toLowerCase() == 'content-type'),
    );
  }

  final http.Response res;
  try {
    final streamed = await request.send().timeout(timeout);
    res = await http.Response.fromStream(streamed);
  } on TimeoutException {
    throw ApiTransportException('timeout: POST $url');
  } catch (e) {
    throw ApiTransportException('unreachable: $e');
  }
  return ApiHttpResult(
      statusCode: res.statusCode, body: utf8.decode(res.bodyBytes));
}
