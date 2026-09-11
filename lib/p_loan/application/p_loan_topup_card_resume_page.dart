import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_state.dart';
import '../../loan_register/components/loan_register_styles.dart';
import '../../router/app_router.dart';
import '../../services/native_bridge.dart';
import '../../services/p_loan_api.dart';
import '../../services/srisawad_api.dart';
import '../../models/customer_detail.dart';
import '../../services/user_api.dart';
import 'components/p_loan_components.dart';
import 'models/loan_amount_detail.dart';
import 'models/loan_contract.dart';
import 'models/p_loan_flow.dart';

/// **Entry point for a P-Loan Extra deep-linked from the LandAndHouseWeb
/// top-up card** (`/pLoan/resume?dbName=…&contractNo=…`).
///
/// The customer taps สินเชื่อเพิ่ม on the top-up card; the native host opens
/// this build in a fresh WebView pointed here. The card has already shown them
/// the approved amount, so steps 1 and 2 are redundant — this screen rebuilds
/// what those steps would have produced and lands on **step 3 (จำนวนงวด)**.
///
/// It exists because the flow's state is a mutable [PLoanFlow] passed as
/// go_router `extra`: steps 2–6 redirect to step 1 without one, so a URL cannot
/// enter mid-flow directly. Rather than serialise the whole object into the
/// query string, this re-runs the **same calls step 2 makes** from a minimal
/// key (`db_name` + `contract_no`), which also means a refresh reproduces the
/// state instead of resuming a stale copy of it.
///
/// **This build's own top-up card seeds it instead** ([PLoanResumeSeed]),
/// because that screen already holds the contract and the customer — the two
/// fetches below would re-read what is in memory. The fetching path stays for
/// the deep link and for a reload, so the refresh property is unaffected.
///
/// Deliberately not a redirect on the step-3 route: rebuilding needs four
/// awaited API calls, which wants a loading and an error state of its own.
/// Data this route can be handed instead of re-fetching it.
///
/// Only the **in-app** caller has it: this build's own top-up card has already
/// loaded `/loan/list` and `/user/detail` to draw its carousel, so making the
/// resume screen ask for both again is a second round trip the customer waits
/// through for data already in memory.
///
/// ⚠ It is deliberately **optional**, and the fetching path stays. The route's
/// other two callers have nothing to hand over — the LandAndHouseWeb card
/// reaches it through the host in a *fresh WebView*, and a reload drops
/// `extra` — so seeding is an optimisation on one path, never a requirement.
/// That also preserves the property the query-string design was chosen for: a
/// refresh reproduces the state rather than resuming a stale copy.
class PLoanResumeSeed {
  const PLoanResumeSeed({required this.contract, this.customer});

  /// The contract row as `/loan/list` returned it. Must match the route's
  /// `dbName` + `contractNo`, or it is ignored and re-fetched.
  final LoanContract contract;

  /// The customer profile, when the caller has it. Null still saves the
  /// `/loan/list` call.
  final CustomerDetail? customer;

  /// Whether this seed is for [dbName] / [contractNo].
  ///
  /// Guards against a seed and a URL that disagree — the URL wins, because it
  /// is what a reload would use and the two must not resolve differently.
  bool matches(String dbName, String contractNo) =>
      contract.dbName == dbName && contract.contractNo == contractNo;
}

class PLoanTopupCardResumePage extends StatefulWidget {
  const PLoanTopupCardResumePage({
    super.key,
    required this.dbName,
    required this.contractNo,
    this.amount,
    this.seed,
  });

  /// `db_name` + `contract_no` of the contract the top-up is raised against —
  /// the only two values the top-up card has to pass.
  final String dbName;
  final String contractNo;

  /// Requested amount, when the card let the customer choose one.
  ///
  /// Omitted, the amount is `/topup/detail`'s `topup_extra` — the วงเงินเพิ่มเติม
  /// the card displays, which is the fixed offer this product lends. See
  /// [LoanAmountDetail.topupCardRequestAmount].
  final int? amount;

  /// Contract and customer already in memory, when the caller has them — see
  /// [PLoanResumeSeed]. Null on the deep link and on a reload, which is when
  /// this screen fetches.
  final PLoanResumeSeed? seed;

  @override
  State<PLoanTopupCardResumePage> createState() =>
      _PLoanTopupCardResumePageState();
}

class _PLoanTopupCardResumePageState extends State<PLoanTopupCardResumePage> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _resume();
  }

  /// Rebuilds the flow steps 1–2 would have produced, then replaces this route
  /// with step 3.
  ///
  /// `pushReplacement`, not `push`: this screen has no content of its own to
  /// come back to, and leaving it on the stack would make back from step 3
  /// re-run the whole rebuild.
  Future<void> _resume() async {
    setState(() => _error = null);
    final appState = AppState();
    final hash = appState.hashThaiId;

    if (hash.isEmpty) {
      setState(() => _error =
          'ไม่พบข้อมูลผู้ใช้ กรุณาเปิดหน้านี้จากแอปพลิเคชันอีกครั้ง');
      return;
    }
    if (widget.dbName.isEmpty || widget.contractNo.isEmpty) {
      setState(() => _error = 'ไม่พบเลขที่สัญญาที่ต้องการขอสินเชื่อเพิ่ม');
      return;
    }

    try {
      final token = appState.authToken;

      // A seed from this build's own top-up card skips /loan/list and
      // /user/detail — it fetched both to draw the carousel the customer just
      // tapped, so asking again is a round trip spent on data already in
      // memory. Ignored unless it is for this contract: the URL is what a
      // reload uses, so the two must never resolve differently.
      final seed = widget.seed;
      final seeded =
          seed != null && seed.matches(widget.dbName, widget.contractNo);

      final LoanContract contract;
      final CustomerDetail? customer;

      if (seeded) {
        contract = seed.contract;
        // The profile is only *usually* on the seed; fetch it alone if not,
        // rather than giving up the /loan/list saving too.
        customer = seed.customer ??
            await PLoanApi.fetchCustomer(hashThaiId: hash, token: token);
      } else {
        // Same overlap as step 1: both are needed, neither depends on the
        // other.
        final profileRequest =
            PLoanApi.fetchCustomer(hashThaiId: hash, token: token);
        final contractsRequest =
            PLoanApi.listContracts(hashThaiId: hash, token: token);
        customer = await profileRequest;
        final contracts = await contractsRequest;

        // /loan/list is the only source for the payout account, comcode and
        // branch code, so the contract is looked up rather than reconstructed
        // from the two query params.
        try {
          contract = contracts.firstWhere((c) =>
              c.contractNo == widget.contractNo && c.dbName == widget.dbName);
        } on StateError {
          setState(() => _error =
              'ไม่พบสัญญาเลขที่ ${widget.contractNo} ในรายการสัญญาของท่าน');
          return;
        }
      }

      // The same three preconditions step 1 checks before starting an Extra.
      // Checked here too because this route bypasses that screen entirely.
      if (!contract.isSelectable) {
        setState(() =>
            _error = 'สัญญานี้ไม่สามารถขอสินเชื่อเพิ่มได้');
        return;
      }
      if (!contract.hasNoRequestYet) {
        setState(() => _error =
            'สัญญานี้มีคำขออยู่แล้ว (${contract.requestStatus})');
        return;
      }
      if (!contract.isEligible) {
        final reason = contract.topupDetail.canTopupMsg;
        setState(() => _error = reason.isNotEmpty
            ? reason
            : 'สัญญานี้ยังไม่เข้าเงื่อนไขการขอสินเชื่อ');
        return;
      }

      final detail = await PLoanApi.fetchAmountDetail(
        dbName: contract.dbName,
        contractNo: contract.contractNo,
        token: token,
      );

      // `topup_extra` — the วงเงินเพิ่มเติม the top-up card shows — unless the
      // card passed an amount. Null means there is no offer on this contract;
      // min/max_topup_amount are not consulted, so there is no out-of-range
      // case left to report. See [LoanAmountDetail.extraRequestAmount].
      final requested = detail.topupCardRequestAmount(requested: widget.amount);
      if (requested == null) {
        setState(() => _error =
            'ไม่พบวงเงินที่สามารถขอสินเชื่อเพิ่มได้สำหรับสัญญานี้');
        return;
      }

      final plan = await PLoanApi.calculateInstallments(
        dbName: contract.dbName,
        contractNo: contract.contractNo,
        loanAmount: requested,
        interestRate: detail.interestRate,
        feeAmount: detail.feeAmount,
        token: token,
      );
      if (plan.installments.isEmpty) {
        setState(() => _error = 'ไม่พบตัวเลือกจำนวนงวดสำหรับยอดที่ขอ');
        return;
      }
      if (!mounted) return;

      final flow = PLoanFlow(
        hashThaiId: hash,
        // Only an Extra reaches this route — the top-up card is a contract the
        // customer already holds.
        kind: PLoanKind.extra,
        entry: PLoanEntry.topupCard,
        authToken: token,
        customer: customer,
        contract: contract,
        // The duty for the amount actually requested, as step 2 folds it in.
        amountDetail: detail.copyWith(feeAmount: plan.feeAmount),
        empId: appState.empId,
        mktChannel: appState.mktChannel,
        customerSource: appState.customerSource,
      )
        ..requestedAmount = requested
        ..plan = plan;

      context.pushReplacement(AppRoutes.pLoanInstallment, extra: flow);
    } on UserApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on SrisawadApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Back out to the top-up card that opened this WebView.
  void _close() {
    if (NativeCameraBridge.isSupported) {
      NativeCameraBridge.closeWebview();
      return;
    }
    // Plain browser: nothing to close, so fall back to this app's own home.
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: pLoanAppBar(context, 'ขอสินเชื่อเพิ่ม', onBack: _close),
      body: Column(
        children: [
          const PLoanMockBanner(),
          Expanded(
            child: error == null
                ? const PLoanLoadingView(message: 'กำลังเตรียมข้อมูลสินเชื่อ...')
                : PLoanErrorView(message: error, onRetry: _resume),
          ),
        ],
      ),
    );
  }
}
