/// Building blocks for the **ชำระเงิน** screen.
///
/// Reuses [LoanDetailPalette] rather than declaring another: this screen sits
/// one tap from the loan detail screen and shows the same contract, so a
/// second navy would read as a different app.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../loan_detail/components/loan_detail_components.dart';
import '../../p_loan/application/components/p_loan_components.dart';
import '../../p_loan/application/models/loan_contract.dart';

/// **ข้อมูลหลักประกัน** — what the loan is secured on.
///
/// The source's `LoanDetailCardTopupComponent`, reduced to the rows it
/// actually renders for this screen.
class LoanPaymentCollateralCard extends StatelessWidget {
  const LoanPaymentCollateralCard({super.key, required this.contract});

  final LoanContract contract;

  @override
  Widget build(BuildContext context) {
    final details = contract.contractDetails;
    final rows = <({String label, String value})>[
      (label: 'เลขที่สัญญา', value: contract.contractNo.trim()),
      if (details.loanTypeName.trim().isNotEmpty)
        (label: 'ประเภทสินค้า', value: details.loanTypeName.trim()),
      if (details.collateralInformation.trim().isNotEmpty)
        (label: 'เลขทะเบียน', value: details.collateralInformation.trim()),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LoanDetailPalette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ข้อมูลหลักประกัน',
            style: GoogleFonts.notoSansThai(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: LoanDetailPalette.navy,
            ),
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: LoanDetailSummaryRow(
                label: row.label,
                value: row.value,
              ),
            ),
        ],
      ),
    );
  }
}

/// One selectable payment option: a radio, its label, its amount, and — while
/// it is the selected one — its detail block underneath.
class LoanPaymentOptionCard extends StatelessWidget {
  const LoanPaymentOptionCard({
    super.key,
    required this.label,
    required this.amount,
    required this.selected,
    required this.onTap,
    this.detail,
  });

  final String label;

  /// Null renders no figure beside the radio — the typed option's amount is
  /// the field in its detail block, and a second number here would compete.
  final String? amount;
  final bool selected;
  final VoidCallback onTap;

  /// Rendered only when [selected]; the source builds each option's rows
  /// behind its own selected flag.
  final Widget? detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? LoanDetailPalette.navy : LoanDetailPalette.divider,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? LoanDetailPalette.navy
                        : LoanDetailPalette.label,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.notoSansThai(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: LoanDetailPalette.navy,
                      ),
                    ),
                  ),
                  if (amount != null)
                    Text(
                      amount!,
                      style: GoogleFonts.notoSansThai(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: LoanDetailPalette.navy,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
              child: detail,
            ),
        ],
      ),
    );
  }
}

/// A bold sub-heading inside an option's detail block (ค่างวดเลยกำหนดชำระ,
/// กำหนดยอดชำระ).
class LoanPaymentDetailHeading extends StatelessWidget {
  const LoanPaymentDetailHeading({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          text,
          style: GoogleFonts.notoSansThai(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: LoanDetailPalette.label,
          ),
        ),
      );
}

/// A label/value line inside an option's detail block.
class LoanPaymentDetailRow extends StatelessWidget {
  const LoanPaymentDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasised = false,
  });

  final String label;
  final String value;
  final bool emphasised;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: LoanDetailSummaryRow(
          label: label,
          value: value,
          emphasised: emphasised,
        ),
      );
}

/// A standing note — the ceiling reminder, the part-payment warning, or
/// คุณไม่มียอดค้างชำระ.
class LoanPaymentNotice extends StatelessWidget {
  const LoanPaymentNotice({super.key, required this.text, this.alert = false});

  final String text;

  /// Red rather than grey. The two part-payment warnings are alerts; the
  /// "nothing overdue" line is simply a statement.
  final bool alert;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          text,
          style: GoogleFonts.notoSansThai(
            fontSize: 13,
            height: 1.5,
            fontWeight: alert ? FontWeight.w600 : FontWeight.w400,
            color: alert ? LoanDetailPalette.alert : LoanDetailPalette.label,
          ),
        ),
      );
}

/// The typed-amount field, with its `บาท` suffix.
class LoanPaymentAmountField extends StatelessWidget {
  const LoanPaymentAmountField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            textAlign: TextAlign.end,
            style: GoogleFonts.notoSansThai(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: LoanDetailPalette.navy,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: hintText,
              hintStyle: GoogleFonts.notoSansThai(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: LoanDetailPalette.muted,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: LoanDetailPalette.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: LoanDetailPalette.navy),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'บาท',
          style: GoogleFonts.notoSansThai(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: LoanDetailPalette.navy,
          ),
        ),
      ],
    );
  }
}

/// The sticky ชำระเงิน button. Null [onPressed] renders it disabled.
class LoanPaymentPrimaryButton extends StatelessWidget {
  const LoanPaymentPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 60,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: LoanDetailPalette.navy,
            disabledBackgroundColor:
                LoanDetailPalette.navy.withValues(alpha: 0.4),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.notoSansThai(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      );
}

/// The source raises its refusals in a modal dialog. A dialog for a one-line
/// correction to a field the customer is still looking at is heavier than the
/// correction, so this is a SnackBar — the same idiom every other refusal in
/// this build uses.
void showLoanPaymentMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Re-exported so the page need not import the P-Loan kit for one formatter.
String formatPaymentMoney(num? value) => formatMoney(value);
