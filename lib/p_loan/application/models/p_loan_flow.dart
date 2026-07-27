/// The P-Loan flow's accumulated state, passed page → page as a go_router
/// `extra` — the same convention `LoanRegisterForm` uses in the 5-step wizard.
///
/// The source FlutterFlow app kept all of this in a global `FFAppState`, which
/// made it impossible to tell which screen produced which value (and left
/// stale data behind when the user backed out). One mutable object threaded
/// through the routes keeps the data flow explicit: every field below is
/// written by exactly one step.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../../models/customer_address.dart';
import '../../../models/customer_detail.dart';
import '../../../models/ndid_subject.dart';
import 'installment_plan.dart';
import 'loan_amount_detail.dart';
import 'loan_contract.dart';
import 'loan_documents.dart';

/// A photo the flow collects.
///
/// Each slot carries **two** wire identities, because the flow feeds two
/// different submission APIs: [payloadKey] is its field in the `POST /topup`
/// JSON body, and [pLoanGroup] is its `regmast_ploan.php` image group.
enum PLoanPhoto {
  /// Whole-vehicle shot, motorcycles only.
  fullVehicle(
    payloadKey: 'property_image',
    pLoanGroup: 'carImage',
    cameraAction: 'fullVehicleCamera',
    label: 'บังคับถ่ายรูปภาพหลักประกันเต็มคันมองเห็นป้ายทะเบียนชัดเจน*',
    missingMessage: 'บังคับถ่ายรูปภาพหลักประกันเต็มคันมองเห็นป้ายทะเบียนชัดเจน',
  ),

  /// Tax disc (ป้ายวงกลม) — required for every loan type.
  taxDisc(
    payloadKey: 'act_image',
    pLoanGroup: 'documentImage',
    cameraAction: 'circleCamera',
    label: 'บังคับถ่ายรูปภาพป้ายวงกลม*',
    missingMessage: 'บังคับถ่ายรูปภาพป้ายวงกลม',
  ),
  carRight(
    payloadKey: 'car_image_right',
    pLoanGroup: 'carImage',
    cameraAction: 'rightCamera',
    label: 'บังคับถ่ายรูปด้านข้างขวาเต็มคัน*',
    missingMessage: 'บังคับถ่ายรูปด้านข้างขวาเต็มคัน',
  ),
  carLeft(
    payloadKey: 'car_image_left',
    pLoanGroup: 'carImage',
    cameraAction: 'leftCamera',
    label: 'บังคับถ่ายรูปด้านข้างซ้ายเต็มคัน*',
    missingMessage: 'บังคับถ่ายรูปด้านข้างซ้ายเต็มคัน',
  ),
  carFront(
    payloadKey: 'car_image_front',
    pLoanGroup: 'carImage',
    cameraAction: 'frontCamera',
    label: 'บังคับถ่ายรูปด้านหน้าตรงเต็มคันมองเห็นป้ายทะเบียนชัดเจน*',
    missingMessage: 'บังคับถ่ายรูปด้านหน้าตรงเต็มคัน',
  ),
  carBack(
    payloadKey: 'car_image_back',
    pLoanGroup: 'carImage',
    cameraAction: 'backCamera',
    label: 'บังคับถ่ายรูปด้านหลังตรงเต็มคันมองเห็นป้ายทะเบียนชัดเจน*',
    missingMessage: 'บังคับถ่ายรูปด้านหลังตรงเต็มคัน',
  ),
  carMile(
    payloadKey: 'car_image_mile',
    pLoanGroup: 'carImage',
    cameraAction: 'mileCamera',
    label: 'บังคับถ่ายรูปภาพเลขไมล์*',
    missingMessage: 'บังคับถ่ายรูปภาพเลขไมล์',
  ),

  /// Vehicle registration book — no slot in the top-up body, but
  /// `regmast_ploan.php` has one. Optional so it can never block the flow.
  vehicleRegistrationBook(
    payloadKey: '',
    pLoanGroup: 'carBookImage',
    cameraAction: 'carBookCamera',
    label: 'เล่มทะเบียนรถ',
    missingMessage: 'กรุณาถ่ายรูปเล่มทะเบียนรถ',
    optional: true,
  ),

  /// Bank passbook cover, evidencing the payout account. P-Loan payload only.
  bookBank(
    payloadKey: '',
    pLoanGroup: 'bookBankImage',
    cameraAction: 'bookBankCamera',
    label: 'หน้าสมุดบัญชี',
    missingMessage: 'กรุณาถ่ายรูปหน้าสมุดบัญชี',
    optional: true,
  ),

  /// ID card, captured and OCR-verified on step 6.
  idCard(
    payloadKey: 'customer_image_2',
    pLoanGroup: 'cardIdImage',
    cameraAction: 'idCardCamera',
    label: 'บังคับถ่ายรูปภาพบัตรประชาชน*',
    missingMessage: 'กรุณาถ่ายรูปบัตรประชาชน',
  ),

  /// Selfie holding the ID card, captured on step 6.
  selfieWithIdCard(
    payloadKey: 'customer_image_3',
    pLoanGroup: 'customerImage',
    cameraAction: 'selfieCamera',
    label: 'บังคับถ่ายรูปภาพตนเองคู่กับบัตรประชาชน*',
    missingMessage: 'กรุณาถ่ายรูปตนเองคู่กับบัตรประชาชน',
  );

  const PLoanPhoto({
    required this.payloadKey,
    required this.pLoanGroup,
    required this.cameraAction,
    required this.label,
    required this.missingMessage,
    this.optional = false,
  });

  /// Key this photo occupies in the `POST /topup` JSON body. Empty when the
  /// top-up body has no slot for it (P-Loan-only attachments).
  final String payloadKey;

  /// Its `regmast_ploan.php` image group. Several slots share a group and are
  /// sent as repeated `group[]` file parts.
  final String pLoanGroup;

  /// Nice-to-have rather than required — never blocks the Next button.
  final bool optional;

  /// `action` passed to the host's `openCamera` bridge handler.
  final String cameraAction;

  /// Red required-photo label above the capture button.
  final String label;

  /// Thai error shown when the user submits without it.
  final String missingMessage;
}

/// Which P-Loan product an application is for.
///
/// Both kinds run the **same six screens**. They differ only in where the
/// requested amount comes from, and therefore in what comes off the payout:
///
/// | | [extra] | [newLoan] |
/// | --- | --- | --- |
/// | Amount | pre-filled from the contract's approved top-up limit | starts blank, customer names it |
/// | Bounds | `min/max_topup_amount` | none client-side |
/// | Payout | request less old principal less duty | request less duty |
/// | Submits to | `POST /topup` | the P-Loan save API (not wired) |
///
/// The source declared this distinction as
/// `SavePLoanDataModelStruct.isNewPLoan` and read it in exactly one place — the
/// step-2 amount input, which it gated off — but never assigned it. So the
/// new-loan path was designed there and never built; this is it.
/// The endpoint family a completed application is filed to.
enum PLoanSubmitTarget {
  /// `POST /topup` on the mobile API — a top-up of an existing contract.
  topup,

  /// `POST /SavePloanContract` on the P-Loan save API (`PLoanContractApi`).
  pLoanSaveApi,
}

enum PLoanKind {
  /// **P-Loan Extra** — more money against a contract the customer already
  /// has. The old contract is closed out of the new one, which is why its
  /// principal is deducted from what they receive.
  extra(
    label: 'สินเชื่อเพิ่มจากสัญญาเดิม',
    shortLabel: 'สินเชื่อเพิ่ม',
    description: 'ขอวงเงินเพิ่มจากสัญญาสินเชื่อเดิมที่มีอยู่',
  ),

  /// **New P-Loan** — a fresh personal loan at an amount the customer chooses.
  ///
  /// A contract is still selected on step 1, but only as a **data reference**:
  /// every endpoint downstream (`/topup/detail` for the rate and duty,
  /// `/topup/calculator`, `/pdf/loan`) is keyed by `db_name` + `contract_no`,
  /// so one is needed to reach them at all. Nothing is drawn against it — see
  /// [PLoanFlow.toSubmissionJson], which refuses to build a top-up body for
  /// this kind.
  newLoan(
    label: 'ขอสินเชื่อใหม่',
    shortLabel: 'สินเชื่อใหม่',
    description: 'ขอสินเชื่อใหม่ โดยระบุวงเงินที่ต้องการได้เอง',
  );

  const PLoanKind({
    required this.label,
    required this.shortLabel,
    required this.description,
  });

  /// Heading used for this kind's section on step 1.
  final String label;

  /// Compact form, for pills and app-bar suffixes.
  final String shortLabel;

  /// One-line explanation shown under [label].
  final String description;
}

class PLoanFlow implements NdidSubject {
  PLoanFlow({
    required this.hashThaiId,
    this.kind = PLoanKind.extra,
    this.authToken = '',
    this.source = '',
    this.referId = '',
    this.customer,
    this.addressBook,
    this.contract,
    this.amountDetail,
    this.requestedAmount = 0,
    this.plan,
    this.installment,
    this.documents,
    this.verifiedThaiId = '',
    this.latitude = '',
    this.longitude = '',
    this.empId = '',
    this.mktChannel = '',
    this.customerSource = '',
    this.gpsProvinceId = '',
    this.gpsAumphurId = '',
    this.remark = '',
    this.transNo = '',
    this.marketingConsent = false,
    this.sensitiveConsent = false,
  });

  // ── Product ─────────────────────────────────────────────────────────

  /// Which P-Loan this is. Chosen on step 1 and read by every screen after it;
  /// never changes mid-flow, hence `final`.
  final PLoanKind kind;

  /// True for a new P-Loan.
  bool get isNewPLoan => kind == PLoanKind.newLoan;

  // ── Launch parameters (from the host URL / AppState) ─────────────────

  /// Hashed Thai ID identifying the customer; every call needs it.
  final String hashThaiId;

  /// Bearer token from the `?token=` launch param.
  final String authToken;

  /// Attribution passed straight through to the submit payload.
  final String source;
  final String referId;

  // ── regmast_ploan-only inputs ───────────────────────────────────────
  // Fields the P-Loan submission API needs that nothing in this flow can
  // derive. They are carried here so the payload is complete the moment the
  // host supplies them; each defaults to '' rather than to a plausible-looking
  // value, so a missing one is visible instead of silently wrong.

  /// Staff id raising the application (`empId`). Supplied by the host.
  String empId;

  /// Marketing channel code (`mktChannel`). Supplied by the host.
  String mktChannel;

  /// Customer-source code (`customerSource`). Supplied by the host.
  String customerSource;

  /// Province / district ids for the capture location (`gpsProvinceId`,
  /// `gpsAumphurId`). These are ids, not names, so they need a lookup against
  /// [latitude]/[longitude] that this flow does not perform.
  String gpsProvinceId;
  String gpsAumphurId;

  /// Free-text note (`remark`).
  String remark;

  /// Transaction number, set from the submit response.
  String transNo;

  // ── Step 1: contract selection ──────────────────────────────────────

  /// Customer profile (`GET /user/detail`), fetched on step 1.
  CustomerDetail? customer;

  /// Address book (`GET /profile/address/{hash}`), fetched on step 5.
  CustomerAddressBook? addressBook;

  /// The contract this request relates to.
  ///
  /// For [PLoanKind.extra] this is the contract the money is drawn against.
  /// For [PLoanKind.newLoan] nothing is drawn against it — it supplies the
  /// `db_name` + `contract_no` every downstream endpoint is keyed by, and the
  /// interest rate and stamp duty step 2 prices with.
  LoanContract? contract;

  // ── Step 2: requested amount ────────────────────────────────────────

  /// Limits and deductions for [contract] (`GET /topup/detail`).
  LoanAmountDetail? amountDetail;

  /// The amount the user asked for, rounded down to the nearest 100.
  ///
  /// Starts at the contract's approved limit for a P-Loan Extra, and at `0`
  /// (a blank field) for a new P-Loan.
  int requestedAmount;

  // ── Step 3: installment choice ──────────────────────────────────────

  /// Options for [requestedAmount] (`POST /topup/calculator`).
  InstallmentPlan? plan;

  /// The tenor the user picked.
  InstallmentOption? installment;

  // ── Steps 4 & 6: photos, documents, consent ─────────────────────────

  /// Captured photos by slot. Held as raw bytes so they can be previewed and
  /// re-encoded once at submit time.
  final Map<PLoanPhoto, Uint8List> photos = {};

  /// The three contract PDFs (`POST /pdf/loan`), generated on step 6.
  LoanDocuments? documents;

  /// Which documents the customer has accepted.
  final Set<LoanDocumentKind> consented = {};

  /// Thai ID read off the card by `POST /vision/thai-id-validate`; kept so the
  /// match against the profile can be re-checked before submit.
  String verifiedThaiId;

  // ── Step 6: NDID document signing ───────────────────────────────────
  // The same hop the loan-register wizard does on its step 4, against the same
  // shared screens (see NdidSubject). Distinct from the ID-card check above:
  // that is KYC on a photo, this is the customer signing the contract
  // documents with their bank identity.

  /// True once the NDID flow has reported success. Gates [canSubmit].
  bool ndidVerified = false;

  /// [NdidSubject.ndidIdpId] — the IdP the customer picked.
  @override
  String? ndidIdpId;

  /// [NdidSubject.ndidThaiId] — from the profile, which already holds bare
  /// digits. Falls back to the id read off the card when the profile has none.
  @override
  String get ndidThaiId {
    final fromProfile = (customer?.thaiId ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    return fromProfile.isNotEmpty
        ? fromProfile
        : verifiedThaiId.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Device location captured at submit time.
  String latitude;
  String longitude;

  // ── PDPA consents (step 6) ──────────────────────────────────────────
  // Captured from the customer rather than assumed. They map to the payload's
  // `marketing_consent` / `sensitive_consent` (Y/N).

  /// ยินยอมการตลาด — optional opt-in to marketing contact.
  bool marketingConsent;

  /// ยินยอมข้อมูลอ่อนไหว — consent to process sensitive personal data.
  /// Required: the application cannot be assessed without it, so [canSubmit]
  /// gates on it.
  bool sensitiveConsent;

  // ── Derived ─────────────────────────────────────────────────────────

  /// Loan type of the selected contract (`M` motorcycle, `C` car, …).
  String get loanTypeCode => contract?.contractDetails.loanTypeCode ?? '';

  /// Photos step 4 requires, which depends on the loan type.
  ///
  /// Motorcycles need a whole-vehicle shot plus the tax disc; cars need four
  /// sides, the odometer and the tax disc. For any other loan type the source
  /// leaves its confirm button permanently disabled — a dead end — so here the
  /// tax disc alone is required. That is a deliberate deviation: it keeps the
  /// flow completable instead of trapping the user.
  List<PLoanPhoto> get requiredPhotos => switch (loanTypeCode) {
        'M' => const [PLoanPhoto.fullVehicle, PLoanPhoto.taxDisc],
        'C' => const [
            PLoanPhoto.carRight,
            PLoanPhoto.carLeft,
            PLoanPhoto.carFront,
            PLoanPhoto.carBack,
            PLoanPhoto.carMile,
            PLoanPhoto.taxDisc,
          ],
        _ => const [PLoanPhoto.taxDisc],
      };

  /// Extra attachments the P-Loan payload has slots for but the top-up body
  /// does not. Offered on step 4; never gate progress.
  List<PLoanPhoto> get optionalPhotos =>
      PLoanPhoto.values.where((p) => p.optional).toList(growable: false);

  /// The first required step-4 photo still missing, or null when complete.
  PLoanPhoto? get missingVehiclePhoto =>
      requiredPhotos.where((p) => !photos.containsKey(p)).firstOrNull;

  /// Step 6 needs the ID card and the selfie.
  PLoanPhoto? get missingIdentityPhoto =>
      [PLoanPhoto.idCard, PLoanPhoto.selfieWithIdCard]
          .where((p) => !photos.containsKey(p))
          .firstOrNull;

  /// The first document not yet accepted, or null when all three are.
  LoanDocumentKind? get missingConsent => LoanDocumentKind.values
      .where((kind) => !consented.contains(kind))
      .firstOrNull;

  /// Step 6's submit button is enabled only when identity, document consent,
  /// NDID signing and the sensitive-data consent are all done. Marketing
  /// consent is a genuine opt-in and deliberately does not gate anything.
  bool get canSubmit =>
      missingIdentityPhoto == null &&
      missingConsent == null &&
      ndidVerified &&
      sensitiveConsent &&
      contract != null;

  /// Money the customer receives for [requestedAmount].
  ///
  /// A P-Loan Extra clears the old contract out of the new one, so its
  /// principal comes off alongside the stamp duty. A new P-Loan has no old
  /// principal to clear — only the duty comes off.
  int get payoutAmount {
    final detail = amountDetail;
    if (detail == null) return 0;
    return isNewPLoan
        ? requestedAmount - detail.feeAmount
        : detail.payoutFor(requestedAmount);
  }

  /// Smallest amount a new P-Loan may be requested for: the rounding unit,
  /// below which there is nothing to lend.
  static const int newLoanMinimumAmount = 100;

  /// Whether [requestedAmount] is worth sending to the calculator.
  ///
  /// A P-Loan Extra is bounded by the contract's approved top-up range. A new
  /// P-Loan is not — the customer names the amount. Any product floor or
  /// ceiling for a new loan is the server's to enforce: `/topup/calculator`
  /// rejects what it will not price and its message is shown as-is, rather than
  /// a bound being guessed at here.
  bool get isRequestedAmountAllowed {
    final detail = amountDetail;
    if (detail == null) return false;
    return isNewPLoan
        ? requestedAmount >= newLoanMinimumAmount
        : detail.isAmountAllowed(requestedAmount);
  }

  /// Where a completed application of this kind is filed.
  ///
  /// An Extra draws against [contract], which is exactly what `POST /topup`
  /// books. A new P-Loan does not, so it goes to the P-Loan save API instead —
  /// see [toSubmissionJson], which refuses to build a top-up body for it.
  PLoanSubmitTarget get submitTarget => isNewPLoan
      ? PLoanSubmitTarget.pLoanSaveApi
      : PLoanSubmitTarget.topup;

  /// Whether [verifiedThaiId] matches the profile.
  ///
  /// The source also accepted four hardcoded Thai IDs here, which let anyone
  /// holding one of those cards pass identity verification for *any* account.
  /// That backdoor is deliberately not reproduced.
  bool get isThaiIdVerified =>
      verifiedThaiId.isNotEmpty && verifiedThaiId == (customer?.thaiId ?? '');

  /// Body for `POST /topup`.
  ///
  /// Key names mirror the API exactly, including `topup_argeement_file` —
  /// the misspelling is the real wire key.
  ///
  /// **Throws for a new P-Loan.** This endpoint books the request against
  /// `contract_no`; for [PLoanKind.newLoan] that contract is only a data
  /// reference, so posting this body would file a top-up of the customer's
  /// existing loan for an amount that was never approved against it. Refusing
  /// here means no screen can do that by accident. Use [PLoanSubmission] and
  /// the P-Loan save API for a new loan.
  Map<String, dynamic> toSubmissionJson() {
    if (kind != PLoanKind.extra) {
      throw StateError(
        'A ${kind.name} P-Loan cannot be submitted through POST /topup — '
        'that endpoint books against the reference contract',
      );
    }
    final contract = this.contract;
    final detail = amountDetail;
    final installment = this.installment;
    if (contract == null || detail == null || installment == null) {
      throw StateError('P-Loan flow incomplete: cannot build submit payload');
    }

    String image(PLoanPhoto slot) {
      final bytes = photos[slot];
      if (bytes == null || bytes.isEmpty) return '';
      return 'data:image/jpeg;base64,${base64OfPhoto(slot)}';
    }

    return {
      'transno': '',
      'db_name': contract.dbName,
      'hash_thai_id': hashThaiId,
      'contract_no': contract.contractNo,
      'life_insure_amt': detail.lifeInsureAmt,
      'marketing_consent': 'Y',
      'sensitive_consent': 'Y',
      'latitude': latitude,
      'longitude': longitude,
      'loan_amount': requestedAmount,
      'topup_fee': detail.feeAmount,
      'fee_amount': detail.feeAmount,
      'transfer_amount': payoutAmount,
      'interest_rate': detail.interestRate,
      'interest_amount': installment.intAmt,
      'total_amount': installment.totalAmt,
      'credit_limit': detail.contractDetails.creditLimit,
      'term_period': installment.tenor,
      'regular_period': installment.regularPeriodAmt,
      'last_period': installment.lastPeriodAmt,
      'last_period_promo': installment.lastPeriodPromo,
      'act_image': image(PLoanPhoto.taxDisc),
      'property_image': image(PLoanPhoto.fullVehicle),
      'car_image_front': image(PLoanPhoto.carFront),
      'car_image_back': image(PLoanPhoto.carBack),
      'car_image_left': image(PLoanPhoto.carLeft),
      'car_image_right': image(PLoanPhoto.carRight),
      'car_image_mile': image(PLoanPhoto.carMile),
      'customer_image_2': image(PLoanPhoto.idCard),
      'customer_image_3': image(PLoanPhoto.selfieWithIdCard),
      'topup_request_file': documents?.request ?? '',
      'topup_receipt_file': documents?.receipt ?? '',
      // Misspelled on the wire — matches the API, not our typo.
      'topup_argeement_file': documents?.agreement ?? '',
      'source': source,
      'refer_id': referId,
      'product_code': '',
    };
  }

  /// Base64 of a captured photo, or `''` when that slot is empty.
  String base64OfPhoto(PLoanPhoto slot) {
    final bytes = photos[slot];
    if (bytes == null || bytes.isEmpty) return '';
    return base64Encode(bytes);
  }
}
