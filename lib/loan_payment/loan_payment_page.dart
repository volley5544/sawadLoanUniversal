/// **ชำระเงิน** — pick how much of an instalment to pay, then get a QR for it.
///
/// Ported from LandAndHouseWeb's `customer_payment/select_payment_page`, whose
/// UI and visibility rules this reproduces. It is the loan-universal
/// replacement for that page, which the host opens today through
/// `api_url['customer_payment_web' | '…_uat']`.
///
/// Like the loan detail screen it makes **no call of its own**: everything
/// comes off the `GET /loan/list` row, which the source reads the same way.
/// Nothing is filed here either — the screen's whole output is an amount,
/// carried to the QR page, which the customer then pays at their bank. So
/// there is no submit, no confirmation and nothing to undo.
///
/// URL-addressable (`/loanPayment?contNo=`), same shape and same reason as
/// `/loanDetail`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_state.dart';
import '../loan_detail/components/loan_detail_components.dart';
import '../loan_detail/components/loan_detail_header_card.dart';
import '../loan_detail/insurance_list_page.dart';
import '../p_loan/application/components/p_loan_components.dart';
import '../p_loan/application/models/loan_contract.dart';
import '../router/app_router.dart';
import '../services/native_bridge.dart';
import '../services/p_loan_api.dart';
import '../services/srisawad_api.dart';
import 'components/loan_payment_components.dart';
import 'models/loan_payment_option.dart';

class LoanPaymentPage extends StatefulWidget {
  const LoanPaymentPage({
    super.key,
    required this.contractNo,
    this.dbName = '',
    this.fromHost = false,
  });

  final String contractNo;
  final String dbName;

  /// Nothing of this build's own sits beneath this screen, so back closes the
  /// WebView. Set when the host opens it directly; **not** set when the loan
  /// detail screen pushes it, since there the customer came from a real page.
  final bool fromHost;

  @override
  State<LoanPaymentPage> createState() => _LoanPaymentPageState();
}

class _LoanPaymentPageState extends State<LoanPaymentPage> {
  LoanContract? _contract;
  String? _error;

  LoanPaymentOption _option = LoanPaymentOption.full;

  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _amountFocus.addListener(_onAmountFocusChanged);
    _load();
  }

  @override
  void dispose() {
    _amountFocus.removeListener(_onAmountFocusChanged);
    _amountFocus.dispose();
    _amountController.dispose();
    super.dispose();
  }

  /// Focus strips the separators so the field is editable as a plain number;
  /// blur re-formats it and applies the balance ceiling. Both halves are the
  /// source's — see [LoanPaymentSummary.blurredFieldText] for the ⚠ on the
  /// silent clamp.
  void _onAmountFocusChanged() {
    final contract = _contract;
    if (contract == null) return;
    if (_amountFocus.hasFocus) {
      final raw = parsePaymentAmount(_amountController.text);
      _amountController.text = raw == 0 ? '' : _amountController.text
          .replaceAll(',', '');
      return;
    }
    setState(() {
      _amountController.text =
          LoanPaymentSummary(contract).blurredFieldText(_amountController.text);
    });
  }

  Future<void> _load() async {
    setState(() {
      _contract = null;
      _error = null;
    });
    final appState = AppState();
    if (appState.hashThaiId.isEmpty) {
      setState(() => _error =
          'ไม่พบข้อมูลผู้ใช้ กรุณาเปิดหน้านี้จากแอปพลิเคชันอีกครั้ง');
      return;
    }
    final wanted = widget.contractNo.trim();
    if (wanted.isEmpty) {
      setState(() => _error = 'ไม่พบเลขที่สัญญา');
      return;
    }
    try {
      final contracts = await PLoanApi.listContracts(
        hashThaiId: appState.hashThaiId,
        token: appState.authToken,
      );
      final db = widget.dbName.trim();
      LoanContract? match;
      for (final contract in contracts) {
        if (contract.contractNo.trim() != wanted) continue;
        if (db.isNotEmpty && contract.dbName.trim() != db) continue;
        match = contract;
        break;
      }
      if (!mounted) return;
      if (match == null) {
        setState(() => _error = 'ไม่พบสัญญาเลขที่ $wanted');
        return;
      }
      setState(() => _contract = match);
    } on SrisawadApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _onBack() {
    if (widget.fromHost) {
      NativeCameraBridge.closeWebview();
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  void _select(LoanPaymentOption option) {
    if (_option == option) return;
    // Leaving the typed option commits whatever is in the field, so coming
    // back to it shows the same figure rather than a half-typed one.
    _amountFocus.unfocus();
    setState(() => _option = option);
  }

  void _onPay(LoanPaymentSummary summary) {
    final rejection = summary.rejectionFor(_option, _amountController.text);
    if (rejection != null) {
      showLoanPaymentMessage(context, rejection);
      return;
    }
    final amount = summary.amountFor(_option, _amountController.text);
    context.push(
      Uri(
        path: AppRoutes.loanPaymentQr,
        queryParameters: {
          'contNo': summary.contract.contractNo.trim(),
          if (summary.contract.dbName.trim().isNotEmpty)
            'dbName': summary.contract.dbName.trim(),
          'amount': amount.toString(),
        },
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: loanDetailAppBar(context, 'ชำระเงิน', onBack: _onBack),
      body: _body(),
    );
  }

  Widget _body() {
    final error = _error;
    if (error != null) return PLoanErrorView(message: error, onRetry: _load);
    final contract = _contract;
    if (contract == null) {
      return const PLoanLoadingView(message: 'กำลังโหลดข้อมูลสัญญา...');
    }
    final summary = LoanPaymentSummary(contract);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PLoanMockBanner(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // `isShowDownload: false` in the source — the contract-document
                // link belongs on the detail screen, not in front of someone
                // about to pay.
                LoanDetailHeaderCard(
                  contract: contract,
                  showsNotIssuedNotice: false,
                  onDownloadContract: null,
                  onViewInsurances: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          InsuranceListPage(insurances: contract.insurances),
                    ),
                  ),
                ),
                LoanPaymentCollateralCard(contract: contract),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 24, 10, 12),
                  child: Text(
                    '*กรุณาชำระภายในวัน ช่วงเวลา 00.05 ถึง 22.45 น. เท่านั้น '
                    'เพื่อหลีกเลี่ยงการเสียดอกเบี้ยเพิ่มเติม',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: LoanDetailPalette.alert,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    'กรุณาเลือกจำนวนเงินที่ต้องการชำระ',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: LoanDetailPalette.navy,
                    ),
                  ),
                ),
                for (final option in LoanPaymentOption.values)
                  _optionCard(option, summary),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        _payBar(summary),
      ],
    );
  }

  Widget _optionCard(LoanPaymentOption option, LoanPaymentSummary summary) {
    return LoanPaymentOptionCard(
      label: option.label,
      // The typed option's header shows no figure — the amount is the field
      // below it, and a second number beside the radio would compete with it.
      amount: switch (option) {
        LoanPaymentOption.full => '${formatMoney(summary.fullAmount)} บาท',
        LoanPaymentOption.overdue =>
          '${formatMoney(summary.overdueTotal)} บาท',
        LoanPaymentOption.custom => null,
      },
      selected: _option == option,
      onTap: () => _select(option),
      detail: _option == option ? _optionDetail(option, summary) : null,
    );
  }

  Widget _optionDetail(LoanPaymentOption option, LoanPaymentSummary summary) =>
      switch (option) {
        LoanPaymentOption.full => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (summary.showsOverdueBlock) ..._overdueRows(summary),
              LoanPaymentDetailRow(
                label: 'ค่างวดปัจจุบัน',
                value: summary.currentInstallmentLabel,
              ),
              LoanPaymentDetailRow(
                label: '',
                value: '${formatMoney(summary.installmentAmount)} บาท',
              ),
              LoanPaymentDetailRow(
                label: 'วันครบกำหนดชำระ',
                value: summary.currentDueDate,
              ),
            ],
          ),
        LoanPaymentOption.overdue => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (summary.showsOverdueBlock) ...[
                ..._overdueRows(summary),
                LoanPaymentDetailRow(
                  label: 'วันครบกำหนดชำระ',
                  value: summary.currentDueDate,
                ),
              ],
              if (summary.showsNoOverdueNotice)
                const LoanPaymentNotice(text: 'คุณไม่มียอดค้างชำระ'),
            ],
          ),
        LoanPaymentOption.custom => _customAmountBlock(summary),
      };

  /// ค่างวดเลยกำหนดชำระ and its breakdown — shared by the two fixed options,
  /// which render it identically.
  List<Widget> _overdueRows(LoanPaymentSummary summary) => [
        const LoanPaymentDetailHeading(text: 'ค่างวดเลยกำหนดชำระ'),
        LoanPaymentDetailRow(
          label: summary.overdueRangeLabel,
          value: '${formatMoney(summary.overdueAmount)} บาท',
        ),
        if (summary.showsCollectionFee)
          LoanPaymentDetailRow(
            label: 'ค่าติดตามทวงถาม',
            value: '${formatMoney(summary.collectionFee)} บาท',
          ),
        LoanPaymentDetailRow(
          label: 'รวม',
          value: '${formatMoney(summary.overdueTotal)} บาท',
          emphasised: true,
        ),
        LoanPaymentDetailRow(
          label: 'วันครบกำหนดชำระ',
          value: summary.overdueDueDate,
        ),
      ];

  Widget _customAmountBlock(LoanPaymentSummary summary) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LoanPaymentDetailHeading(text: 'กำหนดยอดชำระ'),
          LoanPaymentDetailRow(
            label: 'ยอดหนี้คงเหลือ',
            value: '${formatMoney(summary.osBalance)} บาท',
          ),
          const SizedBox(height: 12),
          LoanPaymentNotice(
            text: '*การกำหนดยอดชำระเอง: การชำระค่างวดไม่เต็มจำนวน '
                'จะมีดอกเบี้ยเพิ่มขึ้นและค่าติดตามทวงถามหนี้ (ถ้ามี) '
                'ส่งผลให้ชำระหนี้ไม่ครบตามระยะเวลาที่กำหนด '
                'สอบถามข้อมูลเพิ่มเติมติดต่อ 1652',
            alert: true,
          ),
          const SizedBox(height: 8),
          // The standing statement of the ceiling. It is why the silent clamp
          // in `blurredFieldText` needs no toast of its own.
          const LoanPaymentNotice(
            text: '**ไม่สามารถระบุจำนวนเงินเกินยอดหนี้คงเหลือได้',
            alert: true,
          ),
          const SizedBox(height: 12),
          LoanPaymentAmountField(
            controller: _amountController,
            focusNode: _amountFocus,
            hintText: 'กรอกจำนวนเงินที่ต้องการจ่ายค่างวด',
          ),
        ],
      );

  Widget _payBar(LoanPaymentSummary summary) {
    final disabled = summary.isDisabled(_option, _amountController.text);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
        child: LoanPaymentPrimaryButton(
          label: 'ชำระเงิน',
          onPressed: disabled ? null : () => _onPay(summary),
        ),
      ),
    );
  }
}

/// Digits and one decimal point — the field is a baht amount, and the source
/// strips everything else on read anyway.
final List<TextInputFormatter> loanPaymentAmountFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
];
