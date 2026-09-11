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
import 'models/topup_card_variant.dart';
import 'models/topup_flow.dart';
import 'models/topup_purpose.dart';

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
  List<LoanContract>? _contracts;
  CustomerDetail? _customer;
  String? _error;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _load();
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
  ///
  /// [product] is set when the customer tapped a สิทธิพิเศษเฉพาะคุณ tile
  /// rather than the plain button: that picks the purpose for them, so step 2
  /// opens with it already chosen and step 3 prices it.
  void _start(LoanContract contract, {LoanProduct? product}) {
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
    if (product != null) {
      flow
        ..purpose = TopupPurpose(
          productCode: product.productCode,
          productName: product.productName,
          productDescription: product.productDescription,
          productPrice: product.productPrice,
        )
        ..requestedAmount = product.productPrice;
    }
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
    final index = _index.clamp(0, contracts.length - 1);
    final contract = contracts[index];

    // **The whole page scrolls**, not just the card. The card grew tall — the
    // credit summary plus a product grid can easily exceed a phone screen —
    // and a PageView inside a scroll view needs a fixed height, which would
    // either clip the tallest card or leave a gap under the shortest.
    //
    // So the carousel is unrolled: one card is rendered inline and the pager
    // moves between them. Swipe is kept with a horizontal drag rather than
    // lost (the ListView claims the vertical axis, this claims the
    // horizontal), so the interaction the manual describes still works.
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        const TopupConditionsPanel(),
        _header(contracts.length),
        if (contracts.length > 1)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '« ปัดซ้าย-ขวา เพื่อดูสัญญาอื่น »',
                style: GoogleFonts.notoSansThai(
                  fontSize: 12.5,
                  color: LoanRegisterStyles.primary,
                ),
              ),
            ),
          ),
        GestureDetector(
          onHorizontalDragEnd: contracts.length > 1
              ? (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  // Ignore a flick too slow to be a deliberate swipe.
                  if (velocity.abs() < 100) return;
                  _movePage(velocity < 0 ? 1 : -1, contracts.length);
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: _TopupContractCard(
              // Keyed by contract so switching cards rebuilds rather than
              // animating one card's content into another's.
              key: ValueKey(contract.contractNo),
              contract: contract,
              onSelect: () => _start(contract),
              onViewStatus: () => _openStatus(contract),
              onSelectProduct: (product) => _start(contract, product: product),
            ),
          ),
        ),
      ],
    );
  }

  /// Steps the pager by [delta], clamped — the ends do not wrap.
  void _movePage(int delta, int total) {
    final next = (_index + delta).clamp(0, total - 1);
    if (next != _index) setState(() => _index = next);
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
          _chevron(Icons.chevron_left, _index > 0,
              () => _movePage(-1, total)),
          const SizedBox(width: 8),
          _chevron(Icons.chevron_right, _index < total - 1,
              () => _movePage(1, total)),
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
    super.key,
    required this.contract,
    required this.onSelect,
    required this.onViewStatus,
    required this.onSelectProduct,
  });

  final LoanContract contract;
  final VoidCallback onSelect;
  final VoidCallback onViewStatus;

  /// Tapping a สิทธิพิเศษเฉพาะคุณ tile starts the flow with that product as
  /// the purpose.
  final ValueChanged<LoanProduct> onSelectProduct;

  @override
  Widget build(BuildContext context) {
    final detail = contract.topupDetail;
    final pending = !contract.hasNoRequestYet;
    final eligible = contract.isEligible;
    final variant = TopupCardVariant.of(contract);

    /// The special limit is granted on top of the default and is **not**
    /// included in it, so the headline figure has to add the two.
    final specials = contract.topupSpecialFlag ? detail.topupSpecials : 0;
    final offered = detail.defaultTopupAmount + specials;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: LoanRegisterStyles.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // One of three headers — see TopupCardVariant.
          if (variant == TopupCardVariant.ineligible)
            const _IneligibleHeader()
          else ...[
            if (variant == TopupCardVariant.specialOffer)
              _SpecialOfferHeader(specials: specials),
            if (!pending) ...[
              _MaxTransferBanner(amount: detail.defaultTransferAmount.round()),
              const SizedBox(height: 12),
            ],
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
            if (showsSpecialOffers(contract)) ...[
              const SizedBox(height: 12),
              _SpecialOffersGrid(
                products:
                    detail.products.where((p) => !p.isEmpty).toList(),
                onSelect: onSelectProduct,
              ),
            ],
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


/// Header for a contract that cannot be topped up at all
/// (`can_topup == 'N'`). No amount and no action — the customer is pointed at
/// a branch, because nothing in this flow can change the answer.
class _IneligibleHeader extends StatelessWidget {
  const _IneligibleHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F3F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: LoanRegisterStyles.label),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ยังไม่สามารถเติมวงเงินได้ในขณะนี้',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: LoanRegisterStyles.value,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'ติดต่อสาขาเพื่อขอคำแนะนำ',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 12.5,
                    color: LoanRegisterStyles.label,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Header for a contract carrying add-on products — it leads with the offer
/// rather than the limit.
class _SpecialOfferHeader extends StatelessWidget {
  const _SpecialOfferHeader({required this.specials});

  /// Extra limit granted on top of the ordinary one. Shown only when there
  /// actually is one; a contract can carry products without a special limit.
  final int specials;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_outlined,
              size: 18, color: LoanRegisterStyles.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'ข้อเสนอพิเศษสำหรับคุณ',
              style: GoogleFonts.notoSansThai(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: LoanRegisterStyles.primary,
              ),
            ),
          ),
          if (specials > 0)
            Text(
              '+${formatMoney(specials)} บาท',
              style: GoogleFonts.notoSansThai(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: LoanRegisterStyles.required,
              ),
            ),
        ],
      ),
    );
  }
}

/// **สิทธิพิเศษเฉพาะคุณ** — the add-on products this contract's limit can be
/// spent on, as a three-across grid of tiles.
///
/// Tapping one starts the flow with that product as the purpose, which is why
/// the section is withheld when a request is already in flight: there would be
/// nothing to start.
///
/// ⚠ **The tiles show a generic icon, not the product's own.** The source
/// resolves an SVG URL from a Firestore `topup_product_config` document in the
/// *LandAndHouseWeb* Firebase project, which this build has no access to — and
/// even the source falls back to a placeholder square when a product code is
/// missing from it. A neutral icon beats a broken image; wiring the real ones
/// means publishing that mapping somewhere this project can read.
class _SpecialOffersGrid extends StatelessWidget {
  const _SpecialOffersGrid({required this.products, required this.onSelect});

  final List<LoanProduct> products;
  final ValueChanged<LoanProduct> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: LoanRegisterStyles.divider, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shopping_bag_outlined,
                  size: 20, color: LoanRegisterStyles.value),
              const SizedBox(width: 8),
              Text(
                'สิทธิพิเศษเฉพาะคุณ',
                style: GoogleFonts.notoSansThai(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: LoanRegisterStyles.value,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.arrow_upward, size: 14, color: Color(0xFF0E8C86)),
              const SizedBox(width: 6),
              Text(
                'ใช้เงินก้อนเดียวกับข้อเสนอด้านบน',
                style: GoogleFonts.notoSansThai(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0E8C86),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.builder(
            padding: EdgeInsets.zero,
            primary: false,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 1.2,
            ),
            itemCount: products.length,
            itemBuilder: (context, i) =>
                _ProductTile(product: products[i], onTap: () => onSelect(products[i])),
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap});

  final LoanProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: LoanRegisterStyles.cardBorder, width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.card_giftcard_outlined,
                size: 21, color: LoanRegisterStyles.primary),
            const SizedBox(height: 4),
            Flexible(
              child: Text(
                product.productName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansThai(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: LoanRegisterStyles.value,
                ),
              ),
            ),
            if (product.productPrice > 0)
              Text(
                formatWholeMoney(product.productPrice),
                style: GoogleFonts.notoSansThai(
                  fontSize: 10,
                  color: LoanRegisterStyles.label,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
