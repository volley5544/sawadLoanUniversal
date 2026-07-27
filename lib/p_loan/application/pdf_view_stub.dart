import 'package:flutter/material.dart';

/// Off-web stub — the app ships as Flutter web, but this keeps the VM /
/// mobile / desktop targets compiling so `flutter test` runs.

/// False off-web; callers fall back to the "open externally" action.
bool get canEmbedPdf => false;

/// Placeholder shown off-web, where there is no browser PDF renderer.
class PdfInlineView extends StatelessWidget {
  const PdfInlineView({
    super.key,
    required this.base64Pdf,
    required this.viewId,
  });

  final String base64Pdf;
  final String viewId;

  @override
  Widget build(BuildContext context) => const Center(
        child: Text(
          'แสดงเอกสารได้เฉพาะบนเว็บ',
          style: TextStyle(fontSize: 13),
        ),
      );
}
