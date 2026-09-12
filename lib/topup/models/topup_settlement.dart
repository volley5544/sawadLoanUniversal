/// Models for `POST /GetRecalTopupData` — the recalculation behind the
/// **ยอดที่ต้องชำระเพื่อเติมวงเงิน** block on the amount screen.
///
/// The response is a superset of `GET /topup/detail`: the same limits and
/// rates, plus the outstanding-settlement breakdown that call has no fields
/// for. Only the new parts are modelled here — the overlapping ones are still
/// read from `LoanAmountDetail`, so there is one definition of each figure
/// rather than two that can disagree.
///
/// ## The breakdown is the server's, not ours
///
/// [TopupSettlementItem] carries its **own Thai `description`**. The rows are
/// rendered in `seq` order exactly as sent — the client maps nothing, names
/// nothing and totals nothing. That matters: the design's six rows
/// (ดอกเบี้ยสัญญาปัจจุบัน, ดอกเบี้ยค้างชำระยกมา, ค่าติดตามทวงถาม, ค่าเบี้ยปรับ,
/// เงินต้นค้างชำระ, ส่วนลด) do not all exist as fields on `/topup/detail`, and
/// guessing which of them `yield` meant would have put a wrong figure on a
/// bill. A server-driven list removes the question, and lets the breakdown
/// change without an app release. The supplied sample returns **three** items,
/// not six — so treat the length as variable.
library;

import '../../p_loan/application/models/json_coerce.dart';

/// One row of the settlement breakdown.
class TopupSettlementItem {
  const TopupSettlementItem({
    required this.seq,
    required this.fieldName,
    required this.description,
    required this.amount,
  });

  /// Display order. The list is sorted by this rather than by arrival, since
  /// the screen numbers the rows.
  final int seq;

  /// The server's own name for the figure (`yield`, `collection_fee`, …).
  /// Not displayed — kept so a support question about a row can be answered
  /// without guessing which field it came from.
  final String fieldName;

  /// The Thai label, **shown verbatim**. Never substitute a local string: the
  /// wording is the server's to change.
  final String description;

  final double amount;

  factory TopupSettlementItem.fromJson(Map<String, dynamic> json) =>
      TopupSettlementItem(
        seq: asInt(json['seq']),
        fieldName: asString(json['field_name']),
        description: asString(json['description']),
        amount: asDouble(json['amount']),
      );
}

/// `POST /GetRecalTopupData` — the parts `/topup/detail` does not carry.
class TopupRecalculation {
  const TopupRecalculation({
    this.code = '',
    this.message = '',
    this.settlementItems = const [],
    this.settlementTotalAmount = 0,
    this.overduePrincipalAmount = 0,
    this.topupDiscountAmount = 0,
    this.payoffBeforeSettlementAmount = 0,
    this.defaultTransferAmount = 0,
    this.closingBalance = 0,
    this.feeAmount = 0,
    this.minTopupAmount = 0,
    this.maxTopupAmount = 0,
    this.defaultTopupAmount = 0,
    this.topupExtra = 0,
    this.overdueDay = 0,
    this.campaignCode = '',
  });

  /// `'200'` on success; anything else means [message] should be shown.
  final String code;
  final String message;

  /// The **ยอดที่ต้องชำระเพื่อเติมวงเงิน** rows, in `seq` order.
  final List<TopupSettlementItem> settlementItems;

  /// **รวมยอดที่ต้องชำระ — the server's own total.**
  ///
  /// Displayed as sent rather than summed from [settlementItems]: the customer
  /// is being told what to pay, and a client that re-adds the rows can disagree
  /// with the server about the amount. [itemsSumMatchesTotal] exists to notice
  /// when they differ, not to override it.
  final double settlementTotalAmount;

  /// `overdue_principal_amount` — principal already past due.
  final double overduePrincipalAmount;

  /// `topup_discount_amount` — a discount applied to the settlement.
  final double topupDiscountAmount;

  /// What would be paid out before the settlement is deducted.
  final double payoffBeforeSettlementAmount;

  /// What actually reaches the account.
  final double defaultTransferAmount;

  final double closingBalance;
  final double feeAmount;
  final int minTopupAmount;
  final int maxTopupAmount;
  final int defaultTopupAmount;

  /// `topup_extra` — **the M35 วงเงินพิเศษ**, added on top of
  /// [defaultTopupAmount] rather than included in it.
  final int topupExtra;

  final int overdueDay;
  final String campaignCode;

  bool get isOk => code == '200';

  /// Whether the **ยอดที่ต้องชำระเพื่อเติมวงเงิน** section is shown at all.
  ///
  /// **`settlement_items` alone decides it** (instructed 2026-09-12): the
  /// section renders exactly what the server sent, so with no rows there is
  /// nothing to render and the whole block — heading, rows, total and the two
  /// buttons under it — is hidden. Deliberately **not** `total > 0`: a total
  /// with no rows would draw a heading and a figure with nothing explaining
  /// it, and the same sample that omits the rows is the one that would carry
  /// a stale total.
  bool get hasSettlement => settlementItems.isNotEmpty;

  /// Whether the rows add up to the total the server sent.
  ///
  /// A mismatch is not corrected — the server's total wins — but it is worth
  /// a breadcrumb, because it means the screen is showing a breakdown that
  /// does not explain the figure under it. Tolerant to a satang of rounding.
  bool get itemsSumMatchesTotal {
    if (settlementItems.isEmpty) return true;
    final sum = settlementItems.fold<double>(0, (a, i) => a + i.amount);
    return (sum - settlementTotalAmount).abs() < 0.01;
  }

  factory TopupRecalculation.fromJson(Map<String, dynamic> json) {
    final items = asMapList(json['settlement_items'])
        .map(TopupSettlementItem.fromJson)
        .toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    return TopupRecalculation(
      code: asString(json['code']),
      message: asString(json['message']),
      settlementItems: List.unmodifiable(items),
      settlementTotalAmount: asDouble(json['settlement_total_amount']),
      overduePrincipalAmount: asDouble(json['overdue_principal_amount']),
      topupDiscountAmount: asDouble(json['topup_discount_amount']),
      payoffBeforeSettlementAmount:
          asDouble(json['payoff_before_settlement_amount']),
      defaultTransferAmount: asDouble(json['default_transfer_amount']),
      closingBalance: asDouble(json['closing_balance']),
      feeAmount: asDouble(json['fee_amount']),
      minTopupAmount: asInt(json['min_topup_amount']),
      maxTopupAmount: asInt(json['max_topup_amount']),
      defaultTopupAmount: asInt(json['default_topup_amount']),
      topupExtra: asInt(json['topup_extra']),
      overdueDay: asInt(json['overdue_day']),
      campaignCode: asString(json['campaign_code']),
    );
  }
}

/// Mock-mode fixture — the supplied sample, with the amount substituted.
///
/// Built through the real [TopupRecalculation.fromJson] like every other
/// fixture in this repo, so a wire-key change breaks it too rather than
/// letting it drift.
TopupRecalculation mockRecalculation(num topupAmount) =>
    TopupRecalculation.fromJson({
      'code': '200',
      'message': 'success',
      'default_topup_amount': topupAmount,
      'min_topup_amount': 86500,
      'max_topup_amount': 91000,
      'closing_balance': 86217.08,
      'fee_amount': 45,
      'overdue_day': 0,
      'overdue_principal_amount': 0.00,
      'topup_discount_amount': 0.00,
      'payoff_before_settlement_amount': 2282.92,
      'default_transfer_amount': 2282.92,
      'settlement_items': [
        {'seq': 1, 'field_name': 'yield', 'description': 'ดอกเบี้ย',
          'amount': 2589.72},
        {'seq': 2, 'field_name': 'collection_fee',
          'description': 'ค่าติดตามทวงถาม', 'amount': 50.00},
        {'seq': 3, 'field_name': 'penalty_fee', 'description': 'ค่าเบี้ยปรับ',
          'amount': 2.49},
      ],
      'settlement_total_amount': 2642.21,
      'campaign_code': '',
    });
