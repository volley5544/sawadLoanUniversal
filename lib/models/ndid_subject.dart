/// What the NDID screens need from whatever flow launched them.
///
/// `ndid_bank_select_page` and `ndid_verify_page` are shared by two unrelated
/// flows — the 5-step loan-register wizard (step 4) and the P-Loan application
/// (step 6) — which carry different state objects: `LoanRegisterForm` and
/// `PLoanFlow`. They only ever needed two values from either, so both implement
/// this instead of the pages being duplicated or one flow having to fabricate
/// the other's model.
abstract interface class NdidSubject {
  /// The person's Thai ID, **digits only**.
  ///
  /// Implementations strip formatting: the wizard holds it as `1-2345-…` for
  /// display, while the API needs bare digits, and the NDID pages should not
  /// have to know which. Empty when unknown — `POST /idp/list` then returns the
  /// full IdP list rather than the customer's registered ones.
  String get ndidThaiId;

  /// Node id of the IdP the customer picked (e.g. `idp1`).
  ///
  /// Written by the bank-select page and read by the verify page, so it is
  /// mutable and lives on the flow rather than being passed as a route param —
  /// the verify page can be reached by back-navigation, and the choice has to
  /// survive that. Null in the plain-browser mock flow, which has no real IdP.
  String? ndidIdpId;
}
