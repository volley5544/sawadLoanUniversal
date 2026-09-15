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

/// One selectable payment option: a mark, its label, its amount and a chevron.
///
/// ⚠ **Its detail does not live inside it.** The detail is one or more
/// [LoanPaymentDetailCard]s rendered as *siblings* underneath — which is how
/// the source lays it out, and why ยอดค้าง and ยอดปัจจุบัน read as two
/// separate blocks rather than one merged list.
class LoanPaymentOptionCard extends StatelessWidget {
  const LoanPaymentOptionCard({
    super.key,
    required this.label,
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  final String label;

  /// Null renders no figure — กำหนดยอดชำระเอง has no amount until one is
  /// typed, and the field below it is where that happens.
  final String? amount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          // Orange marks the choice, not navy: on this screen orange is the
          // colour of the action — the ชำระเงิน button is orange too — and the
          // selected option is that action in miniature.
          color: selected
              ? LoanDetailPalette.contractButtonText
              : LoanDetailPalette.divider,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          child: Row(
            children: [
              _OptionMark(selected: selected),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.notoSansThai(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: LoanDetailPalette.navy,
                  ),
                ),
              ),
              if (amount != null) ...[
                Text(
                  amount!,
                  style: GoogleFonts.notoSansThai(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: LoanDetailPalette.navy,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Down when the detail is closed, up when it is open — the
              // affordance that says the row expands.
              Icon(
                selected ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 20,
                color: LoanDetailPalette.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The selected option's mark is a **filled orange disc with a white tick**,
/// not a radio dot; unselected is a hollow grey ring.
class _OptionMark extends StatelessWidget {
  const _OptionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? LoanDetailPalette.contractButtonText
              : Colors.transparent,
          border: selected
              ? null
              : Border.all(color: LoanDetailPalette.label, width: 1.5),
        ),
        child: selected
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : null,
      );
}

/// A grey block of rows under the selected option, headed in orange.
///
/// ชำระเต็มจำนวน renders **two** of these — ค่างวดเลยกำหนดชำระ and
/// ค่างวดปัจจุบัน. That separation is the point of the screen: one block is
/// what is late, the other is what is due next, and merging them asks the
/// customer to add up rows belonging to different things.
class LoanPaymentDetailCard extends StatelessWidget {
  const LoanPaymentDetailCard({
    super.key,
    required this.heading,
    required this.children,
  });

  final String heading;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              heading,
              style: GoogleFonts.notoSansThai(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: LoanDetailPalette.contractButtonText,
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );
}

/// A label/value line inside a [LoanPaymentDetailCard].
class LoanPaymentDetailRow extends StatelessWidget {
  const LoanPaymentDetailRow({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.notoSansThai(
      fontSize: 14,
      height: 1.6,
      color: LoanDetailPalette.label,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 12),
        Text(value, textAlign: TextAlign.end, style: style),
      ],
    );
  }
}

/// A standing note — the part-payment warnings, or คุณไม่มียอดค้างชำระ.
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

/// The typed-amount field.
///
/// An **underline**, not a box, with the figure left-aligned and `บาท` outside
/// it on the right — the source's shape. A boxed, right-aligned field reads as
/// a form control; this reads as an amount written on a line.
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
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: GoogleFonts.notoSansThai(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: LoanDetailPalette.navy,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: hintText,
              hintStyle: GoogleFonts.notoSansThai(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: LoanDetailPalette.muted,
              ),
              contentPadding: const EdgeInsets.only(bottom: 6),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: LoanDetailPalette.divider),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide:
                    BorderSide(color: LoanDetailPalette.contractButtonText),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'บาท',
            style: GoogleFonts.notoSansThai(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: LoanDetailPalette.navy,
            ),
          ),
        ),
      ],
    );
  }
}

/// The sticky ชำระเงิน button. Null [onPressed] renders it disabled.
///
/// Orange, matching the ชำระเงิน button in the loan detail screen's bottom bar
/// that leads here — the two are the same action one screen apart, so they
/// read as one control rather than two.
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
            backgroundColor: LoanDetailPalette.contractButtonText,
            disabledBackgroundColor:
                LoanDetailPalette.contractButtonText.withValues(alpha: 0.4),
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
