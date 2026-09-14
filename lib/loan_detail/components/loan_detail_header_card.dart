/// The loan detail screen's header card — icon, contract name, and the
/// running figures above the tabs.
///
/// **Shared with the payment screen**, which leads with the same card. That is
/// not a convenience: LandAndHouseWeb's own `select_payment_page` embeds its
/// `LoanDetailCardComponent` for exactly this, and that component carries the
/// same rows and the same rules as the srisawad app's card this was ported
/// from. Two differently-shaped summaries of one contract, one screen apart,
/// would invite the reader to wonder which is right.
///
/// All of its conditions and fallbacks live on [LoanDetailSummary]; this
/// widget only lays them out.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../p_loan/application/models/loan_contract.dart';
import '../models/loan_detail_summary.dart';
import 'loan_detail_components.dart';

/// Icon, contract name, and the running figures — everything above the tabs.
///
/// All of its conditions and fallbacks live on [LoanDetailSummary]; this
/// widget only lays them out.
class LoanDetailHeaderCard extends StatelessWidget {
  const LoanDetailHeaderCard({
    super.key,
    required this.contract,
    required this.showsNotIssuedNotice,
    required this.onDownloadContract,
    required this.onViewInsurances,
  });

  final LoanContract contract;
  final bool showsNotIssuedNotice;

  /// Null when the config names no contract portal, in which case the notice's
  /// `download` link is rendered as plain text rather than a dead tap.
  final VoidCallback? onDownloadContract;
  final VoidCallback onViewInsurances;

  @override
  Widget build(BuildContext context) {
    final summary = LoanDetailSummary(contract);
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 5, 20, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 15),
                  child: LoanTypeIcon(
                      dataUrl: contract.contractDetails.loanTypeIcon),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _rows(context, summary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (summary.showsNotAClosingBalanceNote)
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 8),
              child: Text(
                LoanDetailSummary.notAClosingBalanceNote,
                textAlign: TextAlign.end,
                style: GoogleFonts.notoSansThai(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: LoanDetailPalette.alert,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _rows(BuildContext context, LoanDetailSummary summary) => [
        const SizedBox(height: 3),
        Text(
          contract.contractDetails.loanTypeName,
          style: GoogleFonts.notoSansThai(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: LoanDetailPalette.label,
          ),
        ),
        const SizedBox(height: 4),
        LoanDetailSummaryRow(
          label: 'เลขที่สัญญา',
          value: contract.contractNo.trim(),
        ),
        const SizedBox(height: 3),
        LoanDetailSummaryRow(
          label: 'ชำระภายในวันที่',
          value: summary.payByDateLabel,
          valueColor: summary.payByDateIsOverdue
              ? LoanDetailPalette.alert
              : LoanDetailPalette.label,
        ),
        if (summary.showsInsuranceRow)
          LoanDetailSummaryRow(
            label: 'กรมธรรม์',
            value: '',
            trailing: GestureDetector(
              onTap: onViewInsurances,
              child: Text(
                'ดูรายละเอียด',
                textAlign: TextAlign.end,
                style: GoogleFonts.notoSansThai(
                  fontSize: 13,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: LoanDetailPalette.navy,
                  decoration: TextDecoration.underline,
                  decorationColor: LoanDetailPalette.navy,
                ),
              ),
            ),
          ),
        const SizedBox(height: 3),
        if (showsNotIssuedNotice) _notIssuedNotice(),
        if (summary.showsOverdueRow)
          LoanDetailSummaryRow(
            label: summary.overdueRangeLabel,
            value: summary.overdueValueLabel,
            emphasised: true,
            valueColor: summary.showsPastDueInsteadOfAmount
                ? LoanDetailPalette.alert
                : LoanDetailPalette.navy,
          ),
        if (summary.showsInstallmentRow)
          LoanDetailSummaryRow(
            label: summary.installmentLabel,
            value: summary.installmentValue,
            emphasised: true,
          ),
        if (summary.showsCurrentInstallmentAmountRow)
          LoanDetailSummaryRow(
            label: 'ค่างวดปัจจุบัน',
            value: summary.currentInstallmentAmountLabel,
            emphasised: true,
            valueColor: summary.showsPastDueInsteadOfAmount
                ? LoanDetailPalette.alert
                : LoanDetailPalette.navy,
          ),
        if (summary.showsTotalDueRow)
          LoanDetailSummaryRow(
            label: 'รวมต้องชำระ',
            value: summary.totalDueLabel,
            emphasised: true,
          ),
      ];

  /// *"ถ้าลูกค้ายังไม่ได้รับตั๋วสัญญาใช้เงิน ณ วันที่ทำสัญญา กรุณา download"* —
  /// whether it shows at all is [ComcodeConfig.showsContractNotIssuedNotice].
  Widget _notIssuedNotice() {
    final base = GoogleFonts.notoSansThai(
      fontSize: 14,
      height: 1.5,
      color: LoanDetailPalette.alert,
    );
    return RichText(
      text: TextSpan(
        style: base,
        children: [
          const TextSpan(
              text: 'ถ้าลูกค้ายังไม่ได้รับตั๋วสัญญาใช้เงิน ณ วันที่ทำสัญญา กรุณา '),
          TextSpan(
            text: 'download',
            recognizer: onDownloadContract == null
                ? null
                : (TapGestureRecognizer()..onTap = onDownloadContract),
            style: base.copyWith(
              color: LoanDetailPalette.navy,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: LoanDetailPalette.navy,
            ),
          ),
        ],
      ),
    );
  }
}
