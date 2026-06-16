import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'loan_register_styles.dart';

/// A labelled editable field that matches the read-only rows visually
/// (small grey label on top, bold dark-blue value below, bottom divider) but
/// accepts keyboard input. Used for ชื่อ / นามสกุล / เบอร์โทร / วงเงินที่ต้องการ etc.
class RegisterTextField extends StatelessWidget {
  const RegisterTextField({
    Key? key,
    required this.label,
    required this.controller,
    this.keyboardType,
    this.inputFormatters,
    this.hint,
    this.requiredHint,
    this.labelTrailing,
    this.showDivider = true,
  }) : super(key: key);

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? hint;

  /// Red hint shown under the label (e.g. validation note).
  final String? requiredHint;

  /// Small icon shown right after the label (used for OCR-filled fields).
  final Widget? labelTrailing;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: LoanRegisterStyles.divider))
            : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: LoanRegisterStyles.labelStyle()),
              if (labelTrailing != null) ...[
                const SizedBox(width: 6),
                labelTrailing!,
              ],
              if (requiredHint != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(requiredHint!,
                      style: LoanRegisterStyles.requiredStyle()),
                ),
              ],
            ],
          ),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: LoanRegisterStyles.valueStyle(),
            cursorColor: LoanRegisterStyles.primary,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.only(top: 6, bottom: 2),
              border: InputBorder.none,
              hintText: hint,
              hintStyle: LoanRegisterStyles.valueStyle()
                  .copyWith(color: LoanRegisterStyles.label),
            ),
          ),
        ],
      ),
    );
  }
}
