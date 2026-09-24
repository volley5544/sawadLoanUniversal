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
    final url = Uri.parse('$base/topup');

    // Sent through the transport directly rather than `SrisawadApi.send`, so
    // this method owns the raw status and body and can build [failureReport].
    // `send` decodes and discards them, which is exactly what made a failing
    // submit unactionable — the same reason `POST /ploan` does its own send.
    final ApiHttpResult res;
    try {
      res = await sendApiRequest(
        'POST',
        url,
        headers: await SrisawadApi.authHeaders(token,
            contentType: 'application/json'),
        body: jsonEncode(payload),
        // Per environment — 300 s on uat, 60 s on prod (2026-09-24).
        timeout: AppEnvironment.current.topupSubmitTimeout,
        // ⚠ **Direct, not through the host bridge** (2026-09-24). The bridge
        // runs its own HTTP call with its own limit (30 s on older app
        // builds, 60 s after the 2026-09-13 host fix), so a longer timeout
        // here would be cut off inside the app regardless. The mobile API
        // answers CORS preflight for this path on both gateways (verified
        // 2026-09-24), which is also why `/ploan` already goes direct. It
        // also means the failure report now carries response headers.
        bypassHostBridge: true,
      );
    } on ApiTransportException catch (e) {
      Diagnostics.log('topup submit failed: transport: ${e.message}');
      throw SrisawadApiException(
        'ส่งคำขอไม่สำเร็จ: ${e.message}',
        details: failureReport(url, payload, transportError: e.message),
      );
    }

    final details = failureReport(url, payload, res: res);
    final json = SrisawadApi.decode(res.body);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      Diagnostics.log('topup submit failed: HTTP ${res.statusCode}');
      final message = (json is Map && json['message'] != null)
          ? '${json['message']}'
          : 'HTTP ${res.statusCode}';
      throw SrisawadApiException(message,
          statusCode: res.statusCode, details: details);
    }
    if (json is! Map<String, dynamic>) {
      throw SrisawadApiException('Unexpected /topup response: ${res.body}',
          details: details);
    }
    // ⚠ This endpoint answers `head`/`body` where the rest of the mobile API
    // answers `results` — a 200 here can still be a refusal.
    final head = json['head'];
    final flag = head is Map ? '${head['error_flag'] ?? ''}' : '';
    if (flag != 'N') {
      final desc = head is Map ? '${head['error_desc'] ?? ''}' : '';
      Diagnostics.log('topup submit refused in a 200 body: $desc');
      throw SrisawadApiException(
        desc.isNotEmpty ? desc : 'ส่งคำขอไม่สำเร็จ กรุณาลองใหม่',
        statusCode: res.statusCode,
        details: details,
      );
    }
    final body = json['body'];
    return body is Map ? '${body['trans_no'] ?? ''}' : '';
  }

  /// What a failed `POST /topup` shows a tester: the request that went out and
  /// the response that came back.
  ///
  /// Same shape and same reasoning as `PLoanContractApi.failureReport` — an
  /// `HTTP 400` against 37 fields is unactionable on a device, and a `500` is
  /// usually an HTML page whose last line is the cause.
  ///
  /// ⚠ **Non-prod only at the call site**, like the `/ploan` report: this
  /// contains the customer's personal data, and a gateway stack trace is what
  /// a developer needs and what a customer must not read.
  ///
  /// ⚠ **The base64 fields are elided, everything else is verbatim.** Nine
  /// photos and three PDFs would be tens of megabytes of base64 — unreadable,
  /// unpasteable, and enough to hang the dialog rendering it. Each is replaced
  /// by its size, which is the only thing about it worth debugging; every
  /// scalar, which is what a 400 is actually about, is printed unchanged. The
  /// **response body is never truncated** — on a 500 the cause is often the
  /// last line.
  static String failureReport(
    Uri url,
    Map<String, dynamic> payload, {
    ApiHttpResult? res,
    String? transportError,
  }) {
    final out = StringBuffer()..writeln('POST $url');
    if (transportError != null) {
      out.writeln('transport error: $transportError');
    } else if (res != null) {
      out.writeln('HTTP ${res.statusCode}');
    }
    out
      ..writeln('')
      ..writeln('--- request body (${payload.length} fields) ---')
      ..writeln(_redactedPayload(payload));
    if (res != null) {
      out
        ..writeln('')
        ..writeln('--- response body ---')
        ..writeln(res.body.isEmpty ? '(empty)' : res.body);
    }
    return out.toString();
  }

  /// Pretty-prints [payload] with every base64 value replaced by its size.
  static String _redactedPayload(Map<String, dynamic> payload) {
    Object? shrink(String key, Object? value) {
      if (value is String && _isBase64Field(key, value)) {
        return '<base64 ${(value.length * 3 / 4 / 1024).round()} KB elided>';
      }
      if (value is Map) {
        return {
          for (final e in value.entries) '${e.key}': shrink('${e.key}', e.value)
        };
      }
      return value;
    }

    final shrunk = {
      for (final e in payload.entries) e.key: shrink(e.key, e.value)
    };
    return const JsonEncoder.withIndent('  ').convert(shrunk);
  }

  /// A value is treated as base64 by **length**, not by key name: the photo
  /// and document keys are known, but a new one added later would otherwise
  /// dump megabytes into the dialog before anyone noticed.
  static bool _isBase64Field(String key, String value) => value.length > 512;

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

  /// `POST /topup/recal` — **the top-up flow's replacement for
  /// `GET /topup/detail`** (2026-09-14, on instruction: *"we will use recal
  /// api instead of /topup/detail"*).
  ///
  /// One call now answers both questions the amount screen asks. The body is a
  /// superset of `/topup/detail`'s — the same limits, rate, duty,
  /// `contract_details` and `car_details` — **plus** `settlement_items`, which
  /// `/topup/detail` has no fields for. So [TopupRecalResult] carries a
  /// [LoanAmountDetail] and a [TopupRecalculation] parsed from the *same*
  /// body, and the screen can no longer show limits that disagree with the
  /// settlement under them.
  ///
  /// ⚠ **`GET /topup/detail` is not gone** — [fetchDetail] stays, because
  /// [PLoanApi.fetchAmountDetail] delegates to it and the P-Loan flow is a
  /// different product on a different submit endpoint. The instruction was
  /// about the top-up flow. `topup_amount_page_old.dart` also still calls it,
  /// which is the point of the `_old` pair.
  ///
  /// ⚠ **This one throws**, where the old test-host version returned null for
  /// everything. That was right while the call only fed an optional section;
  /// now it carries the limits the whole screen is built from, so a failure is
  /// a failure — same contract as [fetchDetail], which it replaces. A
  /// *successful* response with no `settlement_items` is still perfectly
  /// normal and simply renders no section.
  ///
  /// ⚠ **The response is flat, not wrapped in `results`.** The retired test
  /// host (`GetRecalTopupData` on `34.142.213.42:8080`) wrapped it; this one
  /// does not. Both shapes are accepted so a rollback needs no code change.
  static Future<TopupRecalResult> fetchRecal({
    required String dbName,
    required String contractNo,
    required num topupAmount,
    required String token,
  }) async {
    if (kPLoanUseMockData) {
      return _mock(TopupRecalResult(
        detail: mockAmountDetail(contractNo),
        recalculation: mockRecalculation(topupAmount),
      ));
    }
    final base = await SrisawadApi.baseUrl();
    final json = await SrisawadApi.send(
      'POST',
      Uri.parse('$base/topup/recal'),
      token: token,
      body: {
        'contract_no': contractNo,
        'db_name': dbName,
        // The sample sends this as a number, not a string.
        'topup_amount': topupAmount,
      },
    );
    if (json is! Map<String, dynamic>) {
      throw SrisawadApiException('Unexpected /topup/recal response: $json');
    }
    // Flat on the QA endpoint; `results`-wrapped on the retired test host.
    final payload = json['results'] is Map<String, dynamic>
        ? json['results'] as Map<String, dynamic>
        : json;

    final detail = LoanAmountDetail.fromJson(payload);
    if (!detail.isOk) {
      // Carries the API's own business-hours message outside 07:00–20:30, and
      // `400 topup_amount out of range` when the amount exceeds this
      // endpoint's ceiling — see TopupFlow.settlementPricingAmount.
      throw SrisawadApiException(
        detail.message.isNotEmpty ? detail.message : 'topup/recal ${detail.code}',
      );
    }

    final recal = TopupRecalculation.fromJson(payload);
    if (!recal.itemsSumMatchesTotal) {
      // Not corrected — the server's total is what the customer owes — but the
      // screen is then showing a breakdown that does not explain the figure
      // under it, which is worth being able to see from a device.
      Diagnostics.log(
          'topup settlement rows do not sum to ${recal.settlementTotalAmount}');
    }
    return TopupRecalResult(detail: detail, recalculation: recal);
  }

  /// Why the settlement section is absent, or null when nothing went wrong.
  ///
  /// Read by the amount screen's **non-prod** notice. A failure inside
  /// [fetchRecal] now *throws* — it carries the screen's limits — so the only
  /// thing that writes this is the screen's own re-read, which deliberately
  /// swallows. Kept because "the section vanished after I changed the amount"
  /// is otherwise unanswerable from a device, which cost most of 2026-09-13.
  static String? lastRecalFailure;

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

/// What `POST /topup/recal` answers with: the limits the amount screen is
/// built from **and** the settlement breakdown under them, parsed from one
/// body.
///
/// They are deliberately kept as the two existing models rather than merged
/// into a third: [LoanAmountDetail] is shared with the P-Loan flow (which
/// still reads it from `GET /topup/detail`), and [TopupRecalculation] owns the
/// `settlement_items` shape. One response, two views, no new wire model.
class TopupRecalResult {
  const TopupRecalResult({required this.detail, required this.recalculation});

  final LoanAmountDetail detail;
  final TopupRecalculation recalculation;
}
