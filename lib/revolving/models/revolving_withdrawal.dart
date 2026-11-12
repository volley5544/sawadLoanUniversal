/// `GET revolvingLoan/withdrawal/{contract_id}` — the BA's
/// `getMobileWithdrawal`: the line's summary and its withdrawal history.
///
/// Field names from the node-api guide (`revolving-frontend-api.md` §5),
/// checked against the QA response of 2026-11-12 (contract 2881).
library;

import '../../p_loan/application/models/json_coerce.dart';

/// `results.revolving_loan_summary`.
class RevolvingLoanSummary {
  const RevolvingLoanSummary({
    this.revolvingFlag = false,
    this.revolvingStatus = '',
    this.revolvingLimit = 0,
    this.maximumRevolvingLimit = 0,
    this.reservedLimit = 0,
    this.utilizationAmount = 0,
    this.utilizationPercentage = 0,
    this.withdrawalExpiryDate = '',
  });

  final bool revolvingFlag;
  final String revolvingStatus;
  final double revolvingLimit;

  /// `maximum_revolving_limit` — **วงเงินอนุมัติ** (the BA's
  /// `getRevolvingInfo.maximumRevolvingLimit`; `/loan/list` doesn't carry it).
  final double maximumRevolvingLimit;
  final double reservedLimit;
  final double utilizationAmount;
  final double utilizationPercentage;

  /// `withdrawal_expiry_date` — the last day a withdrawal may be made.
  /// `""` on QA.
  final String withdrawalExpiryDate;

  factory RevolvingLoanSummary.fromJson(Map<String, dynamic> json) =>
      RevolvingLoanSummary(
        revolvingFlag: asBool(json['revolving_flag']),
        revolvingStatus: asString(json['revolving_status']),
        revolvingLimit: asDouble(json['revolving_limit']),
        maximumRevolvingLimit: asDouble(json['maximum_revolving_limit']),
        reservedLimit: asDouble(json['reserved_limit']),
        utilizationAmount: asDouble(json['utilization_amount']),
        utilizationPercentage: asDouble(json['utilization_percentage']),
        withdrawalExpiryDate: asString(json['withdrawal_expiry_date']),
      );
}

/// One `results.withdrawal_transactions[]` entry.
class RevolvingWithdrawalTransaction {
  const RevolvingWithdrawalTransaction({
    this.contractNo = '',
    this.withdrawalAmount = 0,
    this.withdrawalStatus = '',
    this.withdrawalChannel = '',
    this.withdrawalDate = '',
    this.dueDate = '',
    this.transferDate = '',
    this.bankName = '',
    this.transferType = '',
    this.bankAccountNo = '',
  });

  final String contractNo;

  /// `withdrawal_amount` — the history row's **จำนวนเงิน**.
  final double withdrawalAmount;
  final String withdrawalStatus;
  final String withdrawalChannel;

  /// `withdrawal_date` — the history row's date. QA sends it as UTC end of
  /// day (`2026-05-20T16:59:59.999999Z`), i.e. 23:59 Thai time the same day.
  final String withdrawalDate;
  final String dueDate;
  final String transferDate;
  final String bankName;
  final String transferType;
  final String bankAccountNo;

  factory RevolvingWithdrawalTransaction.fromJson(Map<String, dynamic> json) =>
      RevolvingWithdrawalTransaction(
        contractNo: asString(json['contract_no']),
        withdrawalAmount: asDouble(json['withdrawal_amount']),
        withdrawalStatus: asString(json['withdrawal_status']),
        withdrawalChannel: asString(json['withdrawal_channel']),
        withdrawalDate: asString(json['withdrawal_date']),
        dueDate: asString(json['due_date']),
        transferDate: asString(json['transfer_date']),
        bankName: asString(json['bank_name']),
        transferType: asString(json['transfer_type']),
        bankAccountNo: asString(json['bank_account_no']),
      );
}

/// The whole `results` body.
class RevolvingWithdrawalInfo {
  const RevolvingWithdrawalInfo({
    this.summary = const RevolvingLoanSummary(),
    this.transactions = const [],
  });

  final RevolvingLoanSummary summary;

  /// In the order the API sends them (newest first on QA).
  final List<RevolvingWithdrawalTransaction> transactions;

  /// Accepts the `{results: {…}}` envelope or the bare body.
  factory RevolvingWithdrawalInfo.fromJson(Map<String, dynamic> json) {
    final results =
        json['results'] is Map ? asMap(json['results']) : json;
    return RevolvingWithdrawalInfo(
      summary: RevolvingLoanSummary.fromJson(
          asMap(results['revolving_loan_summary'])),
      transactions: asMapList(results['withdrawal_transactions'])
          .map(RevolvingWithdrawalTransaction.fromJson)
          .toList(growable: false),
    );
  }
}
