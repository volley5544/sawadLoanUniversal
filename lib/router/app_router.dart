import 'package:go_router/go_router.dart';

import '../loan_register/appointment_page.dart';
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
      builder: (context, state) => const NdidBankSelectPage(),
    ),
    GoRoute(
      path: AppRoutes.ndidVerify,
      builder: (context, state) =>
          NdidVerifyPage(form: state.extra as LoanRegisterForm?),
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
  ],
);
