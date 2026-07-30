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

  // There is no payoutFor() here any more. It computed
  // `requested − closing_balance − fee`, the *top-up* transfer: a top-up's
  // larger new loan closes the old contract, so its principal comes off. No
  // product in this flow does that — see [PLoanFlow.payoutAmount], which is
  // `requested − fee` for both kinds. Left as a comment rather than a deprecated
  // method so the wrong formula can't be picked back up by name.

  /// True when [amount] sits inside the allowed request range.
  bool isAmountAllowed(int amount) =>
      amount >= minTopupAmount && amount <= maxTopupAmount;

  /// The amount a **P-Loan Extra** requests: [topupExtra], exactly.
  ///
  /// **P-Loan Extra is not a top-up.** It reads the same `/topup/detail` payload
  /// the top-up card is built from, but the figure it lends is `topup_extra`
  /// ("วงเงินเพิ่มเติม") and that figure is **fixed** — the customer does not
  /// choose it, and [defaultTopupAmount] ("วงเงินสินเชื่อใหม่", the top-up
  /// total) is not a stand-in for it.
  ///
  /// [minTopupAmount] / [maxTopupAmount] are **deliberately not applied.** They
  /// bound the *top-up* product, and this is a different one. Verified against
  /// `MLOAN` / `ฮฮM680702003NF61X`: `topup_extra` 2,000 against a top-up floor
  /// of 8,000, so range-checking the offer would reject every small one and
  /// quietly file the top-up total (12,000) instead — which is what it did
  /// before this was understood.
  ///
  /// `0` means the contract carries **no offer**; callers gate on that rather
  /// than request nothing. See [PLoanFlow.isRequestedAmountAllowed].
  int get extraRequestAmount => topupExtra;

  /// The amount a **top-up-card deep link** should request, or null when the
  /// contract carries no offer to request.
  ///
  /// That entry point skips step 2, so nothing is typed: it is
  /// [extraRequestAmount], unless the card passed an explicit [requested]
  /// figure. That wins, rounded down to the nearest 100 the way step 2 rounds,
  /// so what is filed is the number the card displayed. There is no range left
  /// to refuse it against — see [extraRequestAmount] on why min/max don't apply.
  int? topupCardRequestAmount({int? requested}) {
    final amount =
        requested != null ? requested - (requested % 100) : extraRequestAmount;
    return amount > 0 ? amount : null;
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
