/// The top-up flow's accumulated state, passed page → page as a go_router
/// `extra` — the same convention `LoanRegisterForm` and `PLoanFlow` use.
///
/// The source FlutterFlow app kept all of this in a global `FFAppState`, so a
/// half-finished top-up leaked into the next one and no screen owned any
/// value. One mutable object threaded through the routes keeps it explicit:
/// every field below is written by exactly one step.
///
/// **This is a top-up, not a P-Loan Extra** — the two look alike and price
/// differently, which is the single most important thing to keep straight when
/// editing either. A top-up *closes out* the existing contract and reissues it
/// larger, so the old principal comes off the payout ([payoutAmount]); a P-Loan
/// Extra only references the contract and deducts nothing. See
/// `PLoanFlow.payoutAmount` for the other half of that story.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../models/customer_address.dart';
import '../../services/firebase_storage_rest.dart';
import '../../models/customer_detail.dart';
import '../../p_loan/application/models/installment_plan.dart';
import '../../p_loan/application/models/loan_amount_detail.dart';
import '../../p_loan/application/models/loan_contract.dart';
import '../../p_loan/application/models/loan_documents.dart';
import 'topup_photo.dart';
import 'topup_purpose.dart';

/// How the customer got into the flow, which decides what the back button on
/// the first screen does.
enum TopupEntry {
  /// From this app's own home menu — back pops normally.
  menu,

  /// Launched by the native host straight into the card screen — back has
  /// nothing beneath it, so it closes the WebView.
  host,
}

/// Where the amount screen sends the customer next.
///
/// A top-up is not always possible even on a contract that offers one: land
/// and house loans are not self-service, `can_topup` can refuse, and a payout
/// above the contract's `max_transfer_amount` needs a person. In those cases
/// the source files a **lead** instead, and says so by relabelling its button
/// ส่งข้อมูล rather than ถัดไป.
enum TopupOutcome {
  /// Continue to the installment picker and file a real top-up.
  topup,

  /// File a lead for someone to call the customer back.
  lead,

  /// Accrued interest is outstanding; it must be paid before anything else.
  payInterest,
}

/// The mutable state of one top-up application.
class TopupFlow {
  TopupFlow({
    required this.hashThaiId,
    required this.authToken,
    this.entry = TopupEntry.menu,
    this.source = '',
    this.referId = '',
  });

  // ── Launch context ───────────────────────────────────────────────────
  final String hashThaiId;

  /// Bearer token captured at construction. Only a fallback: every request
  /// re-resolves a fresh one through `AuthToken.resolve`, because a top-up
  /// routinely outlives the hour a Firebase ID token is good for.
  final String authToken;

  final TopupEntry entry;

  /// Attribution passed through to the submit payload untouched.
  final String source;
  final String referId;

  // ── Step 1 — contract ────────────────────────────────────────────────
  LoanContract? contract;
  CustomerDetail? customer;
  CustomerAddressBook? addressBook;

  // ── Set on step 1 — the product the customer picked ──────────────────
  //
  // Null when they tapped เติมวงเงิน (a plain top-up); set when they tapped a
  // สิทธิพิเศษเฉพาะคุณ tile, which fixes both the product code on the payload
  // and the amount. There is no วัตถุประสงค์ screen — the card already asked.
  TopupPurpose? purpose;

  // ── Step 3 — amount ──────────────────────────────────────────────────
  /// `GET /topup/detail` for [contract], with the special-limit uplift already
  /// folded in (see [applySpecialLimit]).
  LoanAmountDetail? amountDetail;

  /// The figure the customer asked for, before the calculator confirms it.
  int requestedAmount = 0;

  /// `POST /topup/calculator` for [requestedAmount].
  InstallmentPlan? plan;

  // ── Step 4 — installments ────────────────────────────────────────────
  InstallmentOption? installment;

  // ── Step 5 — collateral photos, Step 7 — identity photos ─────────────
  final Map<TopupPhoto, Uint8List> photos = {};

  // ── Step 7 — documents, identity and consent ─────────────────────────
  LoanDocuments? documents;

  /// Documents the customer has read and accepted, by kind.
  final Set<LoanDocumentKind> consentedDocuments = {};

  /// The ID number `/vision/thai-id-validate` read off the card photo.
  String verifiedThaiId = '';

  /// PDPA answers, **already given before this build opens** (2026-09-17).
  ///
  /// The srisawad host funnels every top-up entry point through its own
  /// `/consent` page, which shows `assets/consent.md` behind a single
  /// ยอมรับ / ปฏิเสธ pair and launches this build **only** on ยอมรับ. That
  /// document's clause 13 covers collection, use and disclosure, and clause 14
  /// covers marketing — so both answers are settled before step 1, and step 7's
  /// ความยินยอม checkboxes are commented out rather than asking again.
  ///
  /// ⚠ **This is not the source's hardcoded `'Y'`.** That recorded a consent
  /// the customer was never asked for, because the source had no consent
  /// screen anywhere. Here the consent is real and auditable; it is collected
  /// one screen earlier, in another app. The distinction is the whole reason
  /// the deviation note in CLAUDE.md exists — don't read this as reverting it.
  ///
  /// ⚠ **A plain browser bypasses that page.** `/topup` is URL-addressable, so
  /// opening the deployed URL directly skips the host's consent screen and
  /// still files `Y`/`Y`. Inside the app — the only way a customer reaches
  /// this — the page cannot be skipped. Same class as the
  /// `จำลองยืนยันตัวตนสำเร็จ` NDID bypass, and it wants the same fix: a define
  /// that defaults off.
  ///
  /// Restoring the checkboxes means setting both back to `false` in the same
  /// commit — see the commented block in `topup_conclusion_page.dart`.
  bool marketingConsent = true;
  bool sensitiveConsent = true;

  /// Device GPS, captured on the conclusion screen and never awaited.
  String latitude = '';
  String longitude = '';

  /// Transaction number returned by a successful `POST /topup`.
  String transNo = '';

  // ── Derived: amounts ─────────────────────────────────────────────────

  /// ~~Folds the contract's special limit into [amountDetail].~~
  /// **Now a no-op, kept so the call sites read as a deliberate decision.**
  ///
  /// ⚠ **`default_topup_amount` already includes `topup_extra`** (confirmed by
  /// the API team, 2026-09-14). Adding the uplift on top of it — which this
  /// did, and which the card still did inline — **double-counted** it: on
  /// `MLOAN`/`1สM681102002NF63C` the screens offered `38,900 + 5,000 = 43,900`
  /// against a real ceiling of 38,900, and `POST /topup/recal` refused to
  /// price it with `400 topup_amount out of range`.
  ///
  /// That, not a disagreement between two endpoints, is what hid the
  /// ยอดที่ต้องชำระเพื่อเติมวงเงิน section for two days. `/loan/list` and
  /// `/topup/recal` were saying the same thing all along; the client was
  /// adding a number that was already in the total.
  ///
  /// The uplift is still **shown**, as the breakdown of a sum rather than an
  /// addition to it: `topup_actual` + `topup_extra` = `default_topup_amount`.
  /// See the M35 pair on the amount screen.
  void applySpecialLimit() {
    // Deliberately empty. Restoring the addition would re-break the ceiling.
  }

  /// The amount `POST /topup/recal` is asked to price the settlement at: the
  /// limit the endpoint itself states, which is [LoanAmountDetail.defaultTopupAmount].
  ///
  /// ⚠ This used to subtract [LoanAmountDetail.topupSpecials] back out, as a
  /// workaround for the double-count [applySpecialLimit] introduced — the
  /// screen offered 43,900 against a real ceiling of 38,900 and the endpoint
  /// refused it. With the double-count gone the subtraction would take the
  /// uplift off a figure that is supposed to contain it, so it has been
  /// removed. The two must move together; do not restore one without the
  /// other.
  int get settlementPricingAmount =>
      amountDetail?.defaultTopupAmount ?? requestedAmount;

  /// **ยอดจัดสินเชื่อเดิม** — the limit before the M35 uplift, i.e.
  /// `topup_actual` as the API states it.
  ///
  /// ⚠ Not `defaultTopupAmount − specialLimit`. That derivation was only ever
  /// correct while the client double-counted the uplift into the default; see
  /// [applySpecialLimit]. Taking the API's own field cannot drift.
  int get baseLimit {
    final detail = amountDetail;
    if (detail == null) return 0;
    if (detail.topupActual > 0) return detail.topupActual;
    // `/topup/detail` (the `_old` page, P-Loan) may not send it.
    final derived = detail.defaultTopupAmount - specialLimit;
    return derived > 0 ? derived : detail.defaultTopupAmount;
  }

  /// **วงเงินพิเศษเพิ่มเติม** — `topup_extra`, preferring the amount response's
  /// own value over `/loan/list`'s so the pair always decomposes the bar it
  /// sits above.
  int get specialLimit {
    final fromDetail = amountDetail?.topupExtra ?? 0;
    if (fromDetail > 0) return fromDetail;
    final c = contract;
    return c == null ? 0 : specialLimitOf(c);
  }

  /// **The M35 วงเงินพิเศษ on [contract] — `topup_extra`.**
  ///
  /// The design calls this *วงเงินพิเศษเพิ่มเติม* and shows it as a `+5,000.00`
  /// line above the blue วงเงินสินเชื่อใหม่สูงสุด bar, i.e. granted **on top
  /// of** `default_topup_amount` rather than included in it. That is why both
  /// the default and the ceiling are raised rather than just the default.
  ///
  /// ⚠ **It reads `topup_extra`, not `topup_specials`** (changed 2026-09-12 on
  /// instruction: *"วงเงินพิเศษ M35 -> is topup_extra"*). `topup_specials` was
  /// the source's pairing and is left alone on the model; nothing reads it for
  /// this any more.
  ///
  /// ⚠ **`topup_special_flag` is no longer the gate** — a non-zero amount is.
  /// The flag belonged to `topup_specials`, so requiring it would let a
  /// contract carrying a real `topup_extra` show none of it, which hides money
  /// the backend granted. Re-gating is one line here if the flag turns out to
  /// mean something for this field too.
  ///
  /// ⚠ **The same field is a P-Loan Extra's entire request amount**
  /// (`LoanAmountDetail.extraRequestAmount`). One number, two products: here
  /// it raises a top-up's ceiling, there it *is* the loan. Nothing needs to
  /// reconcile them — the card's PLD001 tile leaves this flow entirely — but
  /// don't read one as evidence about the other.
  static int specialLimitOf(LoanContract contract) =>
      contract.topupDetail.topupExtra;

  /// The amount the calculator actually priced, which is what every downstream
  /// figure is derived from. Falls back to what was asked for.
  int get calculatedAmount => plan?.amount ?? requestedAmount;

  /// Stamp duty. **The calculator's, not `/topup/detail`'s.**
  ///
  /// `GET /topup/detail` returns the duty on the contract's *default* limit,
  /// while `POST /topup/calculator` recomputes it for the amount actually
  /// requested. Quoting the former on a smaller request charges duty for a
  /// larger loan than the customer is taking.
  int get feeAmount => plan?.feeAmount ?? amountDetail?.feeAmount ?? 0;

  /// Outstanding principal on the contract being replaced.
  ///
  /// `double` since 2026-09-12 — see [ContractDetails.closingBalance].
  ///
  /// ⚠ **Three sources, in this order, because `POST /topup/recal` sends its
  /// `contract_details` block entirely blank** (verified against the QA sample,
  /// 2026-09-14): every real figure is at the **top level** there, while
  /// `GET /topup/detail` populated the nested block. Reading only the nested
  /// one made this **0** the moment the top-up flow switched endpoints — which
  /// does not look like an error, it looks like a payout larger by the whole
  /// outstanding principal, on screen *and* in `transfer_amount` on the submit
  /// body.
  double get closingBalance {
    final top = amountDetail?.closingBalance ?? 0;
    if (top > 0) return top;
    final nested = amountDetail?.contractDetails.closingBalance ?? 0;
    if (nested > 0) return nested;
    // `/loan/list`'s copy is as of its `data_date`, so it is the last resort.
    return contract?.contractDetails.closingBalance ?? 0;
  }

  /// **The principal deducted from the payout** — `/loan/list`'s
  /// `topup_detail.principal_not_due` (2026-09-24, on request), falling back
  /// to [closingBalance] when the contract carries none. The card's
  /// เงินต้นที่ยังไม่ถึงกำหนดชำระ uses the same field via [principalNotDueOf],
  /// so the card and the amount screen quote one principal.
  ///
  /// ⚠ The fallback is deliberate even though a missing value elsewhere shows
  /// `-`: this figure is **filed** (it sets `transfer_amount`), and a 0 would
  /// overstate the payout by the whole principal. Falling back keeps the
  /// behaviour that shipped before the field existed.
  double get principalDeduction {
    final notDue = contract?.topupDetail.principalNotDue ?? 0;
    if (notDue > 0) return notDue;
    return closingBalance;
  }

  /// The card's version of [principalDeduction]: it has only the `/loan/list`
  /// row, so its fallback is that row's `closing_balance`.
  static double principalNotDueOf(LoanContract contract) {
    final notDue = contract.topupDetail.principalNotDue;
    if (notDue > 0) return notDue;
    return contract.contractDetails.closingBalance;
  }

  /// Accrued interest, counted only when it has not already been settled.
  ///
  /// `double`, not `int` — see [LoanAmountDetail.interestYield].
  double get outstandingInterest =>
      hasUnpaidInterest ? (amountDetail?.interestYield ?? 0) : 0;

  /// `'Y'` means the accrued interest is still owed, and it must be paid
  /// before a top-up can be raised — the amount field locks, the
  /// เลื่อนเพื่อปรับลดวงเงิน slider disappears, and the primary button becomes
  /// ชำระเงิน.
  ///
  /// ⚠ **Falls back to `/loan/list`** (2026-09-14, on instruction), the same
  /// ordering and the same reason as `can_topup` in [outcome]:
  /// `POST /topup/recal` sends `interest_paid_flag` **empty**, so reading only
  /// the amount detail made every contract look settled — the amount stayed
  /// editable and the slider stayed on a contract that owes interest. It was
  /// only the settlement rows, via [TopupOutcome] upgrading ถัดไป, that made
  /// the screen look right at all.
  ///
  /// Detail first, contract second: a `'Y'` arriving *after* the list said
  /// otherwise has to stand. Blank is silence, not an answer.
  bool get hasUnpaidInterest => _interestPaidFlag == 'Y';

  /// `can_topup`, resolved **detail first, list second**.
  ///
  /// Extracted so [outcome] and [canTopupMessage] read one value: if they
  /// resolved it separately they could disagree about whether this contract is
  /// eligible, and the screen would route one way while explaining the other.
  /// See [outcome] for why the order is what it is.
  String get canTopupFlag => _firstNonEmpty([
        amountDetail?.contractDetails.canTopup,
        contract?.topupDetail.canTopup,
      ]);

  /// `topup_detail.can_topup_msg` — the API's note about why this contract
  /// cannot be topped up, shown above the amount screen's buttons.
  ///
  /// ⚠ **Two conditions, both required** (tightened 2026-09-15 on request):
  /// the contract must be ineligible (`can_topup != 'Y'`) **and** the API must
  /// have sent a message. An eligible contract shows nothing, even when a
  /// message is present — the note explains a refusal, so putting it above a
  /// working ชำระเงิน button would read as one where there is none.
  ///
  /// Read off the contract, not [amountDetail]: `can_topup_msg` exists only on
  /// `/loan/list`'s `topup_detail`, and `/topup/recal` sends its nested
  /// `contract_details` blank anyway.
  ///
  /// ⚠ Ineligible does **not** mean the buttons are gone. [outcome] checks
  /// unpaid interest *first*, so a contract can be `can_topup != 'Y'` and
  /// still land on the ชำระเงิน / ปรับปรุงยอดชำระ pair — which is exactly
  /// where this note was asked to appear.
  String get canTopupMessage {
    if (canTopupFlag == 'Y') return '';
    return contract?.topupDetail.canTopupMsg.trim() ?? '';
  }

  String get _interestPaidFlag => _firstNonEmpty([
        amountDetail?.interestPaidFlag,
        contract?.topupDetail.interestPaidFlag,
      ]);

  /// **`transfer_amount` on the submit body**: what reaches the customer's
  /// account once the old contract is closed out and duty taken.
  ///
  /// This is the top-up formula and it is *not* `PLoanFlow.payoutAmount` — a
  /// top-up settles the old principal, a P-Loan Extra does not.
  double get payoutAmount => calculatedAmount - principalDeduction - feeAmount;

  /// Deduction **item 5** — the old contract's unpaid interest and collection
  /// fee together, which the customer must settle before the request can go
  /// through. Zero unless [hasUnpaidInterest].
  double get overdueDeduction => hasUnpaidInterest
      ? (amountDetail?.interestYield ?? 0) + (amountDetail?.collectionFee ?? 0)
      : 0;

  /// **`จำนวนเงินที่จะได้รับ`** — the figure shown to the customer, item 3
  /// less item 5.
  ///
  /// ⚠ This is **not** [payoutAmount] and **not** [netTransferAmount]; the
  /// screen genuinely shows a third number. It differs from [payoutAmount]
  /// only when there is unpaid interest, and from [netTransferAmount] only
  /// when there is not — see that getter for why the collection fee is
  /// unconditional there and conditional here.
  double get receivableAmount => payoutAmount - overdueDeduction;

  /// The stricter figure the **eligibility** check uses, which additionally
  /// nets off unpaid interest and the collection fee.
  ///
  /// Kept separate from [payoutAmount] and [receivableAmount] on purpose: the
  /// source really does compute three different numbers here — one to send
  /// (`transfer_amount`), one to show, and this one to decide whether a
  /// self-service top-up is allowed at all. Collapsing any two would change
  /// either what is filed or what the customer is promised.
  ///
  /// ⚠ Note the collection fee comes off here **unconditionally**, where
  /// [receivableAmount] only subtracts it as part of item 5. That asymmetry is
  /// the source's, reproduced deliberately.
  double get netTransferAmount =>
      payoutAmount - outstandingInterest - (amountDetail?.collectionFee ?? 0);

  /// The numbered deduction list the amount screen renders.
  ///
  /// ⚠ **The numbering really does skip 4.** Item 4 (`ยอดค้างชำระงวดที่`) has
  /// a *different* render condition from item 5 — it additionally needs a
  /// non-zero `overdue_amount` — so the two rarely appear together and the
  /// on-screen list commonly reads 1, 2, 3, 5. That is the source's behaviour
  /// and the numbers are fixed labels, not positions: renumbering them would
  /// make this build disagree with every screenshot and with the QA manual.
  List<TopupDeductionLine> get deductionLines {
    final detail = amountDetail;
    if (detail == null) return const [];
    final contractNo = detail.contractNo;
    final lines = <TopupDeductionLine>[
      TopupDeductionLine(
        number: '1',
        label: 'หักยอดเงินต้นคงเหลือสัญญาเก่า',
        amount: principalDeduction,
        contractNo: contractNo,
      ),
      TopupDeductionLine(
        number: '2',
        label: 'หักอากรสแตมป์',
        amount: feeAmount,
        contractNo: contractNo,
      ),
    ];
    if (!hasUnpaidInterest) {
      // Nothing outstanding: item 3 *is* the payout, so the list stops here
      // and the screen shows จำนวนเงินที่จะได้รับ on its own.
      return lines;
    }
    lines.add(TopupDeductionLine(
      number: '3',
      label: 'จำนวนเงินก่อนจ่ายยอดค้างชำระ',
      amount: payoutAmount,
      contractNo: '',
      caption: '(ก่อนจ่ายยอดค้างชำระ)',
      highlight: true,
    ));
    final overdue = detail.overdueAmount.round();
    if (overdue != 0) {
      final period = _overduePeriod(detail);
      lines.add(TopupDeductionLine(
        number: '4',
        label: 'ยอดค้างชำระงวดที่$period',
        amount: overdue,
        contractNo: contractNo,
      ));
    }
    lines.add(TopupDeductionLine(
      number: '5',
      label: 'รวมหักดอกเบี้ยและยอดติดตามทวงถามสัญญาเก่า',
      amount: overdueDeduction,
      contractNo: contractNo,
      warning: '*กรุณาชำระเงินก่อนดำเนินการ',
      children: [
        TopupDeductionLine(
          number: '5.1',
          label: 'ดอกเบี้ย',
          amount: detail.interestYield,
          contractNo: '',
        ),
        TopupDeductionLine(
          number: '5.2',
          label: 'ค่าติดตามทวงถาม',
          amount: detail.collectionFee,
          contractNo: '',
        ),
      ],
    ));
    return lines;
  }

  /// `" (5-3)"` — the overdue instalment range, or `''` when the API sent
  /// neither bound.
  ///
  /// The source prints `overdue_to`–`overdue_from`, in that order. It reads
  /// backwards, and it is kept that way: the figures come from the server and
  /// swapping them here would make this build disagree with the native app
  /// for the same contract.
  String _overduePeriod(LoanAmountDetail detail) {
    final from = detail.overdueFrom.trim();
    final to = detail.overdueTo.trim();
    if (from.isEmpty && to.isEmpty) return '';
    return ' ($to-$from)';
  }

  /// Upper bound on what may be transferred without a person involved.
  ///
  /// ⚠ **An absent `max_transfer_amount` reads as 0, and 0 refuses
  /// everything** — no positive payout is under it, so every contract files a
  /// lead. That is the source's behaviour reproduced exactly, and it is the
  /// first thing to check if the flow suddenly offers ส่งข้อมูล for every
  /// contract: the field is missing from `/loan/list`, not broken here. It is
  /// deliberately *not* treated as "no limit" — guessing the cap open would
  /// let a request through that the backend meant to hold back.
  int get maxTransferAmount => contract?.topupDetail.maxTransferAmount ?? 0;

  /// Whether [requestedAmount] sits inside the contract's allowed range.
  ///
  /// Unlike a P-Loan Extra, a top-up **does** honour `min/max_topup_amount` —
  /// those bounds describe this product.
  bool get isRequestedAmountAllowed {
    final detail = amountDetail;
    if (detail == null) return false;
    return requestedAmount >= detail.minTopupAmount &&
        requestedAmount <= detail.maxTopupAmount;
  }

  /// Whether the amount field may be edited. A named add-on product is priced
  /// by the product, and unpaid interest locks the field outright.
  bool get isAmountEditable =>
      !hasUnpaidInterest && (purpose?.isOther ?? true);

  // ── Derived: routing ─────────────────────────────────────────────────

  /// What the amount screen's primary button does.
  ///
  /// The three conditions behind [TopupOutcome.lead] are the source's, kept
  /// verbatim: land/house loan types are not self-service, `can_topup` can
  /// refuse after the detail call even when the list said otherwise, and a
  /// payout over `max_transfer_amount` needs a person.
  TopupOutcome get outcome {
    if (hasUnpaidInterest) return TopupOutcome.payInterest;
    final typeCode = contract?.contractDetails.loanTypeCode ?? '';
    // ⚠ **`can_topup` falls back to `/loan/list`** (instructed 2026-09-14).
    // `POST /topup/recal` sends `contract_details` blank, so reading only that
    // gave `''` for every contract — and `'' != 'Y'` sent *every* one of them
    // down the lead branch, which reads as a backend refusal rather than as a
    // missing field.
    //
    // ⚠ The order is **detail first, list second**, not the other way round,
    // and that is deliberate: a refusal arriving *after* the list said `Y` has
    // to stand, which is the whole point of re-checking it here. Blank is not
    // a refusal — it is silence — so it defers to the contract. On the recal
    // endpoint that makes the list the effective source, which is what was
    // asked for, without discarding a real `N` from `/topup/detail` (still the
    // path `_old` and P-Loan take).
    final canTopup = canTopupFlag;
    if (typeCode == 'L' || typeCode == 'H') return TopupOutcome.lead;
    if (canTopup != 'Y') return TopupOutcome.lead;
    if (netTransferAmount > maxTransferAmount) return TopupOutcome.lead;
    return TopupOutcome.topup;
  }

  static String _firstNonEmpty(List<String?> values) =>
      values.firstWhere((v) => v != null && v.isNotEmpty, orElse: () => '') ??
      '';

  /// Label for that button, so the screen never has to restate the rule.
  String get primaryActionLabel => switch (outcome) {
        TopupOutcome.payInterest => 'ชำระเงิน',
        TopupOutcome.lead => 'ส่งข้อมูล',
        TopupOutcome.topup => 'ถัดไป',
      };

  // ── Derived: payout account ──────────────────────────────────────────
  //
  // A top-up always pays into the account already registered against the
  // contract it replaces — there is nothing for the customer to choose, which
  // is why these are read-only getters rather than fields.

  String get bankCode => contract?.contractBankBrandname ?? '';

  String get bankAccountNo => contract?.contractBankAccount ?? '';

  /// The contract carries no holder name, and the account is the customer's
  /// own.
  String get bankAccountName => customer?.fullName ?? '';

  /// Bank/branch logo that came with the contract, base64.
  String get bankLogoBase64 => contract?.branchImage ?? '';

  // ── Derived: photos ──────────────────────────────────────────────────

  String get loanTypeCode => contract?.contractDetails.loanTypeCode ?? '';

  /// Motorcycles need a whole-vehicle shot plus the tax disc; cars need four
  /// sides, the odometer and the tax disc.
  ///
  /// For any other loan type the source leaves its confirm button permanently
  /// disabled — a dead end. Requiring the tax disc alone is a deliberate
  /// deviation that keeps the flow completable, matching what the P-Loan port
  /// already does.
  List<TopupPhoto> get requiredPhotos => switch (loanTypeCode) {
        'M' => const [TopupPhoto.fullVehicle, TopupPhoto.taxDisc],
        'C' => const [
            TopupPhoto.carRight,
            TopupPhoto.carLeft,
            TopupPhoto.carFront,
            TopupPhoto.carBack,
            TopupPhoto.carMile,
            TopupPhoto.taxDisc,
          ],
        _ => const [TopupPhoto.taxDisc],
      };

  bool hasPhoto(TopupPhoto slot) => (photos[slot]?.isNotEmpty ?? false);

  /// Records a capture **and** mirrors it to Cloud Storage.
  ///
  /// The single place a photo enters the flow, so no screen can store one and
  /// forget the mirror — which is exactly what would happen if each of the
  /// three capture sites called `photos[slot] = bytes` itself.
  ///
  /// ⚠ The mirror is **un-awaited and best-effort**. The bytes that file the
  /// request go out in `POST /topup`; Storage is a copy for the branch. So a
  /// failed, slow or unauthenticated upload must not delay the customer or
  /// block the next screen — it records a breadcrumb and nothing else. Same
  /// reasoning as the P-Loan submit screen's GPS capture.
  void setPhoto(TopupPhoto slot, Uint8List bytes) {
    photos[slot] = bytes;
    if (bytes.isEmpty) return;
    final hash = hashThaiId.trim();
    final contractNo = contract?.contractNo.trim() ?? '';
    // The path is keyed on the customer and the contract; without either there
    // is nowhere meaningful to file it, and a guessed path is worse than none.
    if (hash.isEmpty || contractNo.isEmpty) return;
    unawaited(FirebaseStorageRest.uploadJpeg(
      objectPath: FirebaseStorageRest.topupObjectPath(
        hashThaiId: hash,
        loanTypeCode: contract?.contractDetails.loanTypeCode ?? '',
        contractNo: contractNo,
      ),
      bytes: bytes,
    ));
  }

  /// The first required collateral photo still missing, or null.
  TopupPhoto? get missingCollateralPhoto {
    for (final slot in requiredPhotos) {
      if (!hasPhoto(slot)) return slot;
    }
    return null;
  }

  /// The first required identity photo still missing, or null.
  TopupPhoto? get missingIdentityPhoto {
    for (final slot in TopupPhoto.identity) {
      if (!hasPhoto(slot)) return slot;
    }
    return null;
  }

  /// Base64 of a captured photo, or `''` when that slot is empty.
  String base64OfPhoto(TopupPhoto slot) {
    final bytes = photos[slot];
    if (bytes == null || bytes.isEmpty) return '';
    return base64Encode(bytes);
  }

  // ── Derived: identity and submit gating ──────────────────────────────

  /// Whether the scanned card belongs to the customer on file.
  ///
  /// The source also accepted four hardcoded Thai IDs here, which let anyone
  /// holding one of those cards pass identity verification for *any* account.
  /// That backdoor is deliberately not reproduced — the same decision the
  /// P-Loan port made, and a test pins it shut.
  bool get isThaiIdVerified =>
      verifiedThaiId.isNotEmpty && verifiedThaiId == (customer?.thaiId ?? '');

  /// Every document read and accepted.
  bool get hasAllDocumentConsents =>
      documents != null &&
      LoanDocumentKind.values.every(consentedDocuments.contains);

  /// The first document the customer has not accepted yet, or null.
  LoanDocumentKind? get missingDocumentConsent {
    for (final kind in LoanDocumentKind.values) {
      if (!consentedDocuments.contains(kind)) return kind;
    }
    return null;
  }

  /// Whether `POST /topup` may be called.
  bool get canSubmit =>
      contract != null &&
      amountDetail != null &&
      plan != null &&
      installment != null &&
      documents != null &&
      hasAllDocumentConsents &&
      missingCollateralPhoto == null &&
      missingIdentityPhoto == null &&
      isThaiIdVerified &&
      sensitiveConsent;

  /// Why [canSubmit] is false, in the order the customer should fix them.
  /// Null when the request is ready to file.
  String? get submitBlockedReason {
    if (documents == null) return 'ไม่พบเอกสารสัญญา กรุณาลองใหม่';
    final doc = missingDocumentConsent;
    if (doc != null) return doc.consentPrompt;
    final collateral = missingCollateralPhoto;
    if (collateral != null) return collateral.missingMessage;
    final identity = missingIdentityPhoto;
    if (identity != null) return identity.missingMessage;
    if (!isThaiIdVerified) return 'กรุณาถ่ายรูปบัตรประชาชนเพื่อยืนยันตัวตน';
    if (!sensitiveConsent) {
      return 'กรุณายินยอมให้เก็บรวบรวมและใช้ข้อมูลอ่อนไหว';
    }
    if (installment == null) return 'กรุณาเลือกจำนวนงวด';
    return null;
  }

  /// The `/pdf/loan` request for this application, and the same object the
  /// submit body echoes back as `save_pdf`.
  ///
  /// Returns null while the flow is incomplete rather than throwing — the
  /// conclusion screen renders a "documents unavailable" state from it.
  ContractPdfRequest? get pdfRequest {
    final contract = this.contract;
    final detail = amountDetail;
    final installment = this.installment;
    if (contract == null || detail == null || installment == null) return null;
    return ContractPdfRequest(
      contractNo: detail.contractNo,
      dbName: detail.dbName,
      contractDate: detail.contractDate,
      amount: calculatedAmount.toDouble(),
      from: contract.contractDetails.comcode,
      contractBankAccount: contract.contractBankAccount,
      contractBankBrandname: contract.contractBankBrandname,
      contractBankType: contract.contractBankType,
      contractBankBranch: '',
      interestRate: detail.interestRate,
      installmentNumber: installment.tenor.toDouble(),
      amountPerInstallment: installment.regularPeriodAmt.toDouble(),
      startInstallmentDate: plan?.firstDueDate ?? detail.firstDueDate,
      installmentDate: '',
      vehicleType: contract.contractDetails.loanTypeName,
    );
  }
}


/// One row of the amount screen's numbered deduction list.
///
/// [number] is a **label**, not a position — see [TopupFlow.deductionLines]
/// for why the on-screen list can read 1, 2, 3, 5.
class TopupDeductionLine {
  const TopupDeductionLine({
    required this.number,
    required this.label,
    required this.amount,
    required this.contractNo,
    this.caption = '',
    this.warning = '',
    this.highlight = false,
    this.children = const [],
  });

  final String number;
  final String label;

  /// `num`, because the interest and fee rows are decimals while the
  /// principal and duty rows are whole baht.
  final num amount;

  /// Shown small under the label, the way the source repeats the contract
  /// number beneath each deduction. Empty for rows that are not a deduction
  /// against the old contract.
  final String contractNo;

  /// Extra parenthetical under the label.
  final String caption;

  /// Red line under the row, e.g. "*กรุณาชำระเงินก่อนดำเนินการ".
  final String warning;

  /// Renders the amount in red — the source highlights item 3.
  final bool highlight;

  /// Indented sub-rows (5.1, 5.2).
  final List<TopupDeductionLine> children;
}
