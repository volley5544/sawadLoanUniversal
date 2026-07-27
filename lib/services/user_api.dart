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
///      (requires the Firebase `Authorization: Bearer` token the native host
///      passes via the `?token=` launch URL param)
///
/// Base URL + `x-srisawad` header come from [AppEnvironment.current]
/// (prod: `https://mobile-api.swpfin.com` + `x-srisawad: x1`;
/// uat: `https://dev.swpfin.com:7076`, header not required). Transport goes
/// through [sendApiRequest] (host `httpRequest` bridge inside the WebView,
/// plain `http` in a browser — these endpoints do send CORS headers).
class UserApi {
  UserApi._();

  /// Base URL from the Firestore runtime config (`api_url.api_url_base`),
  /// falling back to the compile-time [AppEnvironment] value. Shared with the
  /// top-up and P-Loan groups so every caller agrees on one endpoint — see
  /// [SrisawadApi.baseUrl].
  static Future<String> get _base => SrisawadApi.baseUrl();

  static Map<String, String> _headers({String? token}) =>
      SrisawadApi.headers(token ?? '');

  /// Fetches the customer profile for [hashThaiId]. The payload sits under
  /// `results` with its own `code`/`message`; anything but code 200 throws.
  static Future<CustomerDetail> fetchUserDetail(String hashThaiId) async {
    final base = await _base;
    final json = await _getJson(
      Uri.parse('$base/user/detail'
          '?hash_thai_id=${Uri.encodeQueryComponent(hashThaiId)}'),
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
    String? token,
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

  static Future<dynamic> _getJson(Uri url, {String? token}) async {
    final ApiHttpResult res;
    try {
      res = await sendApiRequest('GET', url, headers: _headers(token: token));
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
