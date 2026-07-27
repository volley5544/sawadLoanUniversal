/// Model for `POST /topup/calculator` — the repayment options for a requested
/// amount, listed on step 3 (เลือกจำนวนงวด).
///
/// Note the wire format: this endpoint's `installments[]` entries use
/// **camelCase** keys (`firstPeriodAmt`, `regularPeriodAmt`, …) while the
/// enclosing object and every other endpoint use snake_case. That asymmetry is
/// real — don't "normalise" it.
library;

import 'json_coerce.dart';

class InstallmentPlan {
  const InstallmentPlan({
    this.code = '',
    this.message = '',
    this.transNo = '',
    this.contractNo = '',
    this.firstDueDate = '',
    this.dueDay = 0,
    this.amount = 0,
    this.interestRate = 0,
    this.topupFeeAmount = 0,
    this.feeAmount = 0,
    this.installments = const [],
  });

  final String code;
  final String message;
  final String transNo;
  final String contractNo;

  /// Date the first installment falls due; sent on to the PDF generator.
  final String firstDueDate;
  final int dueDay;

  /// The approved amount this plan was calculated for.
  final int amount;
  final double interestRate;
  final int topupFeeAmount;
  final int feeAmount;

  /// Available tenors. The API returns shortest-first; step 3 shows them
  /// reversed (longest tenor, i.e. smallest monthly payment, first).
  final List<InstallmentOption> installments;

  bool get isOk => code == '200';

  /// Longest tenor first, matching the source's `reversedListInstallment`.
  List<InstallmentOption> get longestFirst =>
      installments.reversed.toList(growable: false);

  factory InstallmentPlan.fromJson(Map<String, dynamic> json) => InstallmentPlan(
        code: asString(json['code']),
        message: asString(json['message']),
        transNo: asString(json['trans_no']),
        contractNo: asString(json['contract_no']),
        firstDueDate: asString(json['first_due_date']),
        dueDay: asInt(json['due_day']),
        amount: asInt(json['amount']),
        interestRate: asDouble(json['interest_rate']),
        topupFeeAmount: asInt(json['topup_fee_amount']),
        feeAmount: asInt(json['fee_amount']),
        installments: asMapList(json['installments'])
            .map(InstallmentOption.fromJson)
            .toList(growable: false),
      );
}

/// One selectable repayment option. All keys are camelCase on the wire.
class InstallmentOption {
  const InstallmentOption({
    this.tenor = 0,
    this.firstPeriodAmt = 0,
    this.regularPeriodAmt = 0,
    this.lastPeriodAmt = 0,
    this.totalAmt = 0,
    this.intAmt = 0,
    this.lastPeriodPromo = 0,
    this.term = '',
    this.amount = '',
  });

  /// Number of installments.
  final int tenor;
  final int firstPeriodAmt;

  /// The headline monthly payment shown next to the tenor.
  final int regularPeriodAmt;
  final double lastPeriodAmt;

  /// Total repayable across the whole tenor.
  final double totalAmt;

  /// Total interest across the whole tenor.
  final double intAmt;
  final double lastPeriodPromo;
  final String term;
  final String amount;

  bool get isEmpty => tenor == 0 && regularPeriodAmt == 0;

  factory InstallmentOption.fromJson(Map<String, dynamic> json) =>
      InstallmentOption(
        tenor: asInt(json['tenor']),
        firstPeriodAmt: asInt(json['firstPeriodAmt']),
        regularPeriodAmt: asInt(json['regularPeriodAmt']),
        lastPeriodAmt: asDouble(json['lastPeriodAmt']),
        totalAmt: asDouble(json['totalAmt']),
        intAmt: asDouble(json['intAmt']),
        lastPeriodPromo: asDouble(json['lastPeriodPromo']),
        term: asString(json['term']),
        amount: asString(json['amount']),
      );
}
