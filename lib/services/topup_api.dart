import '../p_loan/application/models/installment_plan.dart';
import '../p_loan/application/models/loan_amount_detail.dart';
import 'srisawad_api.dart';

/// **Top-up API group** — `/topup/*` on the srisawad mobile API.
///
/// Kept as its own group even though the P-Loan flow currently calls the same
/// endpoints (see [PLoanApi]). The two products share this endpoint family
/// because they start from the same data: an existing loan contract, its
/// approved limit and its installment calculation. Separating the groups means
/// either product's endpoints can move without disturbing the other.
class TopupApi {
  TopupApi._();

  /// `GET /topup/detail?db_name=&contract_no=` — limits, rate and deductions
  /// for one contract.
  ///
  /// The body carries its own `code`; anything but `200` throws with the
  /// server's message.
  static Future<LoanAmountDetail> fetchDetail({
    required String dbName,
    required String contractNo,
    required String token,
  }) async {
    final base = await SrisawadApi.baseUrl();
    final json = await SrisawadApi.send(
      'GET',
      Uri.parse('$base/topup/detail'
          '?db_name=${Uri.encodeQueryComponent(dbName)}'
          '&contract_no=${Uri.encodeQueryComponent(contractNo)}'),
      token: token,
    );
    if (json is! Map<String, dynamic>) {
      throw SrisawadApiException('Unexpected /topup/detail response: $json');
    }
    final detail = LoanAmountDetail.fromJson(json);
    if (!detail.isOk) {
      throw SrisawadApiException(detail.message.isNotEmpty
          ? detail.message
          : 'topup/detail ${detail.code}');
    }
    return detail;
  }

  /// `POST /topup/calculator` — installment options for [loanAmount].
  static Future<InstallmentPlan> calculateInstallments({
    required String dbName,
    required String contractNo,
    required int loanAmount,
    required double interestRate,
    required int feeAmount,
    required String token,
  }) async {
    final base = await SrisawadApi.baseUrl();
    final json = await SrisawadApi.send(
      'POST',
      Uri.parse('$base/topup/calculator'),
      token: token,
      body: {
        'transno': '',
        'db_name': dbName,
        'contract_no': contractNo,
        'loan_amount': loanAmount.toDouble(),
        'interest_rate': interestRate,
        'topup_fee_amount': feeAmount.toDouble(),
        'fee_amount': feeAmount.toDouble(),
      },
    );
    if (json is! Map<String, dynamic>) {
      throw SrisawadApiException('Unexpected /topup/calculator response: $json');
    }
    final plan = InstallmentPlan.fromJson(json);
    if (plan.installments.isEmpty) {
      throw SrisawadApiException(plan.message.isNotEmpty
          ? plan.message
          : 'ไม่พบตัวเลือกจำนวนงวดสำหรับยอดที่ขอ');
    }
    return plan;
  }

  /// `POST /topup` — submits the request.
  ///
  /// Replies with a `head`/`body` envelope unlike every other endpoint in this
  /// group: `head.error_flag == 'N'` means success and `body.trans_no` is the
  /// new transaction number.
  static Future<String> submit({
    required Map<String, dynamic> payload,
    required String token,
  }) async {
    final base = await SrisawadApi.baseUrl();
    final json = await SrisawadApi.send(
      'POST',
      Uri.parse('$base/topup'),
      token: token,
      body: payload,
    );
    if (json is! Map<String, dynamic>) {
      throw SrisawadApiException('Unexpected /topup response: $json');
    }
    final head = json['head'];
    final flag = head is Map ? '${head['error_flag'] ?? ''}' : '';
    if (flag != 'N') {
      final desc = head is Map ? '${head['error_desc'] ?? ''}' : '';
      throw SrisawadApiException(
          desc.isNotEmpty ? desc : 'ส่งคำขอไม่สำเร็จ กรุณาลองใหม่');
    }
    final body = json['body'];
    return body is Map ? '${body['trans_no'] ?? ''}' : '';
  }
}
