import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ndid_models.dart';

/// Thrown when an NDID proxy call fails (non-2xx, network error, or a body the
/// app can't parse). [statusCode] is the HTTP status when available; [ndidError]
/// carries the proxy's `message` field so the UI can show something meaningful.
class NdidApiException implements Exception {
  NdidApiException(this.message, {this.statusCode, this.ndidError});

  final String message;
  final int? statusCode;
  final String? ndidError;

  @override
  String toString() => 'NdidApiException($statusCode): $message';
}

/// REST client for the NDID/DAP identity-verification flow.
///
/// It talks to the **local NDID Node proxy** (`server.js`, default
/// `http://localhost:7088`, documented in
/// `dap/NDID_Local_API.postman_collection.json`) — NOT the DAP proxy directly.
/// The local node owns the RSA token, so the app never signs anything or sends
/// a token. The relevant endpoints for an RP (this app) are:
///
///  * `POST /idp/list`                    → available Identity Providers
///  * `POST /rp/verify`                   → start verification (returns ref id)
///  * `GET  /rp/verify/{reference_id}`    → poll status
///  * `POST /rp/verify/{reference_id}/close` → cancel the request
///  * `GET  /ndid/callback/{reference_id}`   → last DAP-pushed status (optional)
///
/// Construct with the host's base URL from `AppState().ndidBaseUrl`.
class NdidService {
  NdidService({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// Base URL of the local node proxy, no trailing slash (e.g.
  /// `http://localhost:7088`).
  final String baseUrl;

  final http.Client _client;

  /// Default namespace for a Thai national ID. The flow only deals with
  /// citizen ids for now.
  static const String citizenIdNamespace = 'citizen_id';

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// Quick liveness probe (`GET /health`). Returns true on HTTP 200.
  Future<bool> health() async {
    try {
      final res = await _client
          .get(_uri('/health'))
          .timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// `POST /idp/list` — Identity Providers the [identifier] can verify with.
  ///
  /// When [namespace]/[identifier] are given the proxy returns only IdPs the
  /// user has onboarded (mode 2/3); the defaults mirror the Postman example.
  Future<List<NdidIdp>> listIdps({
    String namespace = citizenIdNamespace,
    String identifier = '',
    double minIal = 1.1,
    double minAal = 1,
    bool agent = false,
    bool filterWhitelist = true,
  }) async {
    final body = <String, dynamic>{
      'min_ial': minIal,
      'min_aal': minAal,
      'agent': agent,
      'on_the_fly_support': false,
      'filter_whitelist': filterWhitelist,
      'filter_idp_service_time': false,
    };
    if (identifier.isNotEmpty) {
      body['namespace'] = namespace;
      body['identifier'] = identifier;
    }
    final decoded = await _post('/idp/list', body);
    return NdidIdp.listFromResponse(decoded);
  }

  /// `POST /rp/verify` — request identity verification from [idpIdList].
  ///
  /// Returns the [NdidVerifyResult] holding the `reference_id` used to poll
  /// status and to close the request. [callbackUrl] (when non-empty) is where
  /// DAP pushes status changes; otherwise poll [checkStatus].
  Future<NdidVerifyResult> verify({
    required String identifier,
    required List<String> idpIdList,
    String namespace = citizenIdNamespace,
    String requestMessage = 'ขอยืนยันตัวตนเพื่อสมัครสินเชื่อ',
    int minIdp = 1,
    double minIal = 1.1,
    double minAal = 1,
    int mode = 2,
    String callbackUrl = '',
    bool bypassIdentityCheck = false,
    int requestTimeout = 3600,
    String requestType = 'Authen Only',
  }) async {
    final body = <String, dynamic>{
      'namespace': namespace,
      'identifier': identifier,
      'request_message': requestMessage,
      'idp_id_list': idpIdList,
      'min_idp': minIdp,
      'min_aal': minAal,
      'min_ial': minIal,
      'mode': mode,
      'bypass_identity_check': bypassIdentityCheck,
      'request_timeout': requestTimeout,
      'request_type': requestType,
    };
    if (callbackUrl.isNotEmpty) body['callback_url'] = callbackUrl;

    final decoded = await _post('/rp/verify', body);
    if (decoded is! Map<String, dynamic>) {
      throw NdidApiException('Unexpected verify response shape');
    }
    return NdidVerifyResult.fromJson(decoded);
  }

  /// `GET /rp/verify/{reference_id}` — current status of the request.
  Future<NdidVerificationStatus> checkStatus(String referenceId) async {
    final decoded = await _get('/rp/verify/$referenceId');
    if (decoded is! Map<String, dynamic>) {
      throw NdidApiException('Unexpected status response shape');
    }
    return NdidVerificationStatus.fromJson(decoded);
  }

  /// `POST /rp/verify/{reference_id}/close` — cancel a pending request.
  Future<void> close(String referenceId, {String callbackUrl = ''}) async {
    await _post('/rp/verify/$referenceId/close', {
      if (callbackUrl.isNotEmpty) 'callback_url': callbackUrl,
    });
  }

  /// `GET /ndid/callback/{reference_id}` — the last status DAP pushed to the
  /// node's callback endpoint. Returns null when nothing is stored (404).
  Future<NdidVerificationStatus?> latestCallback(String referenceId) async {
    try {
      final decoded = await _get('/ndid/callback/$referenceId');
      if (decoded is Map<String, dynamic>) {
        return NdidVerificationStatus.fromJson(decoded);
      }
    } on NdidApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
    return null;
  }

  void dispose() => _client.close();

  // ── Low-level helpers ─────────────────────────────────────────────────────

  Future<dynamic> _get(String path) async {
    try {
      final res = await _client
          .get(_uri(path), headers: _jsonHeaders)
          .timeout(const Duration(seconds: 20));
      return _decode(res);
    } on NdidApiException {
      rethrow;
    } catch (e) {
      throw NdidApiException('เชื่อมต่อ NDID ไม่สำเร็จ: $e');
    }
  }

  Future<dynamic> _post(String path, Object body) async {
    try {
      final res = await _client
          .post(_uri(path), headers: _jsonHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
      return _decode(res);
    } on NdidApiException {
      rethrow;
    } catch (e) {
      throw NdidApiException('เชื่อมต่อ NDID ไม่สำเร็จ: $e');
    }
  }

  /// Parses a response body, mapping non-2xx into [NdidApiException] using the
  /// proxy's `{ status, message }` error envelope when present.
  dynamic _decode(http.Response res) {
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    dynamic decoded;
    if (res.body.isNotEmpty) {
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        decoded = null;
      }
    }
    if (ok) return decoded;

    String? message;
    if (decoded is Map<String, dynamic>) {
      message = decoded['message']?.toString();
    }
    throw NdidApiException(
      message ?? 'NDID ตอบกลับด้วยสถานะ ${res.statusCode}',
      statusCode: res.statusCode,
      ndidError: message,
    );
  }
}
