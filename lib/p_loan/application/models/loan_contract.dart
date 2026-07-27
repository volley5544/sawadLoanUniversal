/// Models for `GET /loan/list?hash_thai_id=<hash>` — the customer's existing
/// loan contracts, one of which the P-Loan flow is raised against.
///
/// Field names and JSON keys are taken verbatim from the source FlutterFlow
/// structs. Two wire keys are deliberately *not* tidied up because the API
/// really spells them this way: [CarDetails.chassisNo] reads `car_chassisNo`
/// and [CarDetails.engineNo] reads `car_engineNo` (mixed case among otherwise
/// snake_case siblings).
///
/// Only `fromJson` is provided for the read-only response models — nothing in
/// the flow sends a contract back to the server. The submit payload lives in
/// `topup_submission.dart`.
library;

import 'json_coerce.dart';

/// One row of `$.results` — a contract the customer already holds.
class LoanContract {
  const LoanContract({
    this.contractName = '',
    this.branchCode = '',
    this.branchName = '',
    this.branchImage = '',
    this.dbName = '',
    this.contractNo = '',
    this.contractBankType = '',
    this.contractBankAccount = '',
    this.contractBankBrandname = '',
    this.contractDetails = const ContractDetails(),
    this.contractDate = '',
    this.contractCloseDate = '',
    this.contractBranchCreatedName = '',
    this.loanTypeCode = '',
    this.loanTypeName = '',
    this.paymentDetails = const PaymentDetails(),
    this.barcodeDetails = const BarcodeDetails(),
    this.topupDetail = const TopupDetail(),
    this.insurances = const [],
    this.dataDate = '',
    this.transNo = '',
    this.requestTopupAmount = 0,
    this.requestDate = '',
    this.requestStatus = '',
    this.requestStatusCode = '',
    this.carDetails = const CarDetails(),
  });

  final String contractName;
  final String branchCode;
  final String branchName;

  /// Bank/branch logo as a base64 image (decoded for display, not a URL).
  final String branchImage;

  /// Backing database name — every downstream call needs it alongside
  /// [contractNo] to identify the contract.
  final String dbName;
  final String contractNo;
  final String contractBankType;
  final String contractBankAccount;
  final String contractBankBrandname;
  final ContractDetails contractDetails;
  final String contractDate;
  final String contractCloseDate;
  final String contractBranchCreatedName;
  final String loanTypeCode;
  final String loanTypeName;
  final PaymentDetails paymentDetails;
  final BarcodeDetails barcodeDetails;
  final TopupDetail topupDetail;
  final List<Insurance> insurances;
  final String dataDate;

  /// Transaction number of an in-flight request, empty when there is none.
  final String transNo;
  final int requestTopupAmount;
  final String requestDate;
  final String requestStatus;
  final String requestStatusCode;
  final CarDetails carDetails;

  /// The status text the API uses for "no request raised yet". The flow may
  /// only be started from this state; any other status means a request is
  /// already in progress and the user should be shown its status instead.
  static const String statusNoRequestYet = 'ยังไม่ได้ทำรายการเติมเงิน';

  /// Whether a new request can be started for this contract.
  bool get hasNoRequestYet =>
      requestStatus.isEmpty || requestStatus == statusNoRequestYet;

  /// `account_status == 'A'` is the only state the source ever lists.
  bool get isActive => contractDetails.accountStatus == 'A';

  /// `can_topup == 'Y'`. When false, [TopupDetail.canTopupMsg] explains why.
  bool get isEligible => topupDetail.canTopup == 'Y';

  /// Promissory-note accounts behave differently and are excluded from the
  /// flow throughout the source.
  bool get isPromissoryNote => contractDetails.accountType == 'L';

  /// Selectable in the contract picker.
  bool get isSelectable => isActive && !isPromissoryNote;

  factory LoanContract.fromJson(Map<String, dynamic> json) => LoanContract(
        contractName: asString(json['contract_name']),
        branchCode: asString(json['branch_code']),
        branchName: asString(json['branch_name']),
        branchImage: asString(json['branch_image']),
        dbName: asString(json['db_name']),
        contractNo: asString(json['contract_no']),
        contractBankType: asString(json['contract_bank_type']),
        contractBankAccount: asString(json['contract_bank_account']),
        contractBankBrandname: asString(json['contract_bank_brandname']),
        contractDetails: ContractDetails.fromJson(asMap(json['contract_details'])),
        contractDate: asString(json['contract_date']),
        contractCloseDate: asString(json['contract_close_date']),
        contractBranchCreatedName:
            asString(json['contract_branch_created_name']),
        loanTypeCode: asString(json['loan_type_code']),
        loanTypeName: asString(json['loan_type_name']),
        paymentDetails: PaymentDetails.fromJson(asMap(json['payment_details'])),
        barcodeDetails: BarcodeDetails.fromJson(asMap(json['barcode_details'])),
        topupDetail: TopupDetail.fromJson(asMap(json['topup_detail'])),
        insurances: asMapList(json['insurances'])
            .map(Insurance.fromJson)
            .toList(growable: false),
        dataDate: asString(json['data_date']),
        transNo: asString(json['transno']),
        requestTopupAmount: asInt(json['request_topup_amount']),
        requestDate: asString(json['request_date']),
        requestStatus: asString(json['request_status']),
        requestStatusCode: asString(json['request_status_code']),
        carDetails: CarDetails.fromJson(asMap(json['car_details'])),
      );

  @override
  String toString() => 'LoanContract($contractNo, $loanTypeName)';
}

/// `contract_details` — the contract's financial and collateral summary.
class ContractDetails {
  const ContractDetails({
    this.closingBalance = 0,
    this.comcode = '',
    this.branchCode = '',
    this.branchName = '',
    this.canTopup = '',
    this.collateralInformation = '',
    this.licensePlateProvince = '',
    this.licensePlateExpireDate = '',
    this.vehicleBrand = '',
    this.currentLtvAmount = 0,
    this.creditLimit = 0,
    this.financeAmount = 0,
    this.osBalance = 0,
    this.installmentAmount = 0,
    this.currentDueAmount = 0,
    this.currentDueDate = '',
    this.accountStatus = '',
    this.loanTypeCode = '',
    this.loanTypeName = '',
    this.loanTypeIcon = '',
    this.comcodeCode = '',
    this.arRemainAmount = 0,
    this.firstDueDate = '',
    this.lastDueDate = '',
    this.accountType = '',
    this.accountTypeMsg = '',
    this.contStat = '',
    this.targetStat = '',
  });

  /// Outstanding principal, deducted from the new loan amount at payout.
  final int closingBalance;
  final String comcode;
  final String branchCode;
  final String branchName;
  final String canTopup;
  final String collateralInformation;
  final String licensePlateProvince;
  final String licensePlateExpireDate;
  final String vehicleBrand;

  /// Current appraised collateral value.
  final int currentLtvAmount;
  final double creditLimit;
  final double financeAmount;
  final double osBalance;
  final int installmentAmount;
  final double currentDueAmount;
  final String currentDueDate;
  final String accountStatus;
  final String loanTypeCode;
  final String loanTypeName;
  final String loanTypeIcon;
  final String comcodeCode;
  final double arRemainAmount;
  final String firstDueDate;
  final String lastDueDate;
  final String accountType;

  /// Explains an unusable [accountType] (shown instead of the amount rows).
  final String accountTypeMsg;
  final String contStat;
  final String targetStat;

  factory ContractDetails.fromJson(Map<String, dynamic> json) =>
      ContractDetails(
        closingBalance: asInt(json['closing_balance']),
        comcode: asString(json['comcode']),
        branchCode: asString(json['branch_code']),
        branchName: asString(json['branch_name']),
        canTopup: asString(json['can_topup']),
        collateralInformation: asString(json['collateral_information']),
        licensePlateProvince: asString(json['license_plate_province']),
        licensePlateExpireDate: asString(json['license_plate_expire_date']),
        vehicleBrand: asString(json['vehicle_brand']),
        currentLtvAmount: asInt(json['current_ltv_amount']),
        creditLimit: asDouble(json['credit_limit']),
        financeAmount: asDouble(json['finance_amount']),
        osBalance: asDouble(json['os_balance']),
        installmentAmount: asInt(json['installment_amount']),
        currentDueAmount: asDouble(json['current_due_amount']),
        currentDueDate: asString(json['current_due_date']),
        accountStatus: asString(json['account_status']),
        loanTypeCode: asString(json['loan_type_code']),
        loanTypeName: asString(json['loan_type_name']),
        loanTypeIcon: asString(json['loan_type_icon']),
        comcodeCode: asString(json['comcode_code']),
        arRemainAmount: asDouble(json['ar_remain_amount']),
        firstDueDate: asString(json['first_due_date']),
        lastDueDate: asString(json['last_due_date']),
        accountType: asString(json['account_type']),
        accountTypeMsg: asString(json['account_type_msg']),
        contStat: asString(json['cont_stat']),
        targetStat: asString(json['target_stat']),
      );
}

/// `payment_details` — repayment history/state for the contract.
class PaymentDetails {
  const PaymentDetails({
    this.installmentAmount = 0,
    this.overdueAmount = 0,
    this.currentDueAmount = 0,
    this.currentInstallmentNumber = 0,
    this.totalInstallmentNumber = 0,
    this.currentDueDate = '',
    this.totalPaidAmount = 0,
    this.osBalance = 0,
    this.overdueDays = 0,
    this.overdueTerms = 0,
    this.overdueFrom = '',
    this.overdueTo = '',
    this.latestPaidDate = '',
    this.currentDateTime = '',
    this.collectionFee = 0,
  });

  final int installmentAmount;
  final double overdueAmount;
  final double currentDueAmount;
  final int currentInstallmentNumber;

  /// `double` on this endpoint even though `TopupDetail` sends it as an int.
  final double totalInstallmentNumber;
  final String currentDueDate;
  final double totalPaidAmount;
  final double osBalance;
  final int overdueDays;
  final int overdueTerms;
  final String overdueFrom;
  final String overdueTo;
  final String latestPaidDate;

  /// Server-side timestamp; the source uses it as the request date rather than
  /// the device clock, so a wrong device time can't date a contract.
  final String currentDateTime;
  final double collectionFee;

  factory PaymentDetails.fromJson(Map<String, dynamic> json) => PaymentDetails(
        installmentAmount: asInt(json['installment_amount']),
        overdueAmount: asDouble(json['overdue_amount']),
        currentDueAmount: asDouble(json['current_due_amount']),
        currentInstallmentNumber: asInt(json['current_installment_number']),
        totalInstallmentNumber: asDouble(json['total_installment_number']),
        currentDueDate: asString(json['current_due_date']),
        totalPaidAmount: asDouble(json['total_paid_amount']),
        osBalance: asDouble(json['os_balance']),
        overdueDays: asInt(json['overdue_days']),
        overdueTerms: asInt(json['overdue_terms']),
        overdueFrom: asString(json['overdue_from']),
        overdueTo: asString(json['overdue_to']),
        latestPaidDate: asString(json['latest_paid_date']),
        currentDateTime: asString(json['current_date_time']),
        collectionFee: asDouble(json['collection_fee']),
      );
}

/// `barcode_details` — repayment barcode parts.
class BarcodeDetails {
  const BarcodeDetails({
    this.prefix = '',
    this.suffix = '',
    this.taxId = '',
    this.ref1 = '',
    this.ref2 = '',
    this.fullBarcode = '',
    this.comcode = '',
  });

  final String prefix;
  final String suffix;
  final String taxId;
  final String ref1;
  final String ref2;
  final String fullBarcode;
  final String comcode;

  factory BarcodeDetails.fromJson(Map<String, dynamic> json) => BarcodeDetails(
        prefix: asString(json['prefix']),
        suffix: asString(json['suffix']),
        taxId: asString(json['tax_id']),
        ref1: asString(json['ref1']),
        ref2: asString(json['ref2']),
        fullBarcode: asString(json['full_barcode']),
        comcode: asString(json['comcode']),
      );
}

/// `topup_detail` — eligibility and headline limits for raising a new request
/// against this contract.
class TopupDetail {
  const TopupDetail({
    this.totalInstallmentAmount = 0,
    this.canTopup = '',
    this.defaultTopupAmount = 0,
    this.totalInstallmentNumber = 0,
    this.currentLtvAmount = 0,
    this.accountStatus = '',
    this.topupExtra = 0,
    this.feeAmount = 0,
    this.balanceReceivable = 0,
    this.collectionFee = 0,
    this.penaltyFee = 0,
    this.interestYield = 0,
    this.interestPaidFlag = '',
    this.canTopupMsg = '',
    this.maxTransferAmount = 0,
    this.products = const [],
    this.defaultTransferAmount = 0,
    this.topupSpecials = 0,
  });

  final int totalInstallmentAmount;

  /// `Y` eligible, `N` not; other codes (`G`, `A`) appear in the source's
  /// display conditions.
  final String canTopup;

  /// Headline approved limit shown on the contract card.
  final int defaultTopupAmount;
  final int totalInstallmentNumber;
  final int currentLtvAmount;
  final String accountStatus;

  /// Extra limit granted on top of the default, shown in red when non-zero.
  final int topupExtra;

  /// Stamp duty, deducted at payout.
  final int feeAmount;

  /// Total payable to close the old contract.
  final int balanceReceivable;
  final int collectionFee;
  final int penaltyFee;

  /// `yield` on the wire — accrued interest. Renamed here because `yield` is
  /// a Dart reserved word.
  final int interestYield;
  final String interestPaidFlag;

  /// Why [canTopup] isn't `Y`; shown to the user in place of the limits.
  final String canTopupMsg;
  final int maxTransferAmount;

  /// Add-on products offered with the limit. Not used by this flow (the
  /// product grid was left out of the slim contract picker), kept because the
  /// submit payload carries a product code.
  final List<LoanProduct> products;
  final double defaultTransferAmount;
  final int topupSpecials;

  factory TopupDetail.fromJson(Map<String, dynamic> json) => TopupDetail(
        totalInstallmentAmount: asInt(json['total_installment_amount']),
        canTopup: asString(json['can_topup']),
        defaultTopupAmount: asInt(json['default_topup_amount']),
        totalInstallmentNumber: asInt(json['total_installment_number']),
        currentLtvAmount: asInt(json['current_ltv_amount']),
        accountStatus: asString(json['account_status']),
        topupExtra: asInt(json['topup_extra']),
        feeAmount: asInt(json['fee_amount']),
        balanceReceivable: asInt(json['balance_receivable']),
        collectionFee: asInt(json['collection_fee']),
        penaltyFee: asInt(json['penalty_fee']),
        interestYield: asInt(json['yield']),
        interestPaidFlag: asString(json['interest_paid_flag']),
        canTopupMsg: asString(json['can_topup_msg']),
        maxTransferAmount: asInt(json['max_transfer_amount']),
        products: asMapList(json['products'])
            .map(LoanProduct.fromJson)
            .toList(growable: false),
        defaultTransferAmount: asDouble(json['default_transfer_amount']),
        topupSpecials: asInt(json['topup_specials']),
      );
}

/// One add-on product offered with a limit.
class LoanProduct {
  const LoanProduct({
    this.productCode = '',
    this.productDescription = '',
    this.productPrice = 0,
    this.productName = '',
  });

  final String productCode;
  final String productDescription;
  final int productPrice;
  final String productName;

  bool get isEmpty =>
      productCode.isEmpty && productName.isEmpty && productPrice == 0;

  factory LoanProduct.fromJson(Map<String, dynamic> json) => LoanProduct(
        productCode: asString(json['product_code']),
        productDescription: asString(json['product_description']),
        productPrice: asInt(json['product_price']),
        productName: asString(json['product_name']),
      );

  Map<String, dynamic> toJson() => {
        'product_code': productCode,
        'product_description': productDescription,
        'product_price': productPrice,
        'product_name': productName,
      };
}

/// One insurance policy attached to the contract.
class Insurance {
  const Insurance({
    this.insCode = '',
    this.insName = '',
    this.effectiveDate = '',
    this.expiredDate = '',
    this.remark = '',
    this.insUrl = '',
  });

  final String insCode;
  final String insName;
  final String effectiveDate;
  final String expiredDate;
  final String remark;
  final String insUrl;

  factory Insurance.fromJson(Map<String, dynamic> json) => Insurance(
        insCode: asString(json['ins_code']),
        insName: asString(json['ins_name']),
        effectiveDate: asString(json['effective_date']),
        expiredDate: asString(json['expired_date']),
        remark: asString(json['remark']),
        insUrl: asString(json['ins_url']),
      );
}

/// `car_details` — vehicle collateral. Two keys are mixed-case on the wire
/// (`car_chassisNo`, `car_engineNo`); that is not a typo on our side.
class CarDetails {
  const CarDetails({
    this.registrationPrefix = '',
    this.registration = '',
    this.province = '',
    this.brand = '',
    this.series = '',
    this.description = '',
    this.chassisNo = '',
    this.cc = '',
    this.engineNo = '',
    this.gear = '',
    this.manufactureYear = '',
    this.color = '',
  });

  final String registrationPrefix;
  final String registration;
  final String province;
  final String brand;
  final String series;
  final String description;
  final String chassisNo;
  final String cc;
  final String engineNo;
  final String gear;
  final String manufactureYear;
  final String color;

  factory CarDetails.fromJson(Map<String, dynamic> json) => CarDetails(
        registrationPrefix: asString(json['car_registration_prefix']),
        registration: asString(json['car_registration']),
        province: asString(json['car_province']),
        brand: asString(json['car_brand']),
        series: asString(json['car_series']),
        description: asString(json['car_desc']),
        chassisNo: asString(json['car_chassisNo']),
        cc: asString(json['car_cc']),
        engineNo: asString(json['car_engineNo']),
        gear: asString(json['car_gear']),
        manufactureYear: asString(json['car_manufacture_year']),
        color: asString(json['car_color']),
      );
}
