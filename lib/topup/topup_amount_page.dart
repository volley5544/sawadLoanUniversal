import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_environment.dart';
import '../loan_register/components/loan_register_styles.dart';
import '../p_loan/application/components/p_loan_components.dart';
import '../router/app_router.dart';
import '../p_loan/application/models/loan_amount_detail.dart';
import '../services/diagnostics.dart';
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

  /// True while a settlement read is in flight — i.e. while [_recal] is null
  /// but not yet *known* to be null.
  ///
  /// ⚠ **The primary button is disabled for exactly this window**, and that is
  /// a correctness gate, not a spinner. [TopupFlow.outcome] upgrades ถัดไป to
  /// ชำระเงิน only once there are rows to settle, so during the gap the button
  /// says ถัดไป — and a customer who taps it walks past interest they owe. The
  /// window is real on a re-price too, where [_loadSettlement] deliberately
  /// clears the old rows *before* fetching the new ones.
  bool _settlementPending = false;
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
      // `POST /topup/recal`, not `GET /topup/detail` (2026-09-14, on
      // instruction). One call carries the limits *and* the settlement, so
      // the two can no longer disagree on screen.
      //
      // ⚠ It has to be asked for an amount before it will tell us the limits,
      // which the seed would normally come from — so the first call uses the
      // contract's own `topup_detail.default_topup_amount` from `/loan/list`,
      // which the card has already loaded. The screen re-seeds from the
      // response immediately after.
      final askedFor = _flow.requestedAmount > 0
          ? _flow.requestedAmount
          : contract.topupDetail.defaultTopupAmount;
      final first = await TopupApi.fetchRecal(
        dbName: contract.dbName,
        contractNo: contract.contractNo,
        topupAmount: askedFor,
        token: _flow.authToken,
      );
      if (!mounted) return;
      _flow.amountDetail = first.detail;
      _flow.applySpecialLimit();
      final seeded = _seedAmount();
      _flow.requestedAmount = seeded;
      _recal = first.recalculation;
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
      // ⚠ **No second settlement read here.** `fetchRecal` above already
      // returned one, and calling `_loadSettlement()` again clears `_recal`
      // and re-fetches it *after* `_loading` goes false — so the screen
      // rendered complete, the ยอดที่ต้องชำระเพื่อเติมวงเงิน section then
      // vanished for a round trip and came back. During that gap
      // [TopupFlow.outcome] saw no rows and the button said **ถัดไป**, letting
      // a customer walk past interest they owe. Reported 2026-09-14.
      //
      // The only case the first response does not cover is a seed that differs
      // from the amount it was priced at — `_seedAmount` can return a purpose
      // price or a previously-typed figure. Then, and only then, re-read.
      if (seeded != askedFor) await _loadSettlement();
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
    if (mounted) {
      setState(() {
        _recal = null;
        _settlementPending = true;
      });
    }
    try {
      final res = await TopupApi.fetchRecal(
        dbName: contract.dbName,
        contractNo: contract.contractNo,
        // The contract's base limit, not what the customer asked for — see
        // TopupFlow.settlementPricingAmount for why the requested figure is
        // refused on a contract carrying an M35 uplift.
        topupAmount: _flow.settlementPricingAmount,
        token: _flow.authToken,
      );
      if (!mounted) return;
      setState(() {
        _recal = res.recalculation;
        _settlementPending = false;
      });
    } on SrisawadApiException catch (e) {
      // ⚠ A re-read failing does **not** fail the screen, unlike the same call
      // in [_load]. By this point the limits are already on screen and still
      // valid; only the settlement is stale, and a top-up amount is
      // requestable without one. The reason is kept for the non-prod notice
      // rather than shown to the customer.
      if (!mounted) return;
      TopupApi.lastRecalFailure =
          'topup recal ${e.statusCode ?? ''} ${e.message}'.trim();
      Diagnostics.log(TopupApi.lastRecalFailure!);
      // Known-absent, not unknown: the button is released.
      setState(() {
        _recal = null;
        _settlementPending = false;
      });
    }
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
      appBar: topupAppBar(context, 'ข้อมูลยอดจัดสินเชื่อ'),
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
              // ⚠ From the contract, not the amount detail: `/topup/recal`
              // sends its `contract_details` block blank, so reading it there
              // renders an empty line under the contract number.
              collateralInformation:
                  contract.contractDetails.collateralInformation.isNotEmpty
                      ? contract.contractDetails.collateralInformation
                      : detail.contractDetails.collateralInformation,
              // No status pill here. The card already showed it, and by this
              // screen the customer has acted on it.
            ),
          ),
          // ── M35 ───────────────────────────────────────────────────────
          // The uplift is broken back out only here. The card shows one
          // combined figure; this screen has to explain where it came from,
          // because the customer is about to choose a number inside it.
          //
          // ⚠ These two rows **decompose** the bar below them, they do not add
          // to it: `default_topup_amount` already contains `topup_extra`
          // (confirmed 2026-09-14), so
          // `topup_actual + topup_extra == defaultTopupAmount`. Reading the
          // base as `default − extra` gave the same answer only while the
          // client was also double-counting the uplift into the default; now
          // it would subtract it twice. `topup_actual` is the base the API
          // states, so take it rather than deriving it.
          if (_flow.specialLimit > 0)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: LoanRegisterStyles.padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TopupStackedFigure(
                    label: 'ยอดจัดสินเชื่อเดิม',
                    value: formatTopupMoney(_flow.baseLimit),
                  ),
                  const SizedBox(height: 10),
                  TopupStackedFigure(
                    label: 'วงเงินพิเศษเพิ่มเติม',
                    // The one figure on the screen that adds, so it carries an
                    // explicit `+`. It stays in the value colour rather than
                    // the accent orange it had: the screenshot draws this pair
                    // as two readings of the same kind, and colouring one of
                    // them made the uplift look like a separate offer instead
                    // of a term of the sum above the bar.
                    value: '+${formatTopupMoney(_flow.specialLimit)}',
                  ),
                  const SizedBox(height: 12),
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
                const SizedBox(height: 8),
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
                  ),
                // ⚠ A `ยอดนี้กำหนดตามวัตถุประสงค์ที่เลือกไว้ (<product>)` notice
                // used to sit here when the amount was fixed. Removed
                // 2026-09-13 on request. It only ever had a product name to
                // quote when the customer arrived via a สิทธิพิเศษเฉพาะคุณ
                // tile, and that section is hidden on the redesigned card — so
                // in practice it rendered with empty parentheses, explaining
                // the locked field by naming nothing. `_old` keeps it, being a
                // comparison aid. The field's own `readOnly` is what states the
                // rule now.
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
          if (_showsSettlement)
            _settlementBlock(_recal!)
          else
            _settlementDebugNotice(),
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

  /// A **non-prod** stand-in for the settlement block, shown whenever there
  /// are no rows and [TopupApi.lastRecalFailure] says why.
  ///
  /// The customer-facing rule is unchanged: no rows, no section. But "no
  /// section" has at least five causes that look identical from the screen —
  /// no credential in the build, the host's allowlist refusing the URL, a
  /// browser blocking mixed content, the server refusing the amount, or a
  /// contract with genuinely nothing to settle — and on 2026-09-13 telling
  /// them apart took a day and a grep of the deployed bundle. This turns that
  /// into one tap.
  ///
  /// Hidden on prod along with [EnvVersionTag] and the diagnostics sheet: it
  /// names the endpoint and quotes the server verbatim.
  Widget _settlementDebugNotice() {
    final failure = TopupApi.lastRecalFailure;
    if (failure == null || AppEnvironment.current.isProd) {
      return const SizedBox.shrink();
    }
    final summary = failure.split('\n').first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          LoanRegisterStyles.padding, 14, LoanRegisterStyles.padding, 0),
      child: InkWell(
        onTap: () => _showSettlementFailure(failure),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF6E5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE8C89A)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Color(0xFF8A6D3B)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ไม่มีรายการที่ต้องชำระ (debug) — $summary',
                  style: GoogleFonts.notoSansThai(
                      fontSize: 11.5, color: const Color(0xFF8A6D3B)),
                ),
              ),
              const Icon(Icons.chevron_right, size: 16, color: Color(0xFF8A6D3B)),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettlementFailure(String failure) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ยอดที่ต้องชำระเพื่อเติมวงเงิน',
            style: TopupTheme.value(size: 15, weight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: SelectableText(
            failure,
            style: const TextStyle(fontSize: 11.5, height: 1.45),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: failure));
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('คัดลอก'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('ปิด'),
          ),
        ],
      ),
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
  /// The **ยอดที่ต้องชำระเพื่อเติมวงเงิน** block, rebuilt 2026-09-14 to the
  /// supplied design.
  ///
  /// Three things changed and each is deliberate:
  ///
  /// - **the total sits in a full-width grey band**, not under a hairline
  ///   divider. It closes the block the way a bill's total line does, and it is
  ///   the only element here the customer has to act on;
  /// - **rows are navy, not label grey.** They were styled as captions, which
  ///   read as footnotes to the payout above rather than as the bill itself;
  /// - **the figures are larger and heavier than the labels beside them**, so a
  ///   column of amounts scans without reading the Thai.
  ///
  /// ⚠ **No card around it** (changed 2026-09-14 on request): a divider above
  /// the heading separates it instead. That is what lets the grey band run
  /// **edge to edge**, the same full-bleed idiom as the blue
  /// วงเงินสินเชื่อใหม่สูงสุด bar further up this screen — boxed, the band could
  /// only ever be as wide as the card's inside, which read as a panel within a
  /// panel. Content keeps the page gutter; only the band ignores it.
  Widget _settlementBlock(TopupRecalculation recal) {
    const gutter =
        EdgeInsets.symmetric(horizontal: LoanRegisterStyles.padding);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        Divider(height: 1, thickness: 1, color: LoanRegisterStyles.divider),
        const SizedBox(height: 4),
        Padding(
          padding: gutter.copyWith(top: 10, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ยอดที่ต้องชำระเพื่อเติมวงเงิน',
                style: TopupTheme.value(size: 18, weight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                '*กรุณาชำระเงินก่อนดำเนินการ',
                style: GoogleFonts.notoSansThai(
                    fontSize: 12, color: TopupTheme.alert),
              ),
              const SizedBox(height: 12),
              Text('รายละเอียด', style: TopupTheme.label(size: 13.5)),
              const SizedBox(height: 2),
              for (var i = 0; i < recal.settlementItems.length; i++)
                _settlementRow(i + 1, recal.settlementItems[i]),
            ],
          ),
        ),
        // The total's own band. Full width by design — see the class note.
        Container(
          color: LoanRegisterStyles.divider,
          padding: gutter.copyWith(top: 13, bottom: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text('รวมยอดที่ต้องชำระ',
                    style:
                        TopupTheme.value(size: 15, weight: FontWeight.w700)),
              ),
              Text(
                // Displayed **as sent**, never summed from the rows above —
                // see TopupRecalculation.itemsSumMatchesTotal.
                formatTopupMoney(recal.settlementTotalAmount),
                style: GoogleFonts.notoSansThai(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: LoanRegisterStyles.primary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'บาท',
                style: GoogleFonts.notoSansThai(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  // The unit takes the figure's colour, as everywhere else on
                  // these screens — a grey บาท breaks the phrase in half.
                  color: LoanRegisterStyles.primary,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: gutter.copyWith(top: 10, bottom: 12),
          child: Text(
            '*สัญญามีผู้ค้ำกรุณาติดต่อสาขาเพื่อทำรายการเติมเงินพร้อมกับผู้ค้ำ',
            // Orange, not alert red (2026-09-14, on request) — the same
            // reasoning as the card's `*เมื่อชำระยอดเพื่อเติมวงเงิน`: it
            // qualifies *how* the payment is made rather than warning about
            // the total above it, and in red under a total it read as a
            // problem with the total.
            style: GoogleFonts.notoSansThai(
                fontSize: 11.5,
                height: 1.4,
                color: LoanRegisterStyles.primary),
          ),
        ),
      ],
    );
  }

  Widget _settlementRow(int number, TopupSettlementItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text('$number.',
                style: TopupTheme.value(size: 14.5, weight: FontWeight.w500)),
          ),
          // The server's own wording, shown verbatim — the client has no
          // mapping table and must not grow one.
          Expanded(
            child: Text(item.description,
                style: TopupTheme.value(size: 14.5, weight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          Text(formatTopupMoney(item.amount),
              style: TopupTheme.value(size: 15, weight: FontWeight.w700)),
          const SizedBox(width: 5),
          Text('บาท',
              style: TopupTheme.value(size: 13.5, weight: FontWeight.w600)),
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
        Text('บาท',
            style: TopupTheme.value(size: 16, weight: FontWeight.w700)),
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
    // `_settlementPending` is here for safety, not for feedback — see the
    // field's doc. Without it the button reverts to ถัดไป while a re-price is
    // in flight and lets the customer past a payment they still owe.
    final busy = _recalculating || _submittingLead || _settlementPending;
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
                tonal: true,
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
