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

/// One selectable payment option: a mark, its label, its amount, a chevron —
/// and, when it is selected, **its own detail nested inside the same card**.
///
/// ⚠ **That nesting is the 2026-09-17 redesign's central change.** The old
/// screen rendered the detail as *sibling* grey cards underneath the bordered
/// header, so an option and its explanation were two things that happened to
/// sit next to each other. Here the orange border wraps both, which is what
/// makes the three options read as an accordion. `loan_payment_page_old.dart`
/// still renders the sibling form, and its private copy of this widget is why
/// editing this one cannot disturb it.
class LoanPaymentOptionCard extends StatelessWidget {
  const LoanPaymentOptionCard({
    super.key,
    required this.label,
    required this.amount,
    required this.selected,
    required this.onTap,
    this.children = const [],
  });

  final String label;

  /// Null renders no figure — กำหนดยอดชำระเอง has no amount until one is
  /// typed, and the field inside it is where that happens.
  final String? amount;
  final bool selected;
  final VoidCallback onTap;

  /// The detail, shown only while [selected].
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
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
                        fontWeight: FontWeight.w700,
                        color: LoanDetailPalette.navy,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Down when the detail is closed, up when it is open — the
                  // affordance that says the row expands.
                  Icon(
                    selected
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: LoanDetailPalette.muted,
                  ),
                ],
              ),
            ),
          ),
          if (selected && children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
        ],
      ),
    );
  }
}

/// ⚠ **A ring with an orange tick, not a filled disc** (changed 2026-09-17).
/// The old screen filled the circle orange and put a white tick in it; the
/// redesign outlines it. Unselected is a hollow grey ring either way.
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
          border: Border.all(
            color: selected
                ? LoanDetailPalette.contractButtonText
                : LoanDetailPalette.label,
            width: 1.5,
          ),
        ),
        child: selected
            ? Icon(Icons.check,
                size: 13, color: LoanDetailPalette.contractButtonText)
            : null,
      );
}

/// A block of rows inside the selected option, headed in **navy**.
///
/// ⚠ Changed 2026-09-17: it was a grey card with an orange heading, sitting
/// *outside* the option. It is now a white card with a soft shadow nested
/// inside the orange border, and the heading is navy — orange is reserved for
/// the selection and the action on this screen, so a second orange heading
/// inside an already-orange card read as another control.
///
/// ชำระเต็มจำนวน renders **two** of these — ยอดค้างชำระ and ค่างวดปัจจุบัน.
/// That separation is the point of the screen: one block is what is late, the
/// other is what is due next, and merging them asks the customer to add up
/// rows belonging to different things.
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
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              heading,
              style: GoogleFonts.notoSansThai(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: LoanDetailPalette.navy,
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );
}

/// A label/value line inside a [LoanPaymentDetailCard].
///
/// [strong] is the block's own total — `รวม` under ยอดค้างชำระ — which the
/// design sets in the label colour but bold on both halves. It is the only
/// thing distinguishing that line from the rows it sums.
class LoanPaymentDetailRow extends StatelessWidget {
  const LoanPaymentDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.notoSansThai(
      fontSize: 14,
      height: 1.7,
      fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
      color: strong ? LoanDetailPalette.navy : LoanDetailPalette.label,
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

/// The compact contract header the redesign leads with (2026-09-17).
///
/// ⚠ **It replaces [LoanDetailHeaderCard] on this screen**, which is the
/// redesign's other structural change. That card restates the whole
/// contract — due date, current instalment, arrears, `รวมต้องชำระ` — directly
/// above three options whose own figures explain the same money. The customer
/// is here to choose an amount, so the header is now only what identifies the
/// contract: the product, the plate and the contract number.
///
/// The loan detail screen still renders the full card; this one does not, so
/// the two screens no longer show the same figures twice in a row.
class LoanPaymentContractHeader extends StatelessWidget {
  const LoanPaymentContractHeader({
    super.key,
    required this.loanTypeIconDataUrl,
    required this.loanTypeName,
    required this.plate,
    required this.contractNo,
  });

  final String loanTypeIconDataUrl;
  final String loanTypeName;

  /// `collateral_information` — the registration plate, shown top-right.
  final String plate;
  final String contractNo;

  @override
  Widget build(BuildContext context) {
    final navy = GoogleFonts.notoSansThai(
      fontSize: 17,
      height: 1.3,
      fontWeight: FontWeight.w700,
      color: LoanDetailPalette.navy,
    );
    final grey = GoogleFonts.notoSansThai(
      fontSize: 14,
      height: 1.4,
      color: LoanDetailPalette.label,
    );
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LoanTypeIcon(dataUrl: loanTypeIconDataUrl, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        child: Text(dashIfEmpty(loanTypeName), style: navy)),
                    const SizedBox(width: 12),
                    // `-` rather than an absent widget: a missing plate is a
                    // data gap to report, not a layout variant.
                    Text(dashIfEmpty(plate), style: navy),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('เลขที่สัญญา', style: grey),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(dashIfEmpty(contractNo),
                          textAlign: TextAlign.end, style: grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
            // Large, as the design draws it — the typed figure is the one
            // thing on that card the customer is producing, and at row size it
            // read as another detail line.
            style: GoogleFonts.notoSansThai(
              fontSize: 30,
              fontWeight: FontWeight.w700,
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
