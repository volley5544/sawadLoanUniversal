import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_environment.dart';

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
/// The node manages the NDID token itself (its `/token` endpoint), so no auth
/// header is sent. Base URL comes from [kNdidApiBase]
/// (`--dart-define=NDID_API_BASE`).
class NdidApi {
  NdidApi._();

  static const Duration _timeout = Duration(seconds: 30);
  static const String citizenIdNamespace = 'citizen_id';

  static Uri _uri(String path) => Uri.parse('$kNdidApiBase$path');

  /// List identity providers. With [identifier] set (13-digit Thai ID) the
  /// node returns only the IdPs the citizen has onboarded with; without it,
  /// all IdPs at the given assurance levels.
  static Future<List<NdidIdp>> listIdps({
    String? identifier,
    double minIal = 1.1,
    num minAal = 1,
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
      'min_aal': 1,
      'min_ial': 1.1,
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

  static Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final http.Response res;
    try {
      res = await http
          .post(_uri(path),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(_timeout);
    } on TimeoutException {
      throw NdidApiException('NDID API timeout: POST $path');
    } catch (e) {
      throw NdidApiException('NDID API unreachable: $e');
    }
    return _decode(res, 'POST $path');
  }

  static Future<dynamic> _get(String path) async {
    final http.Response res;
    try {
      res = await http.get(_uri(path)).timeout(_timeout);
    } on TimeoutException {
      throw NdidApiException('NDID API timeout: GET $path');
    } catch (e) {
      throw NdidApiException('NDID API unreachable: $e');
    }
    return _decode(res, 'GET $path');
  }

  static dynamic _decode(http.Response res, String what) {
    dynamic json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      json = null;
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message = (json is Map && json['message'] != null)
          ? json['message'].toString()
          : 'HTTP ${res.statusCode}';
      throw NdidApiException(message, statusCode: res.statusCode);
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
