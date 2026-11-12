/// บัตรศรีสวัสดิ์ (revolving) calls on the mobile API base — node-api's
/// `revolvingLoan/*` proxy, the customer's own bearer + `x-srisawad`, like
/// every other call here (guide: git-ignored
/// `etc/revolving_feature/api-call/revolving-frontend-api.md`).
///
/// ⚠ **Reads only** (2026-11-12). The write routes — `saveAcceptanceFlag`,
/// `applyForWithdrawal`, `dayOneWithdrawal` — move state or **real money**
/// and are deliberately not here until asked for; the request body
/// `applyForWithdrawal` would take is built (and only built) by
/// `RevolvingWithdrawalRequest`.
library;

import '../config/app_environment.dart';
import '../revolving/models/revolving_withdrawal.dart';
import 'srisawad_api.dart';

class RevolvingApi {
  RevolvingApi._();

  /// `GET revolvingLoan/withdrawal/{contractId}` — the BA's
  /// `getMobileWithdrawal`: วงเงินอนุมัติ, the withdrawal expiry date and
  /// ประวัติการถอน/โอน. [contractId] is `revolving_loans.contract_id` (the
  /// numeric LMS id), **not** `contract_no`.
  static Future<RevolvingWithdrawalInfo> fetchWithdrawal({
    required int contractId,
    required String token,
  }) async {
    // Mock mode must not call the live API behind its banner.
    if (kPLoanUseMockData) return const RevolvingWithdrawalInfo();
    if (contractId <= 0) {
      throw SrisawadApiException('ไม่พบรหัสสัญญาบัตรศรีสวัสดิ์');
    }
    final base = await SrisawadApi.baseUrl();
    final json = await SrisawadApi.send(
      'GET',
      Uri.parse('$base/revolvingLoan/withdrawal/$contractId'),
      token: token,
    );
    if (json is! Map<String, dynamic>) {
      throw SrisawadApiException(
          'Unexpected revolvingLoan/withdrawal response: $json');
    }
    return RevolvingWithdrawalInfo.fromJson(json);
  }
}
