import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_state.dart';
import '../loan_register/components/loan_register_styles.dart';
import '../p_loan/application/components/p_loan_components.dart';
import '../p_loan/application/models/loan_documents.dart';
import '../p_loan/application/pdf_view.dart';
import '../router/app_router.dart';
import '../services/srisawad_api.dart';
import '../services/topup_api.dart';
import 'components/topup_components.dart';
import 'models/topup_status.dart';

/// **สถานะคำขอสินเชื่อเพิ่ม** — `GET /topup/status-detail/{hash}/{db}/{trans}`.
///
/// Not a step in the wizard: it is where the contract card sends a customer
/// whose contract already has a request in flight, so they can see what it is
/// doing and re-read the documents they signed.
///
/// URL-addressable (`/topup/status?dbName=&transNo=`) rather than taking a
/// flow object, because it is reachable without one and a reload has to work.
class TopupStatusPage extends StatefulWidget {
  const TopupStatusPage({
    super.key,
    required this.dbName,
    required this.transNo,
  });

  final String dbName;
  final String transNo;

  @override
  State<TopupStatusPage> createState() => _TopupStatusPageState();
}

class _TopupStatusPageState extends State<TopupStatusPage> {
  TopupStatus? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _status = null;
      _error = null;
    });
    final appState = AppState();
    if (appState.hashThaiId.isEmpty) {
      setState(() => _error =
          'ไม่พบข้อมูลผู้ใช้ กรุณาเปิดหน้านี้จากแอปพลิเคชันอีกครั้ง');
      return;
    }
    if (widget.dbName.isEmpty || widget.transNo.isEmpty) {
      setState(() => _error = 'ไม่พบเลขที่รายการของคำขอนี้');
      return;
    }
    try {
      final status = await TopupApi.fetchStatusDetail(
        hashThaiId: appState.hashThaiId,
        dbName: widget.dbName,
        transNo: widget.transNo,
        token: appState.authToken,
      );
      if (!mounted) return;
      setState(() => _status = status);
    } on SrisawadApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Re-opens a filed document. Read-only here — there is nothing left to
  /// consent to, the request is already in.
  void _openDocument(LoanDocumentKind kind, TopupStatus status) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DocumentSheet(
        title: kind.title,
        base64Pdf: kind.base64From(status.documents),
        viewId: 'topup-status-${kind.name}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: topupAppBar(
        context,
        'สถานะคำขอสินเชื่อเพิ่ม',
        onBack: () =>
            context.canPop() ? context.pop() : context.go(AppRoutes.home),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final error = _error;
    if (error != null) return PLoanErrorView(message: error, onRetry: _load);
    final status = _status;
    if (status == null) {
      return const PLoanLoadingView(message: 'กำลังโหลดสถานะคำขอ...');
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            LoanRegisterStyles.padding, 12, LoanRegisterStyles.padding, 24),
        children: [
          _statusBanner(status),
          ContractSummaryCard(
            loanTypeCode: status.loanTypeCode,
            loanTypeName: status.loanTypeName,
            contractNo: status.contractNo,
            collateralInformation: status.collateralInformation,
          ),
          const PLoanSectionHeader('รายละเอียดคำขอ'),
          PLoanAmountRow(
            label: 'วันที่ยื่นคำขอ',
            value: formatThaiDate(status.requestDate),
          ),
          PLoanAmountRow(
            label: 'ยอดจัดสินเชื่อ',
            value: '${formatMoney(status.amount)} บาท',
          ),
          PLoanAmountRow(
            label: 'ยอดเงินที่ได้รับ',
            value: '${formatMoney(status.actualReceiveAmount)} บาท',
            emphasis: true,
          ),
          PLoanAmountRow(
            label: 'ค่างวด',
            value: '${formatMoney(status.amountPerInstallment)} บาท',
          ),
          PLoanAmountRow(
            label: 'จำนวนงวด',
            value: '${status.installmentNumber} งวด',
          ),
          PLoanAmountRow(
            label: 'ดอกเบี้ย (ต่อเดือน)',
            value: '${status.interestRate}%',
          ),
          PLoanAmountRow(
            label: 'ยอดรวมที่ต้องชำระ',
            value: '${formatMoney(status.totalAmountWithRate)} บาท',
            showDivider: false,
          ),
          if (status.contractBankAccount.isNotEmpty) ...[
            const PLoanSectionHeader('บัญชีรับเงิน'),
            BankAccountCard(
              bankCode: status.contractBankBrandname,
              accountNo: status.contractBankAccount,
              logoBytes: decodeBase64Image(status.branchImage),
            ),
          ],
          if (status.hasDocuments) ...[
            const PLoanSectionHeader('เอกสารประกอบสัญญา'),
            for (final kind in LoanDocumentKind.values)
              _DocumentRow(
                title: kind.title,
                onTap: () => _openDocument(kind, status),
              ),
          ],
        ],
      ),
    );
  }

  /// The API owns this wording, so it is shown verbatim rather than mapped to
  /// a status vocabulary of ours that would drift from theirs.
  Widget _statusBanner(TopupStatus status) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LoanRegisterStyles.primarySoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long,
              size: 28, color: LoanRegisterStyles.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'สถานะคำขอ',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 12,
                    color: LoanRegisterStyles.label,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status.requestStatus.isEmpty ? '-' : status.requestStatus,
                  style: GoogleFonts.notoSansThai(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: LoanRegisterStyles.primary,
                  ),
                ),
                if (widget.transNo.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'เลขที่รายการ ${widget.transNo}',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 12,
                      color: LoanRegisterStyles.label,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: LoanRegisterStyles.cardBorder),
          ),
          child: Row(
            children: [
              SvgPicture.asset('assets/p_loan/document-icon.svg',
                  width: 26, height: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.notoSansThai(
                    fontSize: 14,
                    color: LoanRegisterStyles.value,
                  ),
                ),
              ),
              Icon(Icons.navigate_next,
                  size: 24, color: LoanRegisterStyles.label),
            ],
          ),
        ),
      ),
    );
  }
}

/// Read-only document viewer — no consent checkbox, the request is already in.
class _DocumentSheet extends StatelessWidget {
  const _DocumentSheet({
    required this.title,
    required this.base64Pdf,
    required this.viewId,
  });

  final String title;
  final String base64Pdf;
  final String viewId;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
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
                child: PdfInlineView(base64Pdf: base64Pdf, viewId: viewId),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
