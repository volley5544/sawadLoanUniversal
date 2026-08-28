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

  /// The IdP's **marketing name**, as the bank-select grid showed it
  /// (e.g. `ธนาคารกสิกรไทย`).
  ///
  /// Written beside [ndidIdpId] and read only by the error messages. §6.2.1
  /// bullet 4 of the NDID guideline requires the customer be shown the IdP
  /// Marketing Name rather than the word "IdP" or a node id, and one standard
  /// message (code 30900, "outside that provider's service hours") names it.
  /// Empty when unknown, which those messages degrade to a generic phrase for.
  ///
  /// `abstract` for the same reason [ndidReferenceId] is — an interface field
  /// cannot carry an initialiser, so this declares the getter/setter pair and
  /// leaves the storage to each implementation.
  abstract String ndidIdpName;

  /// NDID's own `reference_id` for the accepted verification
  /// (`POST /rp/verify` → `GET /rp/verify/{reference_id}`).
  ///
  /// Written by the verify page when a **real** request is accepted, and sent to
  /// `POST /ploan` as `ndid_reference_id` so the backend can confirm the
  /// verification with NDID itself instead of taking the client's word for it.
  /// Mutable and on the flow for the same reason [ndidIdpId] is: the value is
  /// produced two screens away from where it is used.
  ///
  /// Empty means **no proven verification is being claimed** — a simulated hop
  /// in a plain browser, or a flow that never reached NDID. It is deliberately
  /// not faked: an unprovable reference is worse than a blank one, which the
  /// submit payload reports as unresolved.
  ///
  /// `abstract` because a non-nullable field on an interface would otherwise
  /// need an initialiser here; this declares the getter/setter pair and leaves
  /// the storage to each implementation.
  abstract String ndidReferenceId;
}
