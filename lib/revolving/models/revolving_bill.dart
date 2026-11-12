/// **ดูบิล** — the BA's `createFileRequest (billing statement)`, from
/// *[Mobile][RVL][Integration] Billing statement process* (2026-11-12).
///
/// | | Spec |
/// | --- | --- |
/// | request | `type: "BILLING_STATEMENT"`, `contractId` |
/// | 200 | `data.url` — the statement PDF, opened in-app, no share / open-in-browser |
/// | 400 | `message` — shown as-is in the "not issued yet" popup (first period, before billing) |
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

  /// `message` on a 400 — or on any failure that carries one.
  final String message;

  bool get hasFile => url.isNotEmpty;

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
    final message = asString(root['message']);
    if (status >= 200 && status < 300 && url.isNotEmpty) {
      return RevolvingBillStatement(url: url);
    }
    return RevolvingBillStatement(message: message.isEmpty ? '-' : message);
  }
}
