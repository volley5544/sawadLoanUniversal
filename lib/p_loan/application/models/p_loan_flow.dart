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

import '../../../config/app_environment.dart';
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
    // Exactly `selfie`, not `selfieCamera`: the host matches this string
    // literally (`action.toLowerCase() == 'selfie'`) to pick the
    // `idCardPlusSelfie` framing mask and the **front** camera. Anything else
    // falls through to the plain `idCard` mask on the rear camera, which is what
    // `selfieCamera` was silently getting. Pinned by a test — the host's
    // vocabulary is `collateral` / `idcard` / `selfie`.
    cameraAction: 'selfie',
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
  /// **No contract is involved.** `refContractNo` is an Extra's field, so this
  /// product carries none: it is offered even to a customer with no contracts,
  /// and [PLoanFlow.contract] stays null for the whole flow. Consequences —
  /// every `/topup/*` endpoint is unreachable (all keyed by `db_name` +
  /// `contract_no`), the collateral and payout account are stated by the
  /// customer instead of read off a contract, and `POST /pdf/loan` cannot run
  /// either (see [PLoanFlow.canGenerateDocuments], which is what blocks a
  /// new-loan submit today).
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

/// The collateral a **new** P-Loan is raised against, as the customer names it.
///
/// A P-Loan Extra reads this off the contract it draws on. A new P-Loan draws
/// on nothing and has no contract at all, so the customer picks it, and that
/// choice drives step 4's required photos exactly the way the contract's loan
/// type does for an Extra.
///
/// [other] deliberately maps to a code outside `M`/`C`, which
/// [PLoanFlow.requiredPhotos] already handles by asking for the tax disc alone.
enum PLoanCollateralType {
  motorcycle(code: 'M', label: 'รถจักรยานยนต์'),
  car(code: 'C', label: 'รถยนต์'),
  other(code: 'O', label: 'อื่นๆ');

  const PLoanCollateralType({required this.code, required this.label});

  /// Loan-type code, in the same alphabet the contract API uses.
  final String code;
  final String label;

  /// True when the type names a specific vehicle, and so has registration
  /// details worth asking the customer for.
  bool get isVehicle => this != other;
}

/// What the customer states about a **new** P-Loan: the facts an Extra reads
/// off its contract and a new loan has no source for.
///
/// Before this existed the screens fell back to a contract picked on step 1,
/// which put another loan's vehicle (`ยี่ห้อสินค้า HONDA`) and another loan's
/// payout account on screen and into the submit payload. Empty is the correct
/// starting value for every field here — a blank the customer fills is
/// recoverable, a confidently-wrong inherited one is not.
class NewLoanDetails {
  /// Collateral kind, picked on step 4. Null until they choose.
  PLoanCollateralType? collateralType;

  // ── Collateral identity (step 4), asked only for a vehicle type ──────
  String brand = '';
  String series = '';
  String registration = '';
  String province = '';

  /// Registration expiry as an ISO `yyyy-MM-dd` date, or `''`.
  String registrationExpiry = '';

  /// Year as typed; the payload converts C.E. to B.E. where needed.
  String manufactureYear = '';

  // ── Payout account (step 5) ──────────────────────────────────────────
  String bankCode = '';
  String bankAccountNo = '';
  String bankAccountName = '';

  /// Collateral facts step 4 will not continue without. The optional ones
  /// (plate number, expiry) are left out on purpose: blank renders blank, and
  /// neither reaches a payload field.
  bool get hasCollateral {
    final type = collateralType;
    if (type == null) return false;
    if (!type.isVehicle) return true;
    return brand.trim().isNotEmpty &&
        series.trim().isNotEmpty &&
        manufactureYear.trim().isNotEmpty;
  }

  /// The account the payout is sent to — all three parts, since a transfer
  /// needs the holder's name as well as the number.
  bool get hasPayoutAccount =>
      bankCode.trim().isNotEmpty &&
      bankAccountNo.trim().isNotEmpty &&
      bankAccountName.trim().isNotEmpty;
}

/// How the flow was entered, which decides **which screens it visits**.
///
/// Both entry points run the same page widgets and produce the same payload —
/// the difference is only which steps are reachable, so nothing downstream has
/// to care beyond the two places that branch on it.
enum PLoanEntry {
  /// The full six-screen wizard, from step 1 in this app.
  wizard(visitedSteps: [1, 2, 3, 4, 5, 6]),

  /// Deep-linked from the **LandAndHouseWeb top-up card**, which has already
  /// shown the customer the approved loan amount and already holds this
  /// contract's collateral data from `/loan/list`. So two steps are redundant
  /// and skipped:
  ///
  /// - **step 2 (ยอดจัดสินเชื่อ)** — the card showed the amount; the resume
  ///   route prices it and lands directly on step 3.
  /// - **step 4 (รูปภาพหลักประกัน)** — an Extra's collateral is already known.
  ///
  /// Visited: จำนวนงวด → ตรวจสอบข้อมูลส่วนตัว → สรุป/ยืนยัน.
  ///
  /// ⚠ Skipping step 4 means the submission carries **no collateral photos** —
  /// `carImage`/`documentImage` are empty and `property_image`/`act_image` go
  /// out as `''`. That is the requirement (the asset is already on file), but
  /// if the backend rejects a top-up without them, this is why.
  topupCard(visitedSteps: [3, 5, 6], precedingSteps: 1);

  const PLoanEntry({required this.visitedSteps, this.precedingSteps = 0});

  /// The screens this entry point visits, as their full-wizard step numbers.
  final List<int> visitedSteps;

  /// Steps the customer already completed **before this build opened**, counted
  /// in the indicator so the journey reads continuously across the two apps.
  ///
  /// For `topupCard` that is 1: the LandAndHouseWeb top-up card, where the
  /// customer picked the contract and saw the amount — i.e. exactly the work
  /// steps 1 and 2 do in the wizard. Landing on "1 of 3" made that card look
  /// like it was not part of the application; it now reads "2 of 4".
  final int precedingSteps;

  /// How many steps the indicator should show, including [precedingSteps].
  int get totalSteps => precedingSteps + visitedSteps.length;

  /// Position of full-wizard [step] within this entry point, 1-based.
  ///
  /// Renumbering matters: a `topupCard` flow would otherwise read
  /// "3 of 6 → 5 of 6", which looks like a broken indicator rather than a
  /// deliberately shorter path. Falls back to [step] for a screen this entry
  /// point does not visit.
  int stepNumber(int step) {
    final index = visitedSteps.indexOf(step);
    return index < 0 ? step : precedingSteps + index + 1;
  }
}

class PLoanFlow implements NdidSubject {
  PLoanFlow({
    required this.hashThaiId,
    this.kind = PLoanKind.extra,
    this.entry = PLoanEntry.wizard,
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

  /// Where the flow was entered, and therefore which screens it visits.
  /// Set once at construction — see [PLoanEntry].
  final PLoanEntry entry;

  /// True when step 4 (collateral photos) is not part of this path, so step 3
  /// continues straight to step 5.
  bool get skipsCollateralPhotos => entry == PLoanEntry.topupCard;

  /// Total steps the indicator shows, and this screen's position in them.
  int get totalSteps => entry.totalSteps;
  int stepNumber(int fullWizardStep) => entry.stepNumber(fullWizardStep);

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

  /// The contract the money is drawn against — **[PLoanKind.extra] only**.
  ///
  /// A new P-Loan has **no contract at all**, not even a reference one: it is
  /// a fresh loan, `refContractNo` is an Extra's field, and nothing about an
  /// existing contract describes it. It is null for the whole of that flow.
  ///
  /// That is the reason a new P-Loan makes none of the `/topup/*` calls (all
  /// keyed by `db_name` + `contract_no`), and the reason it cannot reach
  /// `POST /pdf/loan` either — see [canGenerateDocuments].
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

  // ── Steps 4 & 5: what a new P-Loan states for itself ────────────────

  /// Collateral and payout account as the customer gives them, for a **new**
  /// P-Loan. Untouched (and unread) for an Extra, which takes both off the
  /// contract it draws on — see the `collateral*` / `bank*` getters below,
  /// which pick the right source so no screen or payload has to.
  final NewLoanDetails newLoan = NewLoanDetails();

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

  /// The applicant's own Thai ID, digits only — from the profile, falling back
  /// to the id read off the card when the profile has none.
  String get customerThaiIdDigits {
    final fromProfile = (customer?.thaiId ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    return fromProfile.isNotEmpty
        ? fromProfile
        : verifiedThaiId.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// [NdidSubject.ndidThaiId] — [customerThaiIdDigits], unless a non-prod build
  /// substitutes the NDID test identity.
  ///
  /// The DAP **uat** node only has an identity registered for
  /// [kNdidTestThaiId], so verifying a real customer there fails for want of an
  /// IdP rather than for any reason about them. On **prod**
  /// [AppEnvironment.ndidThaiIdOverride] is null and this is always the
  /// applicant's own id.
  ///
  /// Scoped to NDID deliberately: nothing else reads this getter, so the
  /// substitution cannot reach `/vision/thai-id-validate` (which checks the
  /// card against [customerThaiIdDigits]) or any submitted payload.
  @override
  String get ndidThaiId =>
      AppEnvironment.current.ndidThaiIdOverride ?? customerThaiIdDigits;

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
  // Each of the next few getters answers the same question — "is this fact
  // the customer's, or the contract's?" — once, so the screens and the two
  // payload mappers don't each have to branch on [kind].

  /// Loan type driving step 4's required photos (`M` motorcycle, `C` car, …).
  ///
  /// An Extra's collateral is the contract's. A new P-Loan's is whatever the
  /// customer picked, and is `''` until they do.
  String get loanTypeCode => isNewPLoan
      ? (newLoan.collateralType?.code ?? '')
      : (contract?.contractDetails.loanTypeCode ?? '');

  /// Display name for [loanTypeCode] — also what the contract PDF is titled
  /// with.
  String get loanTypeName => isNewPLoan
      ? (newLoan.collateralType?.label ?? '')
      : (contract?.contractDetails.loanTypeName ?? '');

  String get collateralBrand => isNewPLoan
      ? newLoan.brand
      : (amountDetail?.contractDetails.vehicleBrand ?? '');

  String get collateralSeries =>
      isNewPLoan ? newLoan.series : (amountDetail?.carDetails.series ?? '');

  String get collateralRegistration => isNewPLoan
      ? newLoan.registration
      : (amountDetail?.carDetails.registration ?? '');

  String get collateralProvince =>
      isNewPLoan ? newLoan.province : (amountDetail?.carDetails.province ?? '');

  String get collateralRegistrationExpiry => isNewPLoan
      ? newLoan.registrationExpiry
      : (amountDetail?.contractDetails.licensePlateExpireDate ?? '');

  /// Manufacture year, the one collateral fact both submit payloads carry
  /// (`registerYear`).
  String get collateralManufactureYear => isNewPLoan
      ? newLoan.manufactureYear
      : (amountDetail?.carDetails.manufactureYear ?? '');

  /// Where the payout goes. An Extra reuses the account already registered
  /// against its contract; a new P-Loan has no contract to inherit one from,
  /// so the customer states it on step 5.
  String get bankCode => isNewPLoan
      ? newLoan.bankCode
      : (contract?.contractBankBrandname ?? '');

  String get bankAccountNo =>
      isNewPLoan ? newLoan.bankAccountNo : (contract?.contractBankAccount ?? '');

  /// Account holder. For an Extra the contract carries no holder name and the
  /// account is the customer's own, which is what the save API's sample shows.
  String get bankAccountName =>
      isNewPLoan ? newLoan.bankAccountName : (customer?.fullName ?? '');

  /// Bank logo bytes, when one came with the contract. A typed account has no
  /// logo to show.
  String get bankLogoBase64 => isNewPLoan ? '' : (contract?.branchImage ?? '');

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

  /// Whether the three contract PDFs can be produced for this application.
  ///
  /// `POST /pdf/loan` is keyed by `contract_no` + `db_name` + `from`
  /// (the contract's comcode) + `contract_date`. An Extra has all four. A new
  /// P-Loan has **no contract**, and the new-loan product has no document
  /// endpoint of its own yet, so there is nothing to generate, read, consent
  /// to or sign — and therefore **a new-P-Loan submit cannot complete today**.
  ///
  /// This is the seam to change when that endpoint lands: make it true for a
  /// new loan and point `PLoanApi.generateDocuments` at the new call.
  bool get canGenerateDocuments => !isNewPLoan && contract != null;

  /// Step 6's submit button is enabled only when identity, the contract
  /// documents, their consent, NDID signing and the sensitive-data consent are
  /// all done. Marketing consent is a genuine opt-in and deliberately does not
  /// gate anything.
  ///
  /// A new P-Loan additionally has to have stated its own collateral and
  /// payout account. Both are gated on their own screens too; the check is
  /// repeated here because a submit that silently posts a blank payout account
  /// is worse than a disabled button. It also cannot satisfy [documents] —
  /// see [canGenerateDocuments] — which is what blocks it today.
  bool get canSubmit =>
      missingIdentityPhoto == null &&
      documents != null &&
      missingConsent == null &&
      ndidVerified &&
      sensitiveConsent &&
      (isNewPLoan
          ? (newLoan.hasCollateral && newLoan.hasPayoutAccount)
          : contract != null);

  /// Money the customer receives for [requestedAmount].
  ///
  /// **`requested − stamp duty`, for both kinds.**
  ///
  /// Instructed 2026-07-30: *"ยอดโอนเงินเข้าบัญชี คือ ยอดจัดวงเงินอเนกประสงค์ ลบ
  /// ค่าอากรแสตมป์"*, the credit line being *"ยอดเต็ม"* — the full amount, not
  /// one reduced by the old contract.
  ///
  /// An Extra used to deduct the reference contract's closing balance too, the
  /// way a top-up does: there, a larger new loan *closes* the old contract, so
  /// its principal comes off what is transferred. A P-Loan Extra does not
  /// replace that contract — `topup_extra` is typically far smaller than the
  /// balance would be — so deducting it drove the payout negative
  /// (`2,000 − 7,740 − 1` on `MLOAN`/`ฮฮM680702003NF61X`), and that number was
  /// reaching `transfer_amount` in the submitted body, not just the screen.
  int get payoutAmount {
    final detail = amountDetail;
    if (detail == null) return 0;
    return requestedAmount - detail.feeAmount;
  }

  /// Smallest amount a new P-Loan may be requested for: the rounding unit,
  /// below which there is nothing to lend.
  static const int newLoanMinimumAmount = 100;

  /// Whether [requestedAmount] is worth sending to the calculator.
  ///
  /// Neither kind is range-checked here:
  ///
  ///  - a **P-Loan Extra** requests the fixed `topup_extra` offer, and
  ///    `min/max_topup_amount` bound the *top-up* product rather than this one
  ///    (see [LoanAmountDetail.extraRequestAmount]) — so the only thing that
  ///    disqualifies it is having no offer at all;
  ///  - a **new P-Loan** has the customer name the amount, and any product
  ///    floor or ceiling is the server's to enforce: `/topup/calculator`
  ///    rejects what it will not price and its message is shown as-is, rather
  ///    than a bound being guessed at here.
  bool get isRequestedAmountAllowed {
    if (amountDetail == null) return false;
    return isNewPLoan
        ? requestedAmount >= newLoanMinimumAmount
        : requestedAmount > 0;
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
