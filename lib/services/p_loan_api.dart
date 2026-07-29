import 'dart:typed_data';

import '../config/app_environment.dart';
import '../models/customer_address.dart';
import '../models/customer_detail.dart';
import '../p_loan/application/models/installment_plan.dart';
import '../p_loan/application/models/loan_amount_detail.dart';
import '../p_loan/application/models/loan_contract.dart';
import '../p_loan/application/models/loan_documents.dart';
import '../p_loan/application/models/new_loan_installment.dart';
import '../p_loan/application/models/p_loan_mock.dart';
import '../p_loan/application/models/p_loan_submission.dart';
import 'api_transport.dart';
import 'p_loan_contract_api.dart';
import 'srisawad_api.dart';
import 'topup_api.dart';
import 'user_api.dart';

/// **P-Loan API group** — every call the P-Loan application flow makes.
///
/// The P-Loan product starts from the same data as a top-up (an existing
/// contract, its approved limit, its installment calculation), so the three
/// shared steps below **delegate to [TopupApi]** rather than duplicating the
/// request code. This group is still the single seam the flow talks to: when
/// P-Loan gets its own endpoints, only the delegating methods here change and
/// no screen is touched.
///
/// | This group | Currently calls |
/// | --- | --- |
/// | [listContracts]         | `GET /loan/list` (shared) |
/// | [fetchAmountDetail]     | `GET /topup/detail` |
/// | [calculateInstallments] | `POST /topup/calculator` |
/// | [submit]                | `POST /topup` (Extra) |
/// | [saveNewLoan]           | `POST /SavePloanContract` (new P-Loan) |
/// | [generateDocuments]     | `POST /pdf/loan` (P-Loan only) |
/// | [validateThaiIdCard]    | `POST /vision/thai-id-validate` (P-Loan only) |
///
/// Base URL comes from `api_url['api_url_base']` in the Firestore config, with
/// the compile-time [AppEnvironment] value as fallback — see [SrisawadApi].
/// Customer profile and address book stay on `UserApi`.
class PLoanApi {
  PLoanApi._();

  /// Whether this group is serving fixtures instead of calling the API.
  /// Screens read it to show the mock-mode banner.
  static bool get isMocked => kPLoanUseMockData;

  /// Simulated latency, so loading states still appear in mock mode.
  static Future<T> _mock<T>(T value) =>
      Future.delayed(kMockLatency, () => value);

  // ── customer data (delegated to UserApi when live) ───────────────────

  /// Step 1 — the customer profile the ID check on step 6 matches against.
  ///
  /// Routed through this group rather than calling [UserApi] directly so mock
  /// mode covers the whole flow; the wizard's own startup fetch is untouched.
  static Future<CustomerDetail> fetchCustomer({
    required String hashThaiId,
  }) {
    if (kPLoanUseMockData) return _mock(mockCustomer());
    return UserApi.fetchUserDetail(hashThaiId);
  }

  /// Step 5 — the customer's registered addresses.
  static Future<CustomerAddressBook> fetchAddressBook({
    required String hashThaiId,
    required String token,
  }) {
    if (kPLoanUseMockData) return _mock(mockAddressBook());
    return UserApi.fetchAddressBook(hashThaiId, token: token);
  }

  // ── shared with the top-up flow ──────────────────────────────────────

  /// Step 1 — the customer's contracts to raise a request against.
  static Future<List<LoanContract>> listContracts({
    required String hashThaiId,
    required String token,
  }) {
    if (kPLoanUseMockData) return _mock(mockContracts());
    return SrisawadApi.listContracts(hashThaiId: hashThaiId, token: token);
  }

  /// Step 2 — limits, rate and deductions for the chosen contract.
  static Future<LoanAmountDetail> fetchAmountDetail({
    required String dbName,
    required String contractNo,
    required String token,
  }) {
    if (kPLoanUseMockData) return _mock(mockAmountDetail(contractNo));
    return TopupApi.fetchDetail(
      dbName: dbName,
      contractNo: contractNo,
      token: token,
    );
  }

  /// Steps 2/3 — installment options for the requested amount (**P-Loan
  /// Extra**). A new P-Loan uses [calculateNewLoanInstallments] instead.
  static Future<InstallmentPlan> calculateInstallments({
    required String dbName,
    required String contractNo,
    required int loanAmount,
    required double interestRate,
    required int feeAmount,
    required String token,
  }) {
    if (kPLoanUseMockData) return _mock(mockInstallmentPlan(loanAmount));
    return TopupApi.calculateInstallments(
      dbName: dbName,
      contractNo: contractNo,
      loanAmount: loanAmount,
      interestRate: interestRate,
      feeAmount: feeAmount,
      token: token,
    );
  }

  /// Steps 2/3 — installment options for a **new P-Loan**.
  ///
  /// TEMPORARY: the new-P-Loan product has no installment-calculator endpoint
  /// yet, and [calculateInstallments] (the top-up calculator) can't stand in —
  /// it is keyed by `db_name` + `contract_no`, and a new P-Loan has no
  /// contract. Until the real call exists, this returns the
  /// client-side estimate from [provisionalNewLoanPlan] so the flow stays
  /// walkable. When the endpoint lands, swap the body here for it — no screen
  /// changes (this is the seam [PLoanApi]'s doc describes).
  static Future<InstallmentPlan> calculateNewLoanInstallments({
    required int loanAmount,
  }) =>
      Future.delayed(
        // A short beat so step 2's "กำลังคำนวณ..." state still shows, matching
        // the feel of the real calculator round-trip it stands in for.
        const Duration(milliseconds: 350),
        () => provisionalNewLoanPlan(loanAmount),
      );

  /// Submits the application. [pdfRequest] is echoed back as the `save_pdf`
  /// block, which must match what [generateDocuments] was given.
  ///
  /// In mock mode **nothing is sent** — it returns a `MOCK-` prefixed
  /// transaction number so a demo run can't be mistaken for a filed request.
  static Future<String> submit({
    required Map<String, dynamic> payload,
    required ContractPdfRequest pdfRequest,
    required String token,
  }) {
    if (kPLoanUseMockData) return _mock(mockTransNo());
    return TopupApi.submit(
      payload: {...payload, 'save_pdf': pdfRequest.toJson()},
      token: token,
    );
  }

  /// Files a **new P-Loan** with the P-Loan save API
  /// (`POST /SavePloanContract`).
  ///
  /// A P-Loan Extra uses [submit] instead: it draws against an existing
  /// contract, which is what `POST /topup` books. Both are real submissions —
  /// the split is about which product is being filed, not which one works.
  ///
  /// In mock mode **nothing is sent**; a `MOCK-` prefixed reference comes back.
  static Future<String> saveNewLoan({
    required PLoanContractSubmission submission,
  }) {
    if (kPLoanUseMockData) return _mock(mockTransNo());
    return PLoanContractApi.save(submission);
  }

  // ── P-Loan only ──────────────────────────────────────────────────────

  /// Step 6 — generates the three contract PDFs (base64).
  ///
  /// This endpoint wants `x-srisawad: x1_c3Jpc2F3YWQ`, not the `x1` the rest of
  /// the API uses.
  static Future<LoanDocuments> generateDocuments({
    required ContractPdfRequest request,
    required String hashThaiId,
    required String token,
  }) async {
    if (kPLoanUseMockData) return _mock(mockDocuments());
    final base = await SrisawadApi.baseUrl();
    final json = await SrisawadApi.send(
      'POST',
      Uri.parse('$base/pdf/loan'),
      token: token,
      extraHeaders: const {'x-srisawad': 'x1_c3Jpc2F3YWQ'},
      body: {
        ...request.toJson(),
        'hash_thai_id': hashThaiId,
      },
    );
    if (json is! Map<String, dynamic>) {
      throw SrisawadApiException('Unexpected /pdf/loan response: $json');
    }
    final docs = LoanDocuments.fromJson(json);
    if (!docs.isComplete) {
      throw SrisawadApiException('ไม่สามารถสร้างเอกสารสัญญาได้ กรุณาลองใหม่');
    }
    return docs;
  }

  /// Step 6 — reads and validates a Thai ID card photo.
  ///
  /// Multipart, so this one bypasses the native bridge (see
  /// [sendMultipartApiRequest] for why that's safe here).
  static Future<ThaiIdReadResult> validateThaiIdCard({
    required Uint8List imageBytes,
    required String token,
  }) async {
    if (kPLoanUseMockData) {
      // Returns the mock customer's own id so the match on step 6 passes —
      // the check itself is still exercised, just against a known-good read.
      return _mock(const ThaiIdReadResult(
        thaiId: mockThaiIdOnCard,
        latestDate: '2033-04-12',
        exceptionDate: 'N',
      ));
    }
    final base = await SrisawadApi.baseUrl();
    final ApiHttpResult res;
    try {
      res = await sendMultipartApiRequest(
        Uri.parse('$base/vision/thai-id-validate'),
        headers: SrisawadApi.headers(token),
        fileField: 'file',
        fileName: 'idcard.jpg',
        fileBytes: imageBytes,
      );
    } on ApiTransportException catch (e) {
      throw SrisawadApiException('mobile API ${e.message}');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw SrisawadApiException(
        'กรุณาถ่ายภาพบัตรประชาชนใหม่อีกครั้ง',
        statusCode: res.statusCode,
      );
    }
    final json = SrisawadApi.decode(res.body);
    if (json is! Map<String, dynamic>) {
      throw SrisawadApiException('Unexpected /vision/thai-id-validate: $json');
    }
    return ThaiIdReadResult.fromJson(json);
  }
}

/// Result of `POST /vision/thai-id-validate`.
class ThaiIdReadResult {
  const ThaiIdReadResult({
    this.thaiId = '',
    this.latestDate = '',
    this.exceptionDate = '',
  });

  /// The ID number read off the card.
  final String thaiId;

  /// Card expiry. `lastest_date` on the wire — the misspelling is the real key.
  final String latestDate;

  /// `'Y'` when the server waives the expiry check.
  final String exceptionDate;

  bool get expiryWaived => exceptionDate == 'Y';

  factory ThaiIdReadResult.fromJson(Map<String, dynamic> json) =>
      ThaiIdReadResult(
        thaiId: '${json['thai_id'] ?? ''}'.trim(),
        latestDate: '${json['lastest_date'] ?? ''}'.trim(),
        exceptionDate: '${json['exception_date'] ?? ''}'.trim(),
      );
}
