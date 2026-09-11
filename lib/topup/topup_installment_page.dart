import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../loan_register/components/loan_register_styles.dart';
import '../p_loan/application/components/p_loan_components.dart';
import '../p_loan/application/models/installment_plan.dart';
import '../router/app_router.dart';
import 'components/topup_components.dart';
import 'models/topup_flow.dart';

/// **Step 4 — เลือกจำนวนงวด.** Single-select list of the repayment options
/// `POST /topup/calculator` returned on step 3. No API call of its own.
///
/// Options are shown longest-tenor-first, i.e. smallest monthly payment first,
/// matching the source's `reversedListInstallment`.
class TopupInstallmentPage extends StatefulWidget {
  const TopupInstallmentPage({super.key, required this.flow});

  final TopupFlow flow;

  @override
  State<TopupInstallmentPage> createState() => _TopupInstallmentPageState();
}

class _TopupInstallmentPageState extends State<TopupInstallmentPage> {
  InstallmentOption? _selected;

  @override
  void initState() {
    super.initState();
    // Preserve the choice when the customer comes back to this screen.
    _selected = widget.flow.installment;
  }

  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    final options = flow.plan?.longestFirst ?? const <InstallmentOption>[];

    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: topupAppBar(context, 'เลือกจำนวนงวด'),
      body: Column(
        children: [
          const PLoanMockBanner(),
          const TopupStepIndicator(4),
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
                        'ยอดจัดสินเชื่อ',
                        style: GoogleFonts.notoSansThai(
                          fontSize: 14,
                          color: LoanRegisterStyles.label,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${formatMoney(flow.calculatedAmount)} บาท',
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
                context.push(AppRoutes.topupPhotos, extra: flow);
              },
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
                selected ? Icons.check_circle : Icons.radio_button_off_outlined,
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
