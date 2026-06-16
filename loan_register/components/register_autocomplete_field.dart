import 'package:flutter/material.dart';

import 'loan_register_styles.dart';

/// A labelled text field with type-ahead autocomplete suggestions, styled to
/// match [RegisterTextField] (small grey label on top, bold dark-blue value,
/// bottom divider). Used for free-text-with-suggestions fields such as
/// ยี่ห้อสินค้า / รุ่นสินค้า / รายละเอียดสินค้า.
class RegisterAutocompleteField extends StatelessWidget {
  const RegisterAutocompleteField({
    Key? key,
    required this.label,
    required this.initialValue,
    required this.options,
    required this.onChanged,
    this.hint,
    this.labelTrailing,
    this.showDivider = true,
  }) : super(key: key);

  final String label;
  final String initialValue;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String? hint;

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
            ],
          ),
          Autocomplete<String>(
            initialValue: TextEditingValue(text: initialValue),
            optionsBuilder: (textEditingValue) {
              final query = textEditingValue.text.trim().toLowerCase();
              if (query.isEmpty) return const Iterable<String>.empty();
              return options
                  .where((o) => o.toLowerCase().contains(query));
            },
            onSelected: onChanged,
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                style: LoanRegisterStyles.valueStyle(),
                cursorColor: LoanRegisterStyles.primary,
                onChanged: onChanged,
                onSubmitted: (_) => onFieldSubmitted(),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.only(top: 6, bottom: 2),
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: LoanRegisterStyles.valueStyle()
                      .copyWith(color: LoanRegisterStyles.label),
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, opts) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: opts.length,
                      itemBuilder: (context, index) {
                        final option = opts.elementAt(index);
                        return InkWell(
                          onTap: () => onSelected(option),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            child: Text(
                              option,
                              style: LoanRegisterStyles.valueStyle()
                                  .copyWith(fontWeight: FontWeight.w400),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
