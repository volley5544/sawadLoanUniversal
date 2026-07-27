import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../loan_register/components/loan_register_styles.dart';
import '../../loan_register/components/register_field_row.dart';
import '../../loan_register/components/register_step_indicator.dart';
import '../../router/app_router.dart';
import '../../services/native_bridge.dart';
import '../../services/p_loan_api.dart';
import '../../services/srisawad_api.dart';
import 'components/p_loan_components.dart';
import 'models/loan_documents.dart';
import 'models/p_loan_submission.dart';
import 'models/p_loan_flow.dart';
import 'pdf_opener.dart';
import 'pdf_view.dart';

/// **Step 6 — สรุปรายละเอียดของสัญญา.** Contract summary, ID-card verification,
/// document consent, and the submit.
///
/// Two things differ from the source deliberately. Its submit was unreachable —
/// `if (!false) { Navigator.pop(context); return; }` sat directly above the
/// call — so this is the first version that actually posts. And its ID check
/// accepted four hardcoded Thai IDs alongside the customer's own, which let
/// anyone holding one of those cards verify against *any* account; only the
/// real match is accepted here.
class PLoanConclusionPage extends StatefulWidget {
  const PLoanConclusionPage({super.key, required this.flow});

  final PLoanFlow flow;

  @override
  State<PLoanConclusionPage> createState() => _PLoanConclusionPageState();
}

class _PLoanConclusionPageState extends State<PLoanConclusionPage> {
  final ImagePicker _picker = ImagePicker();

  bool _loading = true;
  bool _busy = false;
  bool _submitting = false;
  String? _error;

  PLoanFlow get _flow => widget.flow;

  @override
  void initState() {
    super.initState();
    _generateDocuments();
  }

  /// Builds the `save_pdf` block, which is both the `/pdf/loan` request body
  /// and a nested field of the submit payload — so it must be identical in
  /// both places.
  ContractPdfRequest? _pdfRequest() {
    final contract = _flow.contract;
    final detail = _flow.amountDetail;
    final installment = _flow.installment;
    if (contract == null || detail == null || installment == null) return null;
    return ContractPdfRequest(
      contractNo: detail.contractNo,
      dbName: detail.dbName,
      contractDate: detail.contractDate,
      amount: _flow.payoutAmount.toDouble(),
      from: contract.contractDetails.comcode,
      contractBankAccount: contract.contractBankAccount,
      contractBankBrandname: contract.contractBankBrandname,
      contractBankType: contract.contractBankType,
      contractBankBranch: '',
      interestRate: detail.interestRate,
      installmentNumber: installment.tenor.toDouble(),
      amountPerInstallment: installment.regularPeriodAmt.toDouble(),
      startInstallmentDate: _flow.plan?.firstDueDate ?? '',
      installmentDate: '',
      vehicleType: contract.contractDetails.loanTypeName,
    );
  }

  Future<void> _generateDocuments() async {
    final request = _pdfRequest();
    if (request == null) {
      setState(() {
        _loading = false;
        _error = 'ข้อมูลไม่ครบถ้วน กรุณาเริ่มรายการใหม่';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final docs = await PLoanApi.generateDocuments(
        request: request,
        hashThaiId: _flow.hashThaiId,
        token: _flow.authToken,
      );
      if (!mounted) return;
      _flow.documents = docs;
      setState(() => _loading = false);
    } on SrisawadApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<Uint8List?> _capture(PLoanPhoto slot) async {
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
  Future<void> _captureIdCard() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capture(PLoanPhoto.idCard);
      if (!mounted || bytes == null || bytes.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final result = await PLoanApi.validateThaiIdCard(
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
        _flow.photos[PLoanPhoto.idCard] = bytes;
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
      final bytes = await _capture(PLoanPhoto.selfieWithIdCard);
      if (!mounted) return;
      setState(() {
        if (bytes != null && bytes.isNotEmpty) {
          _flow.photos[PLoanPhoto.selfieWithIdCard] = bytes;
        }
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('ไม่สามารถถ่ายรูปได้: $e');
    }
  }

  /// Card expiry vs. the server's clock (the source compared against
  /// `payment_details.current_date_time` rather than the device time, so a
  /// wrong device clock can't pass an expired card).
  bool _isExpired(String expiryDate) {
    final expiry = DateTime.tryParse(expiryDate);
    if (expiry == null) return false; // unparseable -> let the server decide
    final serverNow =
        DateTime.tryParse(_flow.contract?.paymentDetails.currentDateTime ?? '');
    return expiry.isBefore(serverNow ?? DateTime.now());
  }

  /// Opens a document then asks for consent.
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
        alreadyAccepted: _flow.consented.contains(kind),
      ),
    );
    if (accepted == true) {
      setState(() => _flow.consented.add(kind));
    }
  }

  /// Opens the NDID sign + identity-verification flow, and flips to the
  /// verified state when it reports success.
  ///
  /// Goes straight to the IdP picker rather than through the wizard's
  /// `document_review_page`: that screen exists to show the contract documents
  /// before signing, and this page already does — with the real PDFs from
  /// `/pdf/loan` rather than the wizard's mock list. So the gate here is the
  /// document consents, which is the same read-then-sign order.
  Future<void> _signWithNdid() async {
    final missing = _flow.missingConsent;
    if (missing != null) {
      _snack(missing.consentPrompt);
      return;
    }
    final ok = await context.push<bool>(
      AppRoutes.ndidBankSelect,
      extra: _flow,
    );
    if (ok == true && mounted) {
      setState(() => _flow.ndidVerified = true);
    }
  }

  /// Green "signed & verified" banner, matching the wizard's step 4.
  Widget _ndidVerifiedBanner() {
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

  /// Opens the signed agreement in a new tab.
  ///
  /// The wizard's equivalent button is a stub SnackBar because that flow has no
  /// documents; here the real PDF is already in hand from `/pdf/loan`.
  Widget _downloadAgreementButton() {
    return InkWell(
      onTap: _openAgreement,
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

  void _openAgreement() {
    final base64Pdf = _flow.documents?.agreement ?? '';
    if (!canOpenPdf || !openBase64Pdf(base64Pdf, fileName: 'agreement.pdf')) {
      _snack('ไม่สามารถเปิดเอกสารได้');
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final request = _pdfRequest();
    if (request == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _BorrowerWarrantyDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      // Two products, two endpoints. An Extra is a top-up of the contract it
      // was raised against; a new P-Loan is filed with the P-Loan save API,
      // which is why toSubmissionJson() refuses to build a /topup body for it.
      final transNo = switch (_flow.submitTarget) {
        PLoanSubmitTarget.pLoanSaveApi => await PLoanApi.saveNewLoan(
            submission: PLoanContractSubmission.fromFlow(_flow),
          ),
        PLoanSubmitTarget.topup => await PLoanApi.submit(
            payload: _flow.toSubmissionJson(),
            pdfRequest: request,
            token: _flow.authToken,
          ),
      };
      if (!mounted) return;
      // Carry it on the flow too — the P-Loan payload has a transNo field.
      _flow.transNo = transNo;
      setState(() => _submitting = false);
      context.push(AppRoutes.pLoanSuccess, extra: (_flow, transNo));
    } on SrisawadApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showSubmitError(e.message);
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showSubmitError(e.message);
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  /// A failed submit gets a dialog, not a SnackBar.
  ///
  /// These messages carry the server's own wording plus, on a refusal, the
  /// fields that went out blank — and a transport failure names the bridge
  /// handler that would fix it. All of that is too long for a strip that
  /// truncates and then disappears.
  void _showSubmitError(String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'ส่งคำขอไม่สำเร็จ',
          style: LoanRegisterStyles.appBarTitleStyle().copyWith(fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            message,
            style: GoogleFonts.notoSansThai(fontSize: 14, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  /// Shows the payload this flow would send.
  ///
  /// Kind-aware, because the two products post different bodies: a new P-Loan
  /// is filed with `POST /SavePloanContract` ([PLoanContractSubmission]), an
  /// Extra with `POST /topup`. For the Extra this previews the
  /// `regmast_ploan.php` mapping instead, which is what it was written for.
  ///
  /// A QA affordance, mirroring the submit form's ดู Payload button, so the
  /// field mapping can be checked against the API's own sample. Only offered in
  /// mock mode — it is not something a customer should see.
  void _previewPLoanPayload() {
    final isNew = _flow.isNewPLoan;
    final fields = isNew
        ? PLoanContractSubmission.fromFlow(_flow).fields
        : PLoanSubmission.fromFlow(_flow).fields;
    final images = isNew
        ? PLoanContractSubmission.fromFlow(_flow).imageGroups
        : PLoanSubmission.fromFlow(_flow).imageGroups;
    final unresolved = isNew
        ? PLoanContractSubmission.fromFlow(_flow).unresolvedFields
        : PLoanSubmission.fromFlow(_flow).unresolvedFields;
    final lines = [
      isNew ? 'POST /SavePloanContract' : 'regmast_ploan.php',
      '',
      for (final e in fields.entries) '${e.key}: ${e.value}',
      '',
      'images:',
      for (final e in images.entries)
        '  ${e.key}[]: ${e.value.length} file(s)',
      if (unresolved.isNotEmpty) ...[
        '',
        'NO SOURCE IN THIS FLOW:',
        ...unresolved.map((f) => '  $f'),
      ],
    ];
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('P-Loan payload',
            style: LoanRegisterStyles.appBarTitleStyle().copyWith(fontSize: 16)),
        content: SingleChildScrollView(
          child: SelectableText(lines.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: pLoanAppBar(context, 'สรุปรายละเอียดของสัญญา'),
      body: Column(
        children: [
          const PLoanMockBanner(),
          PLoanKindBanner(kind: _flow.kind),
          const RegisterStepIndicator(currentStep: 6, totalSteps: 6),
          Expanded(child: _body()),
        ],
      ),
      bottomNavigationBar: _loading || _error != null
          ? null
          : PLoanBottomButton(
              label: 'ยืนยัน',
              busy: _submitting,
              onPressed: _flow.canSubmit ? _submit : null,
            ),
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

    final contract = _flow.contract!;
    final detail = _flow.amountDetail!;
    final installment = _flow.installment!;
    final isNew = _flow.isNewPLoan;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(LoanRegisterStyles.padding, 4,
          LoanRegisterStyles.padding, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isNew) const PLoanSectionHeader('สัญญาอ้างอิง'),
          ContractSummaryCard(
            loanTypeCode: contract.contractDetails.loanTypeCode,
            loanTypeName: contract.contractDetails.loanTypeName,
            contractNo: contract.contractNo,
            collateralInformation:
                contract.contractDetails.collateralInformation,
          ),
          const PLoanSectionHeader('สรุปยอดสินเชื่อใหม่'),
          // The three rows below describe the reference contract's headroom and
          // the principal a top-up would clear. None of it applies to a loan
          // that is not drawn against that contract.
          if (!isNew) ...[
            PLoanAmountRow(
              label: 'ยอดจัดสินเชื่อเดิม',
              value: '${formatMoney(detail.contractDetails.creditLimit)} บาท',
            ),
            if (detail.topupExtra != 0)
              PLoanAmountRow(
                label: 'ยอดจัดสินเชื่อพิเศษ',
                value: formatMoney(detail.topupExtra),
                emphasis: true,
              ),
            PLoanAmountRow(
              label: 'รวมยอดวงเงินที่อนุมัติ',
              value: '${formatMoney(detail.defaultTopupAmount)} บาท',
            ),
          ],
          PLoanAmountRow(
            label: isNew ? 'วงเงินที่ขอ' : 'วงเงินที่ต้องการกู้ใหม่',
            value: '${formatMoney(_flow.requestedAmount)} บาท',
          ),
          if (!isNew)
            PLoanAmountRow(
              label: 'หักยอดเงินต้นสัญญาเก่า',
              caption: 'เลขที่สัญญา ${detail.contractNo}',
              value:
                  '${formatMoney(detail.contractDetails.closingBalance)} บาท',
            ),
          PLoanAmountRow(
            label: 'หักอากรสแตมป์',
            value: '${formatMoney(detail.feeAmount)} บาท',
          ),
          PLoanAmountRow(
            label: 'จำนวนเงินที่จะได้รับ',
            value: '${formatMoney(_flow.payoutAmount)} บาท',
            emphasis: true,
            showDivider: false,
          ),
          const PLoanSectionHeader('รายละเอียดคำขอสินเชื่อใหม่'),
          PLoanAmountRow(
            label: 'ยอดจัดสินเชื่อ',
            value: '${formatMoney(_flow.requestedAmount)} บาท',
          ),
          PLoanAmountRow(
            label: 'ค่างวด',
            value: '${formatMoney(installment.regularPeriodAmt)} บาท',
          ),
          PLoanAmountRow(
            label: 'จำนวนงวด',
            value: '${installment.tenor} งวด',
          ),
          PLoanAmountRow(
            label: 'ดอกเบี้ย (ต่อเดือน)',
            caption: 'เลขที่สัญญา ${detail.contractNo}',
            value: '${detail.interestRate}%',
          ),
          PLoanAmountRow(
            label: 'ชำระทุกวันที่',
            value: '${detail.dueDay}',
            showDivider: false,
          ),
          const PLoanSectionHeader('ข้อมูลเลขที่บัญชี'),
          BankAccountCard(
            bankCode: contract.contractBankBrandname,
            accountNo: contract.contractBankAccount,
            logoBytes: decodeBase64Image(contract.branchImage),
          ),
          const PLoanSectionHeader('ยืนยันตัวตน'),
          _IdentitySlot(
            slot: PLoanPhoto.idCard,
            bytes: _flow.photos[PLoanPhoto.idCard],
            busy: _busy,
            onCapture: _captureIdCard,
            onRemove: () => setState(() {
              _flow.photos.remove(PLoanPhoto.idCard);
              _flow.verifiedThaiId = '';
            }),
          ),
          _IdentitySlot(
            slot: PLoanPhoto.selfieWithIdCard,
            bytes: _flow.photos[PLoanPhoto.selfieWithIdCard],
            busy: _busy,
            onCapture: _captureSelfie,
            onRemove: () => setState(
                () => _flow.photos.remove(PLoanPhoto.selfieWithIdCard)),
          ),
          const PLoanSectionHeader('เอกสารประกอบสัญญา'),
          for (final kind in LoanDocumentKind.values)
            _DocumentRow(
              kind: kind,
              accepted: _flow.consented.contains(kind),
              onTap: () => _reviewDocument(kind),
            ),
          const SizedBox(height: 12),

          // ── ลงนามเอกสารและยืนยันตัวตน NDID ─────────────────────────
          // The same hop the loan-register wizard does on its step 4, using the
          // same shared screens (see NdidSubject). It sits directly under the
          // documents because the order is read-then-sign.
          const PLoanSectionHeader('ลงนามเอกสารและยืนยันตัวตน NDID'),
          RegisterFieldRow(
            label: 'ตรวจสอบเอกสารและยืนยันตัวตน',
            value: _flow.ndidVerified ? 'ยืนยันแล้ว' : '',
            placeholder: 'กรุณาลงนามเอกสารและยืนยันตัวตนด้วย NDID',
            trailing: _flow.ndidVerified
                ? const Icon(Icons.check_circle,
                    color: Colors.green, size: 22)
                : null,
            showDivider: false,
            onTap: _signWithNdid,
          ),
          if (_flow.ndidVerified) ...[
            const SizedBox(height: 8),
            _ndidVerifiedBanner(),
            const SizedBox(height: 12),
            _downloadAgreementButton(),
          ],
          const SizedBox(height: 12),
          const PLoanSectionHeader('ความยินยอม'),
          _ConsentCheckbox(
            label: 'ยินยอมการตลาด',
            description: 'ยินยอมให้ติดต่อเพื่อเสนอผลิตภัณฑ์และบริการ '
                '(ไม่บังคับ)',
            value: _flow.marketingConsent,
            onChanged: (v) => setState(() => _flow.marketingConsent = v),
          ),
          _ConsentCheckbox(
            label: 'ยินยอมข้อมูลอ่อนไหว',
            description: 'ยินยอมให้เก็บและใช้ข้อมูลส่วนบุคคลที่มีความอ่อนไหว '
                'เพื่อพิจารณาสินเชื่อ (จำเป็น)',
            value: _flow.sensitiveConsent,
            required: true,
            onChanged: (v) => setState(() => _flow.sensitiveConsent = v),
          ),
          const SizedBox(height: 12),
          Text(
            'ข้อมูลวันที่ ${formatThaiDate(detail.dataDate)}',
            style: GoogleFonts.notoSansThai(
              fontSize: 12,
              color: LoanRegisterStyles.label,
            ),
          ),
          if (PLoanApi.isMocked)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _previewPLoanPayload,
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text('ดู Payload (P-Loan)',
                    style: GoogleFonts.notoSansThai(fontSize: 13)),
              ),
            ),
          if (!_flow.canSubmit) ...[
            const SizedBox(height: 8),
            Text(
              _flow.missingIdentityPhoto?.missingMessage ??
                  _flow.missingConsent?.consentPrompt ??
                  (!_flow.ndidVerified
                      ? 'กรุณาลงนามเอกสารและยืนยันตัวตนด้วย NDID'
                      : !_flow.sensitiveConsent
                          ? 'กรุณายินยอมข้อมูลอ่อนไหวเพื่อดำเนินการต่อ'
                          : ''),
              style: GoogleFonts.notoSansThai(
                fontSize: 13,
                color: LoanRegisterStyles.required,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A PDPA consent checkbox. [required] marks the one the flow can't proceed
/// without, so an optional opt-in can't be mistaken for a blocker.
class _ConsentCheckbox extends StatelessWidget {
  const _ConsentCheckbox({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    this.required = false,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: LoanRegisterStyles.primary,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Text(
                          label,
                          style: GoogleFonts.notoSansThai(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: LoanRegisterStyles.value,
                          ),
                        ),
                        if (required)
                          Text(
                            ' *',
                            style: GoogleFonts.notoSansThai(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: LoanRegisterStyles.required,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 12,
                      color: LoanRegisterStyles.label,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ID-card / selfie capture block.
class _IdentitySlot extends StatelessWidget {
  const _IdentitySlot({
    required this.slot,
    required this.bytes,
    required this.busy,
    required this.onCapture,
    required this.onRemove,
  });

  final PLoanPhoto slot;
  final Uint8List? bytes;
  final bool busy;
  final VoidCallback onCapture;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final captured = bytes != null && bytes!.isNotEmpty;
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
                  child: Image.memory(bytes!,
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

  /// Opens the document outside the app. Kept as a fallback for embedders
  /// whose engine can't render a PDF in an iframe.
  void _open() {
    final ok = openBase64Pdf(widget.base64Pdf,
        fileName: '${widget.kind.name}.pdf');
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(canOpenPdf
            ? 'ไม่สามารถเปิดเอกสารได้'
            : 'เปิดเอกสารได้เฉพาะบนเว็บ/ในแอปพลิเคชัน'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nearly full height: the document is the point of this sheet, so it gets
    // the space rather than being hidden behind a button.
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
                // Escape hatch for embedders with no built-in PDF renderer
                // (Android WebView) — hands the file to the OS instead.
                IconButton(
                  tooltip: 'เปิดในแท็บใหม่',
                  onPressed: _open,
                  icon: Icon(Icons.open_in_new,
                      size: 20, color: LoanRegisterStyles.primary),
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
                  viewId: widget.kind.name,
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
                // The document is rendered above, so seeing it is no longer
                // a separate step — only the acknowledgement is.
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

/// The borrower's warranty the customer must accept before the request is sent.
class _BorrowerWarrantyDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('ยืนยันข้อมูลเอกสาร',
          style: LoanRegisterStyles.appBarTitleStyle().copyWith(fontSize: 18)),
      content: SingleChildScrollView(
        child: Text(
          'ผู้กู้ตกลงให้คำรับรองแก่ผู้ให้กู้ว่าคำรับรองดังต่อไปนี้'
          'ถูกต้องและตรงตามความเป็นจริง และผู้กู้มีอำนาจทุกประการ'
          'แต่เพียงผู้เดียวสำหรับการกู้ยืมเงินตามสัญญาฉบับนี้',
          style: GoogleFonts.notoSansThai(
            fontSize: 14,
            color: LoanRegisterStyles.value,
            height: 1.6,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('ยกเลิก',
              style: GoogleFonts.notoSansThai(
                  color: LoanRegisterStyles.label)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('ยืนยัน',
              style: GoogleFonts.notoSansThai(
                fontWeight: FontWeight.w600,
                color: LoanRegisterStyles.primary,
              )),
        ),
      ],
    );
  }
}
