/// The button under a bill-payment QR code.
///
/// Shared by the two screens that show one — the top-up flow's interest
/// payment and the loan-payment flow's instalment payment. Their **layouts**
/// are deliberately separate (they differ in labels, in one note and in
/// whether they carry a second button), but this control is the same control
/// doing the same job, and a customer who saves a QR on one screen should not
/// meet a differently-shaped button on the other.
///
/// Shared by construction rather than by care: the two drifted apart within a
/// day of the second screen being written — same size and colour, different
/// corner radius — which is exactly the kind of difference nobody notices in
/// review and everybody notices on a device.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class QrPaymentButton extends StatelessWidget {
  const QrPaymentButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.labelColor,
    this.busy = false,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  /// Overrides the white label — needed once a button carries a pale fill,
  /// where white text would be unreadable.
  final Color? labelColor;

  /// Swaps the label for a spinner. Capturing and saving the screen takes long
  /// enough on a phone to look like nothing happened.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final foreground = labelColor ?? Colors.white;
    return SizedBox(
      width: 140,
      height: 60,
      child: ElevatedButton(
        onPressed: busy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          // Hold the fill while busy: a greyed-out button beside an unchanged
          // one reads as "disabled", not "working".
          disabledBackgroundColor: color,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(foreground),
                ),
              )
            : Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansThai(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
      ),
    );
  }
}
