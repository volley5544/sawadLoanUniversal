import 'dart:convert';
import 'dart:typed_data';

import '../config/app_environment.dart';
import '../models/customer_address.dart';
import '../models/customer_detail.dart';
import '../p_loan/application/models/installment_plan.dart';
import '../p_loan/application/models/loan_amount_detail.dart';
import '../p_loan/application/models/loan_contract.dart';
import '../p_loan/application/models/loan_documents.dart';
import '../p_loan/application/models/p_loan_mock.dart';
import '../topup/models/topup_settlement.dart';
import '../topup/models/topup_status.dart';
import 'api_transport.dart';
import 'diagnostics.dart';
import 'app_config_api.dart';
import 'p_loan_api.dart';
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

  /// Simulated latency, so loading states still appear in mock mode.
  static Future<T> _mock<T>(T value) =>
      Future.delayed(kMockLatency, () => value);

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
    if (kPLoanUseMockData) return _mock(mockAmountDetail(contractNo));
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
    if (kPLoanUseMockData) return _mock(mockInstallmentPlan(loanAmount));
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
    if (kPLoanUseMockData) return _mock(mockTransNo());
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

  /// `GET /topup/status-detail/{hash_thai_id}/{db_name}/{trans_no}` — the
  /// state of a request that has already been filed, plus the three contract
  /// PDFs as filed.
  ///
  /// Note the path is positional, not a query string, unlike every other
  /// `/topup/*` call.
  static Future<TopupStatus> fetchStatusDetail({
    required String hashThaiId,
    required String dbName,
    required String transNo,
    required String token,
  }) async {
    if (kPLoanUseMockData) return _mock(mockTopupStatus(transNo));
    final base = await SrisawadApi.baseUrl();
    final json = await SrisawadApi.send(
      'GET',
      Uri.parse('$base/topup/status-detail'
          '/${Uri.encodeComponent(hashThaiId)}'
          '/${Uri.encodeComponent(dbName)}'
          '/${Uri.encodeComponent(transNo)}'),
      token: token,
    );
    if (json is! Map<String, dynamic>) {
      throw SrisawadApiException('Unexpected /topup/status-detail: $json');
    }
    final status = TopupStatus.fromJson(json);
    if (!status.isOk) {
      throw SrisawadApiException(status.message.isNotEmpty
          ? status.message
          : 'topup/status-detail ${status.code}');
    }
    return status;
  }

  /// `POST /payment/interest` — raises a bill-payment reference for the
  /// accrued interest that has to be settled before a top-up can be raised.
  ///
  /// Returns the barcode/QR reference parts echoed by the server, which the
  /// QR screen renders. The screen also has the contract's own
  /// `barcode_details` to fall back on, so a thin response is not fatal.
  static Future<Map<String, dynamic>> payInterest({
    required Map<String, dynamic> payload,
    required String token,
  }) async {
    if (kPLoanUseMockData) return _mock(const {'code': '200'});
    final base = await SrisawadApi.baseUrl();
    final json = await SrisawadApi.send(
      'POST',
      Uri.parse('$base/payment/interest'),
      token: token,
      body: payload,
    );
    if (json is! Map<String, dynamic>) {
      throw SrisawadApiException('Unexpected /payment/interest: $json');
    }
    final code = '${json['code'] ?? ''}';
    if (code.isNotEmpty && code != '200') {
      throw SrisawadApiException(
        '${json['message'] ?? 'ไม่สามารถสร้างรายการชำระเงินได้'}',
      );
    }
    return json;
  }

  /// Base URL of `POST /GetRecalTopupData`, resolved like every other
  /// endpoint: `api_url['recal_topup_url_base']` from the Firestore config
  /// first, [kTopupRecalApiBase] as the degrade-to value.
  static Future<String> recalBaseUrl() async {
    final config = await AppConfigApi.ensureLoaded();
    return config.urlFor('recal_topup_url_base') ?? kTopupRecalApiBase;
  }

  /// `POST /GetRecalTopupData` — re-prices [topupAmount] and returns the
  /// **ยอดที่ต้องชำระเพื่อเติมวงเงิน** breakdown the amount screen shows.
  ///
  /// The response is a superset of `GET /topup/detail`; only the parts that
  /// call cannot supply are modelled — see [TopupRecalculation].
  ///
  /// **Returns `null` when the section cannot be shown**, rather than
  /// throwing, and that is the whole error policy of this call. The section is
  /// driven entirely by `settlement_items`: no rows means no section, so a
  /// build with no credential ([kTopupRecalConfigured]), a gateway that cannot
  /// be reached from a browser (see [kTopupRecalApiBase]) and a contract with
  /// nothing outstanding all render **the same screen**. A top-up amount is
  /// still perfectly requestable without a settlement block, so a failure here
  /// must not take the page down with it. Every null leaves a
  /// [Diagnostics] breadcrumb, because otherwise "why is the section missing?"
  /// is unanswerable from a device.
  ///
  /// ⚠ It takes **no `token`**, unlike every other method here: this endpoint
  /// is off the mobile API base and authenticates with its own shared
  /// credential, not the customer's bearer. When it moves behind the mobile
  /// API (Outstanding #33) that becomes a `required String token` like the
  /// rest, and [kTopupRecalApiAuth] goes away.
  static Future<TopupRecalculation?> recalculate({
    required String dbName,
    required String contractNo,
    required num topupAmount,
  }) async {
    if (kPLoanUseMockData) return _mock(mockRecalculation(topupAmount));
    if (!kTopupRecalConfigured) {
      Diagnostics.log('topup recal not configured — settlement hidden');
      return null;
    }
    final base = await recalBaseUrl();
    try {
      final res = await sendApiRequest(
        'POST',
        Uri.parse('$base/GetRecalTopupData'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': kTopupRecalApiAuth,
        },
        body: jsonEncode({
          'contract_no': contractNo,
          'db_name': dbName,
          // The sample sends this as a number, not a string.
          'topup_amount': topupAmount,
        }),
      );
      final json = SrisawadApi.decode(res.body);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        Diagnostics.log('topup recal HTTP ${res.statusCode}');
        return null;
      }
      // Wrapped in `results`, like /user/detail rather than /topup/detail.
      final results = (json is Map<String, dynamic>) ? json['results'] : null;
      if (results is! Map<String, dynamic>) {
        Diagnostics.log('topup recal: unexpected body');
        return null;
      }
      final recal = TopupRecalculation.fromJson(results);
      if (!recal.isOk) {
        Diagnostics.log('topup recal ${recal.code} ${recal.message}');
        return null;
      }
      if (!recal.itemsSumMatchesTotal) {
        // Not corrected — the server's total is what the customer owes — but
        // the screen is then showing a breakdown that does not explain the
        // figure under it, which is worth being able to see from a device.
        Diagnostics.log('topup settlement rows do not sum to '
            '${recal.settlementTotalAmount}');
      }
      return recal;
    } on ApiTransportException catch (e) {
      Diagnostics.log('topup recal transport: ${e.message}');
      return null;
    }
  }

  /// Base URL of the lead service, resolved like every other endpoint:
  /// `api_url['lead_url_base']` from the Firestore config first, the
  /// compile-time [kTopupLeadApiBase] as the degrade-to value.
  static Future<String> leadBaseUrl() async {
    final config = await AppConfigApi.ensureLoaded();
    return config.urlFor('lead_url_base') ?? kTopupLeadApiBase;
  }

  /// `POST {lead base}/ssw_service_api/api/leads/lh-save` — files a lead when
  /// a self-service top-up is not possible.
  ///
  /// ⚠ **Not on the mobile API base and not bearer-authenticated.** It wants
  /// its own `x-api-key` and `Authorization`, which the source hardcoded into
  /// the bundle. Here they are build-time inputs that default to empty, so an
  /// unconfigured build throws [SrisawadApiException] with a message the
  /// screen can show instead of shipping a shared credential to every visitor.
  /// See [kTopupLeadApiKey].
  static Future<int?> saveLead(Map<String, dynamic> payload) async {
    if (kPLoanUseMockData) return _mock(0);
    if (!kTopupLeadApiConfigured) {
      throw SrisawadApiException(
        'ระบบส่งข้อมูลยังไม่พร้อมใช้งาน กรุณาติดต่อสาขา',
      );
    }
    final base = await leadBaseUrl();
    if (base.isEmpty) {
      throw SrisawadApiException(
        'ระบบส่งข้อมูลยังไม่พร้อมใช้งาน กรุณาติดต่อสาขา',
      );
    }
    final ApiHttpResult res;
    try {
      res = await sendApiRequest(
        'POST',
        Uri.parse('$base/ssw_service_api/api/leads/lh-save'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': kTopupLeadApiKey,
          'Authorization': kTopupLeadApiAuth,
        },
        body: jsonEncode(payload),
      );
    } on ApiTransportException catch (e) {
      throw SrisawadApiException('lead API ${e.message}');
    }
    final json = SrisawadApi.decode(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message = (json is Map && json['message'] != null)
          ? '${json['message']}'
          : 'HTTP ${res.statusCode}';
      throw SrisawadApiException(message, statusCode: res.statusCode);
    }
    final code = (json is Map) ? '${json['code'] ?? ''}' : '';
    if (code.isNotEmpty && code != '200') {
      throw SrisawadApiException(
        (json as Map)['message']?.toString() ?? 'ส่งข้อมูลไม่สำเร็จ',
      );
    }
    final results = (json is Map) ? json['results'] : null;
    final data = (results is Map) ? results['data'] : null;
    final leadsId = (data is Map) ? data['leads_id'] : null;
    return leadsId is int ? leadsId : int.tryParse('${leadsId ?? ''}');
  }

  // ── Shared with the P-Loan group ─────────────────────────────────────
  //
  // `/pdf/loan` and `/vision/thai-id-validate` are product-neutral: one
  // renders a contract's documents, the other reads a Thai ID card. Both
  // already live on [PLoanApi], which owns their request details (the
  // per-environment `x-srisawad` on `/pdf/loan`, and the multipart transport
  // that has to bypass the host bridge). Delegating keeps one implementation
  // instead of two that drift; it also means `--dart-define=P_LOAN_MOCK=true`
  // covers the top-up flow as a whole rather than half of it.

  /// `GET /loan/list` — the customer's contracts.
  static Future<List<LoanContract>> listContracts({
    required String hashThaiId,
    required String token,
  }) =>
      PLoanApi.listContracts(hashThaiId: hashThaiId, token: token);

  /// `GET /user/detail` — the profile the ID-card check matches against.
  static Future<CustomerDetail> fetchCustomer({
    required String hashThaiId,
    required String token,
  }) =>
      PLoanApi.fetchCustomer(hashThaiId: hashThaiId, token: token);

  /// `GET /profile/address/{hash}` — the addresses shown on the customer-data
  /// screen.
  static Future<CustomerAddressBook> fetchAddressBook({
    required String hashThaiId,
    required String token,
  }) =>
      PLoanApi.fetchAddressBook(hashThaiId: hashThaiId, token: token);

  /// `POST /pdf/loan` — the three contract PDFs to read and consent to.
  static Future<LoanDocuments> generateDocuments({
    required ContractPdfRequest request,
    required String hashThaiId,
    required String token,
  }) =>
      PLoanApi.generateDocuments(
        request: request,
        hashThaiId: hashThaiId,
        token: token,
      );

  /// `POST /vision/thai-id-validate` — reads and validates an ID-card photo.
  static Future<ThaiIdReadResult> validateThaiIdCard({
    required Uint8List imageBytes,
    required String token,
  }) =>
      PLoanApi.validateThaiIdCard(imageBytes: imageBytes, token: token);
}
