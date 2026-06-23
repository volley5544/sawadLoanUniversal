import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../router/app_router.dart';
import 'components/loan_register_styles.dart';
import 'components/register_field_row.dart';
import 'components/register_step_indicator.dart';
import 'components/save_next_bar.dart';
import 'models/loan_register_form.dart';
import 'ocr_capture_page.dart';

/// Step 4 of the loan-register wizard — เอกสารแนบ (Document Attachments).
/// First screen on slide 8 ("ขั้นตอนที่ 3 ยืนยันตัวตนผ่าน NDID") and on slide 9.
///
/// The customer attaches the required documents (บัตรประชาชน, เล่มทะเบียนรถ,
/// extra docs), then reviews + signs the contract documents and verifies their
/// identity through NDID via [DocumentReviewPage]. Once verified the
/// เอกสารประกอบสัญญา card flips to its signed state (green check +
/// ดาวน์โหลดเอกสาร) and the bottom ถัดไป proceeds to step 5.
class DocumentAttachPage extends StatefulWidget {
  const DocumentAttachPage({Key? key, this.form}) : super(key: key);

  final LoanRegisterForm? form;

  @override
  State<DocumentAttachPage> createState() => _DocumentAttachPageState();
}

class _DocumentAttachPageState extends State<DocumentAttachPage> {
  late final LoanRegisterForm _form = widget.form ?? LoanRegisterForm.mock();

  /// Captured bytes per attachment slot (UI-only — not persisted).
  Uint8List? _idCardBytes;
  Uint8List? _vehicleRegBytes;
  Uint8List? _extraBytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: LoanRegisterStyles.primary),
        centerTitle: true,
        title:
            Text('4. เอกสารแนบ', style: LoanRegisterStyles.appBarTitleStyle()),
      ),
      body: Column(
        children: [
          const RegisterStepIndicator(currentStep: 4),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  horizontal: LoanRegisterStyles.padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const RegisterSectionTitle('เอกสารแนบ'),
                  const SizedBox(height: 8),
                  _AttachDocCard(
                    title: 'บัตรประชาชน',
                    bytes: _idCardBytes,
                    onAttach: () => _attach((b) => _idCardBytes = b),
                    onDelete: () => setState(() => _idCardBytes = null),
                    onView: () => _viewDocument(_idCardBytes!),
                  ),
                  const SizedBox(height: 12),
                  _AttachDocCard(
                    title: 'เล่มทะเบียนรถ',
                    bytes: _vehicleRegBytes,
                    onAttach: () => _attach((b) => _vehicleRegBytes = b),
                    onDelete: () => setState(() => _vehicleRegBytes = null),
                    onView: () => _viewDocument(_vehicleRegBytes!),
                  ),

                  // ── เพิ่มเติมเอกสาร ───────────────────────────────
                  const RegisterSectionTitle('เพิ่มเติมเอกสาร'),
                  const SizedBox(height: 8),
                  _AttachDocCard(
                    title: 'เอกสารเพิ่มเติม',
                    bytes: _extraBytes,
                    onAttach: () => _attach((b) => _extraBytes = b),
                    onDelete: () => setState(() => _extraBytes = null),
                    onView: () => _viewDocument(_extraBytes!),
                  ),

                  // ── เอกสารประกอบสัญญา ─────────────────────────────
                  const RegisterSectionTitle('เอกสารประกอบสัญญา'),
                  RegisterFieldRow(
                    label: 'ตรวจสอบเอกสาร',
                    value: _form.ndidVerified ? 'ตรวจสอบแล้ว' : '',
                    placeholder: 'กรุณาตรวจสอบและลงนามเอกสาร',
                    trailing: _form.ndidVerified
                        ? const Icon(Icons.check_circle,
                            color: Colors.green, size: 22)
                        : null,
                    showDivider: false,
                    onTap: _reviewDocuments,
                  ),
                  if (_form.ndidVerified) ...[
                    const SizedBox(height: 8),
                    _verifiedBanner(),
                    const SizedBox(height: 12),
                    _downloadButton(),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          SaveNextBar(
            onSaveDraft: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('บันทึกข้อมูลร่างแล้ว')),
            ),
            onNext: _onNext,
          ),
        ],
      ),
    );
  }

  /// Green "signed & verified" banner shown after the NDID flow completes.
  Widget _verifiedBanner() {
    return Row(
      children: [
        const Icon(Icons.check_circle, size: 18, color: Colors.green),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'ลงนามเอกสารและยืนยันตัวตนด้วย NDID สำเร็จ',
            style: GoogleFonts.notoSansThai(
              fontSize: 13,
              color: Colors.green,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _downloadButton() {
    return InkWell(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ดาวน์โหลดเอกสาร')),
      ),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: LoanRegisterStyles.primarySoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: LoanRegisterStyles.primary),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_outlined,
                size: 20, color: LoanRegisterStyles.primary),
            const SizedBox(width: 8),
            Text(
              'ดาวน์โหลดเอกสาร',
              style: GoogleFonts.notoSansThai(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: LoanRegisterStyles.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Open the in-app camera and store the captured bytes in the given slot.
  Future<void> _attach(ValueChanged<Uint8List> assign) async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const OcrCapturePage()),
    );
    if (!mounted || bytes == null) return;
    setState(() => assign(bytes));
  }

  /// Open the contract-document review + NDID sign flow; flip to the verified
  /// state when it reports success.
  Future<void> _reviewDocuments() async {
    final ok = await context.push<bool>(
      AppRoutes.documentReview,
      extra: _form,
    );
    if (ok == true && mounted) {
      setState(() => _form.ndidVerified = true);
    }
  }

  void _onNext() {
    if (!_form.ndidVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาตรวจสอบและลงนามเอกสารก่อน')),
      );
      return;
    }
    context.push(AppRoutes.appointment, extra: _form);
  }

  /// Full-screen, zoomable preview of an attached document.
  void _viewDocument(Uint8List bytes) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              maxScale: 4,
              child: Center(child: Image.memory(bytes)),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single document-attachment card: shows an "แนบเอกสาร" button when empty,
/// or the attached state (status, ดูเอกสาร, delete) once a photo is captured.
class _AttachDocCard extends StatelessWidget {
  const _AttachDocCard({
    required this.title,
    required this.bytes,
    required this.onAttach,
    required this.onDelete,
    required this.onView,
  });

  final String title;
  final Uint8List? bytes;
  final VoidCallback onAttach;
  final VoidCallback onDelete;
  final VoidCallback onView;

  bool get _attached => bytes != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LoanRegisterStyles.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.notoSansThai(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: LoanRegisterStyles.value,
                  ),
                ),
              ),
              if (_attached)
                Row(
                  children: [
                    const Icon(Icons.check_circle, size: 16, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      'แนบเอกสารแล้ว',
                      style: GoogleFonts.notoSansThai(
                          fontSize: 12, color: Colors.green),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_attached)
            Row(
              children: [
                Expanded(
                  child: _CardButton(
                    icon: Icons.visibility_outlined,
                    label: 'ดูเอกสาร',
                    color: LoanRegisterStyles.primary,
                    onTap: onView,
                  ),
                ),
                const SizedBox(width: 10),
                _CardButton(
                  icon: Icons.delete_outline,
                  label: 'ลบ',
                  color: LoanRegisterStyles.required,
                  onTap: onDelete,
                ),
              ],
            )
          else
            _CardButton(
              icon: Icons.camera_alt_outlined,
              label: 'แนบเอกสาร',
              color: const Color(0xFF1D71B8),
              fill: const Color(0xFFD9EBFF),
              onTap: onAttach,
              expand: true,
            ),
        ],
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.fill,
    this.expand = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final Color? fill;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: fill ?? color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.notoSansThai(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
