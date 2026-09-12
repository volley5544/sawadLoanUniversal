/// Widgets specific to the top-up flow.
///
/// Formatters and the generic cards come from the P-Loan kit
/// (`p_loan/application/components/p_loan_components.dart`) — those are
/// product-neutral, so duplicating them here would only let the two drift.
/// What lives in this file is what a top-up needs and a P-Loan does not.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../loan_register/components/env_version_tag.dart';
import '../../loan_register/components/loan_register_styles.dart';
import '../../loan_register/components/register_step_indicator.dart';
import '../../p_loan/application/components/p_loan_components.dart';
import '../models/topup_flow.dart';
import '../models/topup_photo.dart';

/// Number of screens the step indicator counts:
/// สัญญา → ยอดเงิน → งวด → รูปหลักประกัน → ข้อมูลลูกค้า → สรุป.
///
/// The contract screen is **step 1 and shows no indicator** — it is where the
/// product is chosen, so it sits ahead of the wizard rather than inside it.
/// The bar therefore first appears on the amount screen at 2 of 6. Counting it
/// rather than renumbering from the amount screen keeps the flow from
/// disowning the screen the customer just used, the same reasoning as
/// `PLoanEntry.precedingSteps`.
///
/// ⚠ There is no วัตถุประสงค์ step any more (removed 2026-09-11). The card
/// already settles which product this is: **เติมวงเงิน** starts a top-up, and
/// a **สิทธิพิเศษเฉพาะคุณ** tile either carries its product onto the flow or,
/// for `PLD001`, leaves for the P-Loan Extra flow entirely.
const int kTopupTotalSteps = 6;

/// The flow's app bar. Carries [EnvVersionTag] like every other screen in the
/// app, so a tester can read the env + build off any page.
///
/// [onBack] replaces the default pop — needed on the flow's first screen when
/// it was launched by the host and has nothing beneath it on the stack.
AppBar topupAppBar(BuildContext context, String title, {VoidCallback? onBack}) =>
    AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: BackButton(color: LoanRegisterStyles.primary, onPressed: onBack),
      centerTitle: true,
      title: Text(
        title,
        style: LoanRegisterStyles.appBarTitleStyle()
            .copyWith(color: LoanRegisterStyles.primary),
      ),
      actions: const [EnvVersionTag()],
    );

/// The 1–7 header, so no screen has to remember the total.
class TopupStepIndicator extends StatelessWidget {
  const TopupStepIndicator(this.step, {super.key});

  final int step;

  @override
  Widget build(BuildContext context) =>
      RegisterStepIndicator(currentStep: step, totalSteps: kTopupTotalSteps);
}

/// One photo slot: tap to capture, tap the thumbnail to view, × to clear.
///
/// Capture goes through the native host's camera (`openCamera`), which is why
/// [onCapture] is a future — the host answers with the image, and the tile
/// shows a spinner until it does.
class TopupPhotoTile extends StatelessWidget {
  const TopupPhotoTile({
    super.key,
    required this.slot,
    required this.bytes,
    required this.onCapture,
    required this.onClear,
    this.busy = false,
  });

  final TopupPhoto slot;
  final Uint8List? bytes;
  final VoidCallback onCapture;
  final VoidCallback onClear;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final image = bytes;
    final captured = image != null && image.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            slot.label,
            style: GoogleFonts.notoSansThai(
              fontSize: 13,
              color: captured
                  ? LoanRegisterStyles.label
                  : LoanRegisterStyles.required,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: busy ? null : (captured ? () => _preview(context) : onCapture),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 148,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: captured
                      ? LoanRegisterStyles.cardBorder
                      : LoanRegisterStyles.divider,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: busy
                  ? const Center(child: CircularProgressIndicator())
                  : captured
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(image, fit: BoxFit.cover),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: _RoundIconButton(
                                icon: Icons.close,
                                onTap: onClear,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.photo_camera_outlined,
                                size: 34, color: LoanRegisterStyles.primary),
                            const SizedBox(height: 8),
                            Text(
                              'ถ่ายรูปภาพ',
                              style: GoogleFonts.notoSansThai(
                                fontSize: 13,
                                color: LoanRegisterStyles.primary,
                              ),
                            ),
                          ],
                        ),
            ),
          ),
          if (captured)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton(
                onPressed: busy ? null : onCapture,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'ถ่ายใหม่',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 13,
                    color: LoanRegisterStyles.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _preview(BuildContext context) {
    final image = bytes;
    if (image == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.memory(image),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('ปิด', style: GoogleFonts.notoSansThai()),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(icon, size: 17, color: Colors.white),
          ),
        ),
      );
}

/// A short explanatory strip — used for the provisional/blocked notices the
/// flow shows in place of an error when the data is fine but a step cannot
/// proceed.
class TopupNotice extends StatelessWidget {
  const TopupNotice(
    this.message, {
    super.key,
    this.icon = Icons.info_outline,
    this.tone = TopupNoticeTone.info,
    this.accent,
  });

  final String message;
  final IconData icon;
  final TopupNoticeTone tone;

  /// Overrides the tone's colour.
  ///
  /// Exists for the 2026-09 redesign, whose footnote red is pure where
  /// [LoanRegisterStyles.required] is a softer material red — see
  /// `TopupTheme.alert`. Passing it keeps a redesigned screen internally
  /// consistent **without** repainting the screens that still use the tone
  /// default: the un-redesigned steps, and the `_old` pair, which must render
  /// exactly as they did.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ??
        switch (tone) {
          TopupNoticeTone.info => LoanRegisterStyles.primary,
          TopupNoticeTone.warning => LoanRegisterStyles.required,
        };
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.notoSansThai(fontSize: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

enum TopupNoticeTone { info, warning }

/// The flow's primary button **without** the sticky-bar chrome.
///
/// `PLoanBottomButton` is that same button wrapped in a white bar with a top
/// divider, which is right at the bottom of a screen and wrong inside a card.
class TopupPrimaryButton extends StatelessWidget {
  const TopupPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  /// Secondary styling — an orange outline instead of a filled button.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final child = busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(
            label,
            style: GoogleFonts.notoSansThai(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: outlined ? LoanRegisterStyles.primary : Colors.white,
            ),
          );
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: outlined
          ? OutlinedButton(
              onPressed: enabled ? onPressed : null,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: LoanRegisterStyles.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: child,
            )
          : ElevatedButton(
              onPressed: enabled ? onPressed : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: LoanRegisterStyles.primary,
                disabledBackgroundColor:
                    LoanRegisterStyles.primary.withValues(alpha: 0.5),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: child,
            ),
    );
  }
}

/// Checkbox row used for the two PDPA questions on the conclusion screen.
class TopupConsentCheckbox extends StatelessWidget {
  const TopupConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.required = false,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                  activeColor: LoanRegisterStyles.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: label),
                      if (required)
                        TextSpan(
                          text: ' *',
                          style: TextStyle(color: LoanRegisterStyles.required),
                        ),
                    ],
                  ),
                  style: GoogleFonts.notoSansThai(
                    fontSize: 13,
                    color: LoanRegisterStyles.value,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}


/// One row of the amount screen's numbered deduction list, plus its
/// indented children.
///
/// The number is rendered as part of the label (`1.หักยอด…`) exactly as the
/// source does, rather than as a separate column — see
/// [TopupFlow.deductionLines] for why the sequence can skip 4.
class TopupDeductionRow extends StatelessWidget {
  const TopupDeductionRow(this.line, {super.key});

  final TopupDeductionLine line;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${line.number}.${line.label}',
                      style: GoogleFonts.notoSansThai(
                        fontSize: 14,
                        color: LoanRegisterStyles.value,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${formatMoney(line.amount)} บาท',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: line.highlight
                          ? LoanRegisterStyles.required
                          : LoanRegisterStyles.value,
                    ),
                  ),
                ],
              ),
              if (line.caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    line.caption,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 12,
                      color: LoanRegisterStyles.required,
                    ),
                  ),
                ),
              if (line.contractNo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'เลขที่สัญญา ${line.contractNo}',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 11.5,
                      color: LoanRegisterStyles.label,
                    ),
                  ),
                ),
              if (line.warning.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    line.warning,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 12.5,
                      color: LoanRegisterStyles.required,
                    ),
                  ),
                ),
              if (line.children.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'รายละเอียด (${line.number})',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 13,
                    color: LoanRegisterStyles.label,
                  ),
                ),
                for (final child in line.children)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${child.number} ${child.label}',
                            style: GoogleFonts.notoSansThai(
                              fontSize: 13.5,
                              color: LoanRegisterStyles.value,
                            ),
                          ),
                        ),
                        Text(
                          '${formatMoney(child.amount)} บาท',
                          style: GoogleFonts.notoSansThai(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: LoanRegisterStyles.value,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: LoanRegisterStyles.divider),
      ],
    );
  }
}

/// The "วิธีขอปรับวงเงินเพิ่ม" conditions panel at the top of the contract
/// screen.
///
/// Wording is the source's, including the service hours and the 30-minute
/// transfer promise — this is a commitment to the customer, not copy of ours
/// to reword. The business-hours window is also enforced server-side:
/// `GET /topup/detail` answers `503` outside 07:00–20:30.
class TopupConditionsPanel extends StatelessWidget {
  const TopupConditionsPanel({super.key});

  static const List<String> _bullets = [
    'จ่ายตรง -> เครดิตดี -> ได้วงเงินเพิ่ม',
    'จ่ายช้า -> ขอปรับสัญญาที่สาขา -> รักษาเครดิต -> ปรับวงเงินเพิ่ม',
  ];

  static const List<String> _notes = [
    '* สามารถทำการขอเติมวงเงินได้เวลาทำการ 07.00 - 20.30 น.',
    '** เงื่อนไขอาจมีการเปลี่ยนแปลงได้ โดยไม่ต้องแจ้งให้ทราบล่วงหน้า',
    '*** บริษัทจะดำเนินการโอนเงินภายใน 30 นาที ในวันและเวลาทำการ '
        '07.00 - 20.30 น.',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
          LoanRegisterStyles.padding, 8, LoanRegisterStyles.padding, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LoanRegisterStyles.primarySoft,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'วิธีขอปรับวงเงินเพิ่ม',
            style: GoogleFonts.notoSansThai(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: LoanRegisterStyles.primary,
            ),
          ),
          const SizedBox(height: 8),
          for (final bullet in _bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $bullet',
                style: GoogleFonts.notoSansThai(
                  fontSize: 13,
                  height: 1.5,
                  color: LoanRegisterStyles.value,
                ),
              ),
            ),
          const SizedBox(height: 4),
          for (final note in _notes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                note,
                style: GoogleFonts.notoSansThai(
                  fontSize: 12.5,
                  height: 1.5,
                  color: LoanRegisterStyles.required,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
