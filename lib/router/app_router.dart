import 'package:go_router/go_router.dart';

import '../loan_register/appointment_datetime_page.dart';
import '../loan_register/appointment_page.dart';
import '../loan_register/branch_select_page.dart';
import '../loan_register/collateral_info_page.dart';
import '../loan_register/customer_info_page.dart';
import '../loan_register/document_attach_page.dart';
import '../loan_register/document_review_page.dart';
import '../loan_register/documents_to_prepare_page.dart';
import '../loan_register/installment_picker_page.dart';
import '../loan_register/loan_info_page.dart';
import '../loan_register/loan_register_list_page.dart';
import '../loan_register/models/loan_register_form.dart';
import '../loan_register/ndid_bank_select_page.dart';
import '../loan_register/ndid_verify_page.dart';
import '../loan_register/transfer_type_picker_page.dart';
import '../models/ndid_subject.dart';
import '../p_loan/application/models/p_loan_flow.dart';
import '../p_loan/application/p_loan_amount_page.dart';
import '../p_loan/application/p_loan_conclusion_page.dart';
import '../p_loan/application/p_loan_contract_select_page.dart';
import '../p_loan/application/p_loan_customer_data_page.dart';
import '../p_loan/application/p_loan_installment_page.dart';
import '../p_loan/application/p_loan_success_page.dart';
import '../p_loan/application/p_loan_topup_card_resume_page.dart';
import '../p_loan/application/p_loan_vehicle_photos_page.dart';
import '../p_loan/submit_form/p_loan_form_page.dart';

/// Route paths for the loan-register wizard. These map 1:1 to the browser URL
/// (path strategy is enabled in main.dart), e.g.
/// `https://sawad-loan-universal-uat.web.app/customerInfoPage?hashThaiId=<...>`.
///
/// Any query string (e.g. `?hashThaiId=`) is preserved by the browser and read
/// in `main.dart` via `Uri.base` — it is not part of the route definitions.
abstract final class AppRoutes {
  static const String home = '/';
  static const String customerInfo = '/customerInfoPage';
  static const String collateralInfo = '/collateralInfoPage';
  static const String loanInfo = '/loanInfoPage';
  static const String installmentPicker = '/installmentPicker';
  static const String transferTypePicker = '/transferTypePicker';
  // Step 4: เอกสารแนบ + ลงนาม/ยืนยันตัวตน NDID (slide 8)
  static const String documentAttach = '/documentAttachPage';
  static const String documentReview = '/documentReviewPage';
  static const String ndidBankSelect = '/ndidBankSelectPage';
  static const String ndidVerify = '/ndidVerifyPage';
  // Step 5: นัดหมายส่งเอกสาร (slide 9)
  static const String appointment = '/appointmentPage';
  static const String documentsToPrepare = '/documentsToPreparePage';
  static const String branchSelect = '/branchSelectPage';
  static const String appointmentDateTime = '/appointmentDateTimePage';
  // Standalone P-Loan registration form (maps to the regmast_ploan.php API).
  static const String pLoanForm = '/pLoanFormPage';

  // P-Loan application flow (lib/p_loan/application/) — a 6-step wizard over
  // the mobile API. Paths are consistently camelCase, unlike the source
  // project's mix of /PloanCardPage01 and /ploanInstallmentPage03.
  static const String pLoanContractSelect = '/pLoan/contract';

  /// Deep link from the LandAndHouseWeb top-up card straight into a P-Loan
  /// Extra at step 3 — the one P-Loan route besides step 1 that a URL may
  /// enter, because it builds its own `PLoanFlow` instead of needing one.
  /// Takes `?dbName=&contractNo=` (+ optional `&amount=`).
  static const String pLoanTopupCardResume = '/pLoan/resume';
  static const String pLoanAmount = '/pLoan/amount';
  static const String pLoanInstallment = '/pLoan/installment';
  static const String pLoanVehiclePhotos = '/pLoan/photos';
  static const String pLoanCustomerData = '/pLoan/customer';
  static const String pLoanConclusion = '/pLoan/conclusion';
  static const String pLoanSuccess = '/pLoan/success';
}

/// The app router.
///
/// The wizard passes its mutable [LoanRegisterForm] from page to page via
/// GoRouter `extra`. A direct deep-link (no `extra`, e.g. opening the URL
/// fresh) falls back to each page's own `.mock()` seed, so every route renders
/// standalone.
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.home,
  routes: <RouteBase>[
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const LoanRegisterListPage(),
    ),
    GoRoute(
      path: AppRoutes.pLoanForm,
      builder: (context, state) => const PLoanFormPage(),
    ),
    // ── P-Loan application flow ────────────────────────────────────────
    // Steps 2-6 carry the accumulated PLoanFlow in `extra`. Unlike the
    // loan-register wizard there is no mock seed to fall back on (the flow is
    // wired to live APIs), so a deep link without `extra` redirects to step 1
    // rather than rendering a half-empty screen.
    GoRoute(
      path: AppRoutes.pLoanContractSelect,
      builder: (context, state) => const PLoanContractSelectPage(),
    ),
    // Deep link from the top-up card. Unlike steps 2-6 this one carries its
    // state in the query string, not in `extra`, so it survives a refresh —
    // it rebuilds the flow from `db_name` + `contract_no` and replaces itself
    // with step 3.
    GoRoute(
      path: AppRoutes.pLoanTopupCardResume,
      builder: (context, state) {
        final q = state.uri.queryParameters;
        return PLoanTopupCardResumePage(
          dbName: q['dbName'] ?? '',
          contractNo: q['contractNo'] ?? '',
          amount: int.tryParse(q['amount'] ?? ''),
        );
      },
    ),
    GoRoute(
      path: AppRoutes.pLoanAmount,
      redirect: (context, state) =>
          state.extra is PLoanFlow ? null : AppRoutes.pLoanContractSelect,
      builder: (context, state) =>
          PLoanAmountPage(flow: state.extra as PLoanFlow),
    ),
    GoRoute(
      path: AppRoutes.pLoanInstallment,
      redirect: (context, state) =>
          state.extra is PLoanFlow ? null : AppRoutes.pLoanContractSelect,
      builder: (context, state) =>
          PLoanInstallmentPage(flow: state.extra as PLoanFlow),
    ),
    GoRoute(
      path: AppRoutes.pLoanVehiclePhotos,
      redirect: (context, state) =>
          state.extra is PLoanFlow ? null : AppRoutes.pLoanContractSelect,
      builder: (context, state) =>
          PLoanVehiclePhotosPage(flow: state.extra as PLoanFlow),
    ),
    GoRoute(
      path: AppRoutes.pLoanCustomerData,
      redirect: (context, state) =>
          state.extra is PLoanFlow ? null : AppRoutes.pLoanContractSelect,
      builder: (context, state) =>
          PLoanCustomerDataPage(flow: state.extra as PLoanFlow),
    ),
    GoRoute(
      path: AppRoutes.pLoanConclusion,
      redirect: (context, state) =>
          state.extra is PLoanFlow ? null : AppRoutes.pLoanContractSelect,
      builder: (context, state) =>
          PLoanConclusionPage(flow: state.extra as PLoanFlow),
    ),
    GoRoute(
      path: AppRoutes.pLoanSuccess,
      redirect: (context, state) =>
          state.extra is (PLoanFlow, String) ? null : AppRoutes.home,
      builder: (context, state) {
        final (flow, transNo) = state.extra as (PLoanFlow, String);
        return PLoanSuccessPage(flow: flow, transNo: transNo);
      },
    ),
    GoRoute(
      path: AppRoutes.customerInfo,
      builder: (context, state) =>
          CustomerInfoPage(form: state.extra as LoanRegisterForm?),
    ),
    GoRoute(
      path: AppRoutes.collateralInfo,
      builder: (context, state) =>
          CollateralInfoPage(form: state.extra as LoanRegisterForm?),
    ),
    GoRoute(
      path: AppRoutes.loanInfo,
      builder: (context, state) =>
          LoanInfoPage(form: state.extra as LoanRegisterForm?),
    ),
    // Full-screen sub-selectors opened from step 3 (จำนวนงวด / ประเภทการโอน) —
    // not wizard steps. Opened with the current value as `extra`; they pop the
    // chosen value back to the caller via context.pop().
    GoRoute(
      path: AppRoutes.installmentPicker,
      builder: (context, state) =>
          InstallmentPickerPage(selected: (state.extra as int?) ?? 12),
    ),
    GoRoute(
      path: AppRoutes.transferTypePicker,
      builder: (context, state) => TransferTypePickerPage(
        selected: (state.extra as String?) ?? 'บัญชีลูกค้า',
      ),
    ),
    // ── Step 4: เอกสารแนบ + NDID (slide 8) ──────────────────────────
    GoRoute(
      path: AppRoutes.documentAttach,
      builder: (context, state) =>
          DocumentAttachPage(form: state.extra as LoanRegisterForm?),
    ),
    GoRoute(
      path: AppRoutes.documentReview,
      builder: (context, state) =>
          DocumentReviewPage(form: state.extra as LoanRegisterForm?),
    ),
    GoRoute(
      path: AppRoutes.ndidBankSelect,
      // NdidSubject, not LoanRegisterForm: both the wizard's step 4 and the
      // P-Loan flow's step 6 push here with their own state object.
      builder: (context, state) =>
          NdidBankSelectPage(form: state.extra as NdidSubject?),
    ),
    GoRoute(
      path: AppRoutes.ndidVerify,
      builder: (context, state) =>
          NdidVerifyPage(form: state.extra as NdidSubject?),
    ),
    // ── Step 5: นัดหมายส่งเอกสาร (slide 9) ──────────────────────────
    GoRoute(
      path: AppRoutes.appointment,
      builder: (context, state) =>
          AppointmentPage(form: state.extra as LoanRegisterForm?),
    ),
    GoRoute(
      path: AppRoutes.documentsToPrepare,
      builder: (context, state) =>
          DocumentsToPreparePage(form: state.extra as LoanRegisterForm?),
    ),
    // Branch + date/time pickers for the appointment. The branch list is the
    // web fallback — inside the native host the branch comes from the native
    // map via the `openBranchPicker` bridge handler instead.
    GoRoute(
      path: AppRoutes.branchSelect,
      builder: (context, state) => const BranchSelectPage(),
    ),
    GoRoute(
      path: AppRoutes.appointmentDateTime,
      builder: (context, state) =>
          AppointmentDateTimePage(branchName: state.extra as String?),
    ),
  ],
);
