import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../loan_register/components/loan_register_styles.dart';
import '../../router/app_router.dart';
import 'components/p_loan_components.dart';
import 'models/p_loan_flow.dart';

/// Terminal screen after a successful submit.
///
/// The source's equivalent had two problems worth not repeating: its headline
/// read `'ยืนคำขอ…'` (missing ยัน), and both of its buttons navigated into the
/// *top-up* flow's pages rather than the P-Loan ones — a copy-paste leftover.
class PLoanSuccessPage extends StatelessWidget {
  const PLoanSuccessPage({
    super.key,
    required this.flow,
    required this.transNo,
  });

  final PLoanFlow flow;

  /// Transaction number the submit returned (`body.trans_no`).
  final String transNo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      body: SafeArea(
        child: Column(
          children: [
            // Matters most on this screen: without it, a mock run looks like a
            // request that was actually filed.
            const PLoanMockBanner(),
            Expanded(
              child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'ยืนยันคำขอสินเชื่อเรียบร้อยแล้ว',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansThai(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: LoanRegisterStyles.value,
                ),
              ),
              const SizedBox(height: 24),
              SvgPicture.asset('assets/p_loan/success-icon.svg',
                  width: 200, height: 200),
              const SizedBox(height: 24),
              Text(
                'ยอดเงินที่จะได้รับ ${formatMoney(flow.payoutAmount)} บาท',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansThai(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: LoanRegisterStyles.required,
                ),
              ),
              if (transNo.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'เลขที่รายการ $transNo',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 14,
                    color: LoanRegisterStyles.label,
                  ),
                ),
              ],
              const SizedBox(height: 40),
              SizedBox(
                height: 56,
                width: double.infinity,
                child: ElevatedButton(
                  // Clear the wizard off the stack so back doesn't re-enter a
                  // flow that has already been submitted.
                  onPressed: () => context.go(AppRoutes.home),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LoanRegisterStyles.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'กลับสู่หน้าแรก',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
