/// **ดูบิล** — the BA's `createFileRequest (billing statement)`, from
/// *[Mobile][RVL][Integration] Billing statement process* **v02** (2026-11-12).
///
/// | | Spec |
/// | --- | --- |
/// | header | `Accept-Language: th` ([requestHeaders]) — new in v02 |
/// | request | `type: "BILLING_STATEMENT"`, `contract_id` |
/// | 200 | `data.url` — the statement PDF, opened in-app, no share / open-in-browser |
/// | 400 | **`detail`** — shown as-is in the "not issued yet" popup (first period, before billing). v01 said `message`; v02 changed it |
///
/// ⚠ **node-api has no route for it yet** — its revolving guide lists only
/// the acceptance, withdrawal and history calls — so nothing calls this. The
/// request and response are mapped here so wiring the call is one function
/// in `RevolvingApi`. The contract goes out as **`contract_id`**: the BA's
/// spec spells LMS's camelCase, but node-api and the srisawad backend use
/// snake_case (confirmed 2026-11-12).
library;

import '../../p_loan/application/models/json_coerce.dart';

class RevolvingBillStatement {
  const RevolvingBillStatement({this.url = '', this.message = ''});

  /// `data.url` on a 200.
  final String url;

  /// The popup text: `detail` on a 400 (or any failure carrying one). `-`
  /// when the response has none — v01's `message` is deliberately not read.
  final String message;

  bool get hasFile => url.isNotEmpty;

  /// The extra header v02 names, so the backend answers [message] in Thai.
  /// Not sent anywhere yet.
  static const Map<String, String> requestHeaders = {'Accept-Language': 'th'};

  /// The body the spec names. Not sent anywhere yet.
  static Map<String, dynamic> requestBody(int contractId) => {
        'type': 'BILLING_STATEMENT',
        'contract_id': contractId,
      };

  /// Maps a response by its HTTP status, tolerating a `results` envelope.
  /// A 200 with no `data.url` is reported through [message] as `-`, never
  /// as a file.
  factory RevolvingBillStatement.fromResponse(int status, dynamic json) {
    final body = asMap(json);
    final root = body['results'] is Map ? asMap(body['results']) : body;
    final url = asString(asMap(root['data'])['url']);
    final message = asString(root['detail']);
    if (status >= 200 && status < 300 && url.isNotEmpty) {
      return RevolvingBillStatement(url: url);
    }
    return RevolvingBillStatement(message: message.isEmpty ? '-' : message);
  }
}
