/// The **uat** failure dialog for an API call: the customer message, then the
/// request that went out and the response that came back, with a คัดลอก
/// button — the same shape as the top-up submit's (`topup_conclusion_page`).
///
/// ⚠ **Non-prod only.** On prod [showApiFailureDialog] does nothing and the
/// screen keeps showing only its message, as before: the report can carry the
/// customer's data and a gateway stack trace. Used by every บัตรศรีสวัสดิ์
/// call (2026-11-12).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_environment.dart';
import '../loan_register/components/loan_register_styles.dart';
import '../services/srisawad_api.dart';

/// Whether [e] has a report a uat dialog can show.
bool apiFailureHasReport(SrisawadApiException e) =>
    !AppEnvironment.current.isProd && (e.details ?? '').isNotEmpty;

/// Shows the report for [e] on non-prod builds; a no-op on prod or when the
/// failure carries no report.
Future<void> showApiFailureDialog(
  BuildContext context,
  SrisawadApiException e, {
  String title = 'เรียก API ไม่สำเร็จ',
}) async {
  if (!apiFailureHasReport(e)) return;
  final details = e.details!;
  // The message goes on the clipboard too, so a pasted body keeps its context.
  final copyText = '${e.message}\n\n$details';
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        title,
        style: LoanRegisterStyles.appBarTitleStyle().copyWith(fontSize: 16),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              e.message,
              style: GoogleFonts.notoSansThai(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(
              'คำขอที่ส่งและคำตอบจากเซิร์ฟเวอร์ (สำหรับผู้พัฒนา)',
              style: GoogleFonts.notoSansThai(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: LoanRegisterStyles.primary,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              details,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: copyText));
            if (!dialogContext.mounted) return;
            ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(content: Text('คัดลอกข้อผิดพลาดแล้ว')));
          },
          child: Text('คัดลอก', style: GoogleFonts.notoSansThai()),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('ปิด'),
        ),
      ],
    ),
  );
}
