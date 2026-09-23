/// The three ways a customer may pay an instalment, and the rules behind them.
///
/// Transcribed from LandAndHouseWeb's `select_payment_page_widget.dart`, which
/// holds them as an `installmentTypeSelectedList` of three bools and
/// recomputes each amount inline at four separate call sites — the
/// radio label, the option's own detail block, the button's disabled test and
/// the push to the QR screen. Gathered here so those four cannot disagree, and
/// so the arithmetic is testable without a widget.
library;

import '../../p_loan/application/components/p_loan_components.dart';
import '../../loan_detail/components/loan_detail_components.dart';
import '../../p_loan/application/models/loan_contract.dart';

enum LoanPaymentOption {
  /// **ชำระเต็มจำนวน** — this instalment plus anything overdue.
  full('ชำระเต็มจำนวน'),

  /// **ยอดค้างชำระ** — the arrears only.
  overdue('ยอดค้างชำระ'),

  /// **กำหนดยอดชำระเอง** — whatever the customer types.
  custom('กำหนดยอดชำระเอง');

  const LoanPaymentOption(this.label);
  final String label;
}

/// Everything the payment screen derives from one contract.
class LoanPaymentSummary {
  LoanPaymentSummary(this.contract);

  final LoanContract contract;

  // ── the figures the options are built from ──────────────────────────

  /// `payment_details.current_due_amount` — due this instalment.
  double get currentDueAmount => contract.paymentDetails.currentDueAmount;

  /// `payment_details.overdue_amount` — arrears.
  double get overdueAmount => contract.paymentDetails.overdueAmount;

  /// `payment_details.collection_fee` — ค่าติดตามค้างชำระ.
  double get collectionFee => contract.paymentDetails.collectionFee;

  /// `payment_details.penalty_fee` — ค่าเบี้ยปรับค้างชำระ, added to this
  /// screen by the 2026-09-17 redesign. See [PaymentDetails.penaltyFee]: the
  /// wire name is unconfirmed, and 0 withholds the row.
  double get penaltyFee => contract.paymentDetails.penaltyFee;

  /// `payment_details.installment_amount` — the scheduled instalment, shown
  /// under ค่างวดปัจจุบัน.
  ///
  /// ⚠ Not [currentDueAmount], which is what is *owed* now. The two differ on
  /// a contract in arrears, and the source reads them from these two separate
  /// fields — see the same distinction on `LoanDetailSummary`.
  int get installmentAmount => contract.paymentDetails.installmentAmount;

  /// `contract_details.os_balance` — the ceiling a typed amount is clamped to.
  ///
  /// ⚠ **Not displayed** since 2026-09-14: the screen's ยอดหนี้คงเหลือ row was
  /// removed on request, because the company does not show the outstanding
  /// balance here. It is still the rule — this getter feeds
  /// [blurredFieldText], and the screen still carries the note saying the
  /// amount cannot exceed it. Do not delete it because nothing renders it.
  double get osBalance => contract.contractDetails.osBalance;

  // ── per-option amounts ──────────────────────────────────────────────

  /// ชำระเต็มจำนวน: **`current_due_amount` alone.**
  ///
  /// ⚠ **Changed 2026-09-17, and it is a billing change.** It used to add the
  /// collection fee on top. That field "includes all the customer need to
  /// pay" (confirmed with the API owner while building the redesign), so
  /// adding the fee double-counted it — the redesign's own figures only
  /// reconcile without it: `1,060.25` arrears + `1,440.00` instalment =
  /// `2,500.25`, which is exactly `current_due_amount`.
  ///
  /// It is also the **same field** the loan detail screen shows as
  /// `รวมต้องชำระ` and breaks down as `ยอดรวมต้องชำระ`. Those two screens are
  /// one tap apart over one contract, so a customer must not see two totals.
  ///
  /// ⚠ `loan_payment_page_old.dart` keeps the old formula, via its own copy of
  /// this class — that is what the `_old` pair is for.
  double get fullAmount => currentDueAmount;

  /// ยอดค้างชำระ: the arrears **plus both fees**.
  ///
  /// ⚠ The penalty joined the collection fee here on 2026-09-17; before that
  /// only the collection fee rode along, and a contract carrying a penalty was
  /// under-billed on this option. The redesign draws all three rows and a
  /// `รวม` that sums them, so the option's headline figure has to match what
  /// its own block adds up to.
  double get overdueTotal => overdueAmount + collectionFee + penaltyFee;

  /// The amount [option] would send to the QR screen.
  ///
  /// [customText] is the raw field text, only read for
  /// [LoanPaymentOption.custom].
  double amountFor(LoanPaymentOption option, String customText) =>
      switch (option) {
        LoanPaymentOption.full => fullAmount,
        LoanPaymentOption.overdue => overdueTotal,
        LoanPaymentOption.custom => parsePaymentAmount(customText),
      };

  // ── which rows each option shows ────────────────────────────────────

  /// The arrears block (ค่างวดเลยกำหนดชำระ and its three rows) appears only
  /// when there are arrears. Zero is withheld rather than shown as `0.00`.
  bool get showsOverdueBlock => overdueAmount != 0;

  /// ค่าติดตามค้างชำระ appears only when a fee was charged — likewise.
  bool get showsCollectionFee => collectionFee != 0;

  /// ค่าเบี้ยปรับค้างชำระ, likewise — and it is how a response carrying no
  /// `penalty_fee` renders the design's own no-fee case rather than `0.00`.
  bool get showsPenaltyFee => penaltyFee != 0;

  /// Whether the **ยอดค้างชำระ** option's block ends in a `รวม` row.
  ///
  /// ⚠ Asymmetric with ชำระเต็มจำนวน, which always shows one — the source
  /// guards this option's total behind a fee being present and the other
  /// option's not at all. With no fee the total would only repeat the single
  /// row above it.
  ///
  /// ⚠ Widened on 2026-09-17 from "a collection fee" to "either fee", because
  /// the redesign added the penalty row: a contract with a penalty and no
  /// collection fee now also has more than one row to total.
  bool get showsArrearsTotal => showsCollectionFee || showsPenaltyFee;

  /// **คุณไม่มียอดค้างชำระ**, in place of the ยอดค้างชำระ option's detail
  /// block. The exact complement of [showsOverdueBlock].
  bool get showsNoOverdueNotice => !showsOverdueBlock;

  String get overdueRangeLabel =>
      'ค้างชำระ (งวดที่${contract.paymentDetails.overdueFrom}-'
      '${contract.paymentDetails.overdueTo})';

  /// งวดที่ N, under ค่างวดปัจจุบัน.
  String get currentInstallmentLabel =>
      'งวดที่ ${contract.paymentDetails.currentInstallmentNumber}';

  /// Due date shown against the **arrears** block — `overdue_date` **and
  /// nothing else**.
  ///
  /// ⚠ **It used to fall back to [currentDueDate]** (until 2026-09-19). On a
  /// real contract (2026-09-14, `000จYC69020100002NFX`) `overdue_date` came
  /// back empty while the old build plainly rendered a date in this row, and
  /// the fallback was added on the grounds that a blank date under a bill is
  /// certainly wrong.
  ///
  /// The policy is now the opposite, for a better reason: a date borrowed from
  /// the instalment block is wrong **silently**, and the customer cannot tell
  /// it apart from the real thing. `-` is visible, gets reported, and gets
  /// fixed at source. The loan detail screen's arrears block changed with it.
  ///
  /// ⚠ **An empty or unreadable `overdue_date` reads ชำระทันที, not `-`**
  /// (2026-09-23, tester round, on request). Still no borrowed date — arrears
  /// with no usable due date on file are due now, which is a statement, not a
  /// substitute value.
  String get overdueDueDate {
    final formatted = thaiDateOrDash(contract.paymentDetails.overdueDate);
    return formatted == '-' ? payNowLabel : formatted;
  }

  static const String payNowLabel = 'ชำระทันที';

  /// Due date of the instalment coming up (`current_due_date`).
  String get currentDueDate =>
      thaiDateOrDash(contract.paymentDetails.currentDueDate);

  // ── what the ชำระเงิน button does ───────────────────────────────────

  /// Whether the button is disabled for [option].
  ///
  /// The source computes this per option:
  ///
  ///   * the two fixed options are disabled when their total is zero — there
  ///     is nothing to pay, so there is no bill to raise;
  ///   * the typed option is disabled only when the field holds something that
  ///     reads as zero. An **empty** field leaves the button *enabled*, and
  ///     pressing it raises `กรอกจำนวนเงินที่ต้องการจ่ายค่างวด` — the prompt is
  ///     more useful than a dead button, and it is the source's behaviour.
  bool isDisabled(LoanPaymentOption option, String customText) =>
      switch (option) {
        LoanPaymentOption.full => fullAmount == 0,
        LoanPaymentOption.overdue => overdueTotal == 0,
        LoanPaymentOption.custom =>
          customText.isNotEmpty && parsePaymentAmount(customText) == 0,
      };

  /// Why a press cannot proceed, or null when it can. [LoanPaymentOption.full]
  /// and [LoanPaymentOption.overdue] always can — [isDisabled] has already
  /// stopped the zero cases.
  String? rejectionFor(LoanPaymentOption option, String customText) {
    if (option != LoanPaymentOption.custom) return null;
    if (customText.trim().isEmpty) {
      return 'กรอกจำนวนเงินที่ต้องการจ่ายค่างวด';
    }
    // `>= 1`, so exactly one baht is allowed even though the message reads
    // "more than 1". The wording is the source's; the rule is the source's too.
    if (parsePaymentAmount(customText) < 1) {
      return 'จำนวนที่จ่ายต้องมากกว่า 1 บาท';
    }
    return null;
  }

  // ── the typed field ─────────────────────────────────────────────────

  /// What the field should read once focus leaves it.
  ///
  /// ⚠ **An amount above [osBalance] is silently replaced by it.** That is the
  /// source's behaviour, reproduced deliberately: type 999,999 against a
  /// balance of 40,000 and the field hands back `40,000.00` with no message.
  ///
  /// ⚠⚠ That silence got quieter on 2026-09-14, when the ยอดหนี้คงเหลือ row
  /// was removed from the screen. The correction was previously explainable
  /// from what was on screen — the note named the rule and the row named the
  /// number. Now the note names the rule and the number is nowhere, so a
  /// customer who types more than their balance sees their figure change to
  /// one they have never been shown. Both halves are deliberate, but if that
  /// is ever reported as a bug, this is the reason and a toast here is the
  /// one-line fix.
  ///
  /// An empty field becomes `0.0` — not `0.00`; the source writes the shorter
  /// literal here and the comma formatter never runs on it.
  String blurredFieldText(String raw) {
    if (raw.isEmpty) return '0.0';
    final typed = parsePaymentAmount(raw);
    return formatMoney(typed <= osBalance ? typed : osBalance);
  }
}

/// The field text as a number: separators stripped, anything unparseable read
/// as zero.
///
/// Mirrors the source's `removeCommaFromNumText`, which strips every character
/// outside `[A-Za-z0-9.]` and falls back to `0.00` — so a field holding only
/// punctuation is zero rather than an error.
double parsePaymentAmount(String text) =>
    double.tryParse(text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
