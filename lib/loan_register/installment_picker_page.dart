import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'components/loan_register_styles.dart';

/// Full-screen selector for จำนวนงวด (number of installments) — screen #4 on
/// slide 7. Pops with the selected [int] when ตกลง is tapped.
class InstallmentPickerPage extends StatefulWidget {
  const InstallmentPickerPage({
    Key? key,
    required this.selected,
    this.options = const [3, 6, 9, 10, 12, 15, 18, 21, 24, 27, 30, 33, 36],
  }) : super(key: key);

  final int selected;
  final List<int> options;

  @override
  State<InstallmentPickerPage> createState() => _InstallmentPickerPageState();
}

class _InstallmentPickerPageState extends State<InstallmentPickerPage> {
  late int _selected = widget.selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: LoanRegisterStyles.primary),
        centerTitle: true,
        title: Text('จำนวนงวด', style: LoanRegisterStyles.appBarTitleStyle()),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              itemCount: widget.options.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: LoanRegisterStyles.divider),
              itemBuilder: (context, index) {
                final value = widget.options[index];
                final isSelected = value == _selected;
                return ListTile(
                  onTap: () => setState(() => _selected = value),
                  title: Text(
                    '$value',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 16,
                      color: LoanRegisterStyles.value,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check, color: LoanRegisterStyles.value)
                      : null,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                LoanRegisterStyles.padding, 8, LoanRegisterStyles.padding, 8),
            child: _ConfirmButton(onTap: () => context.pop(_selected)),
          ),
        ],
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: LoanRegisterStyles.primary,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'ตกลง',
          style: GoogleFonts.notoSansThai(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
