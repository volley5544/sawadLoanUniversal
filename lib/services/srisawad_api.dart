import 'dart:convert';

import '../config/app_environment.dart';
import '../p_loan/application/models/loan_contract.dart';
import 'api_transport.dart';
import 'app_config_api.dart';

/// Shared plumbing for the srisawad **mobile API** groups ([TopupApi],
/// [PLoanApi] and [UserApi]).
///
/// ## Base URL
///
/// Resolved at call time, in this order:
///
///   1. `api_url['api_url_base']` from the Firestore config document — the
///      per-project base, so the uat project holds the uat host and prod holds
///      prod. This is the authoritative value.
///   2. `api_url['api_url_prod']` / `api_url['api_url_dev']` for the active
///      environment, if `api_url_base` is missing.
///   3. [AppEnvironment.current.mobileApiBase], the compile-time default.
///
/// Step 3 means a config outage degrades to the built-in endpoint rather than
/// breaking the app. [baseUrl] awaits the memoised config load, so the first
/// call may wait on that one request and later calls resolve immediately.
class SrisawadApi {
  SrisawadApi._();

  /// Endpoint every group below hangs off. No trailing slash.
  static Future<String> baseUrl() async {
    final config = await AppConfigApi.ensureLoaded();
    final fromConfig = config.apiUrlBase ??
        (AppEnvironment.current.isProd ? config.apiUrlProd : config.apiUrlDev);
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

  /// GET/POST returning decoded JSON, or throwing [SrisawadApiException].
  static Future<dynamic> send(
    String method,
    Uri url, {
    required String token,
    Map<String, dynamic>? body,
    Map<String, String> extraHeaders = const {},
  }) async {
    final ApiHttpResult res;
    try {
      res = await sendApiRequest(
        method,
        url,
        headers: headers(
          token,
          contentType: body == null ? null : 'application/json',
          extra: extraHeaders,
        ),
        body: body == null ? null : jsonEncode(body),
      );
    } on ApiTransportException catch (e) {
      throw SrisawadApiException('mobile API ${e.message}');
    }

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
    final json = await send(
      'GET',
      Uri.parse(
          '$base/loan/list?hash_thai_id=${Uri.encodeQueryComponent(hashThaiId)}'),
      token: token,
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
  SrisawadApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'SrisawadApiException: $message';
}
