import 'dart:convert';

import '../config/app_environment.dart';
import 'api_transport.dart';

/// Client for the **NDID local-node API** (the `localhost:7088` wrapper in
/// `ndid_doc/NDID_Local_API.postman_collection.json`; it fronts the NDID
/// proxy — spec `NDID_Proxy_Specification_V4.0.pdf`).
///
/// Only the RP (relying party) endpoints needed by the loan flow are wired:
///
///   1. `POST /idp/list`                — list identity providers (banks)
///   2. `POST /rp/verify`               — create a verification request
///   3. `GET  /rp/verify/{referenceId}` — poll the request status
///   4. `POST /rp/verify/{referenceId}/close` — cancel (best effort)
///
/// The node manages the NDID token itself (its `/token` endpoint); client
/// auth is an `X-API-Key` header ([kNdidApiKey]). Base URL comes from
/// [kNdidApiBase] (`--dart-define=NDID_API_BASE`).
class NdidApi {
  NdidApi._();

  static const Duration _timeout = Duration(seconds: 30);
  static const String citizenIdNamespace = 'citizen_id';

  /// Assurance levels every request asks for — **IAL 2.3 / AAL 2.2**, raised
  /// from `1.1` / `1` on 2026-07-30.
  ///
  /// Shared by [listIdps] and [createVerifyRequest] on purpose: the first
  /// decides which IdPs the customer may pick from and the second is what that
  /// IdP is then asked to assert, so a pair that drifts apart would offer a bank
  /// under one bar and verify under another. Change them here, once.
  ///
  /// They are a **filter**, not a preference — an IdP that cannot meet them
  /// disappears from the bank-select grids entirely. Verified on the uat node:
  /// `idp-thaid` (ไทยดี) is returned at 1.1/1 and not at 2.3/2.2.
  static const double minIal = 2.3;
  static const num minAal = 2.2;

  static Uri _uri(String path) => Uri.parse('$kNdidApiBase$path');

  static Map<String, String> _headers({bool json = false}) => {
        if (json) 'Content-Type': 'application/json',
        if (kNdidApiKey.isNotEmpty) 'X-API-Key': kNdidApiKey,
      };

  /// List identity providers. With [identifier] set (13-digit Thai ID) the
  /// node returns only the IdPs the citizen has onboarded with; without it,
  /// all IdPs at the given assurance levels.
  ///
  /// Defaults to [NdidApi.minIal] / [NdidApi.minAal] — the same levels
  /// [createVerifyRequest] asks for. Overridable per call, but note these
  /// *filter* the result: a higher floor returns fewer banks.
  static Future<List<NdidIdp>> listIdps({
    String? identifier,
    double minIal = NdidApi.minIal,
    num minAal = NdidApi.minAal,
  }) async {
    final body = <String, dynamic>{
      'min_ial': minIal,
      'min_aal': minAal,
      'agent': false,
      'filter_whitelist': true,
      if (identifier != null && identifier.isNotEmpty) ...{
        'namespace': citizenIdNamespace,
        'identifier': identifier,
      },
    };
    final json = await _post('/idp/list', body);
    final list = json is Map<String, dynamic>
        ? (json['id_providers'] ?? json['idp_list'] ?? const [])
        : json; // tolerate a bare array
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(NdidIdp.fromJson)
        .toList(growable: false);
  }

  /// Create a verification request against the chosen IdP. Returns the
  /// reference used to poll [getVerifyStatus].
  ///
  /// Asks for [NdidApi.minIal] / [NdidApi.minAal] — the same levels [listIdps]
  /// filtered the chosen IdP by, so the bank is verified at the bar it was
  /// offered under.
  static Future<NdidVerifyRequest> createVerifyRequest({
    required String identifier,
    required String idpId,
    String requestMessage = 'ขอยืนยันตัวตนเพื่อสมัครสินเชื่อกับ ศรีสวัสดิ์',
    int requestTimeoutSeconds = 3600,
  }) async {
    final json = await _post('/rp/verify', {
      'namespace': citizenIdNamespace,
      'identifier': identifier,
      'request_message': requestMessage,
      'idp_id_list': [idpId],
      'min_idp': 1,
      'min_aal': minAal,
      'min_ial': minIal,
      'mode': 2,
      'bypass_identity_check': false,
      'request_timeout': requestTimeoutSeconds,
      'request_type': 'Authen Only',
    });
    if (json is! Map<String, dynamic> || json['reference_id'] == null) {
      throw NdidApiException('Unexpected /rp/verify response: $json');
    }
    return NdidVerifyRequest(
      referenceId: json['reference_id'].toString(),
      ndidRequestId: json['ndid_request_id']?.toString(),
    );
  }

  /// Poll the status of a verification request.
  static Future<NdidVerifyStatus> getVerifyStatus(String referenceId) async {
    final json = await _get('/rp/verify/$referenceId');
    if (json is! Map<String, dynamic>) {
      throw NdidApiException('Unexpected status response: $json');
    }
    return NdidVerifyStatus.fromJson(json);
  }

  /// Close (cancel) a pending verification request. Best effort — errors are
  /// swallowed, the caller is abandoning the request anyway.
  static Future<void> closeVerifyRequest(String referenceId) async {
    try {
      await _post('/rp/verify/$referenceId/close', const {});
    } catch (_) {/* best effort */}
  }

  // ── HTTP plumbing ──────────────────────────────────────────────────
  // Requests go through [sendApiRequest] (host bridge inside the WebView —
  // the NDID gateway sends no CORS headers, so a direct browser fetch is
  // blocked; plain `http` only in a plain browser).

  static Future<dynamic> _post(String path, Map<String, dynamic> body) =>
      _request('POST', path, body: jsonEncode(body));

  static Future<dynamic> _get(String path) => _request('GET', path);

  static Future<dynamic> _request(String method, String path,
      {String? body}) async {
    final ApiHttpResult res;
    try {
      res = await sendApiRequest(
        method,
        _uri(path),
        headers: _headers(json: body != null),
        body: body,
        timeout: _timeout,
      );
    } on ApiTransportException catch (e) {
      throw NdidApiException('NDID API ${e.message}');
    }
    return _decode(res.statusCode, res.body);
  }

  static dynamic _decode(int statusCode, String bodyText) {
    dynamic json;
    try {
      json = jsonDecode(bodyText);
    } catch (_) {
      json = null;
    }
    if (statusCode < 200 || statusCode >= 300) {
      final message = (json is Map && json['message'] != null)
          ? json['message'].toString()
          : 'HTTP $statusCode';
      throw NdidApiException(message, statusCode: statusCode);
    }
    return json;
  }
}

class NdidApiException implements Exception {
  NdidApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'NdidApiException: $message';
}

/// One identity provider (bank) from `POST /idp/list`.
class NdidIdp {
  const NdidIdp({
    required this.id,
    required this.displayNameTh,
    required this.displayNameEn,
  });

  final String id;
  final String displayNameTh;
  final String displayNameEn;

  factory NdidIdp.fromJson(Map<String, dynamic> json) {
    final en = (json['display_name'] ?? '').toString();
    final th = (json['display_name_th'] ?? '').toString();
    return NdidIdp(
      id: (json['id'] ?? json['node_id'] ?? '').toString(),
      displayNameTh: th.isNotEmpty ? th : en,
      displayNameEn: en,
    );
  }
}

/// Result of `POST /rp/verify`.
class NdidVerifyRequest {
  const NdidVerifyRequest({required this.referenceId, this.ndidRequestId});

  final String referenceId;
  final String? ndidRequestId;
}

/// Result of `GET /rp/verify/{referenceId}`.
/// Status: CREATED | PENDING | ACCEPTED | REJECTED | TIMEOUT | CANCELLED.
class NdidVerifyStatus {
  const NdidVerifyStatus({required this.status});

  final String status;

  factory NdidVerifyStatus.fromJson(Map<String, dynamic> json) =>
      NdidVerifyStatus(status: (json['status'] ?? '').toString().toUpperCase());

  bool get isAccepted => status == 'ACCEPTED';
  bool get isRejected => status == 'REJECTED';
  bool get isTimeout => status == 'TIMEOUT';
  bool get isCancelled => status == 'CANCELLED';

  /// Still waiting for the customer to act in their bank app.
  bool get isPending => !isAccepted && !isRejected && !isTimeout && !isCancelled;
}
