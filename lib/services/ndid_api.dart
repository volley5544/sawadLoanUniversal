import 'dart:convert';

import '../config/app_environment.dart';
import 'api_transport.dart';
import 'app_config_api.dart';
import 'ndid_common_message.dart';

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
/// auth is an `X-API-Key` header ([kNdidApiKey]). Base URL is resolved per call
/// by [baseUrl] — the Firestore runtime config first, [kNdidApiBase] as the
/// compile-time fallback.
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

  /// Gateway endpoint every path below hangs off. No trailing slash.
  ///
  /// Resolved at call time, mirroring `SrisawadApi.baseUrl`:
  ///
  ///   1. `api_url['ndid_url_base']` from the Firestore config document — the
  ///      per-project value, so the uat project's copy holds the uat node. This
  ///      is the authoritative one.
  ///   2. [kNdidApiBase] (`--dart-define=NDID_API_BASE`), the compile-time
  ///      default, so a config outage degrades to the built-in gateway rather
  ///      than leaving NDID with no endpoint at all.
  ///
  /// Awaits the memoised config load, so only the first call can wait on that
  /// one request.
  ///
  /// ⚠ **Whatever this resolves to must be allowlisted by the native host.**
  /// The gateway sends no CORS headers, so inside the app every request goes
  /// through the host's `httpRequest` bridge, which refuses any URL outside
  /// `_kHttpRequestAllowedPrefixes` in `loan_universal_web_widget.dart`. Moving
  /// this key to a new host therefore needs a matching host change *and an app
  /// release* — a config edit alone will fail with `URL not allowed`.
  static Future<String> baseUrl() async {
    final config = await AppConfigApi.ensureLoaded();
    return config.ndidUrlBase ?? kNdidApiBase;
  }

  static Future<Uri> _uri(String path) async =>
      Uri.parse('${await baseUrl()}$path');

  /// Optional `request_type` for [createVerifyRequest]: the Firestore config's
  /// `ndid_request_type`, else [kNdidRequestType]. **Empty means send no
  /// `request_type` at all**, which is the default and what uat wants.
  ///
  /// Resolved from the same document as [baseUrl] because, when set, the two must
  /// move together: each gateway publishes its own valid set at
  /// `GET /request-types` and they don't overlap.
  static Future<String> requestType() async {
    final config = await AppConfigApi.ensureLoaded();
    return config.ndidRequestType ?? kNdidRequestType;
  }

  /// The gateway's own list of valid `request_type` values.
  ///
  /// Not called by the flow — it is the diagnostic for a
  /// `20091 - Invalid request type`, which means [requestType] is not in here.
  static Future<List<String>> listRequestTypes() async {
    final json = await _get('/request-types');
    if (json is! List) return const [];
    return json.map((e) => e.toString()).toList(growable: false);
  }

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
  ///
  /// Sends **no `request_type`** unless one is configured — see [requestType].
  /// [transactionRef] is the RP-generated customer-facing reference (digits
  /// only, 5-9 of them — see [NdidTransactionRef]). It goes into the
  /// `request_message` the IdP app displays, so the number the customer reads
  /// on our waiting screen is the same one their bank shows them. Required
  /// rather than defaulted: a request that quotes no reference, or a different
  /// one, is what NDID rejected the app review over.
  static Future<NdidVerifyRequest> createVerifyRequest({
    required String identifier,
    required String idpId,
    required String transactionRef,
    String? requestMessage,
    int requestTimeoutSeconds = 3600,
    String? requestType,
  }) async {
    assert(NdidTransactionRef.isValid(transactionRef),
        'Transaction Ref must be 5-9 digits: $transactionRef');
    final message = requestMessage ??
        NdidCommonMessage.requestMessage(transactionRef: transactionRef);
    final type = requestType ?? await NdidApi.requestType();
    final json = await _post('/rp/verify', {
      'namespace': citizenIdNamespace,
      'identifier': identifier,
      'request_message': message,
      'idp_id_list': [idpId],
      'min_idp': 1,
      'min_aal': minAal,
      'min_ial': minIal,
      'mode': 2,
      'bypass_identity_check': false,
      'request_timeout': requestTimeoutSeconds,
      // Omitted unless configured — neither gateway requires it, and uat does
      // not use it. See [kNdidRequestType].
      if (type.isNotEmpty) 'request_type': type,
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
        await _uri(path),
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
    this.logoUrl = '',
    this.hasLogo = false,
  });

  final String id;
  final String displayNameTh;
  final String displayNameEn;

  /// Absolute URL of the IdP's logo, served by the gateway itself.
  ///
  /// Two things about it decide how the bank grid renders it: the gateway sends
  /// **no CORS headers**, and when [hasLogo] is false this points at a shared
  /// `_default.svg` — so it can be an **SVG**. Byte-fetching handles neither,
  /// which is why the tile displays it through an HTML `<img>` element (see
  /// `ndid_bank_select_page.dart`).
  final String logoUrl;

  /// False when [logoUrl] is the gateway's generic placeholder glyph rather than
  /// this IdP's own artwork. Still worth displaying — it is a clean neutral mark.
  final bool hasLogo;

  factory NdidIdp.fromJson(Map<String, dynamic> json) {
    final en = (json['display_name'] ?? '').toString();
    final th = (json['display_name_th'] ?? '').toString();
    return NdidIdp(
      id: (json['id'] ?? json['node_id'] ?? '').toString(),
      displayNameTh: th.isNotEmpty ? th : en,
      displayNameEn: en,
      logoUrl: (json['logo_url'] ?? '').toString(),
      hasLogo: json['has_logo'] == true,
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
  const NdidVerifyStatus({required this.status, this.errorCode});

  final String status;

  /// The IdP or AS error code, when the request failed with one.
  ///
  /// This is what selects the customer-facing wording — see
  /// [NdidCommonMessage.forErrorCode]. It arrives inside `response_list`
  /// (per-IdP) rather than at the top level, which is why it was being dropped
  /// before 2026-08-28: the old model read `status` and nothing else, so every
  /// distinct failure showed the same generic sentence.
  final int? errorCode;

  factory NdidVerifyStatus.fromJson(Map<String, dynamic> json) =>
      NdidVerifyStatus(
        status: (json['status'] ?? '').toString().toUpperCase(),
        errorCode: _errorCode(json),
      );

  /// Digs the error code out wherever this gateway put it: on the envelope, or
  /// on the first `response_list` entry that carries one. Tolerant of a string
  /// because the API returns numbers as both (see `json_coerce.dart` for the
  /// same problem on the mobile API).
  static int? _errorCode(Map<String, dynamic> json) {
    int? asInt(Object? v) => v == null
        ? null
        : v is int
            ? v
            : int.tryParse(v.toString());

    final top = asInt(json['error_code']);
    if (top != null) return top;
    final list = json['response_list'];
    if (list is List) {
      for (final entry in list) {
        if (entry is Map) {
          final code = asInt(entry['error_code']);
          if (code != null) return code;
        }
      }
    }
    return null;
  }

  bool get isAccepted => status == 'ACCEPTED';
  bool get isRejected => status == 'REJECTED';
  bool get isTimeout => status == 'TIMEOUT';
  bool get isCancelled => status == 'CANCELLED';

  /// The gateway's two error statuses (`API_USAGE.md` in the backend repo):
  /// NDID itself failed the request, or an IdP/AS answered with an error code.
  bool get isError => status == 'REQUESTED_ERROR' || status == 'IDP_OR_AS_ERROR';

  /// Still waiting for the customer to act in their bank app.
  ///
  /// Anything not known to be final counts as pending, so a status this build
  /// has never heard of keeps polling instead of failing the customer — but
  /// [isError] is listed explicitly, because those two used to fall in here and
  /// poll forever against a request that was already dead.
  bool get isPending =>
      !isAccepted && !isRejected && !isTimeout && !isCancelled && !isError;
}
