/// A contract already in memory, handed to the next screen instead of making
/// it fetch `/loan/list` again.
///
/// The payment screens are reached in two very different ways:
///
///   * **from inside this build** — the loan detail screen already loaded the
///     contract to draw the card the customer just tapped, and the payment
///     screen hands the same row on to the QR screen. Neither has any reason
///     to ask the API for a row it is holding;
///   * **from the host, in a fresh WebView** — nothing is in memory, so the
///     screen fetches.
///
/// So the seed is **an optimisation on one path, never a requirement**. Every
/// screen that takes one still works without it, which is what keeps a reload
/// working: go_router drops `extra` on refresh, and the screen re-fetches
/// rather than resuming a stale copy. Same shape and same reasoning as
/// `PLoanResumeSeed`.
library;

import '../../p_loan/application/models/loan_contract.dart';

class LoanPaymentSeed {
  const LoanPaymentSeed({required this.contract});

  /// The contract row as `/loan/list` returned it.
  final LoanContract contract;

  /// Whether this seed is for the contract the **URL** names.
  ///
  /// ⚠ The query string stays the authority. A seed that disagrees with it is
  /// ignored and the contract is fetched, because the URL is what a reload
  /// would use and the two must never resolve differently.
  ///
  /// [dbName] is optional on these routes — contract numbers are unique only
  /// within a database, so when the caller supplies one it is matched, and
  /// when it does not the contract number alone decides. That is exactly the
  /// rule the fetching path applies, so seeded and unseeded runs cannot pick
  /// different contracts.
  bool matches({required String contractNo, required String dbName}) {
    if (contract.contractNo.trim() != contractNo.trim()) return false;
    final db = dbName.trim();
    return db.isEmpty || contract.dbName.trim() == db;
  }
}
