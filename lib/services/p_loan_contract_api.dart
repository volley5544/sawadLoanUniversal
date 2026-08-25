import 'dart:convert';

import '../p_loan/application/models/p_loan_submission.dart';
import 'api_transport.dart';
import 'srisawad_api.dart';

/// Client for the **P-Loan save API** — `POST /ploan`, where a completed P-Loan
/// application (either kind) is filed.
///
/// **Retargeted 2026-08-04** from the old `POST <:8082>/SavePloanContract`
/// (multipart body, a shared HTTP **Basic** credential baked into the bundle) to
/// a plain **mobile-API-style call**:
///
///   - **Base URL** = `api_url['api_url_base']` from the Firestore config
///     document `application/public_config` — the same per-project base
///     [SrisawadApi.baseUrl] resolves, so uat lands on `dev.swpfin.com:7076`;
///   - **Auth** = the customer's own Firebase **bearer token** (the `?token=`
///     launch param), so no service credential ships in the bundle — this is
///     what closed that pentest finding;
///   - **Header** `x-srisawad` from [SrisawadApi.headers] like every other
///     mobile-API call (`x1` on both prod and the new uat gateway);
///   - **Body** = `multipart/form-data` (2026-08-07, was JSON): the 30 scalar
///     fields from the API's sample call **plus `ndid_reference_id`**
///     (2026-08-14) as form fields, plus five real file parts — `cardIdImage`,
///     `customerImage` and `documentImage[]` ×3 carrying the contract PDFs the
///     customer consented to.
///
/// **The upload goes direct through `package:http`, never the host bridge**
/// (`bypassHostBridge: true`). That is the whole reason multipart is affordable
/// here: the host's `httpRequest`/`httpMultipart` handlers exist because the
/// **old** `<:8082>/SavePloanContract` sent no CORS headers, so a browser upload
/// was blocked outright. `/ploan` is on the mobile API base, which answers
/// `access-control-allow-origin: *` — the same reason
/// [sendMultipartApiRequest] already uploads the ID card that way. So this
/// needs **no `httpMultipart` bridge handler and no app release**, in the host
/// or a plain browser alike.
///
/// ⚠ The request carries five files, so it is large. A timeout or a
/// request-size limit is the first thing to suspect if a submit that used to
/// work starts failing.
class PLoanContractApi {
  PLoanContractApi._();

  /// Path appended to [SrisawadApi.baseUrl].
  static const String path = '/ploan';

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
    // `empId` is deliberately absent: it is accepted blank (see
    // PLoanContractSubmission.acceptedBlank), so naming it in a refusal would
    // point at a field that is empty on purpose.
    'branchId',
    // NDID's reference for the accepted verification. `canSubmit` requires the
    // NDID hop, so a blank one means the flow was completed without a real
    // verification (a simulated hop) — precisely the thing the server will
    // refuse, and worth naming so the refusal is legible.
    'ndid_reference_id',
    // The file fields. `canSubmit` gates on all three, so a blank one here is
    // worth naming rather than leaving the server to say "HTTP 400".
    'cardIdImage',
    'customerImage',
    'documentImage',
  };

  /// Files [submission] as `multipart/form-data` and returns the reference the
  /// server assigns, or `''` when the response carries none. [token] is the
  /// customer's Firebase bearer token (the `?token=` launch param).
  ///
  /// Throws [SrisawadApiException] with the server's own message on refusal, so
  /// callers render the API's wording rather than a substitute.
  static Future<String> save(
    PLoanContractSubmission submission, {
    required String token,
  }) async {
    final base = await SrisawadApi.baseUrl();
    final url = Uri.parse('$base$path');

    final ApiHttpResult res;
    try {
      res = await sendMultipartGroupsApiRequest(
        url,
        // No Content-Type: MultipartRequest has to append its own boundary.
        headers: SrisawadApi.headers(token),
        fields: submission.fields,
        files: [
          for (final f in submission.files)
            MultipartFilePart(
              field: f.field,
              filename: f.filename,
              contentType: f.contentType,
              bytes: f.bytes,
            ),
        ],
        // The mobile API sends `access-control-allow-origin: *`, so the upload
        // goes direct and needs no `httpMultipart` handler in the host.
        bypassHostBridge: true,
      );
    } on ApiTransportException catch (e) {
      throw SrisawadApiException('ส่งคำขอไม่สำเร็จ: ${e.message}');
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
