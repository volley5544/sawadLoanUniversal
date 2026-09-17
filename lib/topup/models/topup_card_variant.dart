/// Which of the three headers a contract card shows.
///
/// The source decides this in one `if / else if / else` inside the carousel's
/// item builder, and the order matters: a contract that is *both* ineligible
/// and carries products shows the ineligible header, not the offer.
///
/// ⚠ The same page also contains a **dead** copy of this chain guarded by
/// `if (true)`, which always returns the plain header. That copy is a
/// FlutterFlow leftover from a list layout that was replaced by the carousel;
/// reading it instead of the carousel's is an easy way to conclude the
/// variants do not exist.
library;

import '../../p_loan/application/models/loan_contract.dart';

enum TopupCardVariant {
  /// `can_topup == 'N'` — the contract cannot be topped up at all. No amount
  /// and no action; the customer is pointed at a branch.
  ineligible,

  /// The contract carries add-on products, so the card leads with the offer.
  specialOffer,

  /// The ordinary card.
  plain;

  /// Picks the variant for [contract], in the source's order.
  static TopupCardVariant of(LoanContract contract) {
    if (contract.topupDetail.canTopup == 'N') return TopupCardVariant.ineligible;
    if (contract.topupDetail.products.any((p) => !p.isEmpty)) {
      return TopupCardVariant.specialOffer;
    }
    return TopupCardVariant.plain;
  }
}

/// Whether the **สิทธิพิเศษเฉพาะคุณ** product grid renders in the card body.
///
/// Three conditions, all the source's: there must be products, the contract
/// must be toppable, and there must be no request already in flight — picking
/// a product starts a new request, which a contract mid-request cannot take.
///
/// Note this is *not* the same as [TopupCardVariant.specialOffer]: the header
/// can be the offer one while the grid is withheld because a request is
/// already filed.
bool showsSpecialOffers(LoanContract contract) =>
    contract.topupDetail.products.any((p) => !p.isEmpty) &&
    contract.topupDetail.canTopup != 'N' &&
    contract.hasNoRequestYet;

/// Loan types the in-app top-up supports: **motorcycle (`M`) and car (`C`)**.
///
/// Everything else — land/house (`L`/`H`), and any code the API adds later —
/// is branch business. The set is named rather than inlined because two rules
/// below key on it and `TopupFlow.requiredPhotos` switches on the same two
/// codes.
const Set<String> kTopupSelfServiceLoanTypes = {'M', 'C'};

/// Whether [contract] can actually raise a top-up in the app.
///
/// **Both halves are required** (instructed 2026-09-17): the loan type must be
/// `M` or `C` **and** `can_topup` must be `'Y'`.
///
/// ⚠ This is deliberately **not** `LoanContract.isEligible`, which tests
/// `can_topup == 'Y'` alone. That getter is shared with the **P-Loan Extra**
/// flow (`p_loan_contract_select_page`, `/pLoan/resume`), and a P-Loan Extra is
/// a different product that only *references* the contract — a loan type this
/// flow cannot service says nothing about whether that one can. Widening
/// `isEligible` would silently refuse P-Loan Extra applications too.
///
/// ⚠ **A blank `loan_type_code` refuses**, like a blank `can_topup`. Blank is
/// silence, not permission, and the direction that withholds an action is the
/// safe one. It cannot happen on this screen today — the card is built from
/// `/loan/list`, whose `contract_details` is populated — but note
/// `POST /topup/recal` sends that whole block **blank**, so a future reader
/// wiring this to `amountDetail` instead would refuse every contract.
bool canTopupInApp(LoanContract contract) =>
    kTopupSelfServiceLoanTypes
        .contains(contract.contractDetails.loanTypeCode.trim()) &&
    contract.isEligible;

/// Why the refusal card is being shown, as its second line.
///
/// ⚠ `can_topup_msg` is only quoted when `can_topup` is what refused. On a
/// contract the API says is eligible but whose **loan type** this flow cannot
/// service, that message either does not exist or describes something else
/// entirely — the same reason the amount screen withholds it above a working
/// button. Naming an unrelated cause is worse than naming none, so the
/// loan-type refusal falls back to the branch line.
String topupRefusalReason(LoanContract contract) => contract.isEligible
    ? TopupDetail.contactBranchFallback
    : contract.topupDetail.ineligibleReason;
