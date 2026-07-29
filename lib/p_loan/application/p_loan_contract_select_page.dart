import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app_state.dart';
import '../../loan_register/components/loan_register_styles.dart';
import '../../loan_register/components/register_step_indicator.dart';
import '../../models/customer_detail.dart';
import '../../router/app_router.dart';
import '../../services/p_loan_api.dart';
import '../../services/srisawad_api.dart';
import '../../services/user_api.dart';
import 'components/p_loan_components.dart';
import 'models/loan_contract.dart';
import 'models/p_loan_flow.dart';

/// **Step 1 — เลือกประเภทสินเชื่อ.** Entry point for both P-Loan products; see
/// [PLoanKind].
///
///  - **ขอสินเชื่อใหม่** (new P-Loan) — the section at the top. A fresh loan at
///    an amount the customer types in themselves.
///  - **สินเชื่อเพิ่มจากสัญญาเดิม** (P-Loan Extra) — the contract carousel
///    below. More money against a contract they already have, bounded by its
///    approved limit.
///
/// Both then run the same five screens, but only an Extra picks a contract.
/// A new P-Loan has none — it is a fresh loan, and `refContractNo` is an
/// Extra's field — so **the new-loan card is offered even when the customer
/// has no contracts at all**, and the empty-list message speaks only for the
/// Extra below it.
///
/// This is the slimmed-down counterpart of the source's 8,257-line
/// `ploan_card_page01`. Deliberately left out: the add-on product grid (and the
/// Firestore `topupProductConfig` collection behind it), the "special limit"
/// offer cards, three dead duplicate card implementations, and the card taps
/// that navigated out into the top-up flow. What remains is the part the
/// P-Loan wizard actually needs — pick a contract, then continue.
class PLoanContractSelectPage extends StatefulWidget {
  const PLoanContractSelectPage({super.key});

  @override
  State<PLoanContractSelectPage> createState() =>
      _PLoanContractSelectPageState();
}

class _PLoanContractSelectPageState extends State<PLoanContractSelectPage> {
  final PageController _pageController = PageController(viewportFraction: 0.92);

  List<LoanContract>? _contracts;
  String? _error;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Fetches the profile and the contract list together. The profile is needed
  /// later (step 6 matches the ID card against it), so a failure here is fatal
  /// to the flow rather than something to skip past.
  Future<void> _load() async {
    setState(() {
      _error = null;
      _contracts = null;
    });
    final appState = AppState();
    final hash = appState.hashThaiId;
    if (hash.isEmpty) {
      setState(() => _error =
          'ไม่พบข้อมูลผู้ใช้ กรุณาเปิดหน้านี้จากแอปพลิเคชันอีกครั้ง');
      return;
    }
    try {
      final token = appState.authToken;
      // Kick both off before awaiting either, so they overlap.
      final profileRequest = PLoanApi.fetchCustomer(hashThaiId: hash);
      final contractsRequest =
          PLoanApi.listContracts(hashThaiId: hash, token: token);
      final customer = await profileRequest;
      final contracts = await contractsRequest;
      if (!mounted) return;
      setState(() {
        _customer = customer;
        _contracts =
            contracts.where((c) => c.isSelectable).toList(growable: false);
        // A retry can return a shorter list; the carousel position and the
        // new-loan card's reference both index into it.
        _index = 0;
      });
    } on UserApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on SrisawadApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  CustomerDetail? _customer;

  /// Starts a [kind] application and opens step 2.
  ///
  /// [contract] is the one being topped up, and is **null for a new P-Loan** —
  /// that product is not raised against anything, so it carries no contract
  /// through the flow at all.
  ///
  /// The two top-up preconditions below therefore apply to [PLoanKind.extra]
  /// only. Both describe whether *that contract* can be topped up — an
  /// in-flight top-up request, or a `can_topup` refusal — and neither says
  /// anything about whether the customer may take out a new loan.
  void _start(LoanContract? contract, {required PLoanKind kind}) {
    if (kind == PLoanKind.extra) {
      if (contract == null) return;
      if (!contract.hasNoRequestYet) {
        // A request is already in flight for this contract. The source pushed
        // its status screen here; that screen isn't part of this pass, so say
        // so rather than silently doing nothing.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('สัญญานี้มีคำขออยู่แล้ว (${contract.requestStatus})'),
        ));
        return;
      }
      if (!contract.isEligible) {
        final reason = contract.topupDetail.canTopupMsg;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(reason.isNotEmpty
              ? reason
              : 'สัญญานี้ยังไม่เข้าเงื่อนไขการขอสินเชื่อ'),
        ));
        return;
      }
    }
    final appState = AppState();
    final flow = PLoanFlow(
      hashThaiId: appState.hashThaiId,
      kind: kind,
      authToken: appState.authToken,
      customer: _customer,
      // Null for a new P-Loan, by the same reasoning as above.
      contract: kind == PLoanKind.extra ? contract : null,
      empId: appState.empId,
      mktChannel: appState.mktChannel,
      customerSource: appState.customerSource,
    );
    context.push(AppRoutes.pLoanAmount, extra: flow);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: pLoanAppBar(context, 'สมัครสินเชื่อส่วนบุคคล'),
      body: Column(
        children: [
          const PLoanMockBanner(),
          const RegisterStepIndicator(currentStep: 1, totalSteps: 6),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    final error = _error;
    if (error != null) {
      return PLoanErrorView(message: error, onRetry: _load);
    }
    final contracts = _contracts;
    if (contracts == null) {
      return const PLoanLoadingView(message: 'กำลังโหลดข้อมูลสัญญา...');
    }
    final newLoanCard =
        _NewPLoanCard(onStart: () => _start(null, kind: PLoanKind.newLoan));
    if (contracts.isEmpty) {
      // Only the Extra needs a contract. A new P-Loan is still available with
      // none, so this is a notice under the card rather than an error view
      // that ends the flow for both products.
      return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          newLoanCard,
          Padding(
            padding: const EdgeInsets.fromLTRB(
                LoanRegisterStyles.padding, 12, LoanRegisterStyles.padding, 0),
            child: Text(
              'ไม่พบสัญญาที่สามารถขอสินเชื่อเพิ่มได้\n'
              'คุณยังสามารถขอสินเชื่อใหม่ได้จากด้านบน',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansThai(
                fontSize: 14,
                height: 1.5,
                color: LoanRegisterStyles.label,
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        newLoanCard,
        _header(contracts.length),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: contracts.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 24),
              child: _ContractCard(
                contract: contracts[i],
                onSelect: () =>
                    _start(contracts[i], kind: PLoanKind.extra),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Title, position pill and the prev/next chevrons.
  Widget _header(int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          LoanRegisterStyles.padding, 8, LoanRegisterStyles.padding, 4),
      child: Row(
        children: [
          Text(
            PLoanKind.extra.label,
            style: GoogleFonts.notoSansThai(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: LoanRegisterStyles.value,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: LoanRegisterStyles.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${_index + 1}/$total',
              style: GoogleFonts.notoSansThai(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: LoanRegisterStyles.primary,
              ),
            ),
          ),
          const Spacer(),
          _chevron(Icons.chevron_left, _index > 0,
              () => _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.ease,
                  )),
          const SizedBox(width: 8),
          _chevron(Icons.chevron_right, _index < total - 1,
              () => _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.ease,
                  )),
        ],
      ),
    );
  }

  Widget _chevron(IconData icon, bool enabled, VoidCallback onTap) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled
                ? LoanRegisterStyles.primary
                : LoanRegisterStyles.divider,
          ),
        ),
        child: Icon(
          icon,
          size: 22,
          color:
              enabled ? LoanRegisterStyles.primary : LoanRegisterStyles.label,
        ),
      ),
    );
  }
}

/// One contract in the picker: identity, limits, and the action that enters
/// the flow.
class _ContractCard extends StatelessWidget {
  const _ContractCard({required this.contract, required this.onSelect});

  final LoanContract contract;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final details = contract.contractDetails;
    final topup = contract.topupDetail;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ContractSummaryCard(
            loanTypeCode: details.loanTypeCode,
            loanTypeName: details.loanTypeName,
            contractNo: contract.contractNo,
            collateralInformation: details.collateralInformation,
          ),
          if (contract.requestStatus.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _statusPill(),
            ),
          const SizedBox(height: 4),
          PLoanAmountRow(
            label: 'วงเงินสินเชื่อเดิม',
            value: '${formatMoney(details.creditLimit)} บาท',
          ),
          PLoanAmountRow(
            label: 'ราคาประเมินปัจจุบัน',
            value: '${formatMoney(details.currentLtvAmount)} บาท',
          ),
          PLoanAmountRow(
            label: 'ยอดปิดบัญชี',
            caption: contract.dataDate.isEmpty
                ? null
                : 'ณ วันที่ ${formatThaiDate(contract.dataDate)}',
            value: '-${formatWholeMoney(topup.balanceReceivable)} บาท',
          ),
          if (topup.topupExtra != 0)
            PLoanAmountRow(
              label: 'วงเงินเพิ่มเติม',
              value: formatMoney(topup.topupExtra),
              emphasis: true,
            ),
          PLoanAmountRow(
            label: 'วงเงินสินเชื่อปัจจุบัน',
            value: '${formatMoney(topup.defaultTopupAmount)} บาท',
            large: true,
            showDivider: false,
          ),
          if (!contract.isEligible) _ineligibleNotice(topup.canTopupMsg),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onSelect,
              icon: const Icon(Icons.add_card_outlined, size: 20),
              style: ElevatedButton.styleFrom(
                backgroundColor: LoanRegisterStyles.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              label: Text(
                'ขอสินเชื่อเพิ่มจากสัญญานี้',
                style: GoogleFonts.notoSansThai(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill() {
    final pending = !contract.hasNoRequestYet;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: pending
            ? const Color(0xFFD3FFF8)
            : LoanRegisterStyles.primarySoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined,
              size: 14,
              color: pending
                  ? LoanRegisterStyles.value
                  : LoanRegisterStyles.label),
          const SizedBox(width: 6),
          Text(
            contract.requestStatus,
            style: GoogleFonts.notoSansThai(
              fontSize: 12,
              color: pending
                  ? LoanRegisterStyles.value
                  : LoanRegisterStyles.label,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ineligibleNotice(String message) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LoanRegisterStyles.primarySoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message.isNotEmpty ? message : 'สัญญานี้ยังไม่เข้าเงื่อนไข',
        textAlign: TextAlign.center,
        style: GoogleFonts.notoSansThai(
          fontSize: 13,
          color: LoanRegisterStyles.required,
        ),
      ),
    );
  }
}

/// The **ขอสินเชื่อใหม่** section at the top of step 1.
///
/// Styled as a soft-filled panel rather than one of the white contract cards,
/// so it reads as a separate product and not as another contract in the list.
///
/// It names no contract, and is shown whether or not the customer has any: a
/// new P-Loan is a fresh loan, raised against nothing.
class _NewPLoanCard extends StatelessWidget {
  const _NewPLoanCard({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
          LoanRegisterStyles.padding, 10, LoanRegisterStyles.padding, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LoanRegisterStyles.primarySoft,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
            color: LoanRegisterStyles.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.request_quote_outlined,
                  size: 22, color: LoanRegisterStyles.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  PLoanKind.newLoan.label,
                  style: GoogleFonts.notoSansThai(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: LoanRegisterStyles.value,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            PLoanKind.newLoan.description,
            style: GoogleFonts.notoSansThai(
              fontSize: 13,
              color: LoanRegisterStyles.label,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 46,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.edit_outlined, size: 18),
              style: ElevatedButton.styleFrom(
                backgroundColor: LoanRegisterStyles.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              label: Text(
                'ระบุวงเงินที่ต้องการเอง',
                style: GoogleFonts.notoSansThai(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
