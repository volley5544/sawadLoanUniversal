import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../router/app_router.dart';
import '../services/native_bridge.dart';
import 'components/loan_register_styles.dart';
import 'models/loan_register_form.dart';

/// เอกสารที่ต้องเตรียมวันนัดหมาย — the checklist of documents the customer must
/// bring on the appointment day (third frame on slide 9).
///
/// Reached from the "เพิ่ม สาขาและวันที่-เวลานัดหมาย" card on
/// [AppointmentPage]. ถัดไป continues to the branch picker — inside the native
/// host that's the **native map page** (`openBranchPicker` bridge handler:
/// GPS + nearby search live there); in a plain browser it falls back to the
/// web [BranchSelectPage] list — then the [AppointmentDateTimePage]. The
/// chosen `{branch, dateTime}` pops back to the appointment list.
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

  /// Branch picker → date/time picker → pop `{branch, dateTime}` back to the
  /// appointment list. Backing out of either picker stays on this checklist.
  Future<void> _next(BuildContext context) async {
    String? branchName;
    if (NativeCameraBridge.isSupported) {
      // Inside the native host: the branch is picked on the native map page.
      try {
        final branch = await NativeCameraBridge.pickBranch();
        branchName = branch?['branchName']?.toString();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ไม่สามารถเปิดหน้าค้นหาสาขาได้')),
          );
        }
        return;
      }
    } else {
      // Plain browser (dev): fall back to the web branch list.
      if (!context.mounted) return;
      final branch = await context
          .push<Map<String, dynamic>>(AppRoutes.branchSelect);
      branchName = branch?['branchName']?.toString();
    }
    if (branchName == null || branchName.isEmpty) return; // cancelled

    if (!context.mounted) return;
    final dateTime = await context.push<String>(
      AppRoutes.appointmentDateTime,
      extra: branchName,
    );
    if (dateTime == null || dateTime.isEmpty) return; // backed out

    if (!context.mounted) return;
    context.pop(<String, String>{
      'branch': 'สาขา$branchName',
      'dateTime': dateTime,
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
