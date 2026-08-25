import 'dart:convert';

import '../config/app_environment.dart';
import '../models/customer_address.dart';
import '../models/customer_detail.dart';
import 'api_transport.dart';
import 'srisawad_api.dart';

/// Client for the srisawad **mobile API** (`api_data/api1.md`):
///
///   1. `GET /user/detail?hash_thai_id=<hash>` — customer profile
///   2. `GET /profile/address/<hash>`          — customer address book
///
/// **Both require the Firebase `Authorization: Bearer` token** the native host
/// passes via the `?token=` launch URL param, so [token] is a required argument
/// on each — the compiler is the guard, since a caller that simply forgot it is
/// how `/user/detail` came to be fetched unauthenticated (pentest finding #2,
/// "Authenticated API could be accessed without authentication", which names
/// that endpoint first). The header itself is added by [SrisawadApi.headers].
///
/// Base URL + `x-srisawad` header come from [AppEnvironment.current]
/// (prod: `https://mobile-api.swpfin.com` + `x-srisawad: x1`;
/// uat: `https://dev.swpfin.com:7076` + `x-srisawad: x1` — the new uat gateway
/// requires it too, as of 2026-08-04). Transport goes
/// through [sendApiRequest] (host `httpRequest` bridge inside the WebView,
/// plain `http` in a browser — these endpoints do send CORS headers).
class UserApi {
  UserApi._();

  /// Base URL from the Firestore runtime config (`api_url.api_url_base`),
  /// falling back to the compile-time [AppEnvironment] value. Shared with the
  /// top-up and P-Loan groups so every caller agrees on one endpoint — see
  /// [SrisawadApi.baseUrl].
  static Future<String> get _base => SrisawadApi.baseUrl();

  /// Takes the token positionally and non-null: an optional one let `?? ''`
  /// stand in for a real credential, which is exactly the omission that left
  /// `/user/detail` unauthenticated.
  static Map<String, String> _headers(String token) =>
      SrisawadApi.headers(token);

  /// Fetches the customer profile for [hashThaiId]. The payload sits under
  /// `results` with its own `code`/`message`; anything but code 200 throws.
  ///
  /// [token] is the Firebase auth token from the native host (`?token=` launch
  /// param) — required, see the class doc.
  static Future<CustomerDetail> fetchUserDetail(
    String hashThaiId, {
    required String token,
  }) async {
    final base = await _base;
    final json = await _getJson(
      Uri.parse('$base/user/detail'
          '?hash_thai_id=${Uri.encodeQueryComponent(hashThaiId)}'),
      token: token,
    );
    final results = json is Map<String, dynamic> ? json['results'] : null;
    if (results is! Map<String, dynamic>) {
      throw UserApiException('Unexpected /user/detail response: $json');
    }
    final code = '${results['code'] ?? ''}';
    if (code != '200') {
      throw UserApiException(
          'user/detail failed: $code ${results['message'] ?? ''}');
    }
    return CustomerDetail.fromJson(results);
  }

  /// Fetches the customer's address book for [hashThaiId]. [token] is the
  /// Firebase auth token from the native host (`?token=` launch param).
  static Future<CustomerAddressBook> fetchAddressBook(
    String hashThaiId, {
    required String token,
  }) async {
    final base = await _base;
    final json = await _getJson(
      Uri.parse('$base/profile/address/${Uri.encodeComponent(hashThaiId)}'),
      token: token,
    );
    if (json is! Map<String, dynamic>) {
      throw UserApiException('Unexpected /profile/address response: $json');
    }
    return CustomerAddressBook.fromJson(json);
  }

  static Future<dynamic> _getJson(Uri url, {required String token}) async {
    final ApiHttpResult res;
    try {
      res = await sendApiRequest('GET', url, headers: _headers(token));
    } on ApiTransportException catch (e) {
      throw UserApiException('mobile API ${e.message}');
    }
    dynamic json;
    try {
      json = jsonDecode(res.body);
    } catch (_) {
      json = null;
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message = (json is Map && json['message'] != null)
          ? json['message'].toString()
          : 'HTTP ${res.statusCode}';
      throw UserApiException(message, statusCode: res.statusCode);
    }
    return json;
  }
}

class UserApiException implements Exception {
  UserApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'UserApiException: $message';
}
