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
import 'components/loan_payment_components_old.dart';
import 'models/loan_payment_option_old.dart';
import 'models/loan_payment_seed.dart';

/// ⚠ **Superseded — kept for comparison only** (2026-09-17).
///
/// This is the pre-redesign ชำระเงิน screen, frozen at the version that
/// shipped before the new design landed, and routed at **`/loanPayment/old`**.
/// It carries **private copies** of everything it renders —
/// `loan_payment_components_old.dart` and `loan_payment_option_old.dart` — so
/// that editing the live screen, its components or its arithmetic cannot
/// change what this one shows. That is the whole point of the pair: the `_old`
/// page is what the redesign is compared *against*.
///
/// ⚠ **Delete the three `_old` files together** once the redesign is signed
/// off. They are a comparison aid, not a fallback — nothing routes here except
/// a hand-typed URL.
///
/// ⚠ It keeps the **old amounts** on purpose: `ชำระเต็มจำนวน` still adds the
/// collection fee to `current_due_amount` and `ยอดค้างชำระ` still omits the
/// penalty. The live screen corrected both on 2026-09-17 — see CLAUDE.md.
class LoanPaymentPageOld extends StatefulWidget {
  const LoanPaymentPageOld({
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
  State<LoanPaymentPageOld> createState() => _LoanPaymentPageStateOld();
}

class _LoanPaymentPageStateOld extends State<LoanPaymentPageOld> {
  LoanContract? _contract;
  String? _error;

  LoanPaymentOptionOld _option = LoanPaymentOptionOld.full;

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
  /// source's — see [LoanPaymentSummaryOld.blurredFieldText] for the ⚠ on the
  /// silent clamp.
  void _onAmountFocusChanged() {
    final contract = _contract;
    if (contract == null) return;
    if (_amountFocus.hasFocus) {
      final raw = parsePaymentAmountOld(_amountController.text);
      _amountController.text = raw == 0 ? '' : _amountController.text
          .replaceAll(',', '');
      return;
    }
    setState(() {
      _amountController.text =
          LoanPaymentSummaryOld(contract).blurredFieldText(_amountController.text);
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

  void _select(LoanPaymentOptionOld option) {
    if (_option == option) return;
    // Leaving the typed option commits whatever is in the field, so coming
    // back to it shows the same figure rather than a half-typed one.
    _amountFocus.unfocus();
    setState(() => _option = option);
  }

  void _onPay(LoanPaymentSummaryOld summary) {
    final rejection = summary.rejectionFor(_option, _amountController.text);
    if (rejection != null) {
      showLoanPaymentMessageOld(context, rejection);
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
    final summary = LoanPaymentSummaryOld(contract);

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
                for (final option in LoanPaymentOptionOld.values)
                  ..._optionBlock(option, summary),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        _payBar(summary),
      ],
    );
  }

  /// The option's header card, plus its detail cards when it is the selected
  /// one. They are **siblings**, not nested — see [LoanPaymentOptionCardOld].
  List<Widget> _optionBlock(
    LoanPaymentOptionOld option,
    LoanPaymentSummaryOld summary,
  ) =>
      [
        LoanPaymentOptionCardOld(
          label: option.label,
          amount: switch (option) {
            LoanPaymentOptionOld.full => '${formatMoney(summary.fullAmount)} บาท',
            LoanPaymentOptionOld.overdue =>
              '${formatMoney(summary.overdueTotal)} บาท',
            LoanPaymentOptionOld.custom => null,
          },
          selected: _option == option,
          onTap: () => _select(option),
        ),
        if (_option == option) ..._detailCards(option, summary),
      ];

  List<Widget> _detailCards(
    LoanPaymentOptionOld option,
    LoanPaymentSummaryOld summary,
  ) =>
      switch (option) {
        // Two cards, deliberately: what is late, then what is due next.
        LoanPaymentOptionOld.full => [
            if (summary.showsOverdueBlock)
              LoanPaymentDetailCardOld(
                heading: 'ค่างวดเลยกำหนดชำระ',
                children: _arrearsRows(summary, showsTotal: true),
              ),
            LoanPaymentDetailCardOld(
              heading: 'ค่างวดปัจจุบัน',
              children: [
                LoanPaymentDetailRowOld(
                  label: summary.currentInstallmentLabel,
                  value: '${formatMoney(summary.installmentAmount)} บาท',
                ),
                LoanPaymentDetailRowOld(
                  label: 'วันครบกำหนดชำระ',
                  value: summary.currentDueDate,
                ),
              ],
            ),
          ],
        LoanPaymentOptionOld.overdue => [
            if (summary.showsOverdueBlock)
              LoanPaymentDetailCardOld(
                heading: 'ค่างวดเลยกำหนดชำระ',
                // ⚠ **No รวม row unless there is a collection fee**, where
                // ชำระเต็มจำนวน always shows one. Not a tidy-up candidate: the
                // source guards this option's รวม behind `collection_fee != 0`
                // and the other option's not at all. With no fee the total
                // would only repeat the single row above it.
                children: _arrearsRows(
                  summary,
                  showsTotal: summary.showsCollectionFee,
                ),
              ),
            if (summary.showsNoOverdueNotice)
              const LoanPaymentDetailCardOld(
                heading: 'ค่างวดเลยกำหนดชำระ',
                children: [LoanPaymentNoticeOld(text: 'คุณไม่มียอดค้างชำระ')],
              ),
          ],
        LoanPaymentOptionOld.custom => [
            LoanPaymentDetailCardOld(
              heading: 'กำหนดยอดชำระ',
              children: [
                LoanPaymentNoticeOld(
                  text: '*การกำหนดยอดชำระเอง: การชำระค่างวดไม่เต็มจำนวน '
                      'จะมีดอกเบี้ยเพิ่มขึ้นและค่าติดตามทวงถามหนี้ (ถ้ามี) '
                      'ส่งผลให้ชำระหนี้ไม่ครบตามระยะเวลาที่กำหนด '
                      'สอบถามข้อมูลเพิ่มเติมติดต่อ 1652',
                  alert: true,
                ),
                // The standing statement of the ceiling — and, since the
                // ยอดหนี้คงเหลือ row was removed, the only place the rule
                // appears at all.
                const LoanPaymentNoticeOld(
                  text: '**ไม่สามารถระบุจำนวนเงินเกินยอดหนี้คงเหลือได้',
                  alert: true,
                ),
                const SizedBox(height: 12),
                LoanPaymentAmountFieldOld(
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
    LoanPaymentSummaryOld summary, {
    required bool showsTotal,
  }) =>
      [
        LoanPaymentDetailRowOld(
          label: summary.overdueRangeLabel,
          value: '${formatMoney(summary.overdueAmount)} บาท',
        ),
        if (summary.showsCollectionFee)
          LoanPaymentDetailRowOld(
            label: 'ค่าติดตามทวงถาม',
            value: '${formatMoney(summary.collectionFee)} บาท',
          ),
        if (showsTotal)
          LoanPaymentDetailRowOld(
            label: 'รวม',
            value: '${formatMoney(summary.overdueTotal)} บาท',
          ),
        LoanPaymentDetailRowOld(
          label: 'วันครบกำหนดชำระ',
          value: summary.overdueDueDate,
        ),
      ];

  Widget _payBar(LoanPaymentSummaryOld summary) {
    final disabled = summary.isDisabled(_option, _amountController.text);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
        child: LoanPaymentPrimaryButtonOld(
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
