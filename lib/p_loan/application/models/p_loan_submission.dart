/// Maps the accumulated [PLoanFlow] onto the **`regmast_ploan.php`** payload —
/// the 34 scalar fields and 12 image groups that
/// `p_loan/submit_form/p_loan_form_page.dart` collects by hand.
///
/// Nothing here sends anything. It exists so that when the P-Loan save API is
/// wired up, the wizard already carries everything it needs:
/// `PLoanApiService().submit(fields: s.fields, imageGroups: s.imageGroups)`.
///
/// **Every field is accounted for.** Each one is either derived from flow
/// state, a fixed constant, or explicitly listed in [unresolvedFields] because
/// no step of this flow can know it. A field is never filled with a
/// plausible-looking guess — an empty string that shows up in
/// [unresolvedFields] is recoverable, a wrong employee id or GPS district is
/// not.
library;

import 'dart:typed_data';

import 'p_loan_flow.dart';

class PLoanSubmission {
  const PLoanSubmission._(this.fields, this.imageGroups, this.unresolvedFields);

  /// The 34 scalar form fields, keyed by their `regmast_ploan.php` names.
  final Map<String, String> fields;

  /// Image groups, keyed by group name. Each entry is sent as repeated
  /// `group[]` file parts.
  final Map<String, List<Uint8List>> imageGroups;

  /// Fields that came out empty because this flow has no source for them.
  /// Present so a caller can refuse to submit, or prompt, rather than posting
  /// a half-filled application.
  final List<String> unresolvedFields;

  /// True when every field has a value.
  bool get isComplete => unresolvedFields.isEmpty;

  /// Builds the payload from [flow].
  ///
  /// [now] is injectable so the timestamp is testable.
  factory PLoanSubmission.fromFlow(PLoanFlow flow, {DateTime? now}) {
    final contract = flow.contract;
    final detail = flow.amountDetail;
    final installment = flow.installment;
    final customer = flow.customer;
    final stamp = now ?? DateTime.now();

    final fields = <String, String>{
      // ── ข้อมูลรายการ ────────────────────────────────────────────────
      'transNo': flow.transNo,
      'transDate': _timestamp(stamp),
      // 'A' = active/new, matching the sample payload in the submit form.
      'statusCode': 'A',
      'empId': flow.empId,
      // An Extra's filing branch is the contract's. A new P-Loan has no
      // contract and no other source for it, so it goes out blank and is
      // reported — a wrong branch code is worse than an absent one.
      'branchID': contract?.branchCode ?? '',
      // **Extra only.** "เลขที่สัญญาอ้างอิง" is the contract the top-up is
      // raised against. A new P-Loan is not raised against anything, so this
      // is empty by design rather than missing — see [_absentByDesign].
      'refContractNo': flow.isNewPLoan ? '' : (contract?.contractNo ?? ''),
      'mktChannel': flow.mktChannel,
      'customerSource': flow.customerSource,

      // ── ข้อมูลลูกค้า ────────────────────────────────────────────────
      'citizenId': customer?.thaiId ?? '',
      // The submit form labels this 'ชื่อลูกค้า'; the API name really is 'test'.
      'test': _fullName(customer?.firstName, customer?.lastName),
      'mobileNo': customer?.phoneNumber ?? '',
      // The collateral's year, which for a new P-Loan the customer states on
      // step 4 — the reference contract's vehicle is a different one.
      'registerYear': _buddhistYear(flow.collateralManufactureYear),

      // ── ข้อมูลสินเชื่อ ──────────────────────────────────────────────
      // requestCredit = what the customer asked for, creditAmt = the limit
      // already approved, loanAmt = what is actually being drawn.
      //
      // A new P-Loan has no approved limit yet — underwriting decides it — so
      // creditAmt is left blank and reported in [unresolvedFields] rather than
      // borrowing the reference contract's top-up headroom, which describes a
      // different product.
      'requestCredit': _money(flow.requestedAmount),
      'creditAmt':
          flow.isNewPLoan ? '' : _money(detail?.defaultTopupAmount),
      'loanAmt': _money(flow.requestedAmount),
      'termPeriod': _int(installment?.tenor),
      'totalAmt': _money(installment?.totalAmt),
      'intAmt': _money(installment?.intAmt),
      'intRate': _rate(detail?.interestRate),
      'regularPeriod': _money(installment?.regularPeriodAmt),
      'lastPeriod': _money(installment?.lastPeriodAmt),
      'lastPeriodPromo': _money(installment?.lastPeriodPromo),
      'payDay': _int(detail?.dueDay),
      'initialDate': flow.plan?.firstDueDate ?? '',

      // ── ข้อมูลการโอนเงิน ────────────────────────────────────────────
      // An Extra pays out to the account registered against its contract; a
      // new P-Loan to the one the customer gave on step 5.
      'bankCode': flow.bankCode,
      'bankAccNo': flow.bankAccountNo,
      // What actually reaches the customer, after the old principal and duty.
      'transferAmt': _money(flow.payoutAmount),

      // ── ตำแหน่ง GPS ─────────────────────────────────────────────────
      'gpsProvinceId': flow.gpsProvinceId,
      'gpsAumphurId': flow.gpsAumphurId,
      'longitude': flow.longitude,
      'latitude': flow.latitude,

      // ── ความยินยอม ─────────────────────────────────────────────────
      // Captured from the checkboxes on step 6, not assumed.
      'marketingConsent': _yesNo(flow.marketingConsent),
      'sensitiveConsent': _yesNo(flow.sensitiveConsent),
      'remark': flow.remark,
    };

    // Photos, grouped by their regmast group. Several slots share a group
    // (all six vehicle angles are `carImage[]`), so order is stable by enum
    // declaration order rather than by hash order.
    final images = <String, List<Uint8List>>{};
    for (final slot in PLoanPhoto.values) {
      final bytes = flow.photos[slot];
      if (bytes == null || bytes.isEmpty) continue;
      images.putIfAbsent(slot.pLoanGroup, () => <Uint8List>[]).add(bytes);
    }

    return PLoanSubmission._(
      Map.unmodifiable(fields),
      Map.unmodifiable(images),
      List.unmodifiable(_unresolved(fields, _absentByDesign(flow))),
    );
  }

  /// Fields this **product** does not have, as opposed to fields this flow
  /// failed to collect. Reporting them would send the reader looking for a
  /// value that is not supposed to exist.
  ///
  /// `refContractNo` is the only one: it identifies the contract an Extra is
  /// raised against, and a new P-Loan is raised against nothing.
  static Set<String> _absentByDesign(PLoanFlow flow) =>
      flow.isNewPLoan ? const {'refContractNo'} : const {};

  /// Groups this flow has no capture step for, so they are always empty:
  /// the e-signature and the four co-borrower groups. Listed explicitly so
  /// their absence is a documented gap rather than an oversight.
  static const List<String> unsupportedImageGroups = [
    'eSignatureImage',
    'requestDocImage',
    'coBorrowCenSusImage',
    'coBorrowCardIdImage',
    'coCustomerImage',
    'coBorrowRequestDocImage',
  ];

  /// Fields that are legitimately empty for a first submission and so are not
  /// reported as unresolved.
  static const Set<String> _allowedEmpty = {
    // Assigned by the server on submit.
    'transNo',
    // Genuinely optional.
    'remark',
    // Promotional last installment; zero unless a promo applies.
    'lastPeriodPromo',
  };

  // Consents need no entry above: _yesNo always yields 'Y' or 'N', so they can
  // never read as unresolved.

  static List<String> _unresolved(
    Map<String, String> fields,
    Set<String> absentByDesign,
  ) =>
      fields.entries
          .where((e) =>
              e.value.isEmpty &&
              !_allowedEmpty.contains(e.key) &&
              !absentByDesign.contains(e.key))
          .map((e) => e.key)
          .toList()
        ..sort();

  // ── formatting ──────────────────────────────────────────────────────
  // The API takes everything as form-encoded strings. Money carries two
  // decimals and no thousands separators, matching the sample payload.

  static String _yesNo(bool value) => value ? 'Y' : 'N';

  static String _money(num? value) =>
      value == null ? '' : value.toStringAsFixed(2);

  static String _int(int? value) => value == null ? '' : '$value';

  static String _rate(double? value) =>
      value == null ? '' : value.toStringAsFixed(2);

  static String _timestamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  static String _fullName(String? first, String? last) =>
      [first ?? '', last ?? ''].where((p) => p.trim().isNotEmpty).join(' ').trim();

  /// The form expects a Buddhist-era year. Vehicle data may arrive either way,
  /// so convert only when the value looks Gregorian.
  static String _buddhistYear(String? raw) {
    final year = int.tryParse((raw ?? '').trim());
    if (year == null || year == 0) return '';
    return year > 2200 ? '$year' : '${year + 543}';
  }
}


/// Payload for the **P-Loan save API** (`POST /SavePloanContract`) — the
/// endpoint a completed application is actually filed to.
///
/// Near-identical to [PLoanSubmission] (same camelCase oddities, same image
/// group names), but it is **not the same field set**, so the two are kept
/// apart rather than one being bent to fit the other:
///
/// | | [PLoanSubmission] (`regmast_ploan.php`) | here (`SavePloanContract`) |
/// | --- | --- | --- |
/// | Customer name | one `test` field | `firstName` + `lastName` |
/// | Account holder | — | `bankAccName` |
/// | Branch | `branchID` | `branchId` (lower `d`) |
/// | Server-assigned | `transNo`, `transDate` | not sent |
/// | Also absent | — | `payDay`, `initialDate`, `lastPeriodPromo`, `remark` |
///
/// The 30 fields below are exactly what the API's own sample call sends, in its
/// order. Shared values are read back from [PLoanSubmission] rather than
/// re-derived, so the two payloads cannot disagree about the same number.
class PLoanContractSubmission {
  const PLoanContractSubmission._(
      this.fields, this.imageGroups, this.unresolvedFields);

  /// Scalar form fields, keyed by their `SavePloanContract` names.
  final Map<String, String> fields;

  /// Image groups; each entry is sent as repeated `group[]` file parts.
  final Map<String, List<Uint8List>> imageGroups;

  /// Fields this flow had no value for. The API decides whether it minds, but
  /// they are named here so a rejection can say which ones were blank instead
  /// of leaving the cause to guesswork.
  final List<String> unresolvedFields;

  bool get isComplete => unresolvedFields.isEmpty;

  factory PLoanContractSubmission.fromFlow(PLoanFlow flow, {DateTime? now}) {
    final shared = PLoanSubmission.fromFlow(flow, now: now);
    final customer = flow.customer;
    String v(String key) => shared.fields[key] ?? '';

    final fields = <String, String>{
      'refContractNo': v('refContractNo'),
      'citizenId': v('citizenId'),
      'mobileNo': v('mobileNo'),
      // regmast takes the whole name in its oddly-named `test` field; this API
      // wants it split, so it comes off the profile rather than being re-parsed.
      'firstName': customer?.firstName.trim() ?? '',
      'lastName': customer?.lastName.trim() ?? '',
      'creditAmt': v('creditAmt'),
      'loanAmt': v('loanAmt'),
      'requestCredit': v('requestCredit'),
      'termPeriod': v('termPeriod'),
      'totalAmt': v('totalAmt'),
      'intAmt': v('intAmt'),
      'intRate': v('intRate'),
      'regularPeriod': v('regularPeriod'),
      'lastPeriod': v('lastPeriod'),
      'bankCode': v('bankCode'),
      'bankAccNo': v('bankAccNo'),
      // For an Extra the contract carries the payout account number but no
      // holder name — it is the customer's own account, which is what the
      // API's sample shows. A new P-Loan names the holder on step 5, since
      // the account itself is theirs to choose.
      'bankAccName': flow.bankAccountName,
      'transferAmt': v('transferAmt'),
      'statusCode': v('statusCode'),
      'gpsAumphurId': v('gpsAumphurId'),
      'gpsProvinceId': v('gpsProvinceId'),
      'latitude': v('latitude'),
      'longitude': v('longitude'),
      'empId': v('empId'),
      // Same value as regmast's `branchID`; only the spelling differs.
      'branchId': v('branchID'),
      'mktChannel': v('mktChannel'),
      'customerSource': v('customerSource'),
      'registerYear': v('registerYear'),
      'marketingConsent': v('marketingConsent'),
      'sensitiveConsent': v('sensitiveConsent'),
    };

    // Same rule as the regmast payload: a field this product does not have is
    // not a field this flow failed to fill.
    final absentByDesign = PLoanSubmission._absentByDesign(flow);
    return PLoanContractSubmission._(
      Map.unmodifiable(fields),
      shared.imageGroups,
      List.unmodifiable(
        (fields.entries
            .where((e) =>
                e.value.isEmpty && !absentByDesign.contains(e.key))
            .map((e) => e.key)
            .toList()
          ..sort()),
      ),
    );
  }
}
