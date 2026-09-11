import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../loan_register/components/loan_register_styles.dart';
import '../p_loan/application/components/p_loan_components.dart';
import '../router/app_router.dart';
import 'components/topup_components.dart';
import 'models/topup_flow.dart';
import 'models/topup_purpose.dart';

/// **Step 2 — วัตถุประสงค์การขอสินเชื่อ.** What the money is for.
///
/// The options are not fetched: they are the add-on products the contract
/// itself offers, plus a synthesised "อื่นๆ" priced at the contract's default
/// limit — see [TopupPurpose.forContract]. A named product fixes the amount;
/// "อื่นๆ" leaves step 3's field editable.
///
/// No API call of its own.
class TopupPurposePage extends StatefulWidget {
  const TopupPurposePage({super.key, required this.flow});

  final TopupFlow flow;

  @override
  State<TopupPurposePage> createState() => _TopupPurposePageState();
}

class _TopupPurposePageState extends State<TopupPurposePage> {
  late final List<TopupPurpose> _options;
  late final TextEditingController _note;
  TopupPurpose? _selected;

  @override
  void initState() {
    super.initState();
    final contract = widget.flow.contract;
    _options =
        contract == null ? const [] : TopupPurpose.forContract(contract);
    _note = TextEditingController(text: widget.flow.purposeNote);
    // Preserve the choice when the customer comes back to this screen.
    final previous = widget.flow.purpose;
    if (previous != null) {
      _selected = _options.firstWhere(
        (o) => o.productCode == previous.productCode,
        orElse: () => previous,
      );
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _next() {
    final selected = _selected;
    if (selected == null) return;
    widget.flow
      ..purpose = selected
      ..purposeNote = selected.isOther ? _note.text.trim() : ''
      // The purpose seeds the amount. A named product is priced by the
      // product; "อื่นๆ" starts at the contract's default and step 3 lets the
      // customer change it.
      ..requestedAmount = selected.productPrice;
    context.push(AppRoutes.topupAmount, extra: widget.flow);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: topupAppBar(context, 'วัตถุประสงค์'),
      body: Column(
        children: [
          const TopupStepIndicator(2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  LoanRegisterStyles.padding, 4, LoanRegisterStyles.padding, 24),
              children: [
                Text(
                  'ท่านต้องการนำสินเชื่อไปใช้เพื่ออะไร',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: LoanRegisterStyles.value,
                  ),
                ),
                const SizedBox(height: 12),
                for (final option in _options) _tile(option),
              ],
            ),
          ),
          PLoanBottomButton(
            label: 'ถัดไป',
            onPressed: _selected == null ? null : _next,
          ),
        ],
      ),
    );
  }

  Widget _tile(TopupPurpose option) {
    final selected = _selected?.productCode == option.productCode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => setState(() => _selected = option),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? LoanRegisterStyles.primary
                  : LoanRegisterStyles.cardBorder,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 22,
                    color: selected
                        ? LoanRegisterStyles.primary
                        : LoanRegisterStyles.label,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.productName,
                          style: GoogleFonts.notoSansThai(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: LoanRegisterStyles.value,
                          ),
                        ),
                        if (option.productDescription.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            option.productDescription,
                            style: GoogleFonts.notoSansThai(
                              fontSize: 12,
                              color: LoanRegisterStyles.label,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${formatWholeMoney(option.productPrice)} บาท',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: LoanRegisterStyles.primary,
                    ),
                  ),
                ],
              ),
              if (selected && option.isOther) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _note,
                  style: GoogleFonts.notoSansThai(fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'ระบุ...',
                    hintStyle: GoogleFonts.notoSansThai(
                      fontSize: 14,
                      color: LoanRegisterStyles.label,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
