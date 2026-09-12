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
import 'components/topup_redesign.dart';
import 'models/topup_flow.dart';
import 'models/topup_lead_submission.dart';
import 'models/topup_settlement.dart';

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

  /// The **ยอดที่ต้องชำระเพื่อเติมวงเงิน** breakdown from
  /// `POST /GetRecalTopupData`, re-read whenever the amount is re-priced.
  ///
  /// Null means *no section* — and every way of getting null renders the same
  /// screen: an unconfigured build, an unreachable gateway, or a contract with
  /// nothing outstanding. That is deliberate; see [TopupApi.recalculate].
  TopupRecalculation? _recal;
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
      await _loadSettlement();
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
      await _loadSettlement();
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

  /// Re-reads the settlement breakdown for the amount now being requested.
  ///
  /// **Never throws and never blocks the screen.** The breakdown is priced per
  /// `topup_amount`, so it is refreshed with every calculator run — but a
  /// top-up is perfectly requestable without one, and the endpoint is not
  /// reachable from a browser at all today (see `kTopupRecalApiBase`). So a
  /// failure clears the section rather than failing the page.
  ///
  /// ⚠ The old breakdown is cleared *before* the call, not after: leaving the
  /// previous amount's rows on screen while a new amount is priced would show
  /// a settlement that does not belong to the figure above it.
  Future<void> _loadSettlement() async {
    final contract = _flow.contract;
    if (contract == null) return;
    if (mounted) setState(() => _recal = null);
    final recal = await TopupApi.recalculate(
      dbName: contract.dbName,
      contractNo: contract.contractNo,
      topupAmount: _flow.requestedAmount,
    );
    if (mounted) setState(() => _recal = recal);
  }

  /// Whether the **ยอดที่ต้องชำระเพื่อเติมวงเงิน** block is on screen.
  ///
  /// `settlement_items` alone decides it (instructed 2026-09-12) — see
  /// [TopupRecalculation.hasSettlement].
  bool get _showsSettlement => _recal?.hasSettlement ?? false;

  /// What the bottom bar does.
  ///
  /// [TopupFlow.outcome] stays the authority: it is what protects the
  /// unpaid-interest and lead paths, and it works without the recalculation
  /// endpoint, which a web build cannot currently reach at all. The one thing
  /// the breakdown adds is an **upgrade**: rows to settle mean there is
  /// something to pay, so a contract that would otherwise advance gets the
  /// design's ชำระเงิน / ปรับปรุงยอดชำระ pair instead of ถัดไป.
  ///
  /// It never downgrades. A lead contract stays a lead however the settlement
  /// reads, and unpaid interest still blocks with no rows on screen.
  TopupOutcome get _outcome {
    final outcome = _flow.outcome;
    if (outcome == TopupOutcome.topup && _showsSettlement) {
      return TopupOutcome.payInterest;
    }
    return outcome;
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
    switch (_outcome) {
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

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                LoanRegisterStyles.padding, 8, LoanRegisterStyles.padding, 14),
            child: TopupContractHeader(
              loanTypeCode: contract.contractDetails.loanTypeCode,
              loanTypeName: contract.contractDetails.loanTypeName,
              contractNo: detail.contractNo,
              collateralInformation:
                  detail.contractDetails.collateralInformation,
              // No status pill here. The card already showed it, and by this
              // screen the customer has acted on it.
            ),
          ),
          // ── M35 ───────────────────────────────────────────────────────
          // The uplift is broken back out only here. The card shows one
          // combined figure; this screen has to explain where it came from,
          // because the customer is about to choose a number inside it.
          if (detail.topupSpecials > 0)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: LoanRegisterStyles.padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TopupFigureRow(
                    label: 'ยอดจัดสินเชื่อเดิม',
                    amount: detail.defaultTopupAmount - detail.topupSpecials,
                    emphasis: true,
                    suffix: 'บาท',
                  ),
                  _specialLimitRow(detail.topupSpecials),
                ],
              ),
            ),
          const SizedBox(height: 6),
          _newLimitBar(detail.defaultTopupAmount),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                LoanRegisterStyles.padding, 14, LoanRegisterStyles.padding, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _conditionsNote(),
                const SizedBox(height: 14),
                Text(
                  'วงเงินสินเชื่อที่ต้องการกู้ใหม่',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: LoanRegisterStyles.primary,
                  ),
                ),
                const SizedBox(height: 4),
                _amountField(),
                if (_flow.isAmountEditable && !_flow.hasUnpaidInterest) ...[
                  Text(
                    'เลื่อนเพื่อปรับลดวงเงิน',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 12.5,
                      color: LoanRegisterStyles.primary,
                    ),
                  ),
                  _slider(detail),
                ],
                if (!_flow.isRequestedAmountAllowed)
                  TopupNotice(
                    'กรุณาระบุยอดระหว่าง '
                    '${formatWholeMoney(detail.minTopupAmount)} '
                    'ถึง ${formatWholeMoney(detail.maxTopupAmount)} บาท',
                    tone: TopupNoticeTone.warning,
                    accent: TopupTheme.alert,
                  )
                else if (!_flow.isAmountEditable)
                  TopupNotice(
                    'ยอดนี้กำหนดตามวัตถุประสงค์ที่เลือกไว้ '
                    '(${_flow.purpose?.productName ?? ''})',
                  ),
                const SizedBox(height: 6),
                TopupFigureRow(
                  label: 'หัก ยอดเงินต้นคงที่ยังไม่ถึงกำหนดชำระ',
                  caption: '(เลขที่สัญญา ${detail.contractNo})',
                  amount: _flow.closingBalance,
                  deduction: true,
                  suffix: 'บาท',
                ),
                TopupFigureRow(
                  label: 'หัก อากรแสตมป์สัญญาใหม่',
                  amount: _flow.feeAmount,
                  deduction: true,
                  suffix: 'บาท',
                ),
                const Divider(height: 20),
                TopupFigureRow(
                  label: 'เงินคงเหลือโอนเข้าบัญชี',
                  amount: _flow.payoutAmount,
                  emphasis: true,
                  suffix: 'บาท',
                ),
              ],
            ),
          ),
          if (_showsSettlement) _settlementBlock(_recal!),
          if (_flow.outcome == TopupOutcome.lead)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: LoanRegisterStyles.padding),
              child: const TopupNotice(
                'สัญญานี้ไม่สามารถทำรายการผ่านแอปพลิเคชันได้ '
                'กดส่งข้อมูลเพื่อให้เจ้าหน้าที่ติดต่อกลับ',
                icon: Icons.support_agent,
              ),
            ),
        ],
      ),
    );
  }

  /// `+5,000.00` — the M35 วงเงินพิเศษ, drawn in the accent colour because it
  /// is the only row on this screen that *adds*.
  Widget _specialLimitRow(int specials) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              'วงเงินพิเศษเพิ่มเติม',
              style: GoogleFonts.notoSansThai(
                fontSize: 13,
                color: LoanRegisterStyles.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '+${formatTopupMoney(specials)}',
            style: GoogleFonts.notoSansThai(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: LoanRegisterStyles.primary,
            ),
          ),
          const SizedBox(width: 6),
          Text('บาท', style: TopupTheme.label(size: 13)),
        ],
      ),
    );
  }

  /// The blue **วงเงินสินเชื่อใหม่สูงสุด** bar — the ceiling the amount below
  /// is chosen within, and the same blue as the card's band by design.
  Widget _newLimitBar(int amount) {
    return Container(
      color: TopupTheme.band,
      padding: const EdgeInsets.symmetric(
          horizontal: LoanRegisterStyles.padding, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              'วงเงินสินเชื่อใหม่สูงสุด',
              style: GoogleFonts.notoSansThai(
                fontSize: 14.5,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            formatTopupMoney(amount),
            style: GoogleFonts.notoSansThai(
              fontSize: 19,
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text('บาท',
              style: GoogleFonts.notoSansThai(
                  fontSize: 13, color: Colors.white)),
        ],
      ),
    );
  }

  /// The เงื่อนไข note. The rounding rule is stated because the field enforces
  /// it silently — typing 96,050 and being handed 96,000 back is otherwise
  /// indistinguishable from the app losing the input.
  Widget _conditionsNote() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'เงื่อนไข',
          style: GoogleFonts.notoSansThai(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: LoanRegisterStyles.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'คุณสามารถแก้ไขยอดขอสินเชื่อใหม่ได้ '
          '(ระบบจะปัดเป็นจำนวนเต็มร้อยเท่านั้น)',
          style: TopupTheme.label(size: 12.5),
        ),
      ],
    );
  }

  /// **ยอดที่ต้องชำระเพื่อเติมวงเงิน** — the server's breakdown, rendered
  /// exactly as sent.
  ///
  /// Every row is `settlement_items`' own Thai `description` in `seq` order,
  /// numbered by position; the client names nothing. The total is
  /// `settlement_total_amount` **as sent**, never re-added from the rows —
  /// this is a bill, and a client that disagrees with the server about it is
  /// worse than one that cannot explain it.
  Widget _settlementBlock(TopupRecalculation recal) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
          LoanRegisterStyles.padding, 18, LoanRegisterStyles.padding, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LoanRegisterStyles.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ยอดที่ต้องชำระเพื่อเติมวงเงิน',
            style: TopupTheme.value(size: 15.5, weight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            '*กรุณาชำระเงินก่อนดำเนินการ',
            style: GoogleFonts.notoSansThai(
                fontSize: 11.5, color: TopupTheme.alert),
          ),
          const SizedBox(height: 10),
          Text('รายละเอียด', style: TopupTheme.label(size: 13)),
          const SizedBox(height: 4),
          for (var i = 0; i < recal.settlementItems.length; i++)
            _settlementRow(i + 1, recal.settlementItems[i]),
          const Divider(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text('รวมยอดที่ต้องชำระ',
                    style:
                        TopupTheme.value(size: 14.5, weight: FontWeight.w700)),
              ),
              Text(
                formatTopupMoney(recal.settlementTotalAmount),
                style: GoogleFonts.notoSansThai(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: LoanRegisterStyles.primary,
                ),
              ),
              const SizedBox(width: 6),
              Text('บาท', style: TopupTheme.label(size: 12.5)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '*สัญญามีผู้ค้ำกรุณาติดต่อสาขาเพื่อทำรายการเติมเงินพร้อมกับผู้ค้ำ',
            style: GoogleFonts.notoSansThai(
                fontSize: 11.5, height: 1.4, color: TopupTheme.alert),
          ),
        ],
      ),
    );
  }

  Widget _settlementRow(int number, TopupSettlementItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text('$number.', style: TopupTheme.label(size: 13)),
          ),
          // The server's own wording, shown verbatim — the client has no
          // mapping table and must not grow one.
          Expanded(child: Text(item.description,
              style: TopupTheme.label(size: 13))),
          const SizedBox(width: 8),
          Text(formatTopupMoney(item.amount),
              style: TopupTheme.value(size: 13.5, weight: FontWeight.w600)),
          const SizedBox(width: 5),
          Text('บาท', style: TopupTheme.label(size: 12)),
        ],
      ),
    );
  }

  /// The requested amount, as the design draws it: a large plain figure with
  /// `บาท` pushed to the right margin, no box.
  ///
  /// It is still a real text field — the customer may type — but the chrome is
  /// gone because on this screen the number *is* the content. A read-only flow
  /// (a purpose-priced request) greys the value rather than showing a disabled
  /// input, which would look broken next to a slider that is also absent.
  Widget _amountField() {
    final editable = _flow.isAmountEditable;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: TextField(
            controller: _amountController,
            focusNode: _amountFocus,
            readOnly: !editable,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: GoogleFonts.notoSansThai(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: editable
                  ? LoanRegisterStyles.value
                  : LoanRegisterStyles.label,
            ),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 6),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            onSubmitted: (_) => _amountFocus.unfocus(),
          ),
        ),
        const SizedBox(width: 8),
        Text('บาท', style: TopupTheme.label(size: 14)),
      ],
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
            Text(formatTopupMoney(min), style: TopupTheme.label(size: 11.5)),
            Text(formatTopupMoney(max), style: TopupTheme.label(size: 11.5)),
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
    final outcome = _outcome;

    // Two buttons whenever there is something to settle first — the design's
    // pair, and the only way back from a payment this app cannot observe.
    // ปรับปรุงยอดชำระ re-reads /topup/detail as well as the calculator,
    // because settling changes interest_paid_flag and the whole screen with
    // it; the QR screen deliberately refreshes nothing itself, so that two
    // screens cannot disagree about whether the money is still owed.
    if (outcome == TopupOutcome.payInterest) {
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

    final ready = switch (outcome) {
      TopupOutcome.payInterest => true,
      TopupOutcome.lead => true,
      TopupOutcome.topup =>
        _flow.isRequestedAmountAllowed && (editing || _flow.plan != null),
    };
    return PLoanBottomButton(
      label: editing && outcome == TopupOutcome.topup
          ? 'ยืนยันยอดเงิน'
          : outcome == TopupOutcome.topup
              ? 'ถัดไป'
              : _flow.primaryActionLabel,
      busy: busy,
      onPressed: ready && !busy ? _primaryAction : null,
    );
  }
}
