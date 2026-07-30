import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../loan_register/components/loan_register_styles.dart';
import '../../loan_register/components/register_step_indicator.dart';
import '../../router/app_router.dart';
import '../../services/native_bridge.dart';
import 'components/p_loan_components.dart';
import 'models/installment_plan.dart';
import 'models/p_loan_flow.dart';

/// **Step 3 — เลือกจำนวนงวด.** Single-select list of the repayment options the
/// calculator returned on step 2. No API call of its own.
///
/// Options are shown longest-tenor-first (i.e. smallest monthly payment first),
/// matching the source's `reversedListInstallment`.
///
/// Also the **entry screen** for a top-up-card deep link
/// ([PLoanEntry.topupCard]), which changes two things here: back closes the
/// WebView instead of popping to a route that isn't there, and ยืนยัน continues
/// to step 5, since an Extra's collateral is already on file.
class PLoanInstallmentPage extends StatefulWidget {
  const PLoanInstallmentPage({super.key, required this.flow});

  final PLoanFlow flow;

  @override
  State<PLoanInstallmentPage> createState() => _PLoanInstallmentPageState();
}

class _PLoanInstallmentPageState extends State<PLoanInstallmentPage> {
  InstallmentOption? _selected;

  @override
  void initState() {
    super.initState();
    // Preserve the choice when the user comes back to this screen.
    _selected = widget.flow.installment;
  }

  /// This screen is the flow's first when deep-linked, so there is nothing to
  /// pop to — back means "return to the top-up card that opened us".
  void _closeToTopupCard() {
    if (NativeCameraBridge.isSupported) {
      NativeCameraBridge.closeWebview();
      return;
    }
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    final plan = flow.plan;
    final options = plan?.longestFirst ?? const <InstallmentOption>[];
    final isEntryScreen = flow.entry == PLoanEntry.topupCard;

    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: pLoanAppBar(context, 'เลือกจำนวนงวด',
          onBack: isEntryScreen ? _closeToTopupCard : null),
      body: Column(
        children: [
          const PLoanMockBanner(),
          PLoanKindBanner(kind: flow.kind),
          RegisterStepIndicator(
              currentStep: flow.stepNumber(3), totalSteps: flow.totalSteps),
          Expanded(
            child: options.isEmpty
                ? const PLoanErrorView(
                    message: 'ไม่พบตัวเลือกจำนวนงวดสำหรับยอดที่ขอ')
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                        LoanRegisterStyles.padding,
                        4,
                        LoanRegisterStyles.padding,
                        24),
                    children: [
                      Text(
                        // An Extra lends a วงเงินเอนกประสงค์ (the topup_extra
                        // offer); a new P-Loan is a plain new loan.
                        flow.isNewPLoan
                            ? 'ยอดจัดสินเชื่อใหม่'
                            : 'ยอดจัดวงเงินเอนกประสงค์',
                        style: GoogleFonts.notoSansThai(
                          fontSize: 14,
                          color: LoanRegisterStyles.label,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${formatMoney(flow.requestedAmount)} บาท',
                        style: GoogleFonts.notoSansThai(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: LoanRegisterStyles.value,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'กรุณาเลือกจำนวนงวดสำหรับการผ่อนชำระ',
                        style: GoogleFonts.notoSansThai(
                          fontSize: 14,
                          color: LoanRegisterStyles.label,
                        ),
                      ),
                      // A new P-Loan's options are a client-side estimate until
                      // its own calculator API exists (see
                      // PLoanApi.calculateNewLoanInstallments). Flag them so the
                      // figures aren't read as a final quote.
                      if (flow.isNewPLoan) const _ProvisionalEstimateNote(),
                      const SizedBox(height: 12),
                      for (final option in options)
                        _OptionTile(
                          option: option,
                          selected: _selected?.tenor == option.tenor,
                          onTap: () => setState(() => _selected = option),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: PLoanBottomButton(
        label: 'ยืนยัน',
        onPressed: _selected == null
            ? null
            : () {
                flow.installment = _selected;
                // A top-up-card Extra skips step 4 — its collateral is already
                // on file from /loan/list.
                context.push(
                  flow.skipsCollateralPhotos
                      ? AppRoutes.pLoanCustomerData
                      : AppRoutes.pLoanVehiclePhotos,
                  extra: flow,
                );
              },
      ),
    );
  }
}

/// Provisional-estimate banner shown for a new P-Loan, whose installment
/// figures are computed on the client pending its own calculator API.
class _ProvisionalEstimateNote extends StatelessWidget {
  const _ProvisionalEstimateNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LoanRegisterStyles.primarySoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: LoanRegisterStyles.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'ยอดผ่อนชำระเป็นตัวเลขประมาณการเบื้องต้น '
              'อยู่ระหว่างเชื่อมต่อระบบคำนวณสินเชื่อใหม่',
              style: GoogleFonts.notoSansThai(
                fontSize: 12.5,
                height: 1.4,
                color: LoanRegisterStyles.value,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final InstallmentOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? LoanRegisterStyles.primary
                  : LoanRegisterStyles.cardBorder,
              width: selected ? 2 : 1,
            ),
            color: selected ? LoanRegisterStyles.primarySoft : Colors.white,
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.check_circle
                    : Icons.radio_button_off_outlined,
                color: selected
                    ? LoanRegisterStyles.primary
                    : LoanRegisterStyles.label,
              ),
              const SizedBox(width: 12),
              Text(
                '${option.tenor} งวด',
                style: GoogleFonts.notoSansThai(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: LoanRegisterStyles.value,
                ),
              ),
              const Spacer(),
              Text(
                '${formatMoney(option.regularPeriodAmt)} / เดือน',
                style: GoogleFonts.notoSansThai(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: LoanRegisterStyles.value,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
