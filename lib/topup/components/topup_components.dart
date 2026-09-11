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
import '../models/topup_photo.dart';

/// Number of screens in the top-up wizard, as the step indicator counts them:
/// สัญญา → วัตถุประสงค์ → ยอดเงิน → งวด → รูปหลักประกัน → ข้อมูลลูกค้า → สรุป.
const int kTopupTotalSteps = 7;

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
  });

  final String message;
  final IconData icon;
  final TopupNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
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
