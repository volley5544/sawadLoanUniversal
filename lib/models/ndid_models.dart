import 'dart:convert';

/// Plain-Dart models for the NDID/DAP identity-verification REST flow.
///
/// These mirror the JSON returned by the local NDID Node proxy
/// (`localhost:7088`, see `dap/NDID_Local_API.postman_collection.json`), which
/// in turn proxies the DAP "NDID Proxy" API (spec V4.0). No codegen — the app
/// has no `build_runner` step. All parsing goes through the defensive `_as*`
/// helpers so a malformed/empty proxy response never throws.

// ── Identity Provider (POST /idp/list -> { "id_providers": [...] }) ──────────

/// One Identity Provider the user can verify against.
class NdidIdp {
  /// NDID node id of the IdP (`id` in the response). Sent back in `idp_id_list`.
  final String id;

  /// Human-readable English display name (`display_name`).
  final String displayName;

  /// Human-readable Thai display name (`display_name_th`).
  final String displayNameTh;

  /// Whether this IdP is an agent-type node (`agent`).
  final bool agent;

  /// Features the IdP supports, e.g. `on_the_fly` (`supported_feature_list`).
  final List<String> supportedFeatures;

  const NdidIdp({
    this.id = '',
    this.displayName = '',
    this.displayNameTh = '',
    this.agent = false,
    this.supportedFeatures = const [],
  });

  /// Best label to show the user: Thai name, else English, else the raw id.
  String get label {
    final th = displayNameTh.trim();
    if (th.isNotEmpty) return th;
    final en = displayName.trim();
    if (en.isNotEmpty) return en;
    return id;
  }

  factory NdidIdp.fromJson(Map<String, dynamic> json) {
    return NdidIdp(
      id: _asString(json['id'] ?? json['node_id'] ?? json['idp_id']),
      displayName: _asString(json['display_name']),
      displayNameTh: _asString(json['display_name_th']),
      agent: _asBool(json['agent']),
      supportedFeatures: _asStringList(json['supported_feature_list']),
    );
  }

  /// Parses the `idp/list` body, which wraps the array in `id_providers`.
  /// Tolerates a bare array too, in case the proxy is reshaped.
  static List<NdidIdp> listFromResponse(dynamic body) {
    final dynamic list =
        body is Map<String, dynamic> ? body['id_providers'] : body;
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(NdidIdp.fromJson)
        .toList();
  }
}

// ── Verify result (POST /rp/verify -> { reference_id, ndid_request_id }) ─────

/// Returned right after a verification request is accepted by the platform.
/// [referenceId] is the handle used to poll status and to close the request.
class NdidVerifyResult {
  final String referenceId;
  final String ndidRequestId;

  const NdidVerifyResult({this.referenceId = '', this.ndidRequestId = ''});

  factory NdidVerifyResult.fromJson(Map<String, dynamic> json) {
    return NdidVerifyResult(
      referenceId: _asString(json['reference_id']),
      ndidRequestId: _asString(json['ndid_request_id']),
    );
  }
}

// ── Status (GET /rp/verify/{reference_id}) and DAP callback payloads ─────────

/// High-level status of a verification request. Mirrors the spec's status
/// enum; [unknown] guards against an unexpected value.
enum NdidStatus {
  created,
  pending,
  accepted,
  rejected,
  timeout,
  cancelled,
  requestedError,
  idpOrAsError,
  unknown;

  /// Whether the request has reached a final state (stop polling).
  bool get isTerminal =>
      this != NdidStatus.created && this != NdidStatus.pending;

  /// Whether the identity was successfully verified.
  bool get isSuccess => this == NdidStatus.accepted;

  /// Parses the UPPERCASE status string the proxy/callback sends.
  static NdidStatus parse(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'CREATED':
        return NdidStatus.created;
      case 'PENDING':
        return NdidStatus.pending;
      case 'ACCEPTED':
        return NdidStatus.accepted;
      case 'REJECTED':
        return NdidStatus.rejected;
      case 'TIMEOUT':
        return NdidStatus.timeout;
      case 'CANCELLED':
        return NdidStatus.cancelled;
      case 'REQUESTED_ERROR':
        return NdidStatus.requestedError;
      case 'IDP_OR_AS_ERROR':
        return NdidStatus.idpOrAsError;
      default:
        return NdidStatus.unknown;
    }
  }
}

/// One IdP's entry inside a status `response_list`.
class NdidIdpResponse {
  final String idpId;

  /// `accept` | `reject` (absent when the IdP returned an error instead).
  final String status;
  final double? aal;
  final double? ial;
  final int? errorCode;
  final String errorDescription;

  const NdidIdpResponse({
    this.idpId = '',
    this.status = '',
    this.aal,
    this.ial,
    this.errorCode,
    this.errorDescription = '',
  });

  bool get accepted => status.trim().toLowerCase() == 'accept';

  factory NdidIdpResponse.fromJson(Map<String, dynamic> json) {
    return NdidIdpResponse(
      idpId: _asString(json['idp_id']),
      status: _asString(json['status']),
      aal: _asDouble(json['aal']),
      ial: _asDouble(json['ial']),
      errorCode: _asInt(json['error_code']),
      errorDescription: _asString(json['error_description']),
    );
  }
}

/// Full status of a verification request (poll result or stored DAP callback).
class NdidVerificationStatus {
  final String referenceId;
  final String ndidRequestId;
  final NdidStatus status;
  final List<NdidIdpResponse> responseList;

  /// Top-level error for `REQUESTED_ERROR` responses (`error.code/message`).
  final int? errorCode;
  final String errorMessage;

  const NdidVerificationStatus({
    this.referenceId = '',
    this.ndidRequestId = '',
    this.status = NdidStatus.unknown,
    this.responseList = const [],
    this.errorCode,
    this.errorMessage = '',
  });

  factory NdidVerificationStatus.fromJson(Map<String, dynamic> json) {
    final responses = json['response_list'];
    final error = json['error'];
    return NdidVerificationStatus(
      referenceId: _asString(json['reference_id']),
      ndidRequestId: _asString(json['ndid_request_id']),
      status: NdidStatus.parse(_asString(json['status'])),
      responseList: responses is List
          ? responses
              .whereType<Map<String, dynamic>>()
              .map(NdidIdpResponse.fromJson)
              .toList()
          : const [],
      errorCode: error is Map<String, dynamic> ? _asInt(error['code']) : null,
      errorMessage:
          error is Map<String, dynamic> ? _asString(error['message']) : '',
    );
  }
}

// ── Safe coercion helpers (same spirit as CustomerDetail) ───────────────────

String _asString(dynamic v) => v?.toString() ?? '';

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }
  return false;
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim());
}

List<String> _asStringList(dynamic v) {
  if (v is List) return v.map((e) => e.toString()).toList();
  if (v is String && v.trim().isNotEmpty) {
    // Could be a comma-joined string or a JSON array string.
    final s = v.trim();
    if (s.startsWith('[')) {
      try {
        final decoded = jsonDecode(s);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } catch (_) {/* fall through */}
    }
    return s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }
  return const [];
}
