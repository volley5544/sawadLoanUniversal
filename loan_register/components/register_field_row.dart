import 'package:flutter/material.dart';

import 'loan_register_styles.dart';

/// A single labelled field row used throughout the loan-register forms.
///
/// Renders a small grey [label] on top and the bold dark-blue [value] below.
/// Covers every read-only / selector variant on slide 7:
///  • selector  → pass [onTap] (shows a chevron unless [trailing] overrides)
///  • date      → pass a calendar [trailing] icon + [onTap]
///  • calculated→ no [onTap], no chevron
///  • OCR-filled→ pass [labelTrailing] (small image icon next to the label)
///  • required  → pass [requiredHint] (red text shown instead of value)
class RegisterFieldRow extends StatelessWidget {
  const RegisterFieldRow({
    Key? key,
    required this.label,
    this.value = '',
    this.onTap,
    this.trailing,
    this.labelTrailing,
    this.requiredHint,
    this.placeholder,
    this.valueStyle,
    this.showDivider = true,
  }) : super(key: key);

  final String label;
  final String value;
  final VoidCallback? onTap;

  /// Custom trailing widget (e.g. calendar icon). When null and [onTap] is set,
  /// a chevron is shown automatically.
  final Widget? trailing;

  /// Small icon shown right after the label (used for OCR-filled fields).
  final Widget? labelTrailing;

  /// Red hint shown in place of the value when the field still needs input.
  final String? requiredHint;

  /// Greyed placeholder shown in place of the value when it's empty
  /// (e.g. "กรุณาเลือกเพศ"). Falls back to "-" when not provided.
  final String? placeholder;

  final TextStyle? valueStyle;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    Widget? effectiveTrailing = trailing;
    if (effectiveTrailing == null && onTap != null) {
      effectiveTrailing = Icon(Icons.chevron_right,
          color: LoanRegisterStyles.label, size: 22);
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: showDivider
              ? Border(
                  bottom:
                      BorderSide(color: LoanRegisterStyles.divider, width: 1))
              : null,
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
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
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (requiredHint != null)
                    Text(requiredHint!, style: LoanRegisterStyles.requiredStyle())
                  else if (value.isEmpty && placeholder != null)
                    Text(
                      placeholder!,
                      style: LoanRegisterStyles.valueStyle().copyWith(
                        color: LoanRegisterStyles.label,
                        fontWeight: FontWeight.w400,
                      ),
                    )
                  else
                    Text(
                      value.isEmpty ? '-' : value,
                      style: valueStyle ?? LoanRegisterStyles.valueStyle(),
                    ),
                ],
              ),
            ),
            if (effectiveTrailing != null) ...[
              const SizedBox(width: 8),
              effectiveTrailing,
            ],
          ],
        ),
      ),
    );
  }
}

/// Small image icon used to mark OCR auto-filled fields (🖼️ in the design).
class OcrBadge extends StatelessWidget {
  const OcrBadge({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.image_outlined,
        size: 16, color: LoanRegisterStyles.label);
  }
}

/// Section header with the orange vertical bar (e.g. "| ข้อมูลลูกค้า").
class RegisterSectionTitle extends StatelessWidget {
  const RegisterSectionTitle(this.title, {Key? key}) : super(key: key);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: LoanRegisterStyles.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(title, style: LoanRegisterStyles.sectionTitleStyle()),
        ],
      ),
    );
  }
}
