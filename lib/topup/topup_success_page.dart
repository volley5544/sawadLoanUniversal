import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../loan_register/components/env_version_tag.dart';
import '../loan_register/components/loan_register_styles.dart';
import '../p_loan/application/components/p_loan_components.dart';
import '../router/app_router.dart';
import '../services/native_bridge.dart';
import 'models/topup_flow.dart';

/// What the flow ended with, which is the only thing that differs between the
/// two terminal states.
enum TopupSuccessKind {
  /// `POST /topup` accepted the request.
  topup,

  /// The request could not be self-served, so a lead was filed instead and
  /// somebody will call back — see [TopupOutcome.lead].
  lead;

  static TopupSuccessKind parse(String? raw) =>
      raw == 'lead' ? TopupSuccessKind.lead : TopupSuccessKind.topup;
}

/// Terminal screen for both endings.
///
/// [flow] is optional: a reload lands here with no `extra`, and the screen
/// still has to render something sensible rather than crash. Without it the
/// payout line is simply omitted — the transaction number comes from the
/// query string and survives.
class TopupSuccessPage extends StatelessWidget {
  const TopupSuccessPage({
    super.key,
    required this.kind,
    this.flow,
    this.transNo = '',
  });

  final TopupSuccessKind kind;
  final TopupFlow? flow;

  /// Transaction number the submit returned (`body.trans_no`).
  final String transNo;

  bool get _isLead => kind == TopupSuccessKind.lead;

  /// The status screen needs both a `db_name` and a `trans_no`. A reload
  /// lands here with no flow, so the button is offered only when both are
  /// actually available rather than opening a screen that can only error.
  bool get _canTrack =>
      transNo.isNotEmpty && (flow?.contract?.dbName ?? '').isNotEmpty;

  /// The quote's expiry date, from the **server's** clock on the contract
  /// rather than the device's.
  String _deadline(TopupFlow flow) =>
      formatThaiDate(flow.contract?.paymentDetails.currentDateTime);

  @override
  Widget build(BuildContext context) {
    final flow = this.flow;
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      body: SafeArea(
        child: Column(
          children: [
            // Matters most on this screen: without it a mock run looks like a
            // request that was actually filed.
            const PLoanMockBanner(),
            // No AppBar here, so the env/build tag sits where one would be.
            const SizedBox(
              height: 28,
              width: double.infinity,
              child: Align(
                alignment: Alignment.centerRight,
                child: EnvVersionTag(),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isLead
                          ? 'ส่งข้อมูลเรียบร้อยแล้ว'
                          : 'ยืนยันคำขอสินเชื่อเพิ่มเรียบร้อยแล้ว',
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
                    if (_isLead)
                      Text(
                        'เจ้าหน้าที่จะติดต่อกลับเพื่อดำเนินการต่อไป',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansThai(
                          fontSize: 16,
                          color: LoanRegisterStyles.label,
                          height: 1.5,
                        ),
                      )
                    else if (flow != null)
                      Text(
                        // The payout is a *quote*, not a settled figure — it
                        // holds only if the transfer completes by the stated
                        // date, in business hours. Saying so here is the
                        // source's wording and it matters: the customer is
                        // about to stop looking at the app.
                        'ยอดวงเงินที่จะได้รับ '
                        '${formatMoney(flow.receivableAmount)} บาท '
                        'เป็นยอดคำนวณ เมื่อท่านทำรายการ'
                        '${_deadline(flow).isEmpty ? '' : '\n'
                            'ภายในวันที่ ${_deadline(flow)} เท่านั้น'} '
                        '(เวลาทำการ)',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansThai(
                          fontSize: 15,
                          height: 1.5,
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
                    const SizedBox(height: 32),
                    // Tracking the request is the more useful of the two
                    // actions right after filing, so it leads.
                    if (!_isLead)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          height: 56,
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _canTrack
                                ? () => context.push(
                                      Uri(
                                        path: AppRoutes.topupStatus,
                                        queryParameters: {
                                          'dbName':
                                              flow?.contract?.dbName ?? '',
                                          'transNo': transNo,
                                        },
                                      ).toString(),
                                    )
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: LoanRegisterStyles.primary,
                              disabledBackgroundColor: LoanRegisterStyles
                                  .primary
                                  .withValues(alpha: 0.4),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'ดูสถานะการขอเพิ่มวงเงิน',
                              style: GoogleFonts.notoSansThai(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    SizedBox(
                      height: 56,
                      width: double.infinity,
                      child: ElevatedButton(
                        // Clear the wizard off the stack so back cannot
                        // re-enter a flow that has already been submitted. A
                        // host-launched run has no home to return to in this
                        // app — it closes the WebView instead.
                        onPressed: () {
                          if (flow?.entry == TopupEntry.host &&
                              NativeCameraBridge.isSupported) {
                            NativeCameraBridge.closeWebview();
                            return;
                          }
                          context.go(AppRoutes.home);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isLead
                              ? LoanRegisterStyles.primary
                              : LoanRegisterStyles.primarySoft,
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
                            color: _isLead
                                ? Colors.white
                                : LoanRegisterStyles.primary,
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
