/// The one endpoint the **loan detail** screen needs that no other flow calls.
///
/// Everything else on that screen comes from `GET /loan/list`
/// ([SrisawadApi.listContracts]) — deliberately, and the same way both
/// reference clients do it: the list row already carries `contract_details`,
/// `payment_details` and `car_details` in full, so there is no `loan/detail`
/// call to make and the screen cannot disagree with the list it was opened
/// from.
library;

import '../config/app_environment.dart';
import '../loan_detail/models/payment_history_entry.dart';
import '../p_loan/application/models/json_coerce.dart';
import 'srisawad_api.dart';

class LoanDetailApi {
  LoanDetailApi._();

  /// `POST /payment/history_new` — payments already made against a contract,
  /// newest first as the server orders them.
  ///
  /// ⚠ **[dbName] is truncated to its first two characters** — `MLOAN` goes
  /// out as `ML`. **Confirmed on a device, 2026-09-14**: that is what this
  /// endpoint wants, and the whole name returns a `200` with an empty `data`
  /// rather than an error, which is exactly what a well-formed request for a
  /// database that does not exist looks like.
  ///
  /// It is worth knowing the two references disagree, because the truncation
  /// reads like a bug: the srisawad mobile app sends the whole name,
  /// LandAndHouseWeb sends `dbName.substring(0, 2)` — and that call is the
  /// **only** `substring(0, 2)` on a `db_name` in its entire codebase, every
  /// other one passing it whole. A truncation applied to one endpoint out of a
  /// dozen is a deliberate accommodation of that endpoint, and the device test
  /// bore that out.
  ///
  /// The srisawad app's whole-name call stays unexplained — a different
  /// gateway, or its own history tab is quietly empty too. One question to the
  /// API team, not a blocker.
  static Future<PaymentHistory> fetchPaymentHistory({
    required String contractNo,
    required String dbName,
    required String token,
  }) async {
    if (kPLoanUseMockData) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return mockPaymentHistory;
    }
    final base = await SrisawadApi.baseUrl();
    final json = await SrisawadApi.send(
      'POST',
      Uri.parse('$base/payment/history_new'),
      token: token,
      body: {'contract_no': contractNo, 'db_name': wireDbName(dbName)},
    );
    // `data`, not `results` — this endpoint does not use the envelope the rest
    // of the mobile API does. `data_date` sits beside it, at the top level.
    final body = json is Map<String, dynamic> ? json : const {};
    final data = body['data'];
    if (data is! List) {
      throw SrisawadApiException(
          'Unexpected /payment/history_new response: $json');
    }
    return PaymentHistory(
      entries: data
          .whereType<Map<String, dynamic>>()
          .map(PaymentHistoryEntry.fromJson)
          .toList(growable: false),
      dataDate: asString(body['data_date']),
    );
  }

  /// How `db_name` is spelled on the wire for this endpoint. See
  /// [fetchPaymentHistory] for why there are two candidate spellings; change
  /// this one function, not the call site.
  static String wireDbName(String dbName) {
    final name = dbName.trim();
    if (!useDbNamePrefix) return name;
    return name.length <= dbNamePrefixLength
        ? name
        : name.substring(0, dbNamePrefixLength);
  }

  /// `true` sends `ML`, which is what this endpoint answers to; `false` sends
  /// `MLOAN`, which returns no rows. Kept as a named switch rather than
  /// inlined so the truncation reads as a decision — see
  /// [fetchPaymentHistory].
  static const bool useDbNamePrefix = true;
  static const int dbNamePrefixLength = 2;

  /// Fixtures for `--dart-define=P_LOAN_MOCK=true`, built through the real
  /// `fromJson` so a wire-key change breaks them too.
  static final PaymentHistory mockPaymentHistory = PaymentHistory(
    dataDate: '2026-09-09 13:05:04',
    entries: [
    PaymentHistoryEntry.fromJson(const {
      'date': '05-08-2026 14:12',
      'paid_amount': 3250.0,
      'payment_channel_code': 'CTR',
      'payment_channel_name': 'เคาน์เตอร์เซอร์วิส',
    }),
    PaymentHistoryEntry.fromJson(const {
      'date': '04-07-2026 09:47',
      'paid_amount': 3250.0,
      'payment_channel_code': 'MBK',
      'payment_channel_name': 'โมบายแบงก์กิ้ง',
      }),
    ],
  );
}
