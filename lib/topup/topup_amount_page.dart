import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../loan_register/components/loan_register_styles.dart';
import '../p_loan/application/components/p_loan_components.dart';
import '../router/app_router.dart';
import '../p_loan/application/models/loan_amount_detail.dart';
import '../services/srisawad_api.dart';
import '../services/topup_api.dart';
import 'components/topup_components.dart';
import 'models/topup_flow.dart';
import 'models/topup_lead_submission.dart';

/// **Step 3 — ยอดสินเชื่อที่ต้องการ.** The approved limit, the amount the
/// customer asks for, and what they will actually receive.
///
/// Three things make this screen different from the P-Loan Extra's equivalent,
/// and all three are the reason a top-up could not simply reuse it:
///
///  - **`min/max_topup_amount` apply.** They bound the top-up product, which
///    this is. (A P-Loan Extra deliberately ignores them — that product lends a
///    fixed `topup_extra` offer.)
///  - **The old principal comes off the payout.** A top-up closes the existing
///    contract out and reissues it larger, so `closing_balance` is deducted —
///    see [TopupFlow.payoutAmount].
///  - **The primary button is not always ถัดไป.** Unpaid accrued interest has
///    to be settled first (ชำระเงิน → the QR screen), and some contracts cannot
///    be self-served at all and file a lead instead (ส่งข้อมูล). See
///    [TopupFlow.outcome].
class TopupAmountPage extends StatefulWidget {
  const TopupAmountPage({super.key, required this.flow});

  final TopupFlow flow;

  @override
  State<TopupAmountPage> createState() => _TopupAmountPageState();
}

class _TopupAmountPageState extends State<TopupAmountPage> {
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocus = FocusNode();

  bool _loading = true;
  bool _recalculating = false;
  bool _submittingLead = false;
  String? _error;

  TopupFlow get _flow => widget.flow;

  @override
  void initState() {
    super.initState();
    _amountFocus.addListener(_onFocusChange);
    _load();
  }

  @override
  void dispose() {
    _amountFocus.removeListener(_onFocusChange);
    _amountFocus.dispose();
    _amountController.dispose();
    super.dispose();
  }

  /// `GET /topup/detail`, then price the seeded amount with
  /// `POST /topup/calculator`.
  ///
  /// The special limit is folded in between the two: `/topup/detail` does not
  /// include it, so without [TopupFlow.applySpecialLimit] the uplift the card
  /// advertised would be unavailable here.
  Future<void> _load() async {
    final contract = _flow.contract;
    if (contract == null) {
      setState(() {
        _loading = false;
        _error = 'ไม่พบข้อมูลสัญญา';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await TopupApi.fetchDetail(
        dbName: contract.dbName,
        contractNo: contract.contractNo,
        token: _flow.authToken,
      );
      if (!mounted) return;
      _flow.amountDetail = detail;
      _flow.applySpecialLimit();
      final seeded = _seedAmount();
      _flow.requestedAmount = seeded;
      final plan = await TopupApi.calculateInstallments(
        dbName: contract.dbName,
        contractNo: contract.contractNo,
        loanAmount: seeded,
        interestRate: _flow.amountDetail!.interestRate,
        feeAmount: _flow.amountDetail!.feeAmount,
        token: _flow.authToken,
      );
      if (!mounted) return;
      setState(() {
        _flow
          ..plan = plan
          // The duty the calculator returns is the one for the amount actually
          // requested; `/topup/detail`'s is for the contract's default limit.
          ..amountDetail = _flow.amountDetail!.copyWith(
            feeAmount: plan.feeAmount,
          );
        _amountController.text = formatWholeMoney(seeded);
        _loading = false;
      });
    } on SrisawadApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          // Outside 07:00–20:30 this is the API's own business-hours message,
          // not a fault — which is why it is shown verbatim with a retry
          // rather than translated into an error of ours.
          _error = e.message;
        });
      }
    }
  }

  /// The amount the screen opens with: whatever the customer already asked for
  /// on a previous visit, else the purpose's price, else the contract default.
  int _seedAmount() {
    final detail = _flow.amountDetail!;
    if (_flow.requestedAmount > 0) return _flow.requestedAmount;
    final purposePrice = _flow.purpose?.productPrice ?? 0;
    return purposePrice > 0 ? purposePrice : detail.defaultTopupAmount;
  }

  /// Strip separators while editing; on blur commit and re-price.
  void _onFocusChange() {
    if (_amountFocus.hasFocus) {
      _amountController.text = _amountController.text.replaceAll(',', '').trim();
      setState(() {});
      return;
    }
    _commitAmount();
  }

  /// Reads the field, rounds down to the nearest 100, stores it, and drops any
  /// plan priced for a different amount.
  void _commitTypedAmount() {
    final detail = _flow.amountDetail;
    if (detail == null) return;
    final typed = parseAmount(_amountController.text);
    // Clearing the field falls back to the contract's default rather than
    // leaving a zero that no calculator would accept.
    final amount =
        typed == 0 ? detail.defaultTopupAmount : roundDownToHundred(typed);
    _amountController.text = amount == 0 ? '' : formatWholeMoney(amount);
    if (amount != _flow.requestedAmount) {
      _flow
        ..requestedAmount = amount
        ..plan = null
        ..installment = null;
    }
  }

  Future<void> _commitAmount() async {
    if (_flow.amountDetail == null) return;
    _commitTypedAmount();
    setState(() {});
    // An unchanged amount is already priced; an out-of-range one shows inline
    // guidance instead of spending a call on a value the server will refuse.
    if (_flow.plan != null || !_flow.isRequestedAmountAllowed) return;
    await _recalculate();
  }

  /// Prices [TopupFlow.requestedAmount]. Returns true when options came back.
  Future<bool> _recalculate() async {
    final contract = _flow.contract;
    final detail = _flow.amountDetail;
    if (contract == null || detail == null) return false;
    setState(() => _recalculating = true);
    try {
      final plan = await TopupApi.calculateInstallments(
        dbName: contract.dbName,
        contractNo: contract.contractNo,
        loanAmount: _flow.requestedAmount,
        interestRate: detail.interestRate,
        feeAmount: detail.feeAmount,
        token: _flow.authToken,
      );
      if (!mounted) return false;
      setState(() {
        _flow
          ..plan = plan
          ..amountDetail = detail.copyWith(feeAmount: plan.feeAmount)
          ..installment = null;
        _recalculating = false;
      });
      return true;
    } on SrisawadApiException catch (e) {
      if (!mounted) return false;
      setState(() {
        // Drop the stale plan: it was priced for the previous amount, and
        // keeping it would let the customer continue with a schedule that does
        // not match what they asked for.
        _flow
          ..plan = null
          ..installment = null;
        _recalculating = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      return false;
    }
  }

  /// The primary button, which does one of three different things — see
  /// [TopupFlow.outcome].
  Future<void> _primaryAction() async {
    // First tap while the field has focus commits it; the recalculation that
    // follows lights the button for the advancing tap.
    if (_amountFocus.hasFocus) {
      _amountFocus.unfocus();
      return;
    }
    switch (_flow.outcome) {
      case TopupOutcome.payInterest:
        await _payInterest();
      case TopupOutcome.lead:
        await _fileLead();
      case TopupOutcome.topup:
        if (!(_flow.plan?.installments.isNotEmpty ?? false)) {
          final ok = await _recalculate();
          if (!ok || !mounted) return;
        }
        if (!mounted) return;
        context.push(AppRoutes.topupInstallment, extra: _flow);
    }
  }

  /// `POST /payment/interest` → the QR screen.
  ///
  /// The accrued interest has to be settled before a top-up can be raised, so
  /// this is a dead end for the top-up: the customer pays, and comes back.
  Future<void> _payInterest() async {
    final contract = _flow.contract;
    final detail = _flow.amountDetail;
    final customer = _flow.customer;
    if (contract == null || detail == null) return;
    setState(() => _submittingLead = true);
    try {
      // ⚠ Three things here are easy to get wrong, and all three produce a
      // 500 rather than a validation error:
      //
      //  - `comcode` is **`barcode_details.comcode`**, not
      //    `contract_details.comcode`. They are different fields with
      //    different values; this one identifies the biller.
      //  - `firstname`/`lastname` are split from the **contract holder's**
      //    name, not taken from the app user's profile. The two can differ,
      //    and the bill is raised against the contract.
      //  - the three amounts are **decimals**. Sending `2987` where the
      //    server expects `2987.84` both misstates the amount and changes the
      //    JSON type.
      final holder = _splitContractName(contract.contractName);
      await TopupApi.payInterest(
        token: _flow.authToken,
        payload: {
          'comcode': contract.barcodeDetails.comcode,
          'contract_no': contract.contractNo,
          'contract_name': contract.contractName,
          'firstname': holder.$1,
          'lastname': holder.$2,
          'national_thai_id': customer?.thaiId ?? '',
          'hash_thai_id': _flow.hashThaiId,
          'interest_amount': detail.interestYield,
          'collection_fee': detail.collectionFee,
          'penalty_fee': detail.penaltyFee,
          'db': detail.dbName,
          'barcode_ref1': contract.barcodeDetails.ref1,
          'barcode_ref2': contract.barcodeDetails.ref2,
        },
      );
      if (!mounted) return;
      setState(() => _submittingLead = false);
      // Awaited, and the screen reloads whichever way the customer comes back
      // — the QR screen's ปรับปรุงยอดชำระ, its back arrow, or a system back.
      //
      // ⚠ Without this the screen keeps the `/topup/detail` it loaded *before*
      // the payment, so `interest_paid_flag` is still 'Y' and it goes on
      // asking for money that has been paid. Popping does not re-run
      // `initState`, so nothing else would refetch it.
      await context.push(AppRoutes.topupQrPayment, extra: _flow);
      if (!mounted) return;
      await _load();
    } on SrisawadApiException catch (e) {
      if (!mounted) return;
      setState(() => _submittingLead = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Splits a contract holder's name into first and last.
  ///
  /// The source does `name.split(' ')[0]` and `[1]`, which throws RangeError
  /// on a single-word name and silently drops the rest of a three-part one.
  /// Here the first token is the given name and **everything after it** is the
  /// surname, and a name with no space yields an empty surname rather than
  /// crashing the payment.
  (String, String) _splitContractName(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return ('', '');
    if (parts.length == 1) return (parts.first, '');
    return (parts.first, parts.sublist(1).join(' '));
  }

  /// Files a lead and ends the flow on the success screen.
  Future<void> _fileLead() async {
    setState(() => _submittingLead = true);
    try {
      await TopupApi.saveLead(TopupLeadSubmission.fromFlow(_flow).fields);
      if (!mounted) return;
      setState(() => _submittingLead = false);
      context.go(
        Uri(
          path: AppRoutes.topupSuccess,
          queryParameters: const {'kind': 'lead'},
        ).toString(),
        extra: _flow,
      );
    } on SrisawadApiException catch (e) {
      if (!mounted) return;
      setState(() => _submittingLead = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: topupAppBar(context, 'ยอดสินเชื่อที่ต้องการ'),
      body: Column(
        children: [
          const PLoanMockBanner(),
          const TopupStepIndicator(2),
          Expanded(child: _body()),
        ],
      ),
      bottomNavigationBar: _loading || _error != null ? null : _bottomBar(),
    );
  }

  Widget _body() {
    final error = _error;
    if (error != null) return PLoanErrorView(message: error, onRetry: _load);
    if (_loading) {
      return const PLoanLoadingView(message: 'กำลังคำนวณวงเงิน...');
    }

    final detail = _flow.amountDetail!;
    final contract = _flow.contract!;
    final inRange = _flow.isRequestedAmountAllowed;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          LoanRegisterStyles.padding, 4, LoanRegisterStyles.padding, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ContractSummaryCard(
            loanTypeCode: contract.contractDetails.loanTypeCode,
            loanTypeName: contract.contractDetails.loanTypeName,
            contractNo: detail.contractNo,
            collateralInformation: detail.contractDetails.collateralInformation,
          ),
          if (detail.topupSpecials > 0)
            PLoanAmountRow(
              label: 'วงเงินพิเศษเพิ่มเติม',
              value: '${formatMoney(detail.topupSpecials)} บาท',
              emphasis: true,
            ),
          PLoanAmountRow(
            label: 'วงเงินสินเชื่อใหม่',
            value: '${formatMoney(detail.defaultTopupAmount)} บาท',
          ),
          PLoanAmountRow(
            label: 'ยอดเงินต้นคงเหลือสัญญาเดิม',
            value: '${formatMoney(detail.contractDetails.closingBalance)} บาท',
          ),
          const PLoanSectionHeader('วงเงินที่ต้องการกู้ใหม่'),
          _amountField(),
          if (_flow.isAmountEditable && !_flow.hasUnpaidInterest)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'เลื่อนเพื่อปรับลดวงเงิน',
                style: GoogleFonts.notoSansThai(
                  fontSize: 13,
                  color: LoanRegisterStyles.primary,
                ),
              ),
            ),
          if (_flow.hasUnpaidInterest)
            TopupNotice(
              'สัญญานี้มีดอกเบี้ยค้างชำระ ${formatMoney(detail.interestYield)} บาท '
              'กรุณาชำระก่อนทำรายการขอสินเชื่อเพิ่ม',
              icon: Icons.payments_outlined,
              tone: TopupNoticeTone.warning,
            )
          else if (!inRange)
            TopupNotice(
              'กรุณาระบุยอดระหว่าง ${formatWholeMoney(detail.minTopupAmount)} '
              'ถึง ${formatWholeMoney(detail.maxTopupAmount)} บาท',
              tone: TopupNoticeTone.warning,
            )
          else if (!_flow.isAmountEditable)
            TopupNotice(
              'ยอดนี้กำหนดตามวัตถุประสงค์ที่เลือกไว้ '
              '(${_flow.purpose?.productName ?? ''})',
            ),
          if (_flow.isAmountEditable && !_flow.hasUnpaidInterest) _slider(detail),
          const PLoanSectionHeader('รายการหัก'),
          // The numbered list, 1 / 2 / 3 / (4) / 5 — see
          // TopupFlow.deductionLines for why the sequence can skip 4.
          for (final line in _flow.deductionLines) TopupDeductionRow(line),
          PLoanAmountRow(
            label: 'จำนวนเงินที่จะได้รับ',
            value: '${formatMoney(_flow.receivableAmount)} บาท',
            large: true,
            emphasis: true,
            showDivider: false,
          ),
          if (_flow.outcome == TopupOutcome.lead)
            const TopupNotice(
              'สัญญานี้ไม่สามารถทำรายการผ่านแอปพลิเคชันได้ '
              'กดส่งข้อมูลเพื่อให้เจ้าหน้าที่ติดต่อกลับ',
              icon: Icons.support_agent,
            ),
        ],
      ),
    );
  }

  Widget _amountField() {
    final editable = _flow.isAmountEditable;
    return TextField(
      controller: _amountController,
      focusNode: _amountFocus,
      readOnly: !editable,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.right,
      style: GoogleFonts.notoSansThai(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: LoanRegisterStyles.value,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: editable ? Colors.white : LoanRegisterStyles.background,
        suffixText: 'บาท',
        suffixStyle: GoogleFonts.notoSansThai(
          fontSize: 14,
          color: LoanRegisterStyles.label,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: LoanRegisterStyles.cardBorder),
        ),
      ),
      onSubmitted: (_) => _amountFocus.unfocus(),
    );
  }

  /// Coarse adjustment between the contract's floor and ceiling.
  ///
  /// Committing on change-end rather than on every tick keeps this to one
  /// calculator call per drag instead of one per pixel.
  Widget _slider(LoanAmountDetail detail) {
    final min = detail.minTopupAmount;
    final max = detail.maxTopupAmount;
    if (max <= min) return const SizedBox.shrink();
    final value = _flow.requestedAmount.clamp(min, max).toDouble();
    return Column(
      children: [
        Slider(
          value: value,
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: ((max - min) ~/ 100).clamp(1, 1000),
          activeColor: LoanRegisterStyles.primary,
          label: formatWholeMoney(value.round()),
          onChanged: (v) {
            setState(() {
              _amountController.text = formatWholeMoney(roundDownToHundred(v.round()));
            });
          },
          onChangeEnd: (_) => _commitAmount(),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatWholeMoney(min),
                style: GoogleFonts.notoSansThai(
                    fontSize: 12, color: LoanRegisterStyles.label)),
            Text(formatWholeMoney(max),
                style: GoogleFonts.notoSansThai(
                    fontSize: 12, color: LoanRegisterStyles.label)),
          ],
        ),
      ],
    );
  }

  /// Re-prices the current amount on demand — the source's
  /// **ปรับปรุงยอดชำระ**.
  ///
  /// On the overdue screen this is how the customer refreshes the figures
  /// after paying, without the blur/slider interaction that drives the normal
  /// path. It re-reads `/topup/detail` as well as the calculator, because
  /// settling the interest changes `interest_paid_flag` and the whole screen
  /// with it.
  Future<void> _refreshFigures() async {
    setState(() => _recalculating = true);
    await _load();
    if (mounted) setState(() => _recalculating = false);
  }

  Widget? _bottomBar() {
    final busy = _recalculating || _submittingLead;
    final editing = _amountFocus.hasFocus;

    // Unpaid interest: the customer pays, then refreshes. Two buttons, as in
    // the source — ปรับปรุงยอดชำระ is the only way back from a payment the
    // app cannot observe.
    if (_flow.outcome == TopupOutcome.payInterest) {
      return Container(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: LoanRegisterStyles.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TopupPrimaryButton(
                label: 'ชำระเงิน',
                busy: _submittingLead,
                onPressed: busy ? null : _payInterest,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TopupPrimaryButton(
                label: 'ปรับปรุงยอดชำระ',
                outlined: true,
                busy: _recalculating,
                onPressed: busy ? null : _refreshFigures,
              ),
            ),
          ],
        ),
      );
    }

    final ready = switch (_flow.outcome) {
      TopupOutcome.payInterest => true,
      TopupOutcome.lead => true,
      TopupOutcome.topup =>
        _flow.isRequestedAmountAllowed && (editing || _flow.plan != null),
    };
    return PLoanBottomButton(
      label: editing && _flow.outcome == TopupOutcome.topup
          ? 'ยืนยันยอดเงิน'
          : _flow.primaryActionLabel,
      busy: busy,
      onPressed: ready && !busy ? _primaryAction : null,
    );
  }
}
