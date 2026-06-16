import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'loan_register_styles.dart';

/// The sticky bottom action bar shown on every step page:
/// an outlined "บันทึกเตรียมข้อมูล" (save draft) button and a solid orange
/// "ถัดไป" (next) button.
class SaveNextBar extends StatelessWidget {
  const SaveNextBar({
    Key? key,
    required this.onSaveDraft,
    required this.onNext,
    this.nextLabel = 'ถัดไป',
    this.saveLabel = 'บันทึกเตรียมข้อมูล',
  }) : super(key: key);

  final VoidCallback onSaveDraft;
  final VoidCallback onNext;
  final String nextLabel;
  final String saveLabel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            LoanRegisterStyles.padding, 10, LoanRegisterStyles.padding, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: const Color.fromRGBO(0, 0, 0, 0.06),
              offset: const Offset(0, -2),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _Button(
                label: saveLabel,
                onTap: onSaveDraft,
                filled: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Button(
                label: nextLabel,
                onTap: onNext,
                filled: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.onTap,
    required this.filled,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? LoanRegisterStyles.primary : LoanRegisterStyles.primarySoft,
          borderRadius: BorderRadius.circular(14),
          border: filled
              ? null
              : Border.all(color: LoanRegisterStyles.primary, width: 1),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansThai(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: filled ? Colors.white : LoanRegisterStyles.primary,
          ),
        ),
      ),
    );
  }
}
