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

  /// `payment_details.collection_fee` — ค่าติดตามทวงถาม.
  double get collectionFee => contract.paymentDetails.collectionFee;

  /// `payment_details.installment_amount` — the scheduled instalment, shown
  /// under ค่างวดปัจจุบัน.
  ///
  /// ⚠ Not [currentDueAmount], which is what is *owed* now. The two differ on
  /// a contract in arrears, and the source reads them from these two separate
  /// fields — see the same distinction on `LoanDetailSummary`.
  int get installmentAmount => contract.paymentDetails.installmentAmount;

  /// `contract_details.os_balance` — ยอดหนี้คงเหลือ, and the ceiling a typed
  /// amount is clamped to.
  double get osBalance => contract.contractDetails.osBalance;

  // ── per-option amounts ──────────────────────────────────────────────

  /// ชำระเต็มจำนวน: what is due now **plus** the collection fee.
  double get fullAmount => currentDueAmount + collectionFee;

  /// ยอดค้างชำระ: the arrears **plus** the collection fee.
  double get overdueTotal => overdueAmount + collectionFee;

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

  /// ค่าติดตามทวงถาม appears only when a fee was charged — likewise.
  bool get showsCollectionFee => collectionFee != 0;

  /// **คุณไม่มียอดค้างชำระ**, in place of the ยอดค้างชำระ option's detail
  /// block. The exact complement of [showsOverdueBlock].
  bool get showsNoOverdueNotice => !showsOverdueBlock;

  String get overdueRangeLabel =>
      'ค้างชำระ (งวดที่${contract.paymentDetails.overdueFrom}-'
      '${contract.paymentDetails.overdueTo})';

  /// งวดที่ N, under ค่างวดปัจจุบัน.
  String get currentInstallmentLabel =>
      'งวดที่ ${contract.paymentDetails.currentInstallmentNumber}';

  /// Due date of the **overdue** instalments (`overdue_date`), shown against
  /// the arrears block — as opposed to [currentDueDate] below.
  String get overdueDueDate =>
      formatThaiDate(contract.paymentDetails.overdueDate);

  /// Due date of the instalment coming up (`current_due_date`).
  String get currentDueDate =>
      formatThaiDate(contract.paymentDetails.currentDueDate);

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
  /// The screen carries a standing note saying it cannot exceed the balance,
  /// which is why the correction needs no toast of its own — but it does mean
  /// a customer who looks away mid-edit will not see it happen.
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
