/// Model for `GET /topup/status-detail/{hash_thai_id}/{db_name}/{trans_no}` —
/// the state of a top-up request that has already been filed.
///
/// Reached from the contract card when `GET /loan/list` reports a contract
/// whose `request_status` is anything but "no request yet": the customer can
/// no longer raise one, so they are shown this instead.
library;

import '../../p_loan/application/models/json_coerce.dart';
import '../../p_loan/application/models/loan_documents.dart';

class TopupStatus {
  const TopupStatus({
    this.code = '',
    this.message = '',
    this.contractName = '',
    this.contractNo = '',
    this.contractBankAccount = '',
    this.contractBankBrandname = '',
    this.loanTypeCode = '',
    this.loanTypeName = '',
    this.loanTypeIcon = '',
    this.requestDate = '',
    this.requestStatus = '',
    this.collateralInformation = '',
    this.amount = 0,
    this.amountPerInstallment = 0,
    this.installmentNumber = 0,
    this.totalAmountWithRate = 0,
    this.interestRate = 0,
    this.requestFile = '',
    this.agreementFile = '',
    this.receiptFile = '',
    this.actualReceiveAmount = 0,
    this.branchImage = '',
  });

  /// `'200'` on success; anything else means [message] should be shown.
  final String code;
  final String message;

  final String contractName;
  final String contractNo;
  final String contractBankAccount;
  final String contractBankBrandname;
  final String loanTypeCode;
  final String loanTypeName;

  /// Base64 image, not a URL.
  final String loanTypeIcon;

  final String requestDate;

  /// Free-text Thai status, e.g. `รอตรวจสอบ`. Displayed verbatim — the API
  /// owns this wording.
  final String requestStatus;

  final String collateralInformation;

  /// The requested amount.
  final int amount;
  final int amountPerInstallment;
  final int installmentNumber;
  final double totalAmountWithRate;
  final double interestRate;

  /// The three contract PDFs, base64, as filed. Same three documents step 7
  /// generated — re-served here so the customer can read them afterwards.
  final String requestFile;
  final String agreementFile;
  final String receiptFile;

  /// What actually reached the customer's account.
  final int actualReceiveAmount;

  /// Branch logo, base64.
  final String branchImage;

  bool get isOk => code == '200';

  /// The documents in the shape the shared viewer takes, so the status screen
  /// and the conclusion screen render document rows the same way.
  LoanDocuments get documents => LoanDocuments(
        request: requestFile,
        receipt: receiptFile,
        agreement: agreementFile,
      );

  bool get hasDocuments => documents.isComplete;

  factory TopupStatus.fromJson(Map<String, dynamic> json) => TopupStatus(
        code: asString(json['code']),
        message: asString(json['message']),
        contractName: asString(json['contract_name']),
        contractNo: asString(json['contract_no']),
        contractBankAccount: asString(json['contract_bank_account']),
        contractBankBrandname: asString(json['contract_bank_brandname']),
        loanTypeCode: asString(json['loan_type_code']),
        loanTypeName: asString(json['loan_type_name']),
        loanTypeIcon: asString(json['loan_type_icon']),
        requestDate: asString(json['request_date']),
        requestStatus: asString(json['request_status']),
        collateralInformation: asString(json['collateral_information']),
        amount: asInt(json['amount']),
        amountPerInstallment: asInt(json['amount_per_installment']),
        installmentNumber: asInt(json['installment_number']),
        totalAmountWithRate: asDouble(json['total_amount_with_rate']),
        interestRate: asDouble(json['interest_rate']),
        requestFile: asString(json['topup_request_file']),
        // Misspelled on the wire — matches the API, not our typo.
        agreementFile: asString(json['topup_argeement_file']),
        receiptFile: asString(json['topup_receipt_file']),
        actualReceiveAmount: asInt(json['actual_receive_amount']),
        branchImage: asString(json['branch_image']),
      );
}

/// Fixture for `--dart-define=P_LOAN_MOCK=true`, so the status screen can be
/// demoed without a backend.
///
/// Lives here rather than in `p_loan_mock.dart` because the P-Loan flow has no
/// status screen — this is the top-up flow's own fixture. Built through
/// [TopupStatus.fromJson] like the P-Loan ones, so a wire-key change breaks it
/// too instead of letting it drift.
TopupStatus mockTopupStatus(String transNo) => TopupStatus.fromJson({
      'code': '200',
      'message': '',
      'contract_name': 'สัญญาเช่าซื้อรถยนต์',
      'contract_no': 'MOCK-C-6701002',
      'contract_bank_account': '9876543210',
      'contract_bank_brandname': 'SCB',
      'loan_type_code': 'C',
      'loan_type_name': 'สินเชื่อรถยนต์',
      'request_date': '2026-09-01',
      'request_status': 'MOCK - รอตรวจสอบเอกสาร',
      'collateral_information': 'โตโยต้า วีออส 1ขค 5678',
      'amount': 400000,
      'amount_per_installment': 19000,
      'installment_number': 24,
      'total_amount_with_rate': 456000.0,
      'interest_rate': 1.09,
      'actual_receive_amount': 219900,
      'topup_request_file': '',
      'topup_argeement_file': '',
      'topup_receipt_file': '',
      'branch_image': '',
    });
