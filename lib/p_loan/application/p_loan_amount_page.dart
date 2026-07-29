import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../loan_register/components/loan_register_styles.dart';
import '../../loan_register/components/register_step_indicator.dart';
import '../../router/app_router.dart';
import '../../services/p_loan_api.dart';
import '../../services/srisawad_api.dart';
import 'components/p_loan_components.dart';
import 'models/loan_amount_detail.dart';
import 'models/loan_contract.dart';
import 'models/p_loan_flow.dart';

/// **Step 2 — ข้อมูลยอดจัดสินเชื่อ.** Shows the approved limit and lets the
/// customer request an amount within it, recalculating the installment options
/// whenever the amount changes.
///
/// Serves both products (see [PLoanKind]):
///
///  - **P-Loan Extra** — pre-filled with the contract's approved limit and
///    bounded by `min/max_topup_amount`; the old contract's principal is shown
///    as a deduction.
///  - **New P-Loan** — the field starts **blank** and the customer types the
///    amount they want. There is no contract, so no bound is inherited and
///    there is no old principal to deduct — neither is shown, and no
///    `/topup/*` call is made. The calculator only runs once an amount has
///    been entered.
///
/// In the source this screen's entire input block — amount field, slider and
/// validation — sat behind `if (FFAppState().savePLoanData.isNewPLoan)`, and
/// `savePLoanData` was never assigned anywhere in that project, so it always
/// rendered read-only. That flag is [PLoanFlow.isNewPLoan] here, and the input
/// is enabled for both kinds, following the behaviour that dead code
/// documented: round down to the nearest 100 on commit, then re-run the
/// calculator.
class PLoanAmountPage extends StatefulWidget {
  const PLoanAmountPage({super.key, required this.flow});

  final PLoanFlow flow;

  @override
  State<PLoanAmountPage> createState() => _PLoanAmountPageState();
}

class _PLoanAmountPageState extends State<PLoanAmountPage> {
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocus = FocusNode();

  bool _loading = true;
  bool _recalculating = false;
  String? _error;

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

  PLoanFlow get _flow => widget.flow;

  /// Fetches the limits, and — for an Extra only — the installment options for
  /// its default amount.
  ///
  /// A **new P-Loan** makes no call here at all, and needs no contract: it has
  /// none. `GET /topup/detail` is keyed by `db_name` + `contract_no`, so it is
  /// unreachable, and nothing on the screen needs it before an amount is
  /// entered — the rate and stamp duty come from the calculator, run on the
  /// customer's own amount from the Next button (see [_proceed]).
  Future<void> _load() async {
    if (_flow.isNewPLoan) {
      // An empty detail: this product has no approved limit, no old principal
      // and no contract to read either off. The calculator fills in the rate
      // and duty. Reused when returning from a later step so the priced values
      // and the typed amount survive a back-navigation.
      _flow.amountDetail ??= const LoanAmountDetail(code: '200');
      _amountController.text = _flow.requestedAmount > 0
          ? formatWholeMoney(_flow.requestedAmount)
          : '';
      setState(() {
        _loading = false;
        _error = null;
      });
      return;
    }
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
      final detail = await PLoanApi.fetchAmountDetail(
        dbName: contract.dbName,
        contractNo: contract.contractNo,
        token: _flow.authToken,
      );
      final amount = detail.defaultTopupAmount;
      final plan = await PLoanApi.calculateInstallments(
        dbName: contract.dbName,
        contractNo: contract.contractNo,
        loanAmount: amount,
        interestRate: detail.interestRate,
        feeAmount: detail.feeAmount,
        token: _flow.authToken,
      );
      if (!mounted) return;
      _flow
        ..amountDetail = detail.copyWith(feeAmount: plan.feeAmount)
        ..requestedAmount = amount
        ..plan = plan;
      _amountController.text = formatWholeMoney(amount);
      setState(() => _loading = false);
    } on SrisawadApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  /// Strip separators while editing; on blur commit the rounded value and
  /// recalculate.
  void _onFocusChange() {
    if (_amountFocus.hasFocus) {
      _amountController.text =
          _amountController.text.replaceAll(',', '').trim();
      // Rebuild so the bottom button switches to its commit role while the
      // field is being edited — see _bottomBar.
      setState(() {});
      return;
    }
    _commitAmount();
  }

  /// Reads the field, rounds down to the nearest 100, and stores it as the
  /// requested amount, dropping any plan priced for a different one.
  ///
  /// A null plan afterwards is the signal that the amount changed and needs
  /// (re)pricing — [_commitAmount] and [_proceed] both key off it.
  void _commitTypedAmount() {
    final detail = _flow.amountDetail;
    final typed = parseAmount(_amountController.text);
    // Clearing the field falls back to the approved limit for an Extra; for a
    // new P-Loan there is no such default, so blank stays blank.
    final amount = typed == 0 && !_flow.isNewPLoan
        ? (detail?.defaultTopupAmount ?? 0)
        : roundDownToHundred(typed);
    _amountController.text = amount == 0 ? '' : formatWholeMoney(amount);
    if (amount != _flow.requestedAmount) {
      _flow
        ..requestedAmount = amount
        // A new amount invalidates any earlier plan and the tenor picked on
        // step 3 from it.
        ..plan = null
        ..installment = null;
    }
  }

  /// On blur: commit the typed amount. An **Extra** re-prices here as before; a
  /// **new P-Loan** defers pricing to the Next button, so it stops after the
  /// commit (see [_proceed]).
  Future<void> _commitAmount() async {
    final detail = _flow.amountDetail;
    if (detail == null) return;

    _commitTypedAmount();
    setState(() {});

    if (_flow.isNewPLoan) return;
    final contract = _flow.contract;
    if (contract == null) return;
    // Unchanged amount is already priced (plan survived the commit), and
    // out-of-range values show inline guidance instead of calling the API.
    if (_flow.plan != null || !_flow.isRequestedAmountAllowed) return;
    await _recalculate(detail, contract);
  }

  /// Prices [PLoanFlow.requestedAmount] and folds the result into the flow.
  /// Returns true when a usable plan came back.
  ///
  /// An **Extra** hits `POST /topup/calculator` (hence [contract], which only
  /// it has). A **new P-Loan** has no calculator endpoint yet, so it uses the
  /// client-side estimate from [PLoanApi.calculateNewLoanInstallments] — see
  /// that method for why.
  Future<bool> _recalculate(
      LoanAmountDetail detail, LoanContract? contract) async {
    if (!_flow.isNewPLoan && contract == null) return false;
    setState(() => _recalculating = true);
    try {
      final plan = _flow.isNewPLoan
          ? await PLoanApi.calculateNewLoanInstallments(
              loanAmount: _flow.requestedAmount,
            )
          : await PLoanApi.calculateInstallments(
              dbName: contract!.dbName,
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
          // An Extra only refreshes the duty; a new P-Loan skipped
          // /topup/detail, so the rate and duty come from the plan itself
          // (the provisional estimate for now) — fold them in.
          ..amountDetail = _flow.isNewPLoan
              ? detail.copyWith(
                  feeAmount: plan.feeAmount,
                  interestRate: plan.interestRate,
                  dueDay: plan.dueDay,
                  firstDueDate: plan.firstDueDate,
                )
              : detail.copyWith(feeAmount: plan.feeAmount)
          // A new amount invalidates any tenor picked on step 3.
          ..installment = null;
        _recalculating = false;
      });
      return true;
    } on SrisawadApiException catch (e) {
      if (!mounted) return false;
      setState(() {
        // Drop the previous plan: it was priced for the previous amount, and
        // leaving it in place would let the user advance to step 3 with an
        // installment schedule that does not match what they asked for. Much
        // easier to hit on a new P-Loan, where the amount is free-form and the
        // calculator is the thing that rejects it.
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

  /// The Next button. An **Extra** is already priced (on blur), so it just
  /// advances. A **new P-Loan** commits the typed amount and prices it here —
  /// the flow's first and only `POST /topup/calculator` call for a new loan —
  /// then advances once options come back.
  Future<void> _proceed() async {
    final detail = _flow.amountDetail;
    final contract = _flow.contract;
    if (detail == null) return;

    if (!_flow.isNewPLoan) {
      if (contract == null) return;
      // First tap while editing commits the field (mirrors the old behaviour);
      // the on-blur calculation then lights the button for the advancing tap.
      if (_amountFocus.hasFocus) {
        _amountFocus.unfocus();
        return;
      }
      if (!(_flow.plan?.installments.isNotEmpty ?? false)) return;
      context.push(AppRoutes.pLoanInstallment, extra: _flow);
      return;
    }

    _amountFocus.unfocus();
    _commitTypedAmount();
    setState(() {});
    if (!_flow.isRequestedAmountAllowed) return;
    if (_flow.plan == null) {
      final ok = await _recalculate(detail, contract);
      if (!ok) return;
    }
    if (!mounted) return;
    context.push(AppRoutes.pLoanInstallment, extra: _flow);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: pLoanAppBar(context, 'ข้อมูลยอดจัดสินเชื่อ'),
      body: Column(
        children: [
          const PLoanMockBanner(),
          PLoanKindBanner(kind: _flow.kind),
          RegisterStepIndicator(
              currentStep: _flow.stepNumber(2), totalSteps: _flow.totalSteps),
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
    // Extra only — a new P-Loan has no contract at all.
    final contract = _flow.contract;
    final isNew = _flow.isNewPLoan;
    // Only an Extra can be locked: the flag means interest was prepaid on the
    // contract being topped up, which says nothing about a new loan.
    final locked = !isNew && detail.isAmountLocked;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(LoanRegisterStyles.padding, 4,
          LoanRegisterStyles.padding, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Extra only — a new P-Loan has no contract to summarise.
          if (!isNew && contract != null)
            ContractSummaryCard(
              loanTypeCode: contract.contractDetails.loanTypeCode,
              loanTypeName: contract.contractDetails.loanTypeName,
              contractNo: detail.contractNo,
              collateralInformation:
                  detail.contractDetails.collateralInformation,
            ),
          // The approved-limit rows describe this contract's top-up headroom.
          // A new P-Loan is not drawn from it, so showing them would read as a
          // cap that does not apply.
          if (!isNew) ...[
            if (detail.topupExtra != 0)
              PLoanAmountRow(
                label: 'วงเงินเพิ่มเติม',
                value: '${formatMoney(detail.topupExtra)} บาท',
                emphasis: true,
              ),
            PLoanAmountRow(
              label: 'วงเงินสินเชื่อใหม่',
              value: '${formatMoney(detail.defaultTopupAmount)} บาท',
              large: true,
            ),
          ],
          const PLoanSectionHeader('เงื่อนไข'),
          Text(
            isNew
                ? 'กรุณาระบุวงเงินที่ต้องการขอสินเชื่อ '
                    '(ยอดจัดสินเชื่อ ระบบจะปัดเป็นจำนวนเต็มร้อยเท่านั้น) '
                    'วงเงินที่อนุมัติจริงขึ้นอยู่กับผลการพิจารณา'
                : 'คุณสามารถแก้ไขยอดขอสินเชื่อใหม่ได้ แต่จำนวนเงินต้องอยู่ระหว่าง '
                    '${formatMoney(detail.minTopupAmount)} - '
                    '${formatMoney(detail.maxTopupAmount)} บาท '
                    '(ยอดจัดสินเชื่อ ระบบจะปัดเป็นจำนวนเต็มร้อยเท่านั้น)',
            style: GoogleFonts.notoSansThai(
              fontSize: 13,
              color: LoanRegisterStyles.label,
              height: 1.5,
            ),
          ),
          PLoanSectionHeader(
              isNew ? 'วงเงินที่ต้องการ' : 'วงเงินที่ต้องการกู้ใหม่'),
          _amountField(locked, isNew),
          _validationMessage(detail, _flow.requestedAmount, isNew),
          const SizedBox(height: 8),
          if (locked)
            Text(
              '* ยอดขอสินเชื่อถูกกำหนดไว้แล้ว เนื่องจากมีการชำระดอกเบี้ยล่วงหน้า',
              style: GoogleFonts.notoSansThai(
                fontSize: 12,
                color: LoanRegisterStyles.label,
              ),
            ),
          const PLoanSectionHeader('รายการหัก'),
          // A new P-Loan closes no old contract, so there is no principal to
          // deduct — only the stamp duty.
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
        ],
      ),
    );
  }

  Widget _amountField(bool locked, bool isNew) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: 200,
          child: TextField(
            controller: _amountController,
            focusNode: _amountFocus,
            readOnly: locked,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
              LengthLimitingTextInputFormatter(12),
            ],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _amountFocus.unfocus(),
            style: GoogleFonts.notoSansThai(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: locked ? LoanRegisterStyles.label : LoanRegisterStyles.value,
            ),
            decoration: InputDecoration(
              hintText: isNew
                  ? 'กรอกวงเงินที่ต้องการ'
                  : 'กรอกวงเงินที่ต้องการกู้ใหม่',
              hintStyle: GoogleFonts.notoSansThai(
                fontSize: 15,
                color: LoanRegisterStyles.label,
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: LoanRegisterStyles.divider),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: LoanRegisterStyles.primary),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'บาท',
            style: GoogleFonts.notoSansThai(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: LoanRegisterStyles.value,
            ),
          ),
        ),
        if (_recalculating) ...[
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: LoanRegisterStyles.primary),
            ),
          ),
        ],
      ],
    );
  }

  /// The two inline bound messages the source defined, for an Extra.
  ///
  /// A new P-Loan has no inherited bounds — the customer names the amount — so
  /// the only thing checked here is that they have named one. Whether the
  /// product will price it is the calculator's answer, surfaced as its own
  /// message rather than pre-empted with an invented limit.
  Widget _validationMessage(LoanAmountDetail detail, int amount, bool isNew) {
    if (isNew) {
      if (amount < PLoanFlow.newLoanMinimumAmount) {
        return _hint('* กรุณาระบุวงเงินที่ต้องการ '
            '(ไม่น้อยกว่า ${formatMoney(PLoanFlow.newLoanMinimumAmount)} บาท)');
      }
      return const SizedBox.shrink();
    }
    if (amount < detail.minTopupAmount) {
      return _hint('* จำนวนเงินต้องไม่น้อยกว่า '
          '${formatMoney(detail.minTopupAmount)} บาท');
    }
    if (amount > detail.maxTopupAmount) {
      return _hint('* ต้องการวงเงินมากกว่า '
          '${formatMoney(detail.maxTopupAmount)} บาท '
          'สามารถติดต่อสาขาใกล้บ้านที่สะดวก');
    }
    return const SizedBox.shrink();
  }

  Widget _hint(String message) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          message,
          style: GoogleFonts.notoSansThai(
            fontSize: 13,
            color: LoanRegisterStyles.required,
          ),
        ),
      );

  Widget _bottomBar() {
    final editing = _amountFocus.hasFocus;
    // A new P-Loan can proceed as soon as a valid amount is typed — the Next
    // button itself runs the calculator (see [_proceed]). An Extra needs the
    // on-blur calculation to have produced a plan first.
    final ready = _flow.isNewPLoan
        ? _flow.requestedAmount >= PLoanFlow.newLoanMinimumAmount
        : _flow.isRequestedAmountAllowed &&
            (_flow.plan?.installments.isNotEmpty ?? false);
    // Enabled while editing even when not yet `ready`, so the one tap the user
    // makes right after typing isn't dead: for a new P-Loan that tap commits
    // and prices in one go; for an Extra it commits and the on-blur calculation
    // lights the button for the advancing tap.
    return PLoanBottomButton(
      label: 'ถัดไป',
      busy: _recalculating,
      onPressed: (_recalculating || !(ready || editing)) ? null : _proceed,
    );
  }
}
