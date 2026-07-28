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

  /// A minimal detail seeded from the step-1 [LoanContract], for a **new
  /// P-Loan**.
  ///
  /// A new P-Loan does not call `GET /topup/detail`: its reference contract is
  /// only a data key, and the top-up system rejects it (`ไม่พบสัญญาใน vloan`)
  /// for contracts that were never topped up. Everything step 2 shows before
  /// the customer names an amount can be read straight off the contract; the
  /// rate, stamp duty and due day come from the calculator, run on the typed
  /// amount from the Next button — see `PLoanAmountPage`, which folds the
  /// calculator's response back in with [copyWith].
  factory LoanAmountDetail.fromContract(LoanContract contract) =>
      LoanAmountDetail(
        code: '200',
        dbName: contract.dbName,
        contractNo: contract.contractNo,
        contractDate: contract.contractDate,
        contractDetails: contract.contractDetails,
        carDetails: contract.carDetails,
        // Not locked (an Extra-only concept) and no fee yet — the calculator
        // prices the duty for the amount the customer actually requests.
        interestPaidFlag: 'N',
      );

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
