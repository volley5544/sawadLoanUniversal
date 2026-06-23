import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../router/app_router.dart';
import 'components/loan_register_styles.dart';
import 'models/loan_register_form.dart';

/// ตรวจสอบเอกสาร — contract-document review (screen #2 on slide 8).
///
/// Lists the contract documents to review, requires the customer to
/// acknowledge them, then starts the "ลงนามเอกสารและยืนยันตัวตน NDID" flow
/// ([NdidBankSelectPage] → [NdidVerifyPage]). Pops `true` back to the
/// [DocumentAttachPage] once identity verification succeeds.
class DocumentReviewPage extends StatefulWidget {
  const DocumentReviewPage({Key? key, this.form}) : super(key: key);

  final LoanRegisterForm? form;

  @override
  State<DocumentReviewPage> createState() => _DocumentReviewPageState();
}

class _DocumentReviewPageState extends State<DocumentReviewPage> {
  late final LoanRegisterForm _form = widget.form ?? LoanRegisterForm.mock();

  bool _acknowledged = false;

  /// Contract documents the customer must review (UI-only).
  static const List<String> _documents = [
    'ใบคำขอสินเชื่อ',
    'ใบรับเงิน',
    'เอกสารสัญญา',
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
        title:
            Text('ตรวจสอบเอกสาร', style: LoanRegisterStyles.appBarTitleStyle()),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                LoanRegisterStyles.padding, 12, LoanRegisterStyles.padding, 4),
            child: Row(
              children: [
                const Spacer(),
                Text(
                  '1 of ${_documents.length}',
                  style: LoanRegisterStyles.labelStyle(),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(
                  horizontal: LoanRegisterStyles.padding),
              itemCount: _documents.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: LoanRegisterStyles.divider),
              itemBuilder: (context, index) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Text(
                    '${index + 1}',
                    style: LoanRegisterStyles.valueStyle(),
                  ),
                  title: Text(
                    _documents[index],
                    style: LoanRegisterStyles.valueStyle()
                        .copyWith(fontWeight: FontWeight.w400),
                  ),
                  trailing: Icon(Icons.chevron_right,
                      color: LoanRegisterStyles.label),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('เปิดเอกสาร: ${_documents[index]}')),
                  ),
                );
              },
            ),
          ),
          _acknowledgeRow(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(LoanRegisterStyles.padding, 4,
                  LoanRegisterStyles.padding, 12),
              child: _SignButton(
                enabled: _acknowledged,
                onTap: _startNdid,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _acknowledgeRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: LoanRegisterStyles.padding, vertical: 8),
      child: InkWell(
        onTap: () => setState(() => _acknowledged = !_acknowledged),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _acknowledged
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: _acknowledged
                  ? LoanRegisterStyles.primary
                  : LoanRegisterStyles.label,
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'ฉันได้ตรวจสอบและรับทราบเอกสารทั้งหมดนี้แล้ว',
                style: GoogleFonts.notoSansThai(
                  fontSize: 13,
                  color: LoanRegisterStyles.value,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Start the NDID flow; if it returns success, propagate it back to the
  /// caller (step 4) so the contract-docs card flips to the verified state.
  Future<void> _startNdid() async {
    if (!_acknowledged) return;
    final ok = await context.push<bool>(
      AppRoutes.ndidBankSelect,
      extra: _form,
    );
    if (ok == true && mounted) context.pop(true);
  }
}

class _SignButton extends StatelessWidget {
  const _SignButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled
              ? LoanRegisterStyles.primary
              : LoanRegisterStyles.primary.withOpacity(0.4),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'ลงนามเอกสารและยืนยันตัวตน NDID',
          style: GoogleFonts.notoSansThai(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
