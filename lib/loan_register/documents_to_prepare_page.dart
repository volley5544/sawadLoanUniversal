import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'components/loan_register_styles.dart';
import 'models/loan_register_form.dart';

/// เอกสารที่ต้องเตรียมวันนัดหมาย — the checklist of documents the customer must
/// bring on the appointment day (third frame on slide 9).
///
/// Reached from the "เพิ่ม สาขาและวันที่-เวลานัดหมาย" card on
/// [AppointmentPage]. ถัดไป continues to the branch (map) + date/time pickers —
/// those screens (slide 9, right frames) are out of scope here, so this returns
/// a representative appointment back to the appointment list.
class DocumentsToPreparePage extends StatelessWidget {
  const DocumentsToPreparePage({Key? key, this.form}) : super(key: key);

  final LoanRegisterForm? form;

  /// Documents required on the appointment day (UI-only, MC loan).
  static const List<_PrepDoc> _documents = [
    _PrepDoc(Icons.badge_outlined, 'บัตรประชาชน (ตัวจริง)'),
    _PrepDoc(Icons.menu_book_outlined, 'เล่มทะเบียนรถ'),
    _PrepDoc(Icons.two_wheeler_outlined, 'รถมอเตอร์ไซต์ที่ขอสินเชื่อ'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: LoanRegisterStyles.primary),
        centerTitle: true,
        title: Text('เอกสารที่ต้องเตรียมวันนัดหมาย',
            style: LoanRegisterStyles.appBarTitleStyle().copyWith(fontSize: 15)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                  horizontal: LoanRegisterStyles.padding, vertical: 12),
              children: [
                Text('รายการเอกสาร', style: LoanRegisterStyles.labelStyle()),
                const SizedBox(height: 8),
                for (final doc in _documents) _docRow(doc),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(LoanRegisterStyles.padding, 4,
                  LoanRegisterStyles.padding, 12),
              child: _NextButton(onTap: () => _next(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _docRow(_PrepDoc doc) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border:
            Border(bottom: BorderSide(color: LoanRegisterStyles.divider)),
      ),
      child: Row(
        children: [
          Icon(doc.icon, size: 22, color: LoanRegisterStyles.value),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              doc.label,
              style: GoogleFonts.notoSansThai(
                fontSize: 15,
                color: LoanRegisterStyles.value,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Returns a representative appointment to the list. The branch (map) and
  /// date/time pickers (slide 9 right frames) are out of scope.
  void _next(BuildContext context) {
    context.pop(<String, String>{
      'branch': 'สาขาสุขุมวิท 101/1',
      'dateTime': '25/04/2569 10:00 น.',
    });
  }
}

class _PrepDoc {
  const _PrepDoc(this.icon, this.label);
  final IconData icon;
  final String label;
}

class _NextButton extends StatelessWidget {
  const _NextButton({required this.onTap});
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
          'ถัดไป',
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
