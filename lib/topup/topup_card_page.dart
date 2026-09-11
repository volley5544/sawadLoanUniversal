import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_state.dart';
import '../loan_register/components/loan_register_styles.dart';
import '../models/customer_detail.dart';
import '../p_loan/application/components/p_loan_components.dart';
import '../p_loan/application/models/loan_contract.dart';
import '../router/app_router.dart';
import '../services/native_bridge.dart';
import '../services/srisawad_api.dart';
import '../services/topup_api.dart';
import '../services/user_api.dart';
import 'components/topup_components.dart';
import 'models/topup_flow.dart';

/// **Step 1 — เลือกสัญญาที่ต้องการสินเชื่อเพิ่ม.** The top-up flow's entry
/// screen, and the port of the source's 8,183-line `TopupCardPage`.
///
/// Left out of that page on purpose, because none of it belongs to a top-up:
/// the taps that navigated into the loan-detail feature, the P-Loan Extra
/// hand-off (this repo already owns that — see `AppRoutes.pLoanTopupCardResume`)
/// and three dead duplicate card implementations. What remains is the part the
/// flow needs: list the customer's contracts, and for each one either start a
/// request or show the one already in flight.
///
/// Launch context comes from [AppState] (`?hashThaiId=` / `?token=`, resolved
/// per request) plus two optional attribution params this screen accepts and
/// passes through untouched:
///
/// ```
/// /topup?source=<...>&referId=<...>&contNo=<...>
/// ```
///
/// `contNo` preselects a contract, which is how the host deep-links straight
/// to one card.
class TopupCardPage extends StatefulWidget {
  const TopupCardPage({
    super.key,
    this.source = '',
    this.referId = '',
    this.contractNo = '',
    this.fromHost = false,
  });

  /// Attribution, carried into the submit payload verbatim.
  final String source;
  final String referId;

  /// Preselects this contract in the carousel when present.
  final String contractNo;

  /// True when the native host opened this route directly, so back has nothing
  /// beneath it and must close the WebView instead.
  final bool fromHost;

  @override
  State<TopupCardPage> createState() => _TopupCardPageState();
}

class _TopupCardPageState extends State<TopupCardPage> {
  final PageController _pageController = PageController(viewportFraction: 0.92);

  List<LoanContract>? _contracts;
  CustomerDetail? _customer;
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

  /// Fetches the profile and the contract list together.
  ///
  /// The profile is not optional here even though this screen barely shows it:
  /// the conclusion screen matches the ID-card photo against it, so a flow
  /// started without it could never be submitted. Failing now beats failing on
  /// step 7.
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
      final profileRequest =
          TopupApi.fetchCustomer(hashThaiId: hash, token: token);
      final contractsRequest =
          TopupApi.listContracts(hashThaiId: hash, token: token);
      final customer = await profileRequest;
      final contracts = await contractsRequest;
      if (!mounted) return;
      final selectable =
          contracts.where((c) => c.isSelectable).toList(growable: false);
      setState(() {
        _customer = customer;
        _contracts = selectable;
        _index = _preselectedIndex(selectable);
      });
      // The carousel is built after this frame, so jump once it exists.
      if (_index > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients) {
            _pageController.jumpToPage(_index);
          }
        });
      }
    } on UserApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on SrisawadApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Index of `?contNo=` in [contracts], or 0 when it isn't there.
  ///
  /// An unknown contract number lands on the first card rather than erroring:
  /// the customer can still pick, which is better than a dead end over a stale
  /// deep link.
  int _preselectedIndex(List<LoanContract> contracts) {
    if (widget.contractNo.isEmpty) return 0;
    final i = contracts.indexWhere((c) => c.contractNo == widget.contractNo);
    return i < 0 ? 0 : i;
  }

  /// Back on the flow's first screen. Nothing is beneath it when the host
  /// opened this route directly.
  void _back() {
    if (widget.fromHost && NativeCameraBridge.isSupported) {
      NativeCameraBridge.closeWebview();
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  /// Opens the status of the request already filed against [contract].
  void _openStatus(LoanContract contract) {
    context.push(
      Uri(
        path: AppRoutes.topupStatus,
        queryParameters: {
          'dbName': contract.dbName,
          'transNo': contract.transNo,
        },
      ).toString(),
    );
  }

  /// Starts a request against [contract] and opens step 2.
  void _start(LoanContract contract) {
    if (!contract.hasNoRequestYet) {
      _openStatus(contract);
      return;
    }
    if (!contract.isEligible) {
      final reason = contract.topupDetail.canTopupMsg;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(reason.isNotEmpty
            ? reason
            : 'สัญญานี้ยังไม่เข้าเงื่อนไขการขอสินเชื่อเพิ่ม'),
      ));
      return;
    }
    final appState = AppState();
    final flow = TopupFlow(
      hashThaiId: appState.hashThaiId,
      authToken: appState.authToken,
      entry: widget.fromHost ? TopupEntry.host : TopupEntry.menu,
      source: widget.source,
      referId: widget.referId,
    )
      ..contract = contract
      ..customer = _customer;
    context.push(AppRoutes.topupPurpose, extra: flow);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: topupAppBar(context, 'สินเชื่อเพิ่ม', onBack: _back),
      body: Column(
        children: [
          const PLoanMockBanner(),
          const TopupStepIndicator(1),
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
    if (contracts.isEmpty) {
      // The conditions still belong here: they are often *why* there is
      // nothing to show (pay on time, keep the credit record).
      return ListView(
        children: [
          const TopupConditionsPanel(),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'ไม่พบสัญญาที่สามารถขอสินเชื่อเพิ่มได้',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansThai(
                fontSize: 15,
                height: 1.6,
                color: LoanRegisterStyles.label,
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        const TopupConditionsPanel(),
        _header(contracts.length),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '« ปัดซ้าย-ขวา เพื่อดูสัญญาอื่น »',
            style: GoogleFonts.notoSansThai(
              fontSize: 12.5,
              color: LoanRegisterStyles.primary,
            ),
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: contracts.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 24),
              child: _TopupContractCard(
                contract: contracts[i],
                onSelect: () => _start(contracts[i]),
                onViewStatus: () => _openStatus(contracts[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          LoanRegisterStyles.padding, 8, LoanRegisterStyles.padding, 4),
      child: Row(
        children: [
          Text(
            'สัญญาของคุณ',
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
          _chevron(Icons.chevron_left, _index > 0, () {
            _pageController.previousPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.ease,
            );
          }),
          const SizedBox(width: 8),
          _chevron(Icons.chevron_right, _index < total - 1, () {
            _pageController.nextPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.ease,
            );
          }),
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
        child: Icon(icon,
            size: 22,
            color: enabled
                ? LoanRegisterStyles.primary
                : LoanRegisterStyles.label),
      ),
    );
  }
}

/// One contract in the carousel: what it is, what it offers, and the single
/// action available on it.
///
/// Three mutually exclusive states, decided in this order — a request already
/// filed wins over eligibility, because the customer cannot raise a second one
/// whatever `can_topup` says.
class _TopupContractCard extends StatelessWidget {
  const _TopupContractCard({
    required this.contract,
    required this.onSelect,
    required this.onViewStatus,
  });

  final LoanContract contract;
  final VoidCallback onSelect;
  final VoidCallback onViewStatus;

  @override
  Widget build(BuildContext context) {
    final detail = contract.topupDetail;
    final pending = !contract.hasNoRequestYet;
    final eligible = contract.isEligible;

    /// The special limit is granted on top of the default and is **not**
    /// included in it, so the headline figure has to add the two.
    final specials = contract.topupSpecialFlag ? detail.topupSpecials : 0;
    final offered = detail.defaultTopupAmount + specials;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: LoanRegisterStyles.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!pending && eligible) ...[
            _MaxTransferBanner(amount: detail.defaultTransferAmount.round()),
            const SizedBox(height: 12),
          ],
          ContractSummaryCard(
            loanTypeCode: contract.contractDetails.loanTypeCode,
            loanTypeName: contract.loanTypeName.isEmpty
                ? contract.contractDetails.loanTypeName
                : contract.loanTypeName,
            contractNo: contract.contractNo,
            collateralInformation:
                contract.contractDetails.collateralInformation,
          ),
          if (pending) ...[
            TopupNotice(
              'สัญญานี้มีคำขออยู่แล้ว (${contract.requestStatus})',
              icon: Icons.hourglass_top,
            ),
            PLoanAmountRow(
              label: 'ยอดที่ขอไว้',
              value: '${formatWholeMoney(contract.requestTopupAmount)} บาท',
              showDivider: false,
            ),
            const SizedBox(height: 8),
            TopupPrimaryButton(label: 'ดูสถานะคำขอ', onPressed: onViewStatus),
          ] else if (!eligible) ...[
            TopupNotice(
              detail.canTopupMsg.isNotEmpty
                  ? detail.canTopupMsg
                  : 'สัญญานี้ยังไม่เข้าเงื่อนไขการขอสินเชื่อเพิ่ม',
              icon: Icons.info_outline,
              tone: TopupNoticeTone.warning,
            ),
          ] else ...[
            const SizedBox(height: 12),
            _creditSummary(contract, detail, offered, specials),
            const SizedBox(height: 12),
            TopupPrimaryButton(label: 'เติมวงเงิน', onPressed: onSelect),
          ],
        ],
      ),
    );
  }

  /// The credit-summary block: the existing line, the appraisal, the new line,
  /// what closing the old contract costs, and what actually lands in the
  /// account.
  ///
  /// Every figure here is one the customer sees *before* committing, so they
  /// all come straight off `/loan/list` rather than being recomputed.
  Widget _creditSummary(
    LoanContract contract,
    TopupDetail detail,
    int offered,
    int specials,
  ) {
    final details = contract.contractDetails;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7FC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'วงเงินสินเชื่อ (สัญญา ${contract.contractNo})',
            style: GoogleFonts.notoSansThai(
              fontSize: 12.5,
              color: LoanRegisterStyles.label,
            ),
          ),
          const SizedBox(height: 8),
          _summaryLine('วงเงินสินเชื่อเดิม', details.creditLimit),
          _summaryLine(
              'ราคาประเมินหลักทรัพย์ปัจจุบัน', details.currentLtvAmount),
          Divider(height: 18, color: LoanRegisterStyles.divider),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'วงเงินสินเชื่อปัจจุบัน',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: LoanRegisterStyles.value,
                  ),
                ),
              ),
              Text(
                formatMoney(offered),
                style: GoogleFonts.notoSansThai(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: LoanRegisterStyles.value,
                ),
              ),
              Text(' บาท',
                  style: GoogleFonts.notoSansThai(
                      fontSize: 12, color: LoanRegisterStyles.label)),
            ],
          ),
          if (specials > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'รวมวงเงินพิเศษเพิ่มเติม ${formatMoney(specials)} บาท',
                style: GoogleFonts.notoSansThai(
                  fontSize: 12.5,
                  color: LoanRegisterStyles.required,
                ),
              ),
            ),
          Divider(height: 18, color: LoanRegisterStyles.divider),
          Row(
            children: [
              Expanded(
                child: Text(
                  // The date is when the contract data was fetched, not today
                  // — it rides on the payload as `data_date`.
                  'ยอดปิดบัญชี ณ วันที่ ${formatThaiDate(contract.dataDate)}',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 13,
                    color: LoanRegisterStyles.value,
                  ),
                ),
              ),
              Text(
                '-${formatMoney(detail.balanceReceivable)} บาท',
                style: GoogleFonts.notoSansThai(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: LoanRegisterStyles.value,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: LoanRegisterStyles.primarySoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 18, color: LoanRegisterStyles.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'เงินคงเหลือโอนเข้าบัญชี',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 13,
                      color: LoanRegisterStyles.value,
                    ),
                  ),
                ),
                Text(
                  '${formatMoney(detail.defaultTransferAmount)} บาท',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: LoanRegisterStyles.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, num value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.notoSansThai(
                  fontSize: 13,
                  color: LoanRegisterStyles.value,
                ),
              ),
            ),
            Text(
              formatMoney(value),
              style: GoogleFonts.notoSansThai(
                fontSize: 13.5,
                color: LoanRegisterStyles.value,
              ),
            ),
          ],
        ),
      );
}

/// The blue band at the top of an eligible contract card.
///
/// `default_transfer_amount` is the API's own headline — what the customer
/// would receive if they took the full line — so it is read, not recomputed.
class _MaxTransferBanner extends StatelessWidget {
  const _MaxTransferBanner({required this.amount});

  final int amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B3A6B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'รับเงินโอนเข้าบัญชีสูงสุด',
            style: GoogleFonts.notoSansThai(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('สูงสุด ',
                  style: GoogleFonts.notoSansThai(
                      fontSize: 14, color: Colors.white70)),
              Text(
                formatWholeMoney(amount),
                style: GoogleFonts.notoSansThai(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(' บาท',
                  style: GoogleFonts.notoSansThai(
                      fontSize: 14, color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'เพียงเติมวงเงินเต็มจำนวน รับเงินสดใช้จ่ายได้เลย '
                  'หลังปิดบัญชีเดิม',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 12,
                    height: 1.4,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
