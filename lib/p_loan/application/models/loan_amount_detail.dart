/// Model for `GET /topup/detail?db_name=<db>&contract_no=<no>` — the limits,
/// rate and deductions that drive step 2 (ข้อมูลยอดจัดสินเชื่อ).
///
/// This is the envelope the amount screen validates against: the user may
/// request between [minTopupAmount] and [maxTopupAmount], starting at
/// [defaultTopupAmount].
library;

import 'json_coerce.dart';
import 'loan_contract.dart';

class LoanAmountDetail {
  const LoanAmountDetail({
    this.code = '',
    this.message = '',
    this.dbName = '',
    this.contractNo = '',
    this.contractDetails = const ContractDetails(),
    this.carDetails = const CarDetails(),
    this.firstDueDate = '',
    this.dueDay = 0,
    this.contractDate = '',
    this.defaultTopupAmount = 0,
    this.installmentNumber = 0,
    this.installmentAmount = 0,
    this.minAmountWithRate = 0,
    this.maxTopupAmount = 0,
    this.interestRate = 0,
    this.transferAmount = 0,
    this.osBalance = 0,
    this.dataDate = '',
    this.packageId = '',
    this.lifeInsureAmt = '',
    this.minTopupAmount = 0,
    this.topupExtra = 0,
    this.topupActual = 0,
    this.feeAmount = 0,
    this.balanceReceivable = 0,
    this.collectionFee = 0,
    this.penaltyFee = 0,
    this.overdueAmount = 0,
    this.overdueFrom = '',
    this.overdueTo = '',
    this.interestPaidFlag = '',
    this.interestYield = 0,
    this.topupSpecials = 0,
  });

  /// `'200'` on success; anything else means [message] should be shown and the
  /// screen abandoned.
  final String code;
  final String message;
  final String dbName;
  final String contractNo;
  final ContractDetails contractDetails;
  final CarDetails carDetails;
  final String firstDueDate;

  /// Day of month repayments fall due.
  final int dueDay;
  final String contractDate;

  /// Pre-filled request amount, and the value the installment calculator is
  /// first run with.
  final int defaultTopupAmount;
  final int installmentNumber;
  final int installmentAmount;
  final int minAmountWithRate;

  /// Upper bound for the amount input.
  final int maxTopupAmount;
  final double interestRate;
  final int transferAmount;
  final int osBalance;
  final String dataDate;
  final String packageId;
  final String lifeInsureAmt;

  /// Lower bound for the amount input.
  final int minTopupAmount;
  final int topupExtra;
  final int topupActual;

  /// Stamp duty, deducted from the payout.
  final int feeAmount;
  final int balanceReceivable;
  final int collectionFee;
  final int penaltyFee;
  final double overdueAmount;
  final String overdueFrom;
  final String overdueTo;

  /// `'Y'` means overdue interest is already settled; the source locks the
  /// amount input in that case.
  final String interestPaidFlag;

  /// `yield` on the wire — accrued interest (renamed: Dart reserved word).
  final int interestYield;
  final int topupSpecials;

  bool get isOk => code == '200';

  /// The source locks the amount field when interest has been paid.
  bool get isAmountLocked => interestPaidFlag == 'Y';

  /// Money actually transferred to the customer for [requestedAmount]: the
  /// request less the old contract's principal and the stamp duty. Mirrors the
  /// `จำนวนเงินที่จะได้รับ` row on the conclusion screen.
  int payoutFor(int requestedAmount) =>
      requestedAmount - contractDetails.closingBalance - feeAmount;

  /// True when [amount] sits inside the allowed request range.
  bool isAmountAllowed(int amount) =>
      amount >= minTopupAmount && amount <= maxTopupAmount;

  /// The amount a **top-up-card deep link** should request, or null when none
  /// of the candidates is one the calculator will price.
  ///
  /// That entry point skips step 2, so the amount is chosen here instead of
  /// typed. Priority, and why:
  ///
  /// 1. [requested] — a figure the card passed explicitly. Honoured strictly:
  ///    if it is out of range this returns null so the caller can *report* it,
  ///    rather than quietly filing a different number than the card displayed.
  /// 2. [topupExtra] (`topup_extra`, "วงเงินเพิ่มเติม") — what the top-up card
  ///    shows the customer, so it is the default. Often `0`, which is why it
  ///    cannot be the only source.
  /// 3. [defaultTopupAmount] ("วงเงินสินเชื่อใหม่") — what step 2 pre-fills.
  ///
  /// Candidates 2 and 3 fall through to the next when out of range: neither is
  /// a figure the customer asserted, so there is nothing to contradict. A
  /// [requested] value does not fall through, for exactly the opposite reason.
  int? topupCardRequestAmount({int? requested}) {
    if (requested != null) {
      final rounded = requested - (requested % 100);
      return isAmountAllowed(rounded) ? rounded : null;
    }
    for (final candidate in [topupExtra, defaultTopupAmount]) {
      if (candidate > 0 && isAmountAllowed(candidate)) return candidate;
    }
    return null;
  }

  factory LoanAmountDetail.fromJson(Map<String, dynamic> json) =>
      LoanAmountDetail(
        code: asString(json['code']),
        message: asString(json['message']),
        dbName: asString(json['db_name']),
        contractNo: asString(json['contract_no']),
        contractDetails:
            ContractDetails.fromJson(asMap(json['contract_details'])),
        carDetails: CarDetails.fromJson(asMap(json['car_details'])),
        firstDueDate: asString(json['first_due_date']),
        dueDay: asInt(json['due_day']),
        contractDate: asString(json['contract_date']),
        defaultTopupAmount: asInt(json['default_topup_amount']),
        installmentNumber: asInt(json['installment_number']),
        installmentAmount: asInt(json['installment_amount']),
        minAmountWithRate: asInt(json['min_amount_with_rate']),
        maxTopupAmount: asInt(json['max_topup_amount']),
        interestRate: asDouble(json['interest_rate']),
        transferAmount: asInt(json['transfer_amount']),
        osBalance: asInt(json['os_balance']),
        dataDate: asString(json['data_date']),
        packageId: asString(json['package_id']),
        lifeInsureAmt: asString(json['life_insure_amt']),
        minTopupAmount: asInt(json['min_topup_amount']),
        topupExtra: asInt(json['topup_extra']),
        topupActual: asInt(json['topup_actual']),
        feeAmount: asInt(json['fee_amount']),
        balanceReceivable: asInt(json['balance_receivable']),
        collectionFee: asInt(json['collection_fee']),
        penaltyFee: asInt(json['penalty_fee']),
        overdueAmount: asDouble(json['overdue_amount']),
        overdueFrom: asString(json['overdue_from']),
        overdueTo: asString(json['overdue_to']),
        interestPaidFlag: asString(json['interest_paid_flag']),
        interestYield: asInt(json['yield']),
        topupSpecials: asInt(json['topup_specials']),
      );

  // There is deliberately no `fromContract` seed for a new P-Loan. One existed
  // briefly, copying the reference contract's vehicle and limits onto the new
  // application — but a new P-Loan has no contract at all, so step 2 starts
  // from a bare `LoanAmountDetail(code: '200')` and the calculator fills in
  // the rate, due day and stamp duty via [copyWith].

  /// The fields step 2 folds back in after the calculator returns.
  ///
  /// An Extra refreshes only [feeAmount] (the duty for the requested amount);
  /// a new P-Loan additionally takes [interestRate], [dueDay] and
  /// [firstDueDate] from the calculator, since it skipped `GET /topup/detail`
  /// where those would otherwise come from.
  LoanAmountDetail copyWith({
    int? feeAmount,
    double? interestRate,
    int? dueDay,
    String? firstDueDate,
  }) =>
      LoanAmountDetail(
        code: code,
        message: message,
        dbName: dbName,
        contractNo: contractNo,
        contractDetails: contractDetails,
        carDetails: carDetails,
        firstDueDate: firstDueDate ?? this.firstDueDate,
        dueDay: dueDay ?? this.dueDay,
        contractDate: contractDate,
        defaultTopupAmount: defaultTopupAmount,
        installmentNumber: installmentNumber,
        installmentAmount: installmentAmount,
        minAmountWithRate: minAmountWithRate,
        maxTopupAmount: maxTopupAmount,
        interestRate: interestRate ?? this.interestRate,
        transferAmount: transferAmount,
        osBalance: osBalance,
        dataDate: dataDate,
        packageId: packageId,
        lifeInsureAmt: lifeInsureAmt,
        minTopupAmount: minTopupAmount,
        topupExtra: topupExtra,
        topupActual: topupActual,
        feeAmount: feeAmount ?? this.feeAmount,
        balanceReceivable: balanceReceivable,
        collectionFee: collectionFee,
        penaltyFee: penaltyFee,
        overdueAmount: overdueAmount,
        overdueFrom: overdueFrom,
        overdueTo: overdueTo,
        interestPaidFlag: interestPaidFlag,
        interestYield: interestYield,
        topupSpecials: topupSpecials,
      );
}
