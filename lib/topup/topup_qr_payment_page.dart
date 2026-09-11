import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../loan_register/components/loan_register_styles.dart';
import '../p_loan/application/components/p_loan_components.dart';
import '../p_loan/application/models/loan_contract.dart';
import '../router/app_router.dart';
import 'components/topup_components.dart';
import 'models/topup_flow.dart';

/// **ชำระดอกเบี้ยค้างชำระ** — the dead end the amount screen sends a customer to
/// when `interest_paid_flag` is `'Y'`.
///
/// The accrued interest has to be settled before a top-up can be raised, so
/// this screen is not a wizard step: it shows a Thai bill-payment QR for the
/// outstanding amount and the customer comes back once they have paid.
/// `POST /payment/interest` has already been called by the time this opens —
/// this screen renders the reference, it does not create it.
class TopupQrPaymentPage extends StatelessWidget {
  const TopupQrPaymentPage({super.key, required this.flow});

  final TopupFlow flow;

  /// Total due: the accrued interest plus the collection and penalty fees,
  /// which is the figure `/payment/interest` was asked to bill.
  double get _amountDue {
    final detail = flow.amountDetail;
    if (detail == null) return 0;
    return detail.interestYield + detail.collectionFee + detail.penaltyFee;
  }

  /// The Thai bill-payment barcode payload.
  ///
  /// ⚠ **Byte-for-byte the source's `genQRCodePayment`, including the amount's
  /// trailing `.0`** — it multiplies by 100 and calls `toString()` on a
  /// `double`, so ฿1,234 renders as `123400.0` rather than the integer satang
  /// the barcode standard describes. That looks wrong, but this string is what
  /// the shipped app prints and what the bank's scanner is known to accept, so
  /// it is reproduced rather than "fixed" — changing a live payment reference
  /// on a hunch is not a change to make from here. Confirm the intended format
  /// with the payments team before touching it.
  String get _payload {
    final contract = flow.contract;
    final barcode = contract?.barcodeDetails;
    final satang = (_amountDue * 100).toString();
    return '|${barcode?.taxId ?? ''}${barcode?.suffix ?? ''}\n'
        '${barcode?.ref1 ?? ''}\n'
        '${barcode?.ref2 ?? ''}\n'
        '$satang\n';
  }

  /// Registration plate, prefix and number joined.
  String _plate(LoanContract contract) {
    final car = contract.carDetails;
    return '${car.registrationPrefix} ${car.registration}'.trim();
  }

  /// One barcode reference line.
  Widget _reference(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$label ',
              style: GoogleFonts.notoSansThai(
                  fontSize: 13, color: LoanRegisterStyles.label)),
          Text(
            value,
            style: GoogleFonts.notoSansThai(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: LoanRegisterStyles.value,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contract = flow.contract;
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: topupAppBar(context, 'ชำระด้วย QR'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            LoanRegisterStyles.padding, 12, LoanRegisterStyles.padding, 24),
        children: [
          if (contract != null)
            ContractSummaryCard(
              loanTypeCode: contract.contractDetails.loanTypeCode,
              loanTypeName: contract.contractDetails.loanTypeName,
              contractNo: contract.contractNo,
              collateralInformation:
                  contract.contractDetails.collateralInformation,
            ),
          const TopupNotice(
            'กรุณาชำระดอกเบี้ยค้างชำระให้เรียบร้อยก่อน '
            'จึงจะสามารถทำรายการขอสินเชื่อเพิ่มได้',
            icon: Icons.payments_outlined,
            tone: TopupNoticeTone.warning,
          ),
          if (contract != null)
            PLoanAmountRow(
              label: 'เลขทะเบียน',
              value: _plate(contract).isEmpty ? '-' : _plate(contract),
              showDivider: false,
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: LoanRegisterStyles.cardBorder),
            ),
            child: Column(
              children: [
                Text(
                  'ยอดที่ต้องชำระ',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 13,
                    color: LoanRegisterStyles.label,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatMoney(_amountDue)} บาท',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: LoanRegisterStyles.required,
                  ),
                ),
                const SizedBox(height: 12),
                // The payment window is the bank's, not ours, and paying
                // outside it accrues more interest — which is the whole
                // reason the customer is on this screen.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    '*กรุณาชำระเงินภายในวัน 00.05 ถึง 22.45 เท่านั้น '
                    'เพื่อหลีกเลี่ยงการเสียดอกเบี้ยเพิ่มเติม',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 12.5,
                      height: 1.4,
                      color: LoanRegisterStyles.required,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                BarcodeWidget(
                  barcode: Barcode.qrCode(),
                  data: _payload,
                  width: 220,
                  height: 220,
                  drawText: false,
                ),
                const SizedBox(height: 12),
                // The two barcode references, shown so a customer paying at a
                // counter can read them out.
                if (contract != null) ...[
                  _reference('R1', contract.barcodeDetails.ref1),
                  _reference('R2', contract.barcodeDetails.ref2),
                ],
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'สามารถสแกนชำระค่างวด ผ่านโมบายแอปได้ทุกธนาคาร '
                    'ยกเว้นธนาคาร ธ.ก.ส. และออมสิน',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 12.5,
                      height: 1.4,
                      color: LoanRegisterStyles.label,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _payload));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('คัดลอกข้อมูลแล้ว')),
                      );
                    }
                  },
                  icon: Icon(Icons.copy,
                      size: 18, color: LoanRegisterStyles.primary),
                  label: Text(
                    'คัดลอกข้อมูลชำระเงิน',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 13,
                      color: LoanRegisterStyles.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const PLoanSectionHeader('รายละเอียดยอดค้างชำระ'),
          PLoanAmountRow(
            label: 'ดอกเบี้ยค้างชำระ',
            value: '${formatMoney(flow.amountDetail?.interestYield ?? 0)} บาท',
          ),
          PLoanAmountRow(
            label: 'ค่าติดตามทวงถาม',
            value: '${formatMoney(flow.amountDetail?.collectionFee ?? 0)} บาท',
          ),
          PLoanAmountRow(
            label: 'ค่าปรับ',
            value: '${formatMoney(flow.amountDetail?.penaltyFee ?? 0)} บาท',
            showDivider: false,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: LoanRegisterStyles.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TopupPrimaryButton(
                label: 'ปรับปรุงยอดชำระ',
                outlined: true,
                // Popping back to the amount screen re-runs its load, which
                // re-reads `/topup/detail` — the only way the app finds out a
                // payment it cannot observe has landed.
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.home),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TopupPrimaryButton(
                label: 'กลับสู่หน้าแรก',
                onPressed: () => context.go(AppRoutes.home),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
