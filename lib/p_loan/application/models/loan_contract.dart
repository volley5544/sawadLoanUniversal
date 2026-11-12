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
    this.landDetails = const LandDetails(),
    this.revolvingLoan = const RevolvingLoan(),
    this.topupSpecialFlag = false,
    this.rawJson = const {},
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

  /// `land_details` — the land-title collateral, the land counterpart of
  /// [carDetails]. Parsed only (added 2026-09-24); nothing renders it yet.
  final LandDetails landDetails;

  /// `revolving_loans` — the contract's revolving credit line (บัตรศรีสวัสดิ์).
  /// A single object despite the plural key. Parsed only (added 2026-11-11);
  /// nothing renders it yet.
  final RevolvingLoan revolvingLoan;

  /// `topup_special_flag` — the customer has been granted `topup_specials` on
  /// top of this contract's ordinary limit.
  ///
  /// Only the top-up flow reads it, and it has to: `GET /topup/detail` does
  /// **not** include the uplift, so both the default amount and the ceiling
  /// have to be raised client-side or the extra limit is offered nowhere. See
  /// `TopupFlow.applySpecialLimit`.
  final bool topupSpecialFlag;

  /// The row exactly as it arrived.
  ///
  /// Kept only because the top-up flow's **lead** fallback forwards whole
  /// sub-objects (`contract_details`, `car_details`, `payment_details`,
  /// `topup_detail`, `barcode_details`, `insurances`) to a service that is not
  /// ours, and re-serialising them from the typed fields would silently drop
  /// any key this model does not know about. Read it only for that; everything
  /// else should use the typed fields, which are the checked contract.
  final Map<String, dynamic> rawJson;

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
        landDetails: LandDetails.fromJson(asMap(json['land_details'])),
        revolvingLoan: RevolvingLoan.fromJson(asMap(json['revolving_loans'])),
        topupSpecialFlag: json['topup_special_flag'] == true,
        rawJson: json,
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
  /// **`double`, not `int`** — the wire sends `86217.08` and the redesigned
  /// card and amount screens both put this figure on screen to two decimals,
  /// under a total that has to add up. Truncating it misstated the deduction
  /// by up to a baht *and* changed `transfer_amount` on the submit body, the
  /// same defect `yield`/`collection_fee`/`penalty_fee` carried until
  /// 2026-09-11. Widened 2026-09-12 for the same reason.
  final double closingBalance;
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
        closingBalance: asDouble(json['closing_balance']),
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
    this.overdueDate = '',
    this.currentDateTime = '',
    this.collectionFee = 0,
    this.penaltyFee = 0,
    this.totalDueAmount = 0,
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

  /// `overdue_date` — the due date of the *overdue* instalments, as opposed to
  /// [currentDueDate], which is the one coming up. The payment screen's
  /// ชำระเต็มจำนวน option shows both, against different rows.
  final String overdueDate;

  /// Server-side timestamp; the source uses it as the request date rather than
  /// the device clock, so a wrong device time can't date a contract.
  final String currentDateTime;
  final double collectionFee;

  /// `penalty_fee` — the arrears penalty, shown as `ค่าเบี้ยปรับค้างชำระ` in
  /// the loan detail screen's **ยอดรวมต้องชำระ** breakdown.
  ///
  /// ⚠ **The wire name is unconfirmed on this block.** `penalty_fee` is a real
  /// field on `topup_detail`, but no `/loan/list` sample here carries one under
  /// `payment_details`. It defaults to 0, and the row is withheld at 0, so an
  /// API that sends nothing renders the design's own
  /// *กรณี…แต่ไม่มีค่าธรรมเนียม* case rather than a zero row. Point it at the
  /// real key here when the API team names it — nothing else reads it.
  ///
  /// ⚠ Deliberately **not** `topup_detail.penalty_fee`: that block prices a
  /// top-up, not this contract's arrears.
  final double penaltyFee;

  /// `total_due_amount` — everything owed now, arrears included. The loan
  /// detail screen's `รวมต้องชำระ` (header) and `ยอดรวมต้องชำระ` read it
  /// (2026-09-23, tester round; both were `current_due_amount` before).
  final double totalDueAmount;

  /// **The total the loan detail + loan payment screens quote** — header
  /// `รวมต้องชำระ`, `ยอดรวมต้องชำระ`, and the ชำระเต็มจำนวน amount.
  ///
  /// [totalDueAmount] since 2026-09-24, when the backend started sending it.
  /// Between 2026-09-23 and then it was an interim sum, `overdue_amount +
  /// collection_fee + penalty_fee + current_due_amount`. Kept as the single
  /// seam both screens read.
  double get payableTotal => totalDueAmount;

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
        overdueDate: asString(json['overdue_date']),
        currentDateTime: asString(json['current_date_time']),
        collectionFee: asDouble(json['collection_fee']),
        penaltyFee: asDouble(json['penalty_fee']),
        totalDueAmount: asDouble(json['total_due_amount']),
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
    this.principalNotDue = 0,
    this.collectionFee = 0,
    this.penaltyFee = 0,
    this.interestYield = 0,
    this.interestPaidFlag = '',
    this.canTopupMsg = '',
    this.ineligibleDetail = '',
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
  /// `balance_receivable` — the account-closing balance. `double` since
  /// 2026-09-24: it carries satang (`27437.14`), and as the fallback for
  /// [principalNotDue] it now feeds `transfer_amount`, where truncating to an
  /// int would misfile the payout.
  final double balanceReceivable;

  /// `principal_not_due` — principal not yet fallen due: what a top-up
  /// deducts from the payout (2026-09-24). Read by the top-up card's
  /// เงินต้นที่ยังไม่ถึงกำหนดชำระ and `TopupFlow.principalDeduction`. `double`
  /// — it carries satang (`27437.14`).
  final double principalNotDue;
  /// ⚠ Decimal on the wire — see `LoanAmountDetail.collectionFee`.
  final double collectionFee;
  final double penaltyFee;

  /// `yield` on the wire — accrued interest. Renamed here because `yield` is
  /// a Dart reserved word.
  /// ⚠ Decimal on the wire — see `LoanAmountDetail.interestYield`.
  final double interestYield;
  final String interestPaidFlag;

  /// Why [canTopup] isn't `Y`; shown to the user in place of the limits.
  final String canTopupMsg;

  /// Fallback for [ineligibleReason] when the API names no reason.
  static const String contactBranchFallback =
      'กรุณาติดต่อสาขาเจ้าของบัญชี หรือโทร 1652';

  /// The second line of the top-up card's **can_topup = N** state — the fixed
  /// guidance, **always**.
  ///
  /// ⚠ **It carried `can_topup_msg` between 2026-09-14 and 2026-09-19**, on
  /// the grounds that the API's own sentence names the actual reason where a
  /// hardcoded line can only say "phone the branch". Reverted after checking
  /// the design again: `can_topup_msg` now renders on the `Code :` line
  /// instead (see [ineligibleDetail]), and a card that showed it in both places
  /// would say the same thing twice — a live sample reads
  /// `"ระบบขัดข้อง กรุณาติดต่อสาขา"`, which is already the guidance.
  ///
  /// Kept as a getter rather than inlining [contactBranchFallback] at the call
  /// site so the card keeps asking the model what to say.
  String get ineligibleReason => contactBranchFallback;

  /// The small line under the guidance on the **can_topup = N** card,
  /// rendered as `Code : <value>`.
  ///
  /// ⚠ **It is `can_topup_reason_code`** (changed 2026-09-23, tester round,
  /// matching the design's `Code : xxx`). Between 2026-09-19 and then it was
  /// `can_topup_msg` printed bare; that sentence is not shown on the card any
  /// more — it still feeds the amount screen's note via `canTopupMsg`.
  ///
  /// ```jsonc
  /// "can_topup_type":        "ไม่เข้าเงื่อนไข",
  /// "can_topup_msg":         "ระบบขัดข้อง กรุณาติดต่อสาขา",
  /// "can_topup_reason_code": "contract_not_found_in_vloan",  // ← this line
  /// ```
  ///
  /// Empty renders **no line at all**, rather than a bare `Code :`.
  final String ineligibleDetail;
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
        balanceReceivable: asDouble(json['balance_receivable']),
        principalNotDue: asDouble(json['principal_not_due']),
        collectionFee: asDouble(json['collection_fee']),
        penaltyFee: asDouble(json['penalty_fee']),
        interestYield: asDouble(json['yield']),
        interestPaidFlag: asString(json['interest_paid_flag']),
        canTopupMsg: asString(json['can_topup_msg']),
        ineligibleDetail: asString(json['can_topup_reason_code']),
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

/// `land_details` — the land-title collateral (โฉนด). Added 2026-09-24,
/// **parsed only**: no screen reads it yet.
class LandDetails {
  const LandDetails({
    this.deedNumber = '',
    this.sheetNumber = '',
    this.parcelNumber = '',
    this.dealingFileNumber = '',
  });

  /// `deed_number` — เลขที่โฉนด.
  final String deedNumber;

  /// `sheet_number` — ระวาง.
  final String sheetNumber;

  /// `parcel_number` — เลขที่ดิน.
  final String parcelNumber;

  /// `dealing_file_number` — หน้าสำรวจ.
  final String dealingFileNumber;

  bool get isEmpty =>
      deedNumber.isEmpty &&
      sheetNumber.isEmpty &&
      parcelNumber.isEmpty &&
      dealingFileNumber.isEmpty;

  factory LandDetails.fromJson(Map<String, dynamic> json) => LandDetails(
        deedNumber: asString(json['deed_number']),
        sheetNumber: asString(json['sheet_number']),
        parcelNumber: asString(json['parcel_number']),
        dealingFileNumber: asString(json['dealing_file_number']),
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

/// `revolving_loans` — the revolving credit line (บัตรศรีสวัสดิ์) attached to a
/// contract. Added 2026-11-11; the BA calls it `getRevolvingInfo`. Read by
/// `RevolvingCardView.fromContract` (2026-11-12).
///
/// A contract without one still sends the object, zero-filled with
/// `revolving_flag: false` — so [revolvingFlag] is the test, not presence.
class RevolvingLoan {
  const RevolvingLoan({
    this.contractId = 0,
    this.revolvingFlag = false,
    this.revolvingLimit = 0,
    this.utilizationAmount = 0,
    this.revolvingStatus = '',
    this.reservedLimit = 0,
    this.utilizationPercentage = 0,
    this.maximumWithdrawalAmount = 0,
    this.minimumWithdrawalAmount = 0,
    this.remainingRequestLimit = 0,
    this.remainingDailyAvailableLimit = 0,
    this.acceptanceFlag = '',
    this.bankAccounts = const [],
  });

  /// `contract_id`.
  final int contractId;

  /// `revolving_flag` — whether this contract has a revolving line at all.
  final bool revolvingFlag;

  /// `revolving_limit` — the line's total limit.
  final double revolvingLimit;

  /// `utilization_amount` — how much of the limit is drawn.
  final double utilizationAmount;

  /// `revolving_status` — `Active` in the LMS sample (2026-11-11), `Hard block`
  /// on QA contract 2881 (2026-11-12); the full set is not yet known.
  final String revolvingStatus;

  /// `reserved_limit`.
  final double reservedLimit;

  /// `utilization_percentage` — ⚠ **scale unconfirmed**. The LMS sample
  /// (2026-11-11) has `0.55` for 27,500 of 50,000 (a fraction); the QA
  /// `/loan/list` (2026-11-12, contract 2881) has `52.02` (a percent). Ask
  /// the API owner before rendering it.
  final double utilizationPercentage;

  /// `maximum_withdrawal_amount` — the largest single withdrawal allowed.
  final double maximumWithdrawalAmount;

  /// `minimum_withdrawal_amount` — the smallest single withdrawal allowed.
  final double minimumWithdrawalAmount;

  /// `remaining_request_limit` — a **count** of requests left, not money
  /// (it is the one integer among the amounts on the wire).
  final int remainingRequestLimit;

  /// `remaining_daily_available_limit` — money still withdrawable today.
  final double remainingDailyAvailableLimit;

  /// `acceptance_flag` — whether the customer accepted the line's terms
  /// (`Yes` in the LMS sample, `''` on a contract with no line).
  ///
  /// ⚠ **Nothing gates on it yet** (decided 2026-11-11): every revolving
  /// request is treated as accepted for now, and the
  /// `revolvingLoan/check|saveAcceptanceFlag` calls come in a later update.
  final String acceptanceFlag;

  /// `bank_accounts` — the accounts a withdrawal can be paid into. `null`
  /// (every contract without a line) parses to empty, and a non-object
  /// element is dropped.
  final List<RevolvingBankAccount> bankAccounts;

  /// The account a withdrawal goes to unless the customer picks another: the
  /// one marked `is_default`, else the first. `null` when there are none.
  RevolvingBankAccount? get defaultBankAccount {
    for (final a in bankAccounts) {
      if (a.isDefault) return a;
    }
    return bankAccounts.isEmpty ? null : bankAccounts.first;
  }

  factory RevolvingLoan.fromJson(Map<String, dynamic> json) => RevolvingLoan(
        contractId: asInt(json['contract_id']),
        revolvingFlag: asBool(json['revolving_flag']),
        revolvingLimit: asDouble(json['revolving_limit']),
        utilizationAmount: asDouble(json['utilization_amount']),
        revolvingStatus: asString(json['revolving_status']),
        reservedLimit: asDouble(json['reserved_limit']),
        utilizationPercentage: asDouble(json['utilization_percentage']),
        maximumWithdrawalAmount: asDouble(json['maximum_withdrawal_amount']),
        minimumWithdrawalAmount: asDouble(json['minimum_withdrawal_amount']),
        remainingRequestLimit: asInt(json['remaining_request_limit']),
        remainingDailyAvailableLimit:
            asDouble(json['remaining_daily_available_limit']),
        acceptanceFlag: asString(json['acceptance_flag']),
        bankAccounts: asMapList(json['bank_accounts'])
            .map(RevolvingBankAccount.fromJson)
            .toList(),
      );
}

/// One `revolving_loans.bank_accounts[]` entry. Field names from the
/// node-api guide (`revolving-frontend-api.md`); values from the LMS sample,
/// whose own keys are camelCase (`bankName`, …) — this API's are snake_case.
class RevolvingBankAccount {
  const RevolvingBankAccount({
    this.bankName = '',
    this.bankCode = '',
    this.transferType = '',
    this.accountType = '',
    this.accountNumber = '',
    this.accountName = '',
    this.isDefault = false,
  });

  /// `bank_name` — `Bangkok Bank` in the sample (English).
  final String bankName;

  /// `bank_code` — `BBL`; goes out as the withdrawal's `bank_code`.
  final String bankCode;

  /// `transfer_type` — `customer_bank` in the sample; one of the
  /// withdrawal's `transfer_type` values.
  final String transferType;

  /// `account_type` — `SAVING ACCOUNT`.
  final String accountType;

  /// `account_number` — digits, unformatted (`1234567890`).
  final String accountNumber;

  /// `account_name` — required on every withdrawal (LMS validates it).
  final String accountName;

  /// `is_default`.
  final bool isDefault;

  /// [transferType] as the withdrawal request spells it — the mapping in the
  /// BA's *Withdrawal process* spec (2026-11-12):
  ///
  /// | `bank_accounts[].transfer_type` | withdrawal `transfer_type` |
  /// | --- | --- |
  /// | `PROMPT_PAY_MOBILE_NUMBER` | `promptpay_phone` |
  /// | `PROMPT_PAY_CITIZEN_ID` | `promptpay_citizen` |
  /// | `CUSTOMER_BANK` | `customer_bank` |
  ///
  /// Case- and underscore-insensitive, and the already-mapped spellings
  /// (`promptpay_phone`, …, from the node-api guide) map to themselves. Any
  /// other value is passed through lower-cased rather than guessed at.
  String get withdrawalTransferType {
    final key = transferType.trim().toLowerCase().replaceAll('_', '');
    return switch (key) {
      'promptpaymobilenumber' || 'promptpayphone' => 'promptpay_phone',
      'promptpaycitizenid' || 'promptpaycitizen' => 'promptpay_citizen',
      'customerbank' => 'customer_bank',
      _ => transferType.trim().toLowerCase(),
    };
  }

  /// A PromptPay destination (phone or citizen id), whose [accountNumber] is
  /// a phone number or citizen id rather than an account. Reads
  /// [withdrawalTransferType], so `PROMPT_PAY_MOBILE_NUMBER` (the spec) and
  /// `promptpay_phone` (the guide) both count.
  bool get isPromptPay => withdrawalTransferType.startsWith('promptpay');

  factory RevolvingBankAccount.fromJson(Map<String, dynamic> json) =>
      RevolvingBankAccount(
        bankName: asString(json['bank_name']),
        bankCode: asString(json['bank_code']),
        transferType: asString(json['transfer_type']),
        accountType: asString(json['account_type']),
        accountNumber: asString(json['account_number']),
        accountName: asString(json['account_name']),
        isDefault: asBool(json['is_default']),
      );
}
