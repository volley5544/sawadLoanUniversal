import 'dart:convert';

import '../config/app_environment.dart';
import 'api_transport.dart';
import 'app_config_api.dart';
import 'diagnostics.dart';
import 'ndid_common_message.dart';

/// Client for the **NDID local-node API** (the `localhost:7088` wrapper in
/// `ndid_doc/NDID_Local_API.postman_collection.json`; it fronts the NDID
/// proxy — spec `NDID_Proxy_Specification_V4.0.pdf`).
///
/// Only the RP (relying party) endpoints needed by the loan flow are wired:
///
///   1. `POST /idp/list`                — list identity providers (banks)
///   2. `GET  /services/{serviceId}/as` — list a service's Authoritative Sources
///   3. `POST /rp/verify-with-data`     — create a verification request that
///      also asks one AS for the customer's data. **The normal path since
///      2026-09-10.** The gateway proxies it to NDID's
///      `/identity/verify-and-request-data`.
///   4. `POST /rp/verify`               — the same request with no data. Still
///      the fallback when no AS can be matched to the chosen IdP.
///   5. `GET  /rp/verify/{referenceId}` — poll the request status
///   6. `POST /rp/verify/{referenceId}/close` — cancel (best effort)
///
/// The data an AS returns is **backend-only** for now: it goes to
/// [dataCallbackUrl] on the srisawad gateway, and the poll response is read
/// exactly as before ([NdidVerifyStatus] gained nothing).
///
/// The node manages the NDID token itself (its `/token` endpoint); client
/// auth is an `X-API-Key` header ([kNdidApiKey]). Base URL is resolved per call
/// by [baseUrl] — the Firestore runtime config first, [kNdidApiBase] as the
/// compile-time fallback.
class NdidApi {
  NdidApi._();

  static const Duration _timeout = Duration(seconds: 30);
  static const String citizenIdNamespace = 'citizen_id';

  /// NDID service whose data `/rp/verify-with-data` requests — customer info.
  ///
  /// Its Authoritative Sources are listed at `GET /services/$dataServiceId/as`;
  /// see [findAsForIdp] for which of them a request goes to.
  static const String dataServiceId = '001.cust_info_001';

  /// Path of the srisawad gateway's own AS callback, appended to whichever
  /// gateway the request is going to — see [dataCallbackUrl].
  static const String dataCallbackPath = '/ndid/callback';

  /// `callback_url` for `/rp/verify-with-data` — the srisawad gateway's own
  /// callback, so the AS response lands on the backend rather than anywhere
  /// this client can see. The returned data is backend-only for now, which is
  /// why nothing here reads it back.
  ///
  /// ⚠ **It follows the gateway; it is not a fixed host.** It was hardcoded to
  /// `https://ndid.srisawadpower.com/ndid/callback` until 2026-09-11, which
  /// meant a **uat** request asked the prod gateway to receive its callback.
  /// Both gateways' own sample curls use their own host — uat's reads
  /// `https://uat.ndid.srisawadpower.com/ndid/callback` — so the right answer
  /// is the resolved base plus [dataCallbackPath], and there is then nothing
  /// left to keep in step by hand.
  ///
  /// `ndid_callback_url` in the runtime config overrides it (per-environment,
  /// like every other key there) for a gateway that receives its callbacks
  /// somewhere other than itself.
  static Future<String> dataCallbackUrl() async {
    final config = await AppConfigApi.ensureLoaded();
    final override = config.ndidCallbackUrl;
    if (override != null && override.isNotEmpty) return override;
    return '${await baseUrl()}$dataCallbackPath';
  }

  /// How many Authoritative Sources must answer. One — [findAsForIdp] resolves
  /// exactly one, the bank the customer authenticated with.
  static const int minAs = 1;

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

  /// [base] is the gateway [baseUrl] resolved, because the `X-API-Key` is
  /// per gateway — see [ndidApiKeyFor].
  static Map<String, String> _headers(String base, {bool json = false}) {
    final key = ndidApiKeyFor(base);
    return {
      if (json) 'Content-Type': 'application/json',
      if (key.isNotEmpty) 'X-API-Key': key,
    };
  }

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

  /// List the Authoritative Sources that serve [serviceId]
  /// (`GET /services/{serviceId}/as`).
  ///
  /// Unlike `/idp/list`, the gateway does **not** flatten these: the only
  /// identifying field is [NdidAs.nodeName], a JSON *string* holding the
  /// marketing names and codes. [NdidAs.fromJson] parses it.
  static Future<List<NdidAs>> listServiceAs([String serviceId = dataServiceId]) async {
    final json = await _get('/services/$serviceId/as');
    final list = json is Map<String, dynamic>
        ? (json['as'] ?? json['as_list'] ?? const [])
        : json; // the prod gateway answers with a bare array
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(NdidAs.fromJson)
        .toList(growable: false);
  }

  /// The AS node that is **the same institution** as [idpId], or null.
  ///
  /// A bank's IdP node and its AS node are *different* node ids — verified
  /// 2026-09-10 on the prod gateway, where the 13 IdPs and 14 AS nodes share
  /// **no** id at all. What they do share is the `(industry_code,
  /// company_code)` pair inside `node_name`, which matched all 13 exactly. So
  /// that pair is the join, not the node id and not the display name.
  ///
  /// Matching the IdP is deliberate: the customer picked that bank to
  /// authenticate with and the Request Message names it as the data source, so
  /// asking a *different* bank for the data would describe one relationship to
  /// the customer and exercise another. It also needs no hardcoded node id —
  /// the sample curl's `A18AC373-…` is not on the prod gateway at all, which is
  /// the `request_type` mistake of 2026-07-31 in a new costume.
  ///
  /// Returns null rather than throwing when the pair can't be matched; the
  /// caller degrades to a verification with no data request.
  static Future<NdidAs?> findAsForIdp(String idpId,
      {String serviceId = dataServiceId}) async {
    if (idpId.isEmpty) return null;
    final idps = await listIdps();
    NdidIdp? idp;
    for (final candidate in idps) {
      if (candidate.id.toUpperCase() == idpId.toUpperCase()) {
        idp = candidate;
        break;
      }
    }
    if (idp == null || !idp.hasInstitutionCode) return null;
    final sources = await listServiceAs(serviceId);
    for (final source in sources) {
      if (source.industryCode == idp.industryCode &&
          source.companyCode == idp.companyCode) {
        return source;
      }
    }
    return null;
  }

  /// The pinned Authoritative Source, when one is configured.
  ///
  /// `ndid_as_id` in the runtime config (per-environment — see
  /// [AppConfig.ndidAsId]), else [kNdidAsId]. Null when neither is set, which
  /// is the normal case: [findAsForIdp] resolves the AS from the IdP the
  /// customer chose, which is both more correct and gateway-independent.
  ///
  /// The name is resolved from the gateway's own AS list when the config
  /// doesn't carry one. If **neither** yields a name the AS is still used —
  /// the data request is the point — but the Request Message **omits the AS
  /// clause**, because naming a source we cannot confirm is worse than not
  /// naming one.
  static Future<NdidAs?> _pinnedAs() async {
    final config = await AppConfigApi.ensureLoaded();
    final id = config.ndidAsId ?? (kNdidAsId.isEmpty ? null : kNdidAsId);
    if (id == null || id.isEmpty) return null;

    final configuredName =
        config.ndidAsName ?? (kNdidAsName.isEmpty ? null : kNdidAsName);
    var nameTh = configuredName ?? '';
    if (nameTh.isEmpty) {
      // Best effort — this is exactly the call that fails on a gateway whose
      // AS list is unusable, which is why the id was pinned in the first
      // place. Its failure must not cost the data request.
      try {
        for (final source in await listServiceAs()) {
          if (source.nodeId.toUpperCase() == id.toUpperCase()) {
            nameTh = source.displayName;
            break;
          }
        }
      } catch (e) {
        Diagnostics.log('ndid pinned AS $id — name lookup failed ($e), '
            'Request Message will omit the AS clause');
      }
    }
    Diagnostics.log('ndid using pinned AS $id'
        '${nameTh.isEmpty ? ' (no name)' : ' ($nameTh)'}');
    return NdidAs(
      nodeId: id,
      industryCode: '',
      companyCode: '',
      marketingNameTh: nameTh,
      marketingNameEn: '',
    );
  }

  /// [findAsForIdp], with every failure swallowed to null.
  ///
  /// The data request is a **bonus** — the customer is here to prove who they
  /// are, and the AS payload is backend-only today. So a gateway hiccup, a
  /// service with no matching AS, or an unparseable `node_name` must cost the
  /// data request, never the identity verification. The reason is logged so
  /// "why did this go out without data?" is answerable from the WebView
  /// console.
  static Future<NdidAs?> _findAsQuietly(String idpId) async {
    try {
      final source = await findAsForIdp(idpId);
      if (source == null) {
        Diagnostics.log('ndid no AS matches IdP for $dataServiceId — '
            'verifying without a data request');
      }
      return source;
    } catch (e) {
      Diagnostics.log('ndid AS lookup failed ($e) — '
          'verifying without a data request');
      return null;
    }
  }

  /// Create a verification request against the chosen IdP. Returns the
  /// reference used to poll [getVerifyStatus].
  ///
  /// Asks for [NdidApi.minIal] / [NdidApi.minAal] — the same levels [listIdps]
  /// filtered the chosen IdP by, so the bank is verified at the bar it was
  /// offered under.
  ///
  /// Sends **no `request_type`** unless one is configured — see [requestType].
  ///
  /// **The customer-facing Transaction Ref comes back on the response**
  /// ([NdidVerifyRequest.transactionRef]), generated by the gateway, which also
  /// appends the `(Transaction Ref: …)` clause to the Request Message the IdP
  /// app shows. So [transactionRef] is normally left null and the caller reads
  /// the value off the result — one generator, therefore no way for our waiting
  /// screen and the bank's app to quote different numbers, which is what NDID
  /// rejected the app review over. Pass one only against a gateway that does
  /// **not** compose that clause itself (the DAP/SIT node); it must then be 5-9
  /// digits (see [NdidTransactionRef]).
  static Future<NdidVerifyRequest> createVerifyRequest({
    required String identifier,
    required String idpId,
    String? transactionRef,
    String? requestMessage,
    int requestTimeoutSeconds = 3600,
    String? requestType,
    NdidAs? dataSource,
  }) async {
    assert(
        transactionRef == null || NdidTransactionRef.isValid(transactionRef),
        'Transaction Ref must be 5-9 digits: $transactionRef');
    // Resolve the AS first: it decides both the endpoint and whether the
    // Request Message may name a data source. A failure here must not fail the
    // verification, so it degrades to the plain request.
    // A pinned id wins over resolution — it exists precisely for a gateway
    // where resolution does not work.
    final source = dataSource ?? await _pinnedAs() ?? await _findAsQuietly(idpId);
    final message = requestMessage ??
        NdidCommonMessage.requestMessage(
          transactionRef: transactionRef,
          // A pinned AS with no resolvable name contributes no clause rather
          // than an empty or invented one.
          asNames: (source == null || source.displayName.isEmpty)
              ? const []
              : [source.displayName],
        );
    final type = requestType ?? await NdidApi.requestType();
    final path = source == null ? '/rp/verify' : '/rp/verify-with-data';
    // Built once and kept, so the caller can show exactly what went on the
    // wire. Reconstructing it afterwards would be a second implementation
    // that could disagree with the first, which is the opposite of useful
    // when you are debugging what was sent.
    final body = <String, dynamic>{
      'namespace': citizenIdNamespace,
      'identifier': identifier,
      'request_message': message,
      'idp_id_list': [idpId],
      'min_idp': 1,
      'min_aal': minAal,
      'min_ial': minIal,
      'mode': 2,
      if (source != null) ...{
        'data_request_list': [
          {
            'service_id': dataServiceId,
            'as_id_list': [source.nodeId],
            'min_as': minAs,
            'request_params': '{}',
          },
        ],
        'callback_url': await dataCallbackUrl(),
      },
      'bypass_identity_check': false,
      'request_timeout': requestTimeoutSeconds,
      // Omitted unless configured — neither gateway requires it, and uat does
      // not use it. See [kNdidRequestType].
      if (type.isNotEmpty) 'request_type': type,
    };
    final json = await _post(path, body);
    if (json is! Map<String, dynamic> || json['reference_id'] == null) {
      throw NdidApiException('Unexpected $path response: $json');
    }
    return NdidVerifyRequest(
      referenceId: json['reference_id'].toString(),
      ndidRequestId: json['ndid_request_id']?.toString(),
      transactionRef: readTransactionRef(json),
      endpoint: '${await baseUrl()}$path',
      sentBody: body,
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
    // One resolve, so the key cannot come from a different gateway than the
    // URL it is sent to.
    final base = await baseUrl();
    final ApiHttpResult res;
    try {
      res = await sendApiRequest(
        method,
        Uri.parse('$base$path'),
        headers: _headers(base, json: body != null),
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
    this.industryCode = '',
    this.companyCode = '',
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

  /// NDID industry code, e.g. `001` for a bank. Empty when absent.
  final String industryCode;

  /// NDID company code, e.g. `004` for KBANK. Empty when absent.
  final String companyCode;

  /// Whether this IdP can be joined to an AS node — see
  /// [NdidApi.findAsForIdp], which matches on the code pair.
  bool get hasInstitutionCode =>
      industryCode.isNotEmpty && companyCode.isNotEmpty;

  factory NdidIdp.fromJson(Map<String, dynamic> json) {
    final en = (json['display_name'] ?? '').toString();
    final th = (json['display_name_th'] ?? '').toString();
    // The gateway flattens the codes onto the entry, but they also live inside
    // the `node_name` JSON string; read the flat ones and fall back, so this
    // survives a gateway that only sends the raw node_name (as `/services/…/as`
    // does).
    final nested = decodeNodeName(json['node_name']);
    String code(String key) {
      final flat = (json[key] ?? '').toString();
      return flat.isNotEmpty ? flat : (nested[key] ?? '').toString();
    }

    return NdidIdp(
      id: (json['id'] ?? json['node_id'] ?? '').toString(),
      displayNameTh: th.isNotEmpty ? th : en,
      displayNameEn: en,
      logoUrl: (json['logo_url'] ?? '').toString(),
      hasLogo: json['has_logo'] == true,
      industryCode: code('industry_code'),
      companyCode: code('company_code'),
    );
  }
}

/// `node_name` as sent by the gateway: a JSON **string** holding
/// `industry_code`, `company_code`, `marketing_name_th/en`, `role`, `running`.
///
/// `/idp/list` also flattens those onto the entry; `/services/{id}/as` does
/// not, so parsing this is the only way to identify an AS node. Never throws —
/// a malformed or absent value gives an empty map, and the caller degrades to
/// no data request rather than failing a verification over a name.
Map<String, dynamic> decodeNodeName(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  final text = (raw ?? '').toString();
  if (text.isEmpty) return const {};
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : const {};
  } catch (_) {
    return const {};
  }
}

/// One Authoritative Source of an NDID service, from
/// `GET /services/{serviceId}/as`.
class NdidAs {
  const NdidAs({
    required this.nodeId,
    required this.industryCode,
    required this.companyCode,
    required this.marketingNameTh,
    required this.marketingNameEn,
    this.minIal = 0,
    this.minAal = 0,
  });

  final String nodeId;
  final String industryCode;
  final String companyCode;
  final String marketingNameTh;
  final String marketingNameEn;
  final double minIal;
  final num minAal;

  /// The name to show a customer — Thai, falling back to English. This is what
  /// goes in the Request Message's AS clause, so it must be a **marketing
  /// name**, never a node id (§6.2.1 bullet 4).
  String get displayName =>
      marketingNameTh.isNotEmpty ? marketingNameTh : marketingNameEn;

  factory NdidAs.fromJson(Map<String, dynamic> json) {
    final name = decodeNodeName(json['node_name']);
    String field(String key) => (json[key] ?? name[key] ?? '').toString();
    return NdidAs(
      nodeId: (json['node_id'] ?? json['id'] ?? '').toString(),
      industryCode: field('industry_code'),
      companyCode: field('company_code'),
      marketingNameTh: field('marketing_name_th'),
      marketingNameEn: field('marketing_name_en'),
      minIal: double.tryParse('${json['min_ial']}') ?? 0,
      minAal: num.tryParse('${json['min_aal']}') ?? 0,
    );
  }
}

/// Result of `POST /rp/verify`.
class NdidVerifyRequest {
  const NdidVerifyRequest({
    required this.referenceId,
    this.ndidRequestId,
    this.transactionRef,
    this.endpoint = '',
    this.sentBody = const {},
  });

  final String referenceId;
  final String? ndidRequestId;

  /// The full URL the request went to — the resolved gateway plus
  /// `/rp/verify` or `/rp/verify-with-data`. Which of the two is itself the
  /// answer to "did the data request go out?", so it is worth showing.
  final String endpoint;

  /// **The body exactly as posted**, kept for the debug dialog on the verify
  /// screen.
  ///
  /// ⚠ It contains the customer's citizen id in `identifier`, so anything that
  /// displays or copies it must be non-prod only — same rule as
  /// `Diagnostics.report` and the `/ploan` failure report.
  final Map<String, dynamic> sentBody;

  /// [sentBody] as indented JSON, ready to show or copy.
  String get prettyBody {
    try {
      return const JsonEncoder.withIndent('  ').convert(sentBody);
    } catch (_) {
      // A value that won't encode is still worth showing as something.
      return sentBody.toString();
    }
  }

  /// The gateway's customer-facing **Transaction Ref** for this request — the
  /// number `ndid_verify_page` displays and the IdP app quotes.
  ///
  /// Null when the gateway didn't send one (the DAP/SIT node predates the
  /// field). The screen then has nothing legitimate to show, and says so rather
  /// than inventing a reference the bank never saw. See [NdidTransactionRef].
  final String? transactionRef;
}

/// Reads the gateway's `transaction_ref` off a verify or status response.
///
/// Tolerant of the camelCase spelling as well: this gateway is snake_case
/// everywhere, but the field is new (2026-08-31) and a one-line reader is
/// cheaper than a bug report about a blank reference on the waiting screen.
/// An empty value reads as absent.
String? readTransactionRef(Map<String, dynamic> json) {
  final raw = json['transaction_ref'] ?? json['transactionRef'];
  final value = raw?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

/// Result of `GET /rp/verify/{referenceId}`.
/// Status: CREATED | PENDING | ACCEPTED | REJECTED | TIMEOUT | CANCELLED.
class NdidVerifyStatus {
  const NdidVerifyStatus({
    required this.status,
    this.errorCode,
    this.transactionRef,
  });

  final String status;

  /// The gateway's `transaction_ref`, echoed on every poll.
  ///
  /// The create response carries it too; this is the backstop for the case where
  /// it doesn't, so the waiting screen can still fill in the reference on its
  /// first poll instead of showing a dash for the whole hour.
  final String? transactionRef;

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
        transactionRef: readTransactionRef(json),
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
