import 'dart:convert';

import '../config/app_environment.dart';
import '../p_loan/application/models/loan_contract.dart';
import 'api_transport.dart';
import 'app_config_api.dart';
import 'auth_token.dart';
import 'url_masking.dart';

/// Shared plumbing for the srisawad **mobile API** groups ([TopupApi],
/// [PLoanApi] and [UserApi]).
///
/// ## Base URL
///
/// Resolved at call time, in this order:
///
///   1. `api_url['api_url_prod']` on a prod build, `api_url['api_url_dev']` on
///      a uat one — **the authoritative pair**. Environments are separated by
///      field name, so one document cannot hand uat the prod host.
///   2. `api_url['api_url_base']`, for a document carrying neither of those.
///      ⚠ It names no environment, which is why it is no longer preferred
///      (changed 2026-09-11).
///   3. [AppEnvironment.current.mobileApiBase], the compile-time default.
///
/// Step 3 means a config outage degrades to the built-in endpoint rather than
/// breaking the app. [baseUrl] awaits the memoised config load, so the first
/// call may wait on that one request and later calls resolve immediately.
class SrisawadApi {
  SrisawadApi._();

  /// The most recent `GET /loan/list` exchange, **as it came off the wire**.
  ///
  /// Kept so the loan detail screen can show the raw response on a non-prod
  /// build (its `/loan/list` response dialog). It is the transport's own body
  /// rather than a re-encoding of the parsed [LoanContract]s on purpose: a
  /// reconstruction can only contain the fields this build already knows
  /// about, which is the opposite of what someone opens that dialog to find
  /// out — a field the API added, or one it stopped sending.
  ///
  /// Null until a live call has been made. **Mock mode never fills it**, so a
  /// fixture-served list cannot be mistaken for a gateway response.
  static RawApiExchange? lastLoanListExchange;

  /// Endpoint every group below hangs off. No trailing slash.
  static Future<String> baseUrl() async {
    final config = await AppConfigApi.ensureLoaded();
    final fromConfig = config.apiUrlForEnvironment ?? config.apiUrlBase;
    return fromConfig ?? AppEnvironment.current.mobileApiBase;
  }

  /// Standard headers for **every** call on this base: `x-srisawad` and the
  /// customer's Firebase `Authorization: Bearer`. [contentType] is omitted for
  /// GETs.
  ///
  /// An empty [token] sends **no** `Authorization` at all rather than a bare
  /// `Bearer ` — a header with no credential in it is worse than none, since it
  /// looks authenticated in a capture. But an unauthenticated call is not
  /// something to pass over quietly: the caller is about to be 401'd and the
  /// cause is usually a missing `?token=` launch param, so say so once, on the
  /// spot. Silence here is how `/user/detail` went unauthenticated unnoticed.
  static Map<String, String> headers(
    String token, {
    String? contentType,
    Map<String, String> extra = const {},
  }) {
    if (token.isEmpty) {
      // ignore: avoid_print — intentional: surface in the WebView console.
      print('[SawadLoanUniversal] WARNING: mobile-API call with no bearer '
          'token — check the ?token= launch param');
    }
    return {
      if (AppEnvironment.current.srisawadHeader.isNotEmpty)
        'x-srisawad': AppEnvironment.current.srisawadHeader,
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      'Content-Type': ?contentType,
      ...extra,
    };
  }

  /// [headers], with the bearer resolved from the native host rather than
  /// taken on trust from the caller.
  ///
  /// Every mobile-API call goes through here or through [headers] directly, and
  /// the `token` each group threads through is the `?token=` launch param —
  /// which is an hour-lived credential that also does not survive a reload.
  /// [AuthToken.resolve] asks the host for a live one and treats
  /// [launchToken] as the fallback, so callers keep passing exactly what they
  /// passed before.
  ///
  /// [headers] itself stays synchronous and unchanged: it is the pure
  /// credential-shaping rule, pinned by `test/srisawad_api_headers_test.dart`.
  static Future<Map<String, String>> authHeaders(
    String launchToken, {
    String? contentType,
    Map<String, String> extra = const {},
  }) async =>
      headers(
        await AuthToken.resolve(launchToken),
        contentType: contentType,
        extra: extra,
      );

  /// GET/POST returning decoded JSON, or throwing [SrisawadApiException].
  ///
  /// [onResponse] receives the transport result **before** it is decoded or
  /// status-checked, which is the only place the untouched body still exists —
  /// [send] returns parsed JSON and a failure throws. It fires for every
  /// response, 2xx or not; a request that never produced one (a timeout, a
  /// rejected URL) throws past it, as there is nothing to hand over.
  static Future<dynamic> send(
    String method,
    Uri url, {
    required String token,
    Map<String, dynamic>? body,
    Map<String, String> extraHeaders = const {},
    void Function(ApiHttpResult response)? onResponse,
  }) async {
    final ApiHttpResult res;
    try {
      res = await sendApiRequest(
        method,
        url,
        headers: await authHeaders(
          token,
          contentType: body == null ? null : 'application/json',
          extra: extraHeaders,
        ),
        body: body == null ? null : jsonEncode(body),
      );
    } on ApiTransportException catch (e) {
      throw SrisawadApiException('mobile API ${e.message}');
    }
    onResponse?.call(res);

    final json = decode(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message = (json is Map && json['message'] != null)
          ? json['message'].toString()
          : 'HTTP ${res.statusCode}';
      throw SrisawadApiException(message, statusCode: res.statusCode);
    }
    return json;
  }

  static dynamic decode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  /// `GET /loan/list?hash_thai_id=<hash>` — the customer's existing contracts.
  ///
  /// Shared deliberately: both the top-up flow and the P-Loan flow start from
  /// this same list, which is why the P-Loan screens were originally built on
  /// the top-up endpoints.
  static Future<List<LoanContract>> listContracts({
    required String hashThaiId,
    required String token,
  }) async {
    final base = await baseUrl();
    final url = Uri.parse(
        '$base/loan/list?hash_thai_id=${Uri.encodeQueryComponent(hashThaiId)}');
    final json = await send(
      'GET',
      url,
      token: token,
      onResponse: (res) => lastLoanListExchange = RawApiExchange(
        method: 'GET',
        url: url.toString(),
        statusCode: res.statusCode,
        body: res.body,
      ),
    );
    final results = json is Map<String, dynamic> ? json['results'] : null;
    if (results is! List) {
      throw SrisawadApiException('Unexpected /loan/list response: $json');
    }
    return results
        .whereType<Map<String, dynamic>>()
        .map(LoanContract.fromJson)
        .toList(growable: false);
  }
}

/// Failure from any srisawad mobile-API group.
class SrisawadApiException implements Exception {
  SrisawadApiException(this.message, {this.statusCode, this.details});

  final String message;
  final int? statusCode;

  /// The full technical account of the failure, for a screen that offers to
  /// show it — the request line, the status, the response headers and the
  /// **whole response body, untruncated**.
  ///
  /// Deliberately separate from [message], which is what the customer reads:
  /// an HTML 500 page or a stack trace from the gateway is exactly what a
  /// developer needs and exactly what a customer should not be shown. Null
  /// when the caller collected none.
  ///
  /// ⚠ It can contain personal data and must be treated like
  /// `Diagnostics.report` — mask credentials before putting them in here.
  final String? details;

  @override
  String toString() => 'SrisawadApiException: $message';
}

/// One request/response exchange kept verbatim, for a screen that offers to
/// show what the gateway actually said.
///
/// [body] is the transport's own string — never re-encoded from a parsed
/// model, so it still carries fields this build does not read and reveals one
/// the API has stopped sending. [prettyBody] only re-indents it for display;
/// the content is unchanged, and a body that is not JSON is shown as sent
/// rather than swallowed.
///
/// ⚠ It is the customer's own data. Treat it like `Diagnostics.report`: show
/// it on non-prod only, and mask credentials in anything derived from it —
/// [report] runs the URL through `maskUrlSecrets` for exactly that reason.
class RawApiExchange {
  const RawApiExchange({
    required this.method,
    required this.url,
    required this.statusCode,
    required this.body,
  });

  final String method;
  final String url;
  final int statusCode;
  final String body;

  /// [body] re-indented when it parses as JSON, as sent when it does not.
  String get prettyBody {
    final decoded = SrisawadApi.decode(body);
    if (decoded == null) return body;
    try {
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return body;
    }
  }

  /// The whole exchange as one block of text — what a copy button hands over.
  ///
  /// The URL is masked: `hash_thai_id` identifies the customer, and this
  /// string exists to be pasted into a chat.
  String get report =>
      '$method ${maskUrlSecrets(url)}\nHTTP $statusCode\n\n$prettyBody';
}
