/// The derived rules behind the **รายละเอียดสินเชื่อ** header card.
///
/// Every one of these is transcribed from the srisawad mobile app's
/// `loan_installment_payment_detail.dart`, which computes them inline. They
/// live here instead so they can be pinned by a test: the card is a wall of
/// nested ternaries over three dates and four amounts, and "the overdue figure
/// turned red a day early" is not something a screenshot review catches.
///
/// The source's widget also carries a whole second mode behind a `subTitle`
/// argument, for reuse elsewhere. The loan detail page never passes it, so
/// that branch is not reproduced — it would be dead code wearing the
/// appearance of a rule.
library;

import '../../p_loan/application/components/p_loan_components.dart';
import '../../p_loan/application/models/loan_contract.dart';

class LoanDetailSummary {
  LoanDetailSummary(this.contract);

  final LoanContract contract;

  // ── the three facts everything else hangs off ───────────────────────

  int get currentInstallmentNumber =>
      contract.paymentDetails.currentInstallmentNumber;

  /// `total_installment_number`. Parsed as a `double` by [PaymentDetails]
  /// because the top-up endpoints send it that way, but it is a count — so it
  /// is rounded before it is compared or shown, or the last installment of 24
  /// renders as `24.0 งวด` and never equals `24`.
  int get totalInstallmentNumber =>
      contract.paymentDetails.totalInstallmentNumber.round();

  /// The customer is on the **last** installment.
  ///
  /// The whole card changes shape here: the due date can fall back to the
  /// server's own date, the overdue and current-installment figures can be
  /// replaced by the words `เกินกำหนดชำระ`, and `รวมต้องชำระ` disappears.
  bool get isFinalInstallment =>
      currentInstallmentNumber == totalInstallmentNumber;

  /// Due date, from `payment_details.current_due_date`.
  DateTime? get dueDate => DateTime.tryParse(contract.paymentDetails.currentDueDate.trim());

  /// The **server's** clock, from `payment_details.current_date_time`.
  ///
  /// Used rather than `DateTime.now()` on purpose, and it matters here more
  /// than anywhere: a device clock a day fast would tell a customer who is
  /// paid up that they are overdue.
  DateTime? get serverDate =>
      DateTime.tryParse(contract.paymentDetails.currentDateTime.trim());

  /// The due date has not passed yet.
  ///
  /// Either date being unreadable reads as **false** — i.e. treated as due.
  /// The source would throw outright on an unparseable value, so there is no
  /// behaviour to match; this is the direction that does not promise a
  /// customer more time than they have.
  bool get dueDateInFuture {
    final due = dueDate;
    final now = serverDate;
    if (due == null || now == null) return false;
    return due.isAfter(now);
  }

  // ── ชำระภายในวันที่ ─────────────────────────────────────────────────

  /// On the last installment **after** the due date has passed, the row shows
  /// the server's date rather than the contract's — the amount quoted is what
  /// is owed today, not what was owed on a date already gone.
  String get payByDateLabel {
    if (isFinalInstallment && !dueDateInFuture) {
      return formatThaiDate(contract.paymentDetails.currentDateTime);
    }
    return formatThaiDate(contract.paymentDetails.currentDueDate);
  }

  /// The due date is shown red once it has passed.
  bool get payByDateIsOverdue => !dueDateInFuture;

  // ── ค้างชำระ (งวดที่ F-T) ───────────────────────────────────────────

  int get overdueFrom => int.tryParse(contract.paymentDetails.overdueFrom.trim()) ?? 0;
  int get overdueTo => int.tryParse(contract.paymentDetails.overdueTo.trim()) ?? 0;

  /// Only when there is an actual overdue *range*. `0-0` is the API's way of
  /// saying "nothing overdue", and the row is withheld rather than shown as
  /// zero.
  bool get showsOverdueRow => overdueFrom != 0 && overdueTo != 0;

  String get overdueRangeLabel => 'ค้างชำระ (งวดที่$overdueFrom-$overdueTo)';

  /// True when a figure is replaced by the words **เกินกำหนดชำระ**.
  ///
  /// Only on the last installment, once the due date has passed: at that point
  /// the amount on file is stale — the payoff has to be quoted by the branch —
  /// so the card says so instead of showing a number that would be acted on.
  bool get showsPastDueInsteadOfAmount => isFinalInstallment && !dueDateInFuture;

  static const String pastDueLabel = 'เกินกำหนดชำระ';

  String get overdueValueLabel => showsPastDueInsteadOfAmount
      ? pastDueLabel
      : formatMoney(contract.paymentDetails.overdueAmount);

  // ── งวดปัจจุบัน / งวดสุดท้าย ────────────────────────────────────────

  bool get showsInstallmentRow =>
      currentInstallmentNumber != 0 && totalInstallmentNumber != 0;

  String get installmentLabel =>
      isFinalInstallment ? 'งวดสุดท้าย' : 'งวดปัจจุบัน';

  /// On the last installment the denominator is dropped — `24/24` says less
  /// than `24` under the label `งวดสุดท้าย`.
  String get installmentValue => isFinalInstallment
      ? '$currentInstallmentNumber'
      : '$currentInstallmentNumber/$totalInstallmentNumber';

  // ── ค่างวดปัจจุบัน ──────────────────────────────────────────────────

  /// ⚠ From `contract_details.installment_amount`, **not** the identically
  /// named field on `payment_details`. The source reads the contract's, which
  /// is the scheduled installment; the payment one is what is due now and
  /// feeds `รวมต้องชำระ` below.
  int get currentInstallmentAmount => contract.contractDetails.installmentAmount;

  bool get showsCurrentInstallmentAmountRow => currentInstallmentAmount != 0;

  String get currentInstallmentAmountLabel => showsPastDueInsteadOfAmount
      ? pastDueLabel
      : formatMoney(currentInstallmentAmount);

  // ── รวมต้องชำระ ─────────────────────────────────────────────────────

  double get totalDueAmount => contract.paymentDetails.currentDueAmount;

  /// Withheld on the last installment: there is nothing left to total, and the
  /// note below the card explains why the figure above it is not a payoff.
  bool get showsTotalDueRow => !isFinalInstallment && totalDueAmount != 0;

  String get totalDueLabel => formatMoney(totalDueAmount);

  // ── the closing-balance caveat ──────────────────────────────────────

  /// The red note under the card on a last installment, saying the figure is
  /// not a payoff quote.
  bool get showsNotAClosingBalanceNote =>
      isFinalInstallment && currentInstallmentNumber != 0 && totalInstallmentNumber != 0;

  /// ⚠ Reproduced **verbatim from the shipped app, typo included**
  /// (`ไม่ไช่` for `ไม่ใช่`). It is what a customer reads on this screen
  /// today; correcting it here alone would make the two builds disagree on a
  /// sentence about their payoff balance. Fix it in both or neither.
  static const String notAClosingBalanceNote =
      '(ยอดดังกล่าวไม่ไช่ยอดปิดบัญชี กรุณาติดต่อสาขาเพื่อขอยอดปิดบัญชี หรือต่อสัญญา)';

  // ── กรมธรรม์ ────────────────────────────────────────────────────────

  bool get showsInsuranceRow => contract.insurances.isNotEmpty;
}
