/// The top-up flow's accumulated state, passed page → page as a go_router
/// `extra` — the same convention `LoanRegisterForm` and `PLoanFlow` use.
///
/// The source FlutterFlow app kept all of this in a global `FFAppState`, so a
/// half-finished top-up leaked into the next one and no screen owned any
/// value. One mutable object threaded through the routes keeps it explicit:
/// every field below is written by exactly one step.
///
/// **This is a top-up, not a P-Loan Extra** — the two look alike and price
/// differently, which is the single most important thing to keep straight when
/// editing either. A top-up *closes out* the existing contract and reissues it
/// larger, so the old principal comes off the payout ([payoutAmount]); a P-Loan
/// Extra only references the contract and deducts nothing. See
/// `PLoanFlow.payoutAmount` for the other half of that story.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../models/customer_address.dart';
import '../../models/customer_detail.dart';
import '../../p_loan/application/models/installment_plan.dart';
import '../../p_loan/application/models/loan_amount_detail.dart';
import '../../p_loan/application/models/loan_contract.dart';
import '../../p_loan/application/models/loan_documents.dart';
import 'topup_photo.dart';
import 'topup_purpose.dart';

/// How the customer got into the flow, which decides what the back button on
/// the first screen does.
enum TopupEntry {
  /// From this app's own home menu — back pops normally.
  menu,

  /// Launched by the native host straight into the card screen — back has
  /// nothing beneath it, so it closes the WebView.
  host,
}

/// Where the amount screen sends the customer next.
///
/// A top-up is not always possible even on a contract that offers one: land
/// and house loans are not self-service, `can_topup` can refuse, and a payout
/// above the contract's `max_transfer_amount` needs a person. In those cases
/// the source files a **lead** instead, and says so by relabelling its button
/// ส่งข้อมูล rather than ถัดไป.
enum TopupOutcome {
  /// Continue to the installment picker and file a real top-up.
  topup,

  /// File a lead for someone to call the customer back.
  lead,

  /// Accrued interest is outstanding; it must be paid before anything else.
  payInterest,
}

/// The mutable state of one top-up application.
class TopupFlow {
  TopupFlow({
    required this.hashThaiId,
    required this.authToken,
    this.entry = TopupEntry.menu,
    this.source = '',
    this.referId = '',
  });

  // ── Launch context ───────────────────────────────────────────────────
  final String hashThaiId;

  /// Bearer token captured at construction. Only a fallback: every request
  /// re-resolves a fresh one through `AuthToken.resolve`, because a top-up
  /// routinely outlives the hour a Firebase ID token is good for.
  final String authToken;

  final TopupEntry entry;

  /// Attribution passed through to the submit payload untouched.
  final String source;
  final String referId;

  // ── Step 1 — contract ────────────────────────────────────────────────
  LoanContract? contract;
  CustomerDetail? customer;
  CustomerAddressBook? addressBook;

  // ── Step 2 — purpose ─────────────────────────────────────────────────
  TopupPurpose? purpose;

  /// Free text the customer may add under "อื่นๆ" (the source's "ระบุ..."
  /// field).
  ///
  /// ⚠ **No submit field carries it.** `POST /topup` takes `product_code` and
  /// nothing else about the purpose, which is equally true of the source. It
  /// is collected because the screen asks for it; if the backend ever gains a
  /// field, this is the value to send.
  String purposeNote = '';

  // ── Step 3 — amount ──────────────────────────────────────────────────
  /// `GET /topup/detail` for [contract], with the special-limit uplift already
  /// folded in (see [applySpecialLimit]).
  LoanAmountDetail? amountDetail;

  /// The figure the customer asked for, before the calculator confirms it.
  int requestedAmount = 0;

  /// `POST /topup/calculator` for [requestedAmount].
  InstallmentPlan? plan;

  // ── Step 4 — installments ────────────────────────────────────────────
  InstallmentOption? installment;

  // ── Step 5 — collateral photos, Step 7 — identity photos ─────────────
  final Map<TopupPhoto, Uint8List> photos = {};

  // ── Step 7 — documents, identity and consent ─────────────────────────
  LoanDocuments? documents;

  /// Documents the customer has read and accepted, by kind.
  final Set<LoanDocumentKind> consentedDocuments = {};

  /// The ID number `/vision/thai-id-validate` read off the card photo.
  String verifiedThaiId = '';

  /// PDPA answers. Both start **unanswered** rather than defaulting to yes.
  ///
  /// The source hardcoded `'Y'` for both into the submit body, so the customer
  /// was recorded as having consented to marketing they were never asked
  /// about. `N` is a real answer here, which is why neither is ever reported
  /// as a missing field.
  bool marketingConsent = false;
  bool sensitiveConsent = false;

  /// Device GPS, captured on the conclusion screen and never awaited.
  String latitude = '';
  String longitude = '';

  /// Transaction number returned by a successful `POST /topup`.
  String transNo = '';

  // ── Derived: amounts ─────────────────────────────────────────────────

  /// Folds the contract's special limit into [amountDetail].
  ///
  /// `topup_special_flag` on the contract means the customer has been granted
  /// `topup_specials` on top of the ordinary limit, and `/topup/detail` does
  /// **not** include it — so both the default and the ceiling have to be
  /// raised here or the extra limit is offered nowhere.
  void applySpecialLimit() {
    final detail = amountDetail;
    final contract = this.contract;
    if (detail == null || contract == null) return;
    if (!contract.topupSpecialFlag) return;
    final specials = contract.topupDetail.topupSpecials;
    if (specials <= 0) return;
    amountDetail = detail.copyWith(
      topupSpecials: specials,
      defaultTopupAmount: detail.defaultTopupAmount + specials,
      maxTopupAmount: detail.maxTopupAmount + specials,
    );
  }

  /// The amount the calculator actually priced, which is what every downstream
  /// figure is derived from. Falls back to what was asked for.
  int get calculatedAmount => plan?.amount ?? requestedAmount;

  /// Stamp duty. **The calculator's, not `/topup/detail`'s.**
  ///
  /// `GET /topup/detail` returns the duty on the contract's *default* limit,
  /// while `POST /topup/calculator` recomputes it for the amount actually
  /// requested. Quoting the former on a smaller request charges duty for a
  /// larger loan than the customer is taking.
  int get feeAmount => plan?.feeAmount ?? amountDetail?.feeAmount ?? 0;

  /// Outstanding principal on the contract being replaced.
  int get closingBalance => amountDetail?.contractDetails.closingBalance ?? 0;

  /// Accrued interest, counted only when it has not already been settled.
  int get outstandingInterest =>
      hasUnpaidInterest ? (amountDetail?.interestYield ?? 0) : 0;

  /// `'Y'` means the accrued interest is still owed, and it must be paid
  /// before a top-up can be raised — the amount field locks and the primary
  /// button becomes ชำระเงิน.
  bool get hasUnpaidInterest => amountDetail?.interestPaidFlag == 'Y';

  /// **`transfer_amount` on the submit body**: what reaches the customer's
  /// account once the old contract is closed out and duty taken.
  ///
  /// This is the top-up formula and it is *not* `PLoanFlow.payoutAmount` — a
  /// top-up settles the old principal, a P-Loan Extra does not.
  int get payoutAmount => calculatedAmount - closingBalance - feeAmount;

  /// The stricter figure the eligibility check uses, which additionally nets
  /// off unpaid interest and the collection fee.
  ///
  /// Kept separate from [payoutAmount] on purpose: the source really does
  /// compute two different numbers here, one to decide whether a self-service
  /// top-up is allowed at all and one to send. Collapsing them would change
  /// what gets filed.
  int get netTransferAmount =>
      payoutAmount - outstandingInterest - (amountDetail?.collectionFee ?? 0);

  /// Upper bound on what may be transferred without a person involved.
  ///
  /// ⚠ **An absent `max_transfer_amount` reads as 0, and 0 refuses
  /// everything** — no positive payout is under it, so every contract files a
  /// lead. That is the source's behaviour reproduced exactly, and it is the
  /// first thing to check if the flow suddenly offers ส่งข้อมูล for every
  /// contract: the field is missing from `/loan/list`, not broken here. It is
  /// deliberately *not* treated as "no limit" — guessing the cap open would
  /// let a request through that the backend meant to hold back.
  int get maxTransferAmount => contract?.topupDetail.maxTransferAmount ?? 0;

  /// Whether [requestedAmount] sits inside the contract's allowed range.
  ///
  /// Unlike a P-Loan Extra, a top-up **does** honour `min/max_topup_amount` —
  /// those bounds describe this product.
  bool get isRequestedAmountAllowed {
    final detail = amountDetail;
    if (detail == null) return false;
    return requestedAmount >= detail.minTopupAmount &&
        requestedAmount <= detail.maxTopupAmount;
  }

  /// Whether the amount field may be edited. A named add-on product is priced
  /// by the product, and unpaid interest locks the field outright.
  bool get isAmountEditable =>
      !hasUnpaidInterest && (purpose?.isOther ?? true);

  // ── Derived: routing ─────────────────────────────────────────────────

  /// What the amount screen's primary button does.
  ///
  /// The three conditions behind [TopupOutcome.lead] are the source's, kept
  /// verbatim: land/house loan types are not self-service, `can_topup` can
  /// refuse after the detail call even when the list said otherwise, and a
  /// payout over `max_transfer_amount` needs a person.
  TopupOutcome get outcome {
    if (hasUnpaidInterest) return TopupOutcome.payInterest;
    final typeCode = contract?.contractDetails.loanTypeCode ?? '';
    final canTopup = amountDetail?.contractDetails.canTopup ?? '';
    if (typeCode == 'L' || typeCode == 'H') return TopupOutcome.lead;
    if (canTopup != 'Y') return TopupOutcome.lead;
    if (netTransferAmount > maxTransferAmount) return TopupOutcome.lead;
    return TopupOutcome.topup;
  }

  /// Label for that button, so the screen never has to restate the rule.
  String get primaryActionLabel => switch (outcome) {
        TopupOutcome.payInterest => 'ชำระเงิน',
        TopupOutcome.lead => 'ส่งข้อมูล',
        TopupOutcome.topup => 'ถัดไป',
      };

  // ── Derived: payout account ──────────────────────────────────────────
  //
  // A top-up always pays into the account already registered against the
  // contract it replaces — there is nothing for the customer to choose, which
  // is why these are read-only getters rather than fields.

  String get bankCode => contract?.contractBankBrandname ?? '';

  String get bankAccountNo => contract?.contractBankAccount ?? '';

  /// The contract carries no holder name, and the account is the customer's
  /// own.
  String get bankAccountName => customer?.fullName ?? '';

  /// Bank/branch logo that came with the contract, base64.
  String get bankLogoBase64 => contract?.branchImage ?? '';

  // ── Derived: photos ──────────────────────────────────────────────────

  String get loanTypeCode => contract?.contractDetails.loanTypeCode ?? '';

  /// Motorcycles need a whole-vehicle shot plus the tax disc; cars need four
  /// sides, the odometer and the tax disc.
  ///
  /// For any other loan type the source leaves its confirm button permanently
  /// disabled — a dead end. Requiring the tax disc alone is a deliberate
  /// deviation that keeps the flow completable, matching what the P-Loan port
  /// already does.
  List<TopupPhoto> get requiredPhotos => switch (loanTypeCode) {
        'M' => const [TopupPhoto.fullVehicle, TopupPhoto.taxDisc],
        'C' => const [
            TopupPhoto.carRight,
            TopupPhoto.carLeft,
            TopupPhoto.carFront,
            TopupPhoto.carBack,
            TopupPhoto.carMile,
            TopupPhoto.taxDisc,
          ],
        _ => const [TopupPhoto.taxDisc],
      };

  bool hasPhoto(TopupPhoto slot) => (photos[slot]?.isNotEmpty ?? false);

  /// The first required collateral photo still missing, or null.
  TopupPhoto? get missingCollateralPhoto {
    for (final slot in requiredPhotos) {
      if (!hasPhoto(slot)) return slot;
    }
    return null;
  }

  /// The first required identity photo still missing, or null.
  TopupPhoto? get missingIdentityPhoto {
    for (final slot in TopupPhoto.identity) {
      if (!hasPhoto(slot)) return slot;
    }
    return null;
  }

  /// Base64 of a captured photo, or `''` when that slot is empty.
  String base64OfPhoto(TopupPhoto slot) {
    final bytes = photos[slot];
    if (bytes == null || bytes.isEmpty) return '';
    return base64Encode(bytes);
  }

  // ── Derived: identity and submit gating ──────────────────────────────

  /// Whether the scanned card belongs to the customer on file.
  ///
  /// The source also accepted four hardcoded Thai IDs here, which let anyone
  /// holding one of those cards pass identity verification for *any* account.
  /// That backdoor is deliberately not reproduced — the same decision the
  /// P-Loan port made, and a test pins it shut.
  bool get isThaiIdVerified =>
      verifiedThaiId.isNotEmpty && verifiedThaiId == (customer?.thaiId ?? '');

  /// Every document read and accepted.
  bool get hasAllDocumentConsents =>
      documents != null &&
      LoanDocumentKind.values.every(consentedDocuments.contains);

  /// The first document the customer has not accepted yet, or null.
  LoanDocumentKind? get missingDocumentConsent {
    for (final kind in LoanDocumentKind.values) {
      if (!consentedDocuments.contains(kind)) return kind;
    }
    return null;
  }

  /// Whether `POST /topup` may be called.
  bool get canSubmit =>
      contract != null &&
      amountDetail != null &&
      plan != null &&
      installment != null &&
      documents != null &&
      hasAllDocumentConsents &&
      missingCollateralPhoto == null &&
      missingIdentityPhoto == null &&
      isThaiIdVerified &&
      sensitiveConsent;

  /// Why [canSubmit] is false, in the order the customer should fix them.
  /// Null when the request is ready to file.
  String? get submitBlockedReason {
    if (documents == null) return 'ไม่พบเอกสารสัญญา กรุณาลองใหม่';
    final doc = missingDocumentConsent;
    if (doc != null) return doc.consentPrompt;
    final collateral = missingCollateralPhoto;
    if (collateral != null) return collateral.missingMessage;
    final identity = missingIdentityPhoto;
    if (identity != null) return identity.missingMessage;
    if (!isThaiIdVerified) return 'กรุณาถ่ายรูปบัตรประชาชนเพื่อยืนยันตัวตน';
    if (!sensitiveConsent) {
      return 'กรุณายินยอมให้เก็บรวบรวมและใช้ข้อมูลอ่อนไหว';
    }
    if (installment == null) return 'กรุณาเลือกจำนวนงวด';
    return null;
  }

  /// The `/pdf/loan` request for this application, and the same object the
  /// submit body echoes back as `save_pdf`.
  ///
  /// Returns null while the flow is incomplete rather than throwing — the
  /// conclusion screen renders a "documents unavailable" state from it.
  ContractPdfRequest? get pdfRequest {
    final contract = this.contract;
    final detail = amountDetail;
    final installment = this.installment;
    if (contract == null || detail == null || installment == null) return null;
    return ContractPdfRequest(
      contractNo: detail.contractNo,
      dbName: detail.dbName,
      contractDate: detail.contractDate,
      amount: calculatedAmount.toDouble(),
      from: contract.contractDetails.comcode,
      contractBankAccount: contract.contractBankAccount,
      contractBankBrandname: contract.contractBankBrandname,
      contractBankType: contract.contractBankType,
      contractBankBranch: '',
      interestRate: detail.interestRate,
      installmentNumber: installment.tenor.toDouble(),
      amountPerInstallment: installment.regularPeriodAmt.toDouble(),
      startInstallmentDate: plan?.firstDueDate ?? detail.firstDueDate,
      installmentDate: '',
      vehicleType: contract.contractDetails.loanTypeName,
    );
  }
}
