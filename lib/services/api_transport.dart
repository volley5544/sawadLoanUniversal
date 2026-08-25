import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

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
///
/// Set [bypassHostBridge] to skip the bridge even inside the host, for an
/// endpoint that is **known CORS-enabled and not on the host's allowlist**.
///
/// That combination is not hypothetical: the runtime-config read
/// (`firestore.googleapis.com`) and the anonymous sign-in it needs
/// (`identitytoolkit.googleapis.com`) are both absent from
/// `_kHttpRequestAllowedPrefixes`, so routing them through the bridge returned
/// `URL not allowed` and the config silently resolved **empty** — every caller
/// then fell back to its compile-time endpoint. That went unnoticed for days
/// because uat's `api_url_base` equals the compile-time `mobileApiBase`; it only
/// surfaced when `ndid_url_base` named a *different* host and NDID kept talking
/// to the old gateway. Google's APIs answer preflights with
/// `access-control-allow-origin` + `access-control-allow-headers: authorization`
/// (verified), so a direct fetch is the correct transport for them and needs no
/// host release to start working.
///
/// Do **not** set this for the NDID gateway or the P-Loan save API — neither
/// sends CORS headers, so the bridge is the only way to reach them.
Future<ApiHttpResult> sendApiRequest(
  String method,
  Uri url, {
  Map<String, String>? headers,
  String? body,
  // 60 s so the P-Loan `/ploan` submit (and any other slow mobile-API write) has
  // headroom — it was 30 s, which is tight for a contract-filing POST. Raised
  // 2026-08-04.
  Duration timeout = const Duration(seconds: 60),
  bool bypassHostBridge = false,
}) async {
  if (NativeCameraBridge.isSupported && !bypassHostBridge) {
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
/// By default this routes through the host's `httpMultipart` bridge handler
/// when running inside the host, because it was written for an endpoint that
/// sent **no** CORS headers and 401'd the preflight, so a browser upload was
/// blocked outright. File bytes reach the handler as base64 inside its JSON
/// envelope; the host rebuilds the real multipart body natively (see
/// `native_bridge.dart`).
///
/// If the host is too old to have the handler, this falls back to a direct
/// browser upload rather than failing immediately — some WebView configurations
/// allow it. When that fails too, the thrown message names the missing handler,
/// because adding it is the actual fix.
///
/// [bypassHostBridge] skips all of that and always uses `package:http`, the way
/// [sendMultipartApiRequest] does. Set it **only** for a host that sends
/// `access-control-allow-origin: *` — the srisawad mobile API does, which is
/// what lets the P-Loan save upload take this path and need no `httpMultipart`
/// handler at all. Never set it for the NDID gateway.
Future<ApiHttpResult> sendMultipartGroupsApiRequest(
  Uri url, {
  Map<String, String>? headers,
  Map<String, String> fields = const {},
  List<MultipartFilePart> files = const [],
  Duration timeout = const Duration(seconds: 120),
  bool bypassHostBridge = false,
}) async {
  if (NativeCameraBridge.isSupported && !bypassHostBridge) {
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
      // Honour the declared type. The bridge path always passed this through;
      // omitting it here made the same upload arrive as application/octet-stream
      // depending only on which transport ran — and it matters for the P-Loan
      // save call, whose parts are a mix of image/jpeg and application/pdf.
      contentType: MediaType.parse(f.contentType),
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
