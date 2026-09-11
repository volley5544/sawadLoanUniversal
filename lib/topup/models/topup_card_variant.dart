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
