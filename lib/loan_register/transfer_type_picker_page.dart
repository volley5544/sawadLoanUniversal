import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'components/loan_register_styles.dart';

/// Full-screen selector for ประเภทการโอน (transfer type) — screen #5 on
/// slide 7. Pops with the selected [String] when ตกลง is tapped.
class TransferTypePickerPage extends StatefulWidget {
  const TransferTypePickerPage({
    Key? key,
    required this.selected,
    this.options = const [
      'บัญชีลูกค้า',
      'บัตรกดเงินสด',
      'เบอร์มือถือพร้อมเพย์',
      'บัตรประจำตัวประชาชนพร้อมเพย์',
    ],
  }) : super(key: key);

  final String selected;
  final List<String> options;

  @override
  State<TransferTypePickerPage> createState() => _TransferTypePickerPageState();
}

class _TransferTypePickerPageState extends State<TransferTypePickerPage> {
  late String _selected = widget.selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: LoanRegisterStyles.primary),
        centerTitle: true,
        title: Text('ประเภทการโอน', style: LoanRegisterStyles.appBarTitleStyle()),
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
                    value,
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
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(_selected),
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
            ),
          ),
        ],
      ),
    );
  }
}
