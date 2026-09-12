import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_state.dart';
import '../loan_register/components/loan_register_styles.dart';
import '../models/customer_detail.dart';
import '../p_loan/application/components/p_loan_components.dart';
import '../p_loan/application/models/loan_contract.dart';
import '../p_loan/application/p_loan_topup_card_resume_page.dart';
import '../router/app_router.dart';
import '../services/native_bridge.dart';
import '../services/srisawad_api.dart';
import '../services/topup_api.dart';
import '../services/user_api.dart';
import 'components/topup_components.dart';
import 'components/topup_redesign.dart';
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

  /// **สิทธิพิเศษเฉพาะคุณ is hidden** (2026-09-12, on request — "for now").
  ///
  /// The grid, its tiles, the config-driven icons and the taps they fire are
  /// all still here and still tested; this is the one switch. Flip it back to
  /// `true` to restore the section — nothing else has to change.
  ///
  /// ⚠ **It takes this build's P-Loan Extra entry point with it.** The
  /// `PLD001` tile is how the top-up card hands off to `/pLoan/resume`, so
  /// while this is false that hand-off cannot be reached *from this screen*.
  /// The product is not unreachable — the srisawad app's home
  /// สิทธิพิเศษเฉพาะคุณ chip and the LandAndHouseWeb card both open
  /// `/pLoan/resume` directly — but if someone reports that P-Loan Extra
  /// "disappeared", this is why.
  ///
  /// Gated here rather than in [showsSpecialOffers], which
  /// `topup_card_page_old.dart` also calls: the `_old` pair must keep
  /// rendering exactly as it did.
  static const bool showSpecialOffersSection = false;

  /// Product code the **P-Loan Extra** offer is published under.
  ///
  /// Matched literally on `product_code`, the same way the srisawad app's
  /// `LoanCard` and the LandAndHouseWeb top-up card both match it.
  static const String pLoanExtraProductCode = 'PLD001';

  /// Opens the **P-Loan Extra** flow for [contract].
  ///
  /// ⚠ P-Loan Extra is **not** a top-up, so this leaves the top-up flow
  /// entirely rather than carrying PLD001 through it as a purpose. A top-up
  /// closes the contract out and reissues it larger; a P-Loan Extra draws a
  /// separate loan that only *references* it, and files with `POST /ploan`
  /// instead of `POST /topup`.
  ///
  /// `/pLoan/resume` rebuilds its own flow from `dbName` + `contractNo`, which
  /// is the same entry the LandAndHouseWeb card reaches via
  /// `srisawad://ploan-extra` and the host's PLD001 chip reaches natively. No
  /// amount is passed — that route reads the contract's own `topup_extra`.
  void _openPLoanExtra(LoanContract contract) {
    context.push(
      Uri(
        path: AppRoutes.pLoanTopupCardResume,
        queryParameters: {
          'dbName': contract.dbName,
          'contractNo': contract.contractNo,
        },
      ).toString(),
      // Hand over what this screen already loaded. Without it the resume page
      // re-reads /loan/list and /user/detail — two round trips the customer
      // waits through for data that is already in memory, having just been
      // used to draw the card they tapped.
      //
      // The query string is still the authority: the seed is ignored unless it
      // is for the same contract, and a reload drops it and fetches.
      extra: PLoanResumeSeed(contract: contract, customer: _customer),
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
    // A tile carries its product straight onto the flow — the screen that used
    // to ask for it is gone, because the card already asked.
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
    context.push(AppRoutes.topupAmount, extra: flow);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: topupAppBar(context, 'สินเชื่อเพิ่ม', onBack: _back),
      body: Column(
        children: [
          const PLoanMockBanner(),
          // No step indicator here. This screen is where the customer decides
          // *which product* they are starting — เติมวงเงิน for a top-up, a
          // สิทธิพิเศษเฉพาะคุณ tile for something else — so it sits ahead of
          // the wizard rather than inside it. The indicator starts on the next
          // screen, at 2 of 6, which keeps this one counted without presenting
          // it as a step to complete.
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
          const TopupConditionsCard(),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'ไม่พบสัญญาที่สามารถขอสินเชื่อเพิ่มได้',
              textAlign: TextAlign.center,
              style: TopupTheme.body(size: 15, color: LoanRegisterStyles.label),
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
        // Above the cards, where it was before the redesign and where it was
        // put back on request (2026-09-12). It briefly sat below them so the
        // screen would open on the offer the way the render does; the panel is
        // how a customer finds out *why* a card says what it says, which is
        // worth more than leading with the number.
        const TopupConditionsCard(),
        _header(contracts.length),
        if (contracts.length > 1)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '« ปัดซ้าย-ขวา เพื่อดูสัญญาอื่น »',
                style: TopupTheme.body(
                    size: 12.5, color: LoanRegisterStyles.primary),
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
              onSelectProduct: (product) {
                // PLD001 is a different product on a different endpoint —
                // it leaves for the P-Loan flow instead of continuing here.
                if (product.productCode == pLoanExtraProductCode) {
                  _openPLoanExtra(contract);
                  return;
                }
                _start(contract, product: product);
              },
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
          Text('สัญญาของคุณ', style: TopupTheme.heading()),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: LoanRegisterStyles.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${_index + 1}/$total',
              style: TopupTheme.value(
                  size: 12, color: LoanRegisterStyles.primary),
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


/// One contract, in the **2026-09 redesign**
/// (`etc/M35 + หน้าจอเติมเงิน_…pdf`, page 4 and the `can_topup = N` render).
///
/// Two layouts, and the ineligible one is not a variation of the other — it
/// answers a different question. An eligible card leads with what the customer
/// can get and ends in a button; an ineligible one leads with why they cannot
/// get it here, names a branch and a phone number, and has no action at all.
/// So they are separate builds rather than one build full of conditionals.
///
/// ⚠ **A request already in flight outranks both.** The customer cannot raise
/// a second one whatever `can_topup` says, so that state is checked first and
/// shows the status card.
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
    final pending = !contract.hasNoRequestYet;
    final eligible = contract.isEligible;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LoanRegisterStyles.cardBorder),
      ),
      child: !eligible && !pending ? _ineligible() : _offer(pending),
    );
  }

  // ── The ordinary card ────────────────────────────────────────────────

  /// The blue band, the contract block, and the figures that explain the
  /// payout. [pending] swaps the action for ดูสถานะคำขอ and withholds the
  /// product grid — tapping a tile starts a request, which a contract already
  /// mid-request cannot take.
  Widget _offer(bool pending) {
    final detail = contract.topupDetail;
    final specials = TopupFlow.specialLimitOf(contract);

    // The M35 วงเงินพิเศษ is granted **on top of** the ordinary limit and is
    // not included in it, so the headline has to add the two. The card shows
    // only the combined figure; the amount screen breaks it back out.
    final offered = detail.defaultTopupAmount + specials;
    final principal = contract.contractDetails.closingBalance;
    final duty = detail.feeAmount;

    // Computed rather than read from `default_transfer_amount`, which the API
    // sends **without** the duty taken off (verified against the
    // GetRecalTopupData sample: 88,500 − 86,217.08 = 2,282.92, no fee). Three
    // rows and a total that disagrees with them is worse than either number
    // alone, and this is the same formula TopupFlow.payoutAmount files as
    // `transfer_amount`.
    final payout = offered - principal - duty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _band(payout, hasSpecial: specials > 0),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TopupContractHeader(
                loanTypeCode: contract.contractDetails.loanTypeCode,
                loanTypeName: contract.loanTypeName.isEmpty
                    ? contract.contractDetails.loanTypeName
                    : contract.loanTypeName,
                contractNo: contract.contractNo,
                collateralInformation:
                    contract.contractDetails.collateralInformation,
                status: TopupStatusPill(
                  text: pending
                      ? contract.requestStatus.isEmpty
                          ? 'มีคำขออยู่ระหว่างดำเนินการ'
                          : contract.requestStatus
                      : 'ยังไม่ได้ทำรายการเติมวงเงิน',
                  icon: pending ? Icons.schedule : null,
                ),
              ),
              const SizedBox(height: 14),
              const TopupDottedDivider(),
              const SizedBox(height: 6),
              if (pending) ...[
                TopupFigureRow(
                  label: 'ยอดที่ขอไว้',
                  amount: contract.requestTopupAmount,
                  emphasis: true,
                  suffix: 'บาท',
                ),
                const SizedBox(height: 10),
                TopupPrimaryButton(
                    label: 'ดูสถานะคำขอ', onPressed: onViewStatus),
              ] else ...[
                TopupFigureRow(
                  label: 'วงเงินสินเชื่อใหม่สูงสุด',
                  amount: offered,
                  emphasis: false,
                  mutedLabel: true,
                  suffix: 'บาท',
                ),
                TopupFigureRow(
                  label: 'เงินต้นที่ยังไม่ถึงกำหนดชำระ',
                  amount: principal,
                  deduction: true,
                ),
                TopupFigureRow(
                  label: 'อากรแสตมป์สัญญาใหม่',
                  amount: duty,
                  deduction: true,
                ),
                const SizedBox(height: 10),
                _payoutStrip(payout),
                const SizedBox(height: 6),
                Text(
                  // Orange, not the alert red (set 2026-09-12 from a device
                  // check). It qualifies the offer — *when* you get the money
                  // — rather than warning about anything, and in red beside a
                  // payout figure it read as a problem with the payout.
                  '*เมื่อชำระยอดเพื่อเติมวงเงิน',
                  style: TopupTheme.body(
                      size: 11.5, color: LoanRegisterStyles.primary),
                ),
                if (_TopupCardPageState.showSpecialOffersSection &&
                    showsSpecialOffers(contract)) ...[
                  const SizedBox(height: 14),
                  _SpecialOffersGrid(
                    products:
                        detail.products.where((p) => !p.isEmpty).toList(),
                    onSelect: onSelectProduct,
                  ),
                ],
                const SizedBox(height: 14),
                TopupPrimaryButton(label: 'เติมวงเงิน', onPressed: onSelect),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The blue header: what the customer walks away with, stated first.
  ///
  /// ⚠ It quotes the **same** figure as the เงินคงเหลือโอนเข้าบัญชีสูงสุด
  /// strip further down, deliberately — the band is the promise and the rows
  /// under it are the arithmetic behind it. If they ever diverge, one of them
  /// is wrong.
  Widget _band(num payout, {required bool hasSpecial}) {
    return Container(
      width: double.infinity,
      color: TopupTheme.band,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome,
                        size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      'ข้อเสนอพิเศษสำหรับคุณ',
                      style: GoogleFonts.notoSansThai(
                        fontSize: 12.5,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'รับเงินโอนเข้าบัญชีสูงสุด',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'สูงสุด',
                      style: GoogleFonts.notoSansThai(
                          fontSize: 13, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatTopupMoney(payout),
                      style: GoogleFonts.notoSansThai(
                        fontSize: 26,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'บาท',
                      style: GoogleFonts.notoSansThai(
                          fontSize: 13, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // The wallet mark. `hasSpecial` deliberately changes nothing here:
          // the design draws the same band for M35 and non-M35 (pages 10 and
          // 11 differ only in the numbers), so the uplift is visible as a
          // larger figure rather than as different furniture.
          Icon(Icons.account_balance_wallet_outlined,
              size: 70, color: Color(0xFFF7BF97).withValues(alpha: 0.85)),
        ],
      ),
    );
  }

  /// The light-blue result strip.
  Widget _payoutStrip(num payout) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: TopupTheme.strip,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              'เงินคงเหลือโอนเข้าบัญชีสูงสุด*',
              style: TopupTheme.value(size: 13.5, weight: FontWeight.w700),
            ),
          ),
          Text(
            formatTopupMoney(payout),
            style: TopupTheme.value(size: 17, weight: FontWeight.w800),
          ),
          const SizedBox(width: 5),
          // The unit takes the **figure's** colour here, not the label grey it
          // has elsewhere. This row is the card's conclusion and reads as one
          // phrase; a grey บาท hanging off a navy number broke it in half.
          Text('บาท', style: TopupTheme.value(size: 12.5,
              weight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── can_topup = N ────────────────────────────────────────────────────

  /// The **cannot-do-this-in-the-app** card.
  ///
  /// It shows the existing credit line and nothing about a top-up: quoting an
  /// offer above "you cannot take this offer here" is the one thing this
  /// layout exists to avoid. There is no button, on purpose — the action is a
  /// phone call.
  Widget _ineligible() {
    final code = contract.topupDetail.canTopupCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: TopupTheme.warnBand,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: TopupTheme.alert, width: 1.6),
                    ),
                    child: const Icon(Icons.priority_high,
                        size: 20, color: TopupTheme.alert),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'ขออภัย รายการนี้ยังไม่สามารถทำผ่านแอปได้\n'
                      'กรุณาติดต่อสาขาเจ้าของบัญชี หรือโทร 1652',
                      style: GoogleFonts.notoSansThai(
                        fontSize: 13.5,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                        color: LoanRegisterStyles.value,
                      ),
                    ),
                  ),
                ],
              ),
              // Hidden when the API sends no code — see
              // TopupDetail.canTopupCode. A `Code :` with nothing after it
              // tells the branch less than no line at all.
              if (code.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Code : $code',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.notoSansThai(
                        fontSize: 12, color: LoanRegisterStyles.label),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TopupContractHeader(
                loanTypeCode: contract.contractDetails.loanTypeCode,
                loanTypeName: contract.loanTypeName.isEmpty
                    ? contract.contractDetails.loanTypeName
                    : contract.loanTypeName,
                contractNo: contract.contractNo,
                collateralInformation:
                    contract.contractDetails.collateralInformation,
                status: const TopupStatusPill(
                  text: 'ไม่เข้าเงื่อนไข',
                  icon: Icons.schedule,
                ),
              ),
              const SizedBox(height: 14),
              const TopupDottedDivider(),
              const SizedBox(height: 8),
              Text(
                'วงเงินสินเชื่อ (สัญญา ${contract.contractNo})',
                style: TopupTheme.label(size: 12.5),
              ),
              TopupFigureRow(
                label: 'วงเงินสินเชื่อเดิม',
                amount: contract.contractDetails.creditLimit,
              ),
            ],
          ),
        ),
      ],
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
/// Tile icons come from `topup_product_icons` in the runtime config
/// (`application/public_config`), keyed by product code — see
/// [AppConfig.topupProductIcon]. They are public Firebase Storage SVGs that
/// answer `access-control-allow-origin: *`, so `flutter_svg` can fetch them in
/// the browser.
///
/// ⚠ The source stores the same thing as **two parallel arrays** in its own
/// project, and its lookup is broken: the generated record reads
/// `produce_code` while the document stores `product_code`, so
/// `findIndexInList` always returns -1 and every tile there falls back to the
/// placeholder square. A code-keyed map cannot desync that way.
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
                style: TopupTheme.value(size: 13),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.arrow_upward, size: 14, color: Color(0xFF0E8C86)),
              const SizedBox(width: 6),
              Text(
                // Was a one-off teal. The redesign has exactly four text
                // colours — navy, grey, orange, red — and a fifth on one
                // caption read as a different kind of message than it is.
                'ใช้เงินก้อนเดียวกับข้อเสนอด้านบน',
                style: TopupTheme.label(size: 10.5),
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
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              // Square. The name needs two lines under the icon — a Thai
              // product name like "วงเงินเอนกประสงค์" does not fit on one —
              // and at the source's 1.2, with a price row below, there was
              // only room for one, which is what clipped it to "วงเงิน".
              // Dropping the price would already fit on a 390pt screen; this
              // keeps the margin on a narrower one.
              childAspectRatio: 1.0,
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
    // Null until the runtime config lands (it loads un-awaited at boot), and
    // null forever if the read failed — either way the tile falls back to its
    // built-in icon rather than waiting on the network.
    final iconUrl =
        AppState().appConfig?.topupProductIcon(product.productCode);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: LoanRegisterStyles.cardBorder, width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ProductIcon(url: iconUrl),
            const SizedBox(height: 6),
            // Icon and name only. The price is deliberately not shown: this
            // is an offer tile, and the figure it would carry is the
            // product's own price rather than what the customer receives —
            // two different numbers on one card invites reading it as the
            // payout. The amount they are choosing is settled on step 3.
            Flexible(
              child: Text(
                product.productName,
                textAlign: TextAlign.center,
                maxLines: 2,
                // Ellipsis is the last resort, not the expected outcome —
                // the tile is sized for two lines.
                overflow: TextOverflow.ellipsis,
                style: TopupTheme.value(size: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// The product's configured SVG, tinted like an icon.
///
/// Falls back to a built-in Material icon whenever the config has no URL or
/// the fetch fails — a tile with a plausible glyph is better than a broken
/// image or an empty box, and the grid must not depend on a network round
/// trip to be usable.
class _ProductIcon extends StatelessWidget {
  const _ProductIcon({required this.url});

  final String? url;

  static const Widget _fallback =
      Icon(Icons.card_giftcard_outlined, size: 21, color: Color(0xFFE8842A));

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null || url.isEmpty) return _fallback;
    return SizedBox(
      width: 21,
      height: 21,
      child: SvgPicture.network(
        url,
        width: 21,
        height: 21,
        colorFilter:
            ColorFilter.mode(LoanRegisterStyles.primary, BlendMode.srcIn),
        placeholderBuilder: (_) => _fallback,
        // flutter_svg has no onError hook, so a failed fetch renders the
        // placeholder indefinitely — which is the fallback icon, by design.
      ),
    );
  }
}
