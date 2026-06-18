import 'package:go_router/go_router.dart';

import '../loan_register/collateral_info_page.dart';
import '../loan_register/customer_info_page.dart';
import '../loan_register/installment_picker_page.dart';
import '../loan_register/loan_info_page.dart';
import '../loan_register/loan_register_list_page.dart';
import '../loan_register/models/loan_register_form.dart';
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
    // Full-screen selectors (steps 4 & 5). Opened with the current value as
    // `extra`; they pop the chosen value back to the caller via context.pop().
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
  ],
);
