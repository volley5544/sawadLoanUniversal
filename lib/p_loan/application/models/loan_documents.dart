/// Models for `POST /pdf/loan` — generates the three contract documents the
/// customer must read and accept on step 6.
library;

import 'json_coerce.dart';

/// Request body for `POST /pdf/loan`, and the same object is echoed back
/// inside the submit payload as `save_pdf`.
///
/// Numeric types match the wire exactly, which means [installmentNumber] is a
/// `double` here even though the same value is an `int` on `/topup/detail` and
/// `/topup/status-detail`. Keeping it as the server expects avoids a
/// server-side coercion surprise.
class ContractPdfRequest {
  const ContractPdfRequest({
    required this.contractNo,
    required this.dbName,
    required this.contractDate,
    required this.amount,
    required this.from,
    required this.contractBankAccount,
    required this.contractBankBrandname,
    required this.contractBankType,
    required this.contractBankBranch,
    required this.interestRate,
    required this.installmentNumber,
    required this.amountPerInstallment,
    required this.startInstallmentDate,
    required this.installmentDate,
    required this.vehicleType,
  });

  final String contractNo;
  final String dbName;
  final String contractDate;

  /// The payout amount (request less old principal and stamp duty).
  final double amount;

  /// Originating branch code (`contract_details.comcode`).
  final String from;
  final String contractBankAccount;
  final String contractBankBrandname;
  final String contractBankType;
  final String contractBankBranch;
  final double interestRate;
  final double installmentNumber;
  final double amountPerInstallment;
  final String startInstallmentDate;
  final String installmentDate;
  final String vehicleType;

  Map<String, dynamic> toJson() => {
        'contract_no': contractNo,
        'db_name': dbName,
        'contract_date': contractDate,
        'amount': amount,
        'from': from,
        'contract_bank_account': contractBankAccount,
        'contract_bank_brandname': contractBankBrandname,
        'contract_bank_type': contractBankType,
        'contract_bank_branch': contractBankBranch,
        'interest_rate': interestRate,
        'installment_number': installmentNumber,
        'amount_per_installment': amountPerInstallment,
        'start_installment_date': startInstallmentDate,
        'installment_date': installmentDate,
        'vehicle_type': vehicleType,
      };
}

/// Response of `POST /pdf/loan` — three base64-encoded PDFs.
class LoanDocuments {
  const LoanDocuments({
    this.request = '',
    this.receipt = '',
    this.agreement = '',
  });

  /// ใบคำขอสินเชื่อใหม่ — the loan application form.
  final String request;

  /// ใบรับเงิน — the receipt.
  final String receipt;

  /// เอกสารสัญญา — the contract itself.
  final String agreement;

  bool get isComplete =>
      request.isNotEmpty && receipt.isNotEmpty && agreement.isNotEmpty;

  factory LoanDocuments.fromJson(Map<String, dynamic> json) => LoanDocuments(
        request: asString(json['request']),
        receipt: asString(json['receipt']),
        agreement: asString(json['agreement']),
      );
}

/// The three documents in the fixed order step 6 lists and consents to them.
enum LoanDocumentKind {
  request('ใบคำขอสินเชื่อใหม่'),
  receipt('ใบรับเงิน'),
  agreement('เอกสารสัญญา');

  const LoanDocumentKind(this.title);

  /// Thai title shown in the document row and the consent sheet.
  final String title;

  /// The matching base64 blob from [LoanDocuments].
  String base64From(LoanDocuments docs) => switch (this) {
        LoanDocumentKind.request => docs.request,
        LoanDocumentKind.receipt => docs.receipt,
        LoanDocumentKind.agreement => docs.agreement,
      };

  /// Thai message shown when the user tries to submit without consenting.
  String get consentPrompt => 'กรุณาให้ความยินยอม$title';
}
