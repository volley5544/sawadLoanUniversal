import 'package:flutter/material.dart';
// Also the source of Uint8List here, so dart:typed_data is not imported.
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../loan_register/components/loan_register_styles.dart';
import '../p_loan/application/components/p_loan_components.dart';
import '../p_loan/application/models/loan_documents.dart';
import '../p_loan/application/pdf_view.dart';
import '../router/app_router.dart';
import '../services/device_location.dart';
import '../services/diagnostics.dart';
import '../services/native_bridge.dart';
import '../services/srisawad_api.dart';
import '../services/topup_api.dart';
import 'components/topup_components.dart';
import 'models/topup_flow.dart';
import 'models/topup_photo.dart';
import 'models/topup_submission.dart';

/// **Step 7 — สรุปรายละเอียดสินเชื่อ.** The last screen: the figures, the three
/// contract PDFs to read and accept, the identity photos, the two PDPA
/// questions, and the submit.
///
/// Four things happen here that happen nowhere else in the flow:
///
///  - **`POST /pdf/loan`** generates the documents, on entry. They are also
///    echoed back inside the submit body as `save_pdf`, so the request that
///    made them and the request that files them must agree — which is why both
///    read [TopupFlow.pdfRequest].
///  - **Device GPS** is captured, **un-awaited**. The customer spends minutes
///    on this screen, so a fix that takes seconds is long in place before
///    ยืนยัน; awaiting it at submit would put a permission prompt and a cold GPS
///    lock in front of the one button that matters. A denial or timeout is
///    silent by design — the fields stay empty and the request still files.
///  - **The ID card is read by `/vision/thai-id-validate`** and matched against
///    the customer's own record.
///  - **The two PDPA answers are real.** The source hardcoded both to `'Y'` in
///    the submit body; here ยินยอมข้อมูลอ่อนไหว gates the submit and
///    ยินยอมการตลาด is a genuine opt-in that gates nothing.
class TopupConclusionPage extends StatefulWidget {
  const TopupConclusionPage({super.key, required this.flow});

  final TopupFlow flow;

  @override
  State<TopupConclusionPage> createState() => _TopupConclusionPageState();
}

class _TopupConclusionPageState extends State<TopupConclusionPage> {
  final ImagePicker _picker = ImagePicker();

  bool _loading = true;
  bool _busy = false;
  bool _submitting = false;
  String? _error;

  TopupFlow get _flow => widget.flow;

  @override
  void initState() {
    super.initState();
    // Deliberately un-awaited — see the class doc.
    _captureLocation();
    _generateDocuments();
  }

  Future<void> _captureLocation() async {
    final position = await DeviceLocation.current();
    if (position == null) return;
    _flow.latitude = position.latitudeString;
    _flow.longitude = position.longitudeString;
  }

  Future<void> _generateDocuments() async {
    final request = _flow.pdfRequest;
    if (request == null) {
      setState(() {
        _loading = false;
        _error = 'ข้อมูลคำขอไม่ครบถ้วน กรุณาย้อนกลับและทำรายการใหม่';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final docs = await TopupApi.generateDocuments(
        request: request,
        hashThaiId: _flow.hashThaiId,
        token: _flow.authToken,
      );
      if (!mounted) return;
      setState(() {
        _flow.documents = docs;
        _loading = false;
      });
    } on SrisawadApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  /// One capture. Inside the host this is the native camera through the
  /// `openCamera` JS handler; in a plain browser `image_picker` stands in.
  Future<Uint8List?> _capture(TopupPhoto slot) async {
    if (NativeCameraBridge.isSupported) {
      return NativeCameraBridge.captureDocument(slot.cameraAction);
    }
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      imageQuality: 50,
    );
    return file == null ? null : await file.readAsBytes();
  }

  /// Captures the ID card and verifies it against the customer's profile.
  ///
  /// The source additionally accepted four hardcoded Thai IDs here, which let
  /// anyone holding one of those cards pass identity verification for **any**
  /// account. That backdoor is deliberately not reproduced.
  Future<void> _captureIdCard() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capture(TopupPhoto.idCard);
      if (!mounted || bytes == null || bytes.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final result = await TopupApi.validateThaiIdCard(
        imageBytes: bytes,
        token: _flow.authToken,
      );
      if (!mounted) return;

      _flow.verifiedThaiId = result.thaiId;
      if (!_flow.isThaiIdVerified) {
        setState(() => _busy = false);
        _snack('เลขบัตรไม่ตรงกับฐานข้อมูลโปรดลองอีกครั้ง');
        return;
      }
      if (!result.expiryWaived && _isExpired(result.latestDate)) {
        setState(() => _busy = false);
        _snack('บัตรประชาชนหมดอายุ กรุณาติดต่อสาขา');
        return;
      }
      setState(() {
        _flow.photos[TopupPhoto.idCard] = bytes;
        _busy = false;
      });
    } on SrisawadApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('ไม่สามารถถ่ายรูปได้: $e');
    }
  }

  /// Selfie with the card — captured but not OCR-checked, matching the source.
  Future<void> _captureSelfie() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capture(TopupPhoto.selfieWithIdCard);
      if (!mounted) return;
      setState(() {
        if (bytes != null && bytes.isNotEmpty) {
          _flow.photos[TopupPhoto.selfieWithIdCard] = bytes;
        }
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('ไม่สามารถถ่ายรูปได้: $e');
    }
  }

  /// Card expiry against the **server's** clock, which rides on the contract
  /// (`payment_details.current_date_time`), so a wrong device clock cannot pass
  /// an expired card. Falls back to device time only when the server sent none.
  bool _isExpired(String expiryDate) {
    final expiry = DateTime.tryParse(expiryDate);
    if (expiry == null) return false; // unparseable -> let the server decide
    final serverNow =
        DateTime.tryParse(_flow.contract?.paymentDetails.currentDateTime ?? '');
    return expiry.isBefore(serverNow ?? DateTime.now());
  }

  /// Opens a document, then asks for consent to it.
  Future<void> _reviewDocument(LoanDocumentKind kind) async {
    final docs = _flow.documents;
    if (docs == null) return;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ConsentSheet(
        kind: kind,
        base64Pdf: kind.base64From(docs),
        alreadyAccepted: _flow.consentedDocuments.contains(kind),
      ),
    );
    if (accepted == true && mounted) {
      setState(() => _flow.consentedDocuments.add(kind));
    }
  }

  Future<void> _submit() async {
    final blocked = _flow.submitBlockedReason;
    if (blocked != null) {
      _snack(blocked);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _BorrowerWarrantyDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    final submission = TopupSubmission.fromFlow(_flow);
    try {
      final transNo = await TopupApi.submit(
        payload: submission.fields,
        token: _flow.authToken,
      );
      if (!mounted) return;
      _flow.transNo = transNo;
      setState(() => _submitting = false);
      context.go(
        Uri(
          path: AppRoutes.topupSuccess,
          queryParameters: {'kind': 'topup', 'transNo': transNo},
        ).toString(),
        extra: _flow,
      );
    } on SrisawadApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      // Naming the blank fields turns an unactionable "HTTP 400" against 37
      // fields into something a tester can match to a cause.
      final blanks = submission.unresolvedFields;
      Diagnostics.log('topup submit failed: ${e.message}'
          '${blanks.isEmpty ? '' : ' blank=${blanks.join(',')}'}');
      _snack(blanks.isEmpty
          ? e.message
          : '${e.message}\n(ข้อมูลที่ยังว่าง: ${blanks.join(', ')})');
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: topupAppBar(context, 'สรุปรายละเอียดสินเชื่อ'),
      body: Column(
        children: [
          const PLoanMockBanner(),
          const TopupStepIndicator(6),
          Expanded(child: _body()),
        ],
      ),
      bottomNavigationBar: _loading || _error != null ? null : _bottomBar(),
    );
  }

  Widget _body() {
    final error = _error;
    if (error != null) {
      return PLoanErrorView(message: error, onRetry: _generateDocuments);
    }
    if (_loading) {
      return const PLoanLoadingView(message: 'กำลังสร้างเอกสารสัญญา...');
    }

    final flow = _flow;
    final contract = flow.contract!;
    final detail = flow.amountDetail!;
    final installment = flow.installment!;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          LoanRegisterStyles.padding, 4, LoanRegisterStyles.padding, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ContractSummaryCard(
            loanTypeCode: contract.contractDetails.loanTypeCode,
            loanTypeName: contract.contractDetails.loanTypeName,
            contractNo: contract.contractNo,
            collateralInformation:
                contract.contractDetails.collateralInformation,
          ),
          // ── สรุปยอดสินเชื่อใหม่ ─────────────────────────────────────
          // The before/after picture: what the contract was approved for,
          // what is being asked for now, and the two deductions. The customer
          // has already seen these on step 3; repeating them here is the last
          // chance to notice a wrong figure before filing.
          const PLoanSectionHeader('สรุปยอดสินเชื่อใหม่'),
          PLoanAmountRow(
            label: 'ยอดจัดสินเชื่อเดิม',
            value: '${formatMoney(detail.defaultTopupAmount)} บาท',
          ),
          PLoanAmountRow(
            label: 'รวมยอดวงเงินที่อนุมัติ',
            value: '${formatMoney(detail.maxTopupAmount)} บาท',
          ),
          PLoanAmountRow(
            label: 'วงเงินที่ต้องการกู้ใหม่',
            value: '${formatMoney(flow.calculatedAmount)} บาท',
          ),
          PLoanAmountRow(
            label: 'หักยอดเงินต้นสัญญาเก่า',
            caption: 'เลขที่สัญญา ${contract.contractNo}',
            value: '${formatMoney(flow.closingBalance)} บาท',
          ),
          PLoanAmountRow(
            label: 'หักอากรสแตมป์',
            caption: 'เลขที่สัญญา ${contract.contractNo}',
            value: '${formatMoney(flow.feeAmount)} บาท',
          ),
          PLoanAmountRow(
            label: 'จำนวนเงินที่จะได้รับ',
            value: '${formatMoney(flow.receivableAmount)} บาท',
            emphasis: true,
            large: true,
          ),
          const PLoanSectionHeader('รายละเอียดคำขอสินเชื่อใหม่'),
          PLoanAmountRow(
            label: 'ยอดจัดสินเชื่อ',
            value: '${formatMoney(flow.calculatedAmount)} บาท',
          ),
          PLoanAmountRow(
            label: 'ค่างวด',
            value: '${formatMoney(installment.regularPeriodAmt)} บาท',
          ),
          PLoanAmountRow(label: 'จำนวนงวด', value: '${installment.tenor} งวด'),
          PLoanAmountRow(
            label: 'ดอกเบี้ย (ต่อเดือน)',
            value: '${detail.interestRate}%',
          ),
          PLoanAmountRow(
            label: 'ชำระทุกวันที่',
            value: detail.dueDay > 0 ? '${detail.dueDay}' : '-',
            showDivider: false,
          ),
          const PLoanSectionHeader('ข้อมูลบัญชีรับเงิน'),
          BankAccountCard(
            bankCode: flow.bankCode,
            accountNo: flow.bankAccountNo,
            logoBytes: decodeBase64Image(flow.bankLogoBase64),
          ),
          const PLoanSectionHeader('เอกสารประกอบสัญญา'),
          Text(
            'กรุณาอ่านและยอมรับเอกสารทั้งหมดก่อนส่งคำขอ',
            style: GoogleFonts.notoSansThai(
                fontSize: 13, color: LoanRegisterStyles.label),
          ),
          const SizedBox(height: 10),
          for (final kind in LoanDocumentKind.values)
            _DocumentRow(
              kind: kind,
              accepted: flow.consentedDocuments.contains(kind),
              onTap: () => _reviewDocument(kind),
            ),
          const PLoanSectionHeader('ยืนยันตัวตน'),
          _IdentitySlot(
            slot: TopupPhoto.idCard,
            bytes: flow.photos[TopupPhoto.idCard],
            busy: _busy,
            onCapture: _captureIdCard,
            onRemove: () => setState(() {
              flow.photos.remove(TopupPhoto.idCard);
              // The verified id came off that photo; dropping one must drop the
              // other, or the flow would still claim a verified identity with
              // no card behind it.
              flow.verifiedThaiId = '';
            }),
          ),
          _IdentitySlot(
            slot: TopupPhoto.selfieWithIdCard,
            bytes: flow.photos[TopupPhoto.selfieWithIdCard],
            busy: _busy,
            onCapture: _captureSelfie,
            onRemove: () =>
                setState(() => flow.photos.remove(TopupPhoto.selfieWithIdCard)),
          ),
          const PLoanSectionHeader('ความยินยอม'),
          TopupConsentCheckbox(
            value: flow.sensitiveConsent,
            required: true,
            onChanged: (v) => setState(() => flow.sensitiveConsent = v),
            label: 'ข้าพเจ้ายินยอมให้บริษัทเก็บรวบรวม ใช้ และเปิดเผย'
                'ข้อมูลส่วนบุคคลที่มีความอ่อนไหวเพื่อประกอบการพิจารณาสินเชื่อ',
          ),
          TopupConsentCheckbox(
            value: flow.marketingConsent,
            onChanged: (v) => setState(() => flow.marketingConsent = v),
            label: 'ข้าพเจ้ายินยอมให้บริษัทใช้ข้อมูลส่วนบุคคล'
                'เพื่อการติดต่อนำเสนอผลิตภัณฑ์และบริการ',
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final blocked = _flow.submitBlockedReason;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (blocked != null)
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
            child: Text(
              blocked,
              style: GoogleFonts.notoSansThai(
                fontSize: 12.5,
                color: LoanRegisterStyles.required,
              ),
            ),
          ),
        PLoanBottomButton(
          label: 'ยืนยันส่งคำขอ',
          busy: _submitting,
          onPressed: _flow.canSubmit ? _submit : null,
        ),
      ],
    );
  }
}

/// One identity photo: capture, preview, clear.
class _IdentitySlot extends StatelessWidget {
  const _IdentitySlot({
    required this.slot,
    required this.bytes,
    required this.busy,
    required this.onCapture,
    required this.onRemove,
  });

  final TopupPhoto slot;
  final Uint8List? bytes;
  final bool busy;
  final VoidCallback onCapture;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final image = bytes;
    final captured = image != null && image.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            slot.label,
            style: GoogleFonts.notoSansThai(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: LoanRegisterStyles.required,
            ),
          ),
          const SizedBox(height: 10),
          if (!captured)
            SizedBox(
              height: 56,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onCapture,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt_outlined, size: 20),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8F3FB),
                  foregroundColor: const Color(0xFF1D71B8),
                  side: const BorderSide(color: Color(0xFF1D71B8)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                label: Text(
                  'ถ่ายรูปภาพ',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(image,
                      width: double.infinity, height: 200, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: InkWell(
                    onTap: onRemove,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0x98000000),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          size: 20, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// One contract-document row; shows a green check once accepted.
class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.kind,
    required this.accepted,
    required this.onTap,
  });

  final LoanDocumentKind kind;
  final bool accepted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: LoanRegisterStyles.cardBorder),
          ),
          child: Row(
            children: [
              SvgPicture.asset('assets/p_loan/document-icon.svg',
                  width: 28, height: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  kind.title,
                  style: GoogleFonts.notoSansThai(
                    fontSize: 14,
                    color: LoanRegisterStyles.value,
                  ),
                ),
              ),
              if (accepted) ...[
                const Icon(Icons.check_circle,
                    size: 20, color: Color(0xFF249689)),
                const SizedBox(width: 4),
                Text(
                  'ยอมรับแล้ว',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF249689),
                  ),
                ),
              ],
              Icon(Icons.navigate_next,
                  size: 24, color: LoanRegisterStyles.label),
            ],
          ),
        ),
      ),
    );
  }
}

/// Document review + consent sheet. Pops true when accepted.
///
/// The PDF renders inline through `pdfx` (pdf.js), not the embedder's own
/// viewer: Android System WebView ships no PDF renderer at all, so an
/// `<iframe>` on a blob URL came up blank there. See `pdf_view.dart`.
class _ConsentSheet extends StatefulWidget {
  const _ConsentSheet({
    required this.kind,
    required this.base64Pdf,
    required this.alreadyAccepted,
  });

  final LoanDocumentKind kind;
  final String base64Pdf;
  final bool alreadyAccepted;

  @override
  State<_ConsentSheet> createState() => _ConsentSheetState();
}

class _ConsentSheetState extends State<_ConsentSheet> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _checked = widget.alreadyAccepted;
  }

  @override
  Widget build(BuildContext context) {
    // Nearly full height: the document is the point of this sheet, so it gets
    // the space rather than sitting behind a button.
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.kind.title,
                      style: LoanRegisterStyles.appBarTitleStyle()
                          .copyWith(fontSize: 18)),
                ),
                IconButton(
                  tooltip: 'ปิด',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: LoanRegisterStyles.label),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: LoanRegisterStyles.cardBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: PdfInlineView(
                  base64Pdf: widget.base64Pdf,
                  viewId: 'topup-${widget.kind.name}',
                ),
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _checked,
              onChanged: (v) => setState(() => _checked = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: LoanRegisterStyles.primary,
              title: Text(
                'ข้าพเจ้าได้อ่านและยอมรับ${widget.kind.title}',
                style: GoogleFonts.notoSansThai(
                  fontSize: 14,
                  color: LoanRegisterStyles.value,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    _checked ? () => Navigator.of(context).pop(true) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: LoanRegisterStyles.primary,
                  disabledBackgroundColor:
                      LoanRegisterStyles.primary.withValues(alpha: 0.5),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'ยอมรับ',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The borrower's warranty, accepted immediately before the request is sent.
class _BorrowerWarrantyDialog extends StatelessWidget {
  const _BorrowerWarrantyDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text('ยืนยันการส่งคำขอ',
          style: LoanRegisterStyles.appBarTitleStyle().copyWith(fontSize: 18)),
      content: Text(
        'ข้าพเจ้าขอรับรองว่าข้อมูลและเอกสารทั้งหมดที่ให้ไว้เป็นความจริงทุกประการ '
        'และยินยอมให้บริษัทตรวจสอบข้อมูลเพื่อประกอบการพิจารณาสินเชื่อ',
        style: GoogleFonts.notoSansThai(
          fontSize: 14,
          height: 1.5,
          color: LoanRegisterStyles.value,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('ยกเลิก',
              style: GoogleFonts.notoSansThai(
                  color: LoanRegisterStyles.label)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: LoanRegisterStyles.primary,
            elevation: 0,
          ),
          child: Text('ยืนยัน',
              style: GoogleFonts.notoSansThai(color: Colors.white)),
        ),
      ],
    );
  }
}
