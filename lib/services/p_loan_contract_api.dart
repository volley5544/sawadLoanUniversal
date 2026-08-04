import 'dart:convert';

import '../config/app_environment.dart';
import '../p_loan/application/models/p_loan_submission.dart';
import 'api_transport.dart';
import 'app_config_api.dart';
import 'native_bridge.dart';
import 'srisawad_api.dart';

/// Client for the **P-Loan save API** — `POST /SavePloanContract`, where a
/// completed P-Loan application is filed.
///
/// Auth and body still differ from the mobile API: HTTP **Basic** auth instead
/// of a bearer token ([kPLoanSaveApiAuth]), and a `multipart/form-data` body
/// with repeated `group[]` file parts — the same shape `regmast_ploan.php`
/// takes. **The base URL, however, now comes from the same place the mobile API
/// does** (changed 2026-08-04): `api_url['api_url_base']` in the Firestore
/// config document `application/public_config`, with [kPLoanSaveApiBase] kept
/// only as the compile-time degrade-to. See [_base].
///
/// ## ⚠ Transport: this needs the native host
///
/// Verified against the live endpoint on 2026-07-27:
///
///   - a request with no `Authorization` header answers **401**;
///   - **no `Access-Control-Allow-*` header appears on any response**, and the
///     `OPTIONS` preflight is 401'd, so a browser upload is blocked before it
///     is ever sent;
///   - `GET`/`OPTIONS` with valid auth answer 404 — the route is POST-only.
///
/// So this cannot be called from a plain browser at all, and inside the WebView
/// it needs the host's **`httpMultipart`** bridge handler, which the host app
/// does not implement yet ([sendMultipartGroupsApiRequest] falls back to a
/// direct upload and, when that fails, says so). The alternative fix is CORS
/// headers on the endpoint; either side closes it.
class PLoanContractApi {
  PLoanContractApi._();

  /// Path appended to the resolved base (see [_base]).
  static const String path = '/SavePloanContract';

  /// Files the endpoint's own sample call populates. Used only to make a
  /// rejection legible: if the server refuses and one of these went out empty,
  /// say which.
  static const Set<String> _expectedNonEmpty = {
    'refContractNo',
    'citizenId',
    'mobileNo',
    'firstName',
    'lastName',
    'loanAmt',
    'termPeriod',
    'bankCode',
    'bankAccNo',
    'transferAmt',
    'statusCode',
    'empId',
    'branchId',
  };

  /// Files [submission] and returns the reference the server assigns, or `''`
  /// when the response carries none.
  ///
  /// Throws [SrisawadApiException] with the server's own message on refusal, so
  /// callers render the API's wording rather than a substitute.
  static Future<String> save(PLoanContractSubmission submission) async {
    final url = Uri.parse('${await _base()}$path');

    final files = <MultipartFilePart>[];
    submission.imageGroups.forEach((group, images) {
      for (var i = 0; i < images.length; i++) {
        files.add(MultipartFilePart(
          // Repeated `group[]` parts, matching the sample call.
          field: '$group[]',
          filename: '${group}_${i + 1}.jpg',
          bytes: images[i],
        ));
      }
    });

    final ApiHttpResult res;
    try {
      res = await sendMultipartGroupsApiRequest(
        url,
        headers: {'Authorization': kPLoanSaveApiAuth},
        fields: submission.fields,
        files: files,
      );
    } on ApiTransportException catch (e) {
      // Name the likely cause. This endpoint sends no CORS headers, so from a
      // plain browser the request never leaves — which looks like a network
      // outage unless you know that.
      final hint = NativeCameraBridge.isSupported
          ? ''
          : ' (เรียกจากเบราว์เซอร์ไม่ได้ — endpoint นี้ไม่ส่ง CORS header '
              'ต้องเรียกผ่านแอป)';
      throw SrisawadApiException('ส่งคำขอไม่สำเร็จ: ${e.message}$hint');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw SrisawadApiException(
        _refusalMessage(res, submission),
        statusCode: res.statusCode,
      );
    }

    final decoded = _decode(res.body);
    // Some endpoints in this family answer 200 with an error in the body.
    final error = _firstString(decoded, const ['error', 'errorMessage']);
    if (error.isNotEmpty) {
      throw SrisawadApiException(error, statusCode: res.statusCode);
    }
    return _firstString(
      decoded,
      const ['transNo', 'trans_no', 'contractNo', 'contract_no', 'refNo', 'id'],
    );
  }

  /// Base for the POST, resolved at call time.
  ///
  /// `api_url['api_url_base']` from the Firestore config document
  /// (`application/public_config`) is authoritative — the same per-project base
  /// [SrisawadApi.baseUrl] uses, so this call now lands on whatever host the
  /// mobile API does (uat: `https://dev.swpfin.com:7076`). [kPLoanSaveApiBase]
  /// (`:8082`) is only the degrade-to when the config can't be read, so a config
  /// outage still reaches the previously-working host rather than failing.
  static Future<String> _base() async {
    final config = await AppConfigApi.ensureLoaded();
    final base = (config.apiUrlBase ?? kPLoanSaveApiBase).trim();
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  /// The server's message when it gives one, plus the blank fields it may have
  /// objected to — a bare "HTTP 400" against 30 form fields is unactionable.
  static String _refusalMessage(
      ApiHttpResult res, PLoanContractSubmission submission) {
    final decoded = _decode(res.body);
    final fromServer =
        _firstString(decoded, const ['error', 'errorMessage', 'message']);
    final base = fromServer.isNotEmpty
        ? fromServer
        : 'ส่งคำขอไม่สำเร็จ (HTTP ${res.statusCode})';

    final blank = submission.unresolvedFields
        .where(_expectedNonEmpty.contains)
        .toList(growable: false);
    if (blank.isEmpty) return base;
    return '$base [ไม่มีข้อมูล: ${blank.join(', ')}]';
  }

  static dynamic _decode(String body) {
    if (body.trim().isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return body; // plain text is a valid answer here
    }
  }

  /// First non-empty value among [keys], looking one level into a `data`
  /// wrapper — the response shape isn't documented, so accept the usual ones
  /// rather than depending on a guess.
  static String _firstString(dynamic json, List<String> keys) {
    if (json is! Map) return '';
    for (final key in keys) {
      final value = json[key];
      if (value != null && '$value'.trim().isNotEmpty) return '$value'.trim();
    }
    final data = json['data'];
    return data is Map ? _firstString(data, keys) : '';
  }
}
