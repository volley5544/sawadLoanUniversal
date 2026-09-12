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

/// **ชำระด้วย QR** — the dead end the amount screen sends a customer to when
/// `interest_paid_flag` is `'Y'`.
///
/// The accrued interest has to be settled before a top-up can be raised, so
/// this screen is not a wizard step: it shows a Thai bill-payment QR for the
/// outstanding amount and the customer comes back once they have paid.
/// `POST /payment/interest` has already been called by the time this opens —
/// this screen renders the reference, it does not create it.
///
/// ## The layout is the source's, deliberately
///
/// Rebuilt 2026-09-12 to match `customer_topup/qr_payment_page/` and §2.3 of
/// the QA manual rather than this app's usual card idiom: a payment screen is
/// one a customer may have seen in the other app minutes earlier, and two
/// different-looking QR pages for the same bill invites doubt about which one
/// is real. So the plate/amount row, the divider, the red payment-window note,
/// the navy `คิวอาร์โค้ด` pill, the 250×250 QR block, the R1/R2 lines and the
/// two 140×60 buttons are all positioned and coloured as they are there.
///
/// ⚠ [_QrPalette] exists for the same reason. These are the source theme's own
/// values, not `LoanRegisterStyles`, and the difference is visible — its
/// caption grey is darker and its navy deeper than ours. Matching the customer's
/// memory of the screen matters more here than matching the rest of this app,
/// which is why this is the one page that carries its own colours.
class TopupQrPaymentPage extends StatelessWidget {
  const TopupQrPaymentPage({super.key, required this.flow});

  final TopupFlow flow;

  /// Total due: the accrued interest plus the collection and penalty fees,
  /// which is the figure `/payment/interest` was asked to bill.
  ///
  /// Read off `/topup/detail` rather than the contract's own `topup_detail`
  /// (which is what the source uses): the detail call is re-read when the
  /// customer returns from paying, so it is the one that goes stale last.
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
    final barcode = flow.contract?.barcodeDetails;
    final satang = (_amountDue * 100).toString();
    return '|${barcode?.taxId ?? ''}${barcode?.suffix ?? ''}\n'
        '${barcode?.ref1 ?? ''}\n'
        '${barcode?.ref2 ?? ''}\n'
        '$satang\n';
  }

  /// Registration plate, prefix and number joined.
  String _plate(LoanContract contract) {
    final car = contract.carDetails;
    final joined = '${car.registrationPrefix} ${car.registration}'.trim();
    // The source shows `collateral_information` here, which is the same thing
    // already formatted; fall back to it when the parts are empty.
    return joined.isNotEmpty
        ? joined
        : contract.contractDetails.collateralInformation;
  }

  @override
  Widget build(BuildContext context) {
    final contract = flow.contract;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: topupAppBar(context, 'ชำระด้วย QR'),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 30),
        children: [
          if (contract != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: LoanRegisterStyles.padding),
              child: ContractSummaryCard(
                loanTypeCode: contract.contractDetails.loanTypeCode,
                loanTypeName: contract.contractDetails.loanTypeName,
                contractNo: contract.contractNo,
                collateralInformation:
                    contract.contractDetails.collateralInformation,
              ),
            ),
          // Plate on the left, amount on the right — the source's 80pt row.
          SizedBox(
            height: 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StackedValue(
                  label: 'เลขทะเบียน',
                  value: contract == null ? '-' : _plate(contract),
                ),
                _StackedValue(
                  label: 'จำนวนเงินค่างวด',
                  value: formatMoney(_amountDue),
                ),
              ],
            ),
          ),
          const Divider(thickness: 2, color: _QrPalette.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: Text(
              // The payment window is the bank's, not ours, and paying outside
              // it accrues more interest — which is the whole reason the
              // customer is on this screen.
              '*กรุณาชำระเงินภายในวัน 00:05 ถึง 22:45 เท่านั้น\n'
              'เพื่อหลีกเลี่ยงการเสียดอกเบี้ยเพิ่มเติม',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansThai(
                fontSize: 12,
                height: 1.4,
                color: _QrPalette.error,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              width: 200,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _QrPalette.navy,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                'คิวอาร์โค้ด',
                style: GoogleFonts.notoSansThai(
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 250,
              height: 250,
              child: Center(
                child: BarcodeWidget(
                  barcode: Barcode.qrCode(),
                  data: _payload,
                  width: 200,
                  height: 200,
                  color: Colors.black,
                  backgroundColor: Colors.transparent,
                  // The source draws the payload under the code, which is what
                  // the manual's screenshot shows.
                  drawText: true,
                  errorBuilder: (_, _) =>
                      const SizedBox(width: 200, height: 200),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // The two barcode references, so a customer paying at a counter can
          // read them out.
          _Caption('R1 : ${contract?.barcodeDetails.ref1 ?? ''}'),
          const SizedBox(height: 10),
          _Caption('R2 : ${contract?.barcodeDetails.ref2 ?? ''}'),
          const SizedBox(height: 10),
          const _Caption('สามารถสแกนชำระค่างวด ผ่านโมบายแอปได้ทุกธนาคาร'),
          const _Caption('ยกเว้นธนาคาร ธ.ก.ส. และ ออมสิน'),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _QrButton(
                label: 'ปรับปรุงยอดชำระ',
                color: _QrPalette.blue,
                // Pops back to the amount screen, which **reloads on return**
                // — re-reading `/topup/detail` is the only way the app finds
                // out a payment it cannot observe has landed. See
                // `_payInterest` there; this button refreshes nothing itself,
                // and must not, or the two screens could disagree about
                // whether the interest is still owed.
                onTap: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.home),
              ),
              _QrButton(
                label: 'คัดลอกข้อมูล',
                color: _QrPalette.orange,
                // ⚠ The source's second button is **บันทึกรูปภาพ**, which saves
                // the QR through a native custom action this build has no
                // equivalent for — and a web download inside the WebView is
                // not reliably honoured, so it would be a button that silently
                // does nothing. Copying the payment payload is the nearest
                // thing that always works; a screenshot covers the rest. Swap
                // this back only alongside a host handler that actually saves.
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: _payload));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('คัดลอกข้อมูลแล้ว')),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The source theme's own colours for this screen — see the class doc on
/// [TopupQrPaymentPage] for why this page carries its own palette.
abstract final class _QrPalette {
  /// `primaryText` — the `คิวอาร์โค้ด` pill.
  static const Color navy = Color(0xFF003063);

  /// `secondaryText` — every caption on this screen.
  static const Color caption = Color(0xFF646464);

  /// `alternate` — the 2pt divider under the amount row.
  static const Color divider = Color(0xFFE0E3E7);

  /// `error` — the payment-window warning. A true red, not the app's softer
  /// `LoanRegisterStyles.required`.
  static const Color error = Color(0xFFFF0000);

  /// `accent2` — the ปรับปรุงยอดชำระ button.
  static const Color blue = Color(0xFF1D71B8);

  /// `primary` — the second button.
  static const Color orange = Color(0xFFDB771A);
}

/// A grey label over its value, both 16pt — the source's amount-row column.
class _StackedValue extends StatelessWidget {
  const _StackedValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text(
            label,
            style: GoogleFonts.notoSansThai(
              fontSize: 16,
              color: _QrPalette.caption,
            ),
          ),
          Text(
            value.isEmpty ? '-' : value,
            style: GoogleFonts.notoSansThai(
              fontSize: 16,
              color: _QrPalette.navy,
            ),
          ),
        ],
      );
}

/// One centred grey line under the QR.
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.notoSansThai(
          fontSize: 14,
          color: _QrPalette.caption,
        ),
      );
}

/// The source's 140×60 action button: flat, 8pt radius, white label.
class _QrButton extends StatelessWidget {
  const _QrButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 140,
        height: 60,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansThai(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      );
}
