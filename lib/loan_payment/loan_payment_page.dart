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
import '../p_loan/application/components/p_loan_components.dart';
import '../p_loan/application/models/loan_contract.dart';
import '../router/app_router.dart';
import '../services/native_bridge.dart';
import '../services/p_loan_api.dart';
import '../services/srisawad_api.dart';
import 'components/loan_payment_components.dart';
import 'models/loan_payment_option.dart';
import 'models/loan_payment_seed.dart';

class LoanPaymentPage extends StatefulWidget {
  const LoanPaymentPage({
    super.key,
    required this.contractNo,
    this.dbName = '',
    this.fromHost = false,
    this.seed,
  });

  final String contractNo;
  final String dbName;

  /// The contract already in memory, when the caller has it — the loan detail
  /// screen does. Null on the host deep link and on a reload, which is when
  /// this screen fetches. See [LoanPaymentSeed].
  final LoanPaymentSeed? seed;

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

    // The loan detail screen already loaded this row to draw the card the
    // customer just tapped. Asking for it again would put a round trip in
    // front of a screen whose data is sitting in memory.
    final seeded = widget.seed;
    if (seeded != null &&
        seeded.matches(contractNo: wanted, dbName: widget.dbName)) {
      setState(() => _contract = seeded.contract);
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
      // The QR screen needs `barcode_details` and the plate off this same
      // row — all of which is already here. The query string still carries
      // everything it needs to fetch for itself after a reload.
      extra: LoanPaymentSeed(contract: summary.contract),
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
                // ⚠ **The compact header, not `LoanDetailHeaderCard`**
                // (redesign, 2026-09-17). That card restates the whole
                // contract — due date, current instalment, arrears,
                // `รวมต้องชำระ` — directly above three options whose own
                // figures explain the same money. The customer is here to
                // choose an amount, so the header is now only what identifies
                // the contract. `loan_payment_page_old.dart` still renders the
                // full card.
                LoanPaymentContractHeader(
                  loanTypeIconDataUrl: contract.contractDetails.loanTypeIcon,
                  loanTypeName: contract.contractDetails.loanTypeName.trim(),
                  plate: contract.contractDetails.collateralInformation.trim(),
                  contractNo: contract.contractNo.trim(),
                ),
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
                    // Grey and regular, not navy and bold (redesign): it is
                    // an instruction above the controls, not a heading over a
                    // section — and in navy bold it competed with the option
                    // labels underneath it.
                    'กรุณาเลือกจำนวนเงินที่ต้องการชำระ',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 14,
                      color: LoanDetailPalette.label,
                    ),
                  ),
                ),
                for (final option in LoanPaymentOption.values)
                  _optionBlock(option, summary),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        _payBar(summary),
      ],
    );
  }

  /// The option's card, **with its detail nested inside it** when it is the
  /// selected one — see [LoanPaymentOptionCard] for why that changed.
  Widget _optionBlock(
    LoanPaymentOption option,
    LoanPaymentSummary summary,
  ) =>
      LoanPaymentOptionCard(
        label: option.label,
        amount: switch (option) {
          LoanPaymentOption.full => '${formatMoney(summary.fullAmount)} บาท',
          LoanPaymentOption.overdue =>
            '${formatMoney(summary.overdueTotal)} บาท',
          LoanPaymentOption.custom => null,
        },
        selected: _option == option,
        onTap: () => _select(option),
        children: _option == option ? _detailCards(option, summary) : const [],
      );

  List<Widget> _detailCards(
    LoanPaymentOption option,
    LoanPaymentSummary summary,
  ) =>
      switch (option) {
        // Two cards, deliberately: what is late, then what is due next.
        LoanPaymentOption.full => [
            if (summary.showsOverdueBlock)
              LoanPaymentDetailCard(
                heading: 'ยอดค้างชำระ',
                children: _arrearsRows(summary, showsTotal: true),
              ),
            LoanPaymentDetailCard(
              heading: 'ค่างวดปัจจุบัน',
              children: [
                LoanPaymentDetailRow(
                  label: summary.currentInstallmentLabel,
                  value: '${formatMoney(summary.currentDueAmount)} บาท',
                ),
                LoanPaymentDetailRow(
                  label: 'วันครบกำหนดชำระ',
                  value: summary.currentDueDate,
                ),
              ],
            ),
          ],
        LoanPaymentOption.overdue => [
            if (summary.showsOverdueBlock)
              LoanPaymentDetailCard(
                heading: 'ยอดค้างชำระ',
                // ⚠ **No รวม row unless a fee is present**, where
                // ชำระเต็มจำนวน always shows one — see
                // [LoanPaymentSummary.showsArrearsTotal].
                children: _arrearsRows(
                  summary,
                  showsTotal: summary.showsArrearsTotal,
                ),
              ),
            if (summary.showsNoOverdueNotice)
              const LoanPaymentDetailCard(
                heading: 'ยอดค้างชำระ',
                children: [LoanPaymentNotice(text: 'คุณไม่มียอดค้างชำระ')],
              ),
          ],
        LoanPaymentOption.custom => [
            LoanPaymentDetailCard(
              heading: 'กำหนดยอดชำระ',
              children: [
                LoanPaymentNotice(
                  text: '*การกำหนดยอดชำระเอง: การชำระค่างวดไม่เต็มจำนวน '
                      'จะมีดอกเบี้ยเพิ่มขึ้นและค่าติดตามทวงถามหนี้ (ถ้ามี) '
                      'ส่งผลให้ชำระหนี้ไม่ครบตามระยะเวลาที่กำหนด '
                      'สอบถามข้อมูลเพิ่มเติมติดต่อ 1652',
                  alert: true,
                ),
                // The standing statement of the ceiling — and, since the
                // ยอดหนี้คงเหลือ row was removed, the only place the rule
                // appears at all.
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
            ),
          ],
      };

  /// ค่างวดเลยกำหนดชำระ's rows. [showsTotal] differs by option — see the note
  /// on the ยอดค้างชำระ arm above.
  List<Widget> _arrearsRows(
    LoanPaymentSummary summary, {
    required bool showsTotal,
  }) =>
      [
        // ⚠ **The date leads the block now** (redesign) and the arrears figure
        // is labelled `ค่างวดค้างชำระ` rather than `ค้างชำระ (งวดที่ n-m)`.
        // The instalment range is not in the new design at all —
        // `overdueRangeLabel` is kept on the model for the `_old` screen.
        LoanPaymentDetailRow(
          label: 'วันครบกำหนดชำระ',
          value: summary.overdueDueDate,
        ),
        LoanPaymentDetailRow(
          label: 'ค่างวดค้างชำระ',
          value: '${formatMoney(summary.overdueAmount)} บาท',
        ),
        if (summary.showsCollectionFee)
          LoanPaymentDetailRow(
            label: 'ค่าติดตามค้างชำระ',
            value: '${formatMoney(summary.collectionFee)} บาท',
          ),
        if (summary.showsPenaltyFee)
          LoanPaymentDetailRow(
            label: 'ค่าเบี้ยปรับค้างชำระ',
            value: '${formatMoney(summary.penaltyFee)} บาท',
          ),
        if (showsTotal)
          LoanPaymentDetailRow(
            label: 'รวม',
            value: '${formatMoney(summary.overdueTotal)} บาท',
            strong: true,
          ),
      ];

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
