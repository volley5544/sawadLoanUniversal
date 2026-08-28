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
import '../../services/device_location.dart';
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
    _captureLocation();
  }

  /// Fills `latitude` / `longitude` for the submit payload from the device GPS.
  ///
  /// Fired here, on the screen that submits, and **not awaited anywhere**. The
  /// customer spends minutes on this page — reading three PDFs, photographing
  /// their ID card, taking a selfie, signing with NDID — so a fix that takes
  /// seconds is long since in place by the time ยืนยัน is pressed. Awaiting it at
  /// submit would instead put a permission prompt and a GPS lock in front of the
  /// one button that matters.
  ///
  /// A failure is deliberately silent: the fields stay empty, land in
  /// `unresolvedFields` as they always did, and the application still files.
  /// Location is worth having, not worth blocking an application over. The
  /// reason is logged to the WebView console — see [DeviceLocation].
  ///
  /// Note this does **not** fill `gpsProvinceId` / `gpsAumphurId`: those are
  /// srisawad's own province/district **ids**, which need a lookup from these
  /// coordinates that nothing in this app can perform.
  Future<void> _captureLocation() async {
    final position = await DeviceLocation.current();
    if (position == null) return;
    _flow.latitude = position.latitudeString;
    _flow.longitude = position.longitudeString;
  }

  /// Builds the `save_pdf` block, which is both the `/pdf/loan` request body
  /// and a nested field of the submit payload — so it must be identical in
  /// both places.
  ///
  /// **Extra only.** Every key it is built from (`contract_no`, `db_name`,
  /// `from`, `contract_date`) comes from the contract, and a new P-Loan has
  /// none — see [PLoanFlow.canGenerateDocuments].
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
      // Account and collateral come off the flow, not the contract: for a new
      // P-Loan the customer stated both, and the generated agreement must name
      // what they gave rather than the reference contract's.
      contractBankAccount: _flow.bankAccountNo,
      contractBankBrandname: _flow.bankCode,
      contractBankType: contract.contractBankType,
      contractBankBranch: '',
      interestRate: detail.interestRate,
      installmentNumber: installment.tenor.toDouble(),
      amountPerInstallment: installment.regularPeriodAmt.toDouble(),
      startInstallmentDate: _flow.plan?.firstDueDate ?? '',
      installmentDate: '',
      vehicleType: _flow.loanTypeName,
    );
  }

  Future<void> _generateDocuments() async {
    // A new P-Loan cannot produce them at all, and that is not an error in
    // this application's data — the rest of the screen is valid and worth
    // showing, with the document section explaining itself in place.
    if (!_flow.canGenerateDocuments) {
      setState(() {
        _loading = false;
        _error = _flow.isNewPLoan ? null : 'ข้อมูลไม่ครบถ้วน กรุณาเริ่มรายการใหม่';
      });
      return;
    }
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
  ///
  /// ⚠ That clock rides on the contract, so a **new P-Loan falls back to the
  /// device time** and loses the protection. The server re-checks expiry on
  /// submit, and the flow has no other server-time source today; a
  /// `current_date_time` on `/user/detail` (or on the new-loan document call)
  /// would close it.
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
  /// Enters the NDID sub-flow at its own first screen — the NDID service
  /// agreement (`ndid_terms_page`) — and skips the wizard's
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
      AppRoutes.ndidTerms,
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
  ///
  /// **Currently not rendered** — taking the contract out of the app is not
  /// allowed for now. Kept, not deleted, because it is expected back.
  // ignore: unused_element
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
      // Both kinds file with the P-Loan save API since 2026-07-31 — a P-Loan
      // Extra is a P-Loan contract referencing an existing one, not a top-up of
      // it. The `topup` arm is unreachable today; kept so the switch stays
      // exhaustive and reverting is a one-line change in submitTarget.
      final transNo = switch (_flow.submitTarget) {
        PLoanSubmitTarget.pLoanSaveApi => await PLoanApi.savePLoanContract(
            submission: PLoanContractSubmission.fromFlow(_flow),
            token: _flow.authToken,
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
  /// **No longer kind-aware**: since 2026-07-31 both kinds file with the P-Loan
  /// save API (`POST /ploan`, `multipart/form-data`), so this previews
  /// [PLoanContractSubmission] for either. It used to show the `regmast_ploan.php` mapping for an Extra, which
  /// would now be a preview of a body nothing sends — worse than no preview,
  /// because a QA check against it would pass while the real payload differed.
  ///
  /// A QA affordance, mirroring the submit form's ดู Payload button, so the
  /// field mapping can be checked against the API's own sample. Only offered in
  /// mock mode — it is not something a customer should see.
  void _previewPLoanPayload() {
    final submission = PLoanContractSubmission.fromFlow(_flow);
    final fields = submission.fields;
    final images = submission.imageGroups;
    final unresolved = submission.unresolvedFields;
    final lines = [
      'POST /ploan  multipart/form-data  (${_flow.kind.shortLabel})',
      '',
      for (final e in fields.entries) '${e.key}: ${e.value}',
      '',
      // Sizes and content types rather than bytes: enough to tell a JPEG from a
      // PDF from a missing part, which is what a field-mapping check needs.
      'file parts (${submission.files.length}):',
      for (final f in submission.files)
        '  ${f.field}: ${f.filename} (${f.contentType}, '
            '${(f.bytes.length / 1024).toStringAsFixed(1)} KB)',
      '',
      // The regmast multipart grouping. /ploan takes only the three above, so
      // the collateral shots are collected for the flow but never filed.
      'images (collected, NOT sent to /ploan):',
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
          RegisterStepIndicator(
              currentStep: _flow.stepNumber(6), totalSteps: _flow.totalSteps),
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

    final detail = _flow.amountDetail!;
    final installment = _flow.installment!;
    final isNew = _flow.isNewPLoan;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(LoanRegisterStyles.padding, 4,
          LoanRegisterStyles.padding, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // No ContractSummaryCard here. It used to lead this screen for an
          // Extra, but the contract number it showed is repeated by the
          // หักยอดเงินต้นสัญญาเก่า row below and the collateral is summarised
          // further down, so it was the same facts told twice above the fold.
          // Removed 2026-07-30 on request. A new P-Loan never had it.
          // สรุปยอดสินเชื่อใหม่ is **new-P-Loan only** (hidden for an Extra on
          // request, 2026-07-30). Every row in it was framed as a top-up: the
          // reference contract's headroom (ยอดจัดสินเชื่อเดิม / สินเชื่อวงเงิน
          // อเนกประสงค์ / รวมยอดวงเงินที่อนุมัติ) and the old principal a top-up
          // would clear — none of which an Extra draws against. The requested
          // amount survives as ยอดจัดสินเชื่อ in the next section.
          //
          // ⚠ It also took จำนวนเงินที่จะได้รับ off this screen. That figure is
          // still computed, still submitted as `transfer_amount` /
          // `transferAmt`, and still shown on the success screen — hiding the
          // row does not settle Outstanding #8.
          if (isNew) ...[
            const PLoanSectionHeader('สรุปยอดสินเชื่อใหม่'),
            PLoanAmountRow(
              label: 'วงเงินที่ขอ',
              value: '${formatMoney(_flow.requestedAmount)} บาท',
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
          ],
          const PLoanSectionHeader('รายละเอียดคำขอสินเชื่อใหม่'),
          PLoanAmountRow(
            // An Extra lends a วงเงินอเนกประสงค์ — the full topup_extra offer,
            // undiminished by the old contract.
            label: isNew ? 'ยอดจัดสินเชื่อ' : 'ยอดจัดวงเงินอเนกประสงค์',
            value: '${formatMoney(_flow.requestedAmount)} บาท',
          ),
          // Extra only: a new P-Loan already shows the duty in สรุปยอด
          // สินเชื่อใหม่ above, which an Extra no longer renders.
          if (!isNew)
            PLoanAmountRow(
              label: 'ค่าอากรแสตมป์',
              value: '${formatMoney(detail.feeAmount)} บาท',
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
            // The rate is the reference contract's only for an Extra. A new
            // P-Loan's comes from its own pricing, so captioning it with that
            // contract number would attribute it to the wrong loan.
            caption: isNew ? null : 'เลขที่สัญญา ${detail.contractNo}',
            value: '${detail.interestRate}%',
          ),
          PLoanAmountRow(
            label: 'ชำระทุกวันที่',
            value: '${detail.dueDay}',
            // Last row for a new P-Loan; an Extra adds the transfer below.
            showDivider: !isNew,
          ),
          // Extra only, and the section's bottom line: what actually reaches the
          // bank account. `payoutAmount` is the same
          // ยอดจัดวงเงินอเนกประสงค์ − ค่าอากรแสตมป์ shown two rows apart above.
          if (!isNew)
            PLoanAmountRow(
              label: 'ยอดโอนเงินเข้าบัญชี',
              value: '${formatMoney(_flow.payoutAmount)} บาท',
              emphasis: true,
              showDivider: false,
            ),
          if (isNew) ...[
            const PLoanSectionHeader('ข้อมูลหลักประกัน'),
            // What the customer stated on step 4 — shown back for a last check
            // before it is filed.
            PLoanAmountRow(
                label: 'ประเภทหลักประกัน', value: _flow.loanTypeName),
            PLoanAmountRow(
                label: 'ยี่ห้อสินค้า', value: _flow.collateralBrand),
            PLoanAmountRow(
                label: 'รุ่นสินค้า', value: _flow.collateralSeries),
            PLoanAmountRow(
              label: 'ปีที่ผลิต',
              value: _flow.collateralManufactureYear,
              showDivider: false,
            ),
          ],
          const PLoanSectionHeader('ข้อมูลเลขที่บัญชี'),
          BankAccountCard(
            bankCode: _flow.bankCode,
            accountNo: _flow.bankAccountNo,
            logoBytes: decodeBase64Image(_flow.bankLogoBase64),
          ),
          if (isNew && _flow.bankAccountName.isNotEmpty)
            PLoanAmountRow(
              label: 'ชื่อบัญชี',
              value: _flow.bankAccountName,
              showDivider: false,
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
          if (!_flow.canGenerateDocuments)
            // `POST /pdf/loan` is keyed by a contract, which this product does
            // not have. Same treatment as the interim installment estimate:
            // say what is missing rather than showing rows that cannot open.
            const _DocumentsUnavailableNote()
          else
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
          // documents because the order is read-then-sign — so with no
          // documents to read there is nothing to sign, and the row is inert.
          const PLoanSectionHeader('ลงนามเอกสารและยืนยันตัวตน NDID'),
          RegisterFieldRow(
            label: 'ตรวจสอบเอกสารและยืนยันตัวตน',
            value: _flow.ndidVerified ? 'ยืนยันแล้ว' : '',
            placeholder: _flow.canGenerateDocuments
                ? 'กรุณาลงนามเอกสารและยืนยันตัวตนด้วย NDID'
                : 'รอเอกสารประกอบสัญญา',
            trailing: _flow.ndidVerified
                ? const Icon(Icons.check_circle,
                    color: Colors.green, size: 22)
                : null,
            showDivider: false,
            onTap: _flow.canGenerateDocuments ? _signWithNdid : null,
          ),
          if (_flow.ndidVerified) ...[
            const SizedBox(height: 8),
            _ndidVerifiedBanner(),
            // ดาวน์โหลดเอกสาร is withheld for now: the customer may read the
            // contract in the app and consent to it, but not save it out or hand
            // it to another app. Kept (with `_downloadAgreementButton` /
            // `_openAgreement`) for when that is allowed again.
            // const SizedBox(height: 12),
            // _downloadAgreementButton(),
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
          // Only an Extra has a data date: it comes from /topup/detail, which
          // a new P-Loan never calls. An empty one used to render as a bare
          // "ข้อมูลวันที่".
          if (formatThaiDate(detail.dataDate).isNotEmpty)
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
              // Ordered by what the customer can actually act on. The
              // documents come first when they are unavailable, because
              // nothing below it can be completed either and telling them to
              // sign something that does not exist would be a dead end.
              !_flow.canGenerateDocuments
                  ? 'ยังไม่สามารถส่งคำขอสินเชื่อใหม่ได้ '
                      'เนื่องจากอยู่ระหว่างเชื่อมต่อระบบเอกสารสัญญา'
                  : _flow.missingIdentityPhoto?.missingMessage ??
                      _flow.missingConsent?.consentPrompt ??
                      (!_flow.ndidVerified
                          ? 'กรุณาลงนามเอกสารและยืนยันตัวตนด้วย NDID'
                          : !_flow.sensitiveConsent
                              ? 'กรุณายินยอมข้อมูลอ่อนไหวเพื่อดำเนินการต่อ'
                              // Both are gated on their own screens; say which
                              // one to go back to rather than a dead button.
                              : isNew && !_flow.newLoan.hasCollateral
                                  ? 'กรุณาระบุข้อมูลหลักประกันในขั้นตอนที่ 4'
                                  : isNew && !_flow.newLoan.hasPayoutAccount
                                      ? 'กรุณาระบุบัญชีรับเงินในขั้นตอนที่ 5'
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

/// Shown in place of the document rows when the flow cannot produce them.
///
/// Today that means a **new P-Loan**: `POST /pdf/loan` is keyed by a contract
/// and this product has none, so the read-consent-sign step — and therefore
/// the submit — is unreachable until the new-loan document endpoint exists.
/// Deliberately explicit rather than an empty section, so a blocked submit is
/// explained instead of looking broken.
class _DocumentsUnavailableNote extends StatelessWidget {
  const _DocumentsUnavailableNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LoanRegisterStyles.primarySoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: LoanRegisterStyles.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'อยู่ระหว่างเชื่อมต่อระบบสร้างเอกสารสัญญาสำหรับสินเชื่อใหม่ '
              'จึงยังไม่สามารถลงนามและส่งคำขอได้ในขณะนี้',
              style: GoogleFonts.notoSansThai(
                fontSize: 12.5,
                height: 1.4,
                color: LoanRegisterStyles.value,
              ),
            ),
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

  /// Opens the document outside the app.
  ///
  /// **Currently not wired to anything** — the contract is read in the sheet and
  /// consented to there, not handed to the OS. Kept for when that changes.
  // ignore: unused_element
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
                // เปิดในแท็บใหม่ is withheld for now — read and consent in the
                // app; the contract is not handed to the OS or another app. It
                // existed as the escape hatch for embedders with no PDF renderer,
                // which pdfx has since made unnecessary anyway (and on Android it
                // never worked: the host registers no onCreateWindow, so
                // window.open was a no-op). `_open` is kept for when this is
                // allowed again.
                // IconButton(
                //   tooltip: 'เปิดในแท็บใหม่',
                //   onPressed: _open,
                //   icon: Icon(Icons.open_in_new,
                //       size: 20, color: LoanRegisterStyles.primary),
                // ),
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
