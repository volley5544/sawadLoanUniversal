import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'loan_register_styles.dart';

/// The 1‑2‑3‑4‑5 step header shown at the top of every wizard page.
///
/// Steps up to and including [currentStep] are filled orange (done/active);
/// later steps are grey outlines. [totalSteps] defaults to 5 to match slide 7.
class RegisterStepIndicator extends StatelessWidget {
  const RegisterStepIndicator({
    Key? key,
    required this.currentStep,
    this.totalSteps = 5,
  }) : super(key: key);

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    final List<Widget> row = [];
    for (int step = 1; step <= totalSteps; step++) {
      row.add(_circle(step));
      if (step != totalSteps) row.add(_connector(step < currentStep));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: LoanRegisterStyles.padding, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: row,
      ),
    );
  }

  Widget _circle(int step) {
    final bool active = step <= currentStep;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? LoanRegisterStyles.primary : Colors.white,
        border: Border.all(
          color: active ? LoanRegisterStyles.primary : LoanRegisterStyles.label,
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '$step',
        style: GoogleFonts.notoSansThai(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: active ? Colors.white : LoanRegisterStyles.label,
        ),
      ),
    );
  }

  Widget _connector(bool done) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: done ? LoanRegisterStyles.primary : LoanRegisterStyles.divider,
      ),
    );
  }
}
