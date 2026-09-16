import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_contract.dart';
import 'package:sawad_loan_universal/topup/topup_card_page.dart';

/// `?contNo=` preselects a card on the top-up entry screen. It is how the
/// srisawad host deep-links straight to the contract the customer just tapped
/// — from the loan card's เติมวงเงิน button and from the วงเงินอเนกประสงค์
/// (M35) tile.
///
/// The failure mode this pins is quiet: a mismatch does not error, it lands on
/// the first card. The customer sees a screen that loads perfectly and quotes
/// somebody else's contract.
LoanContract _contract(String contractNo) =>
    LoanContract.fromJson({'contract_no': contractNo});

void main() {
  group('TopupCardPage.preselectedIndex', () {
    final contracts = [
      _contract('MLOAN-0001'),
      _contract('MLOAN-0002'),
      _contract('MLOAN-0003'),
    ];

    test('no ?contNo= lands on the first card', () {
      expect(TopupCardPage.preselectedIndex(contracts, ''), 0);
    });

    test('finds the named contract', () {
      expect(TopupCardPage.preselectedIndex(contracts, 'MLOAN-0002'), 1);
      expect(TopupCardPage.preselectedIndex(contracts, 'MLOAN-0003'), 2);
    });

    // ⚠ The srisawad host reads its own `contract_no` raw — `LoanDetail`
    // assigns `json['contract_no']` with no coercion — while this build's
    // `LoanContract` runs it through `asString`, which trims. So a number
    // padded on the wire arrives here already asymmetric, and an exact
    // comparison would miss it.
    test('matches across padding on either side', () {
      expect(TopupCardPage.preselectedIndex(contracts, '  MLOAN-0002  '), 1);
      expect(
        TopupCardPage.preselectedIndex(
          [_contract('MLOAN-0001'), _contract('  MLOAN-0002  ')],
          'MLOAN-0002',
        ),
        1,
      );
    });

    test('whitespace-only ?contNo= is treated as absent, not as unknown', () {
      expect(TopupCardPage.preselectedIndex(contracts, '   '), 0);
    });

    // Covers both "stale deep link" and "real contract, filtered out of the
    // list by isSelectable". Neither is an error — the customer can still
    // pick, which beats a dead end.
    test('an unknown contract falls back to the first card', () {
      expect(TopupCardPage.preselectedIndex(contracts, 'NOT-A-CONTRACT'), 0);
    });

    test('an empty list cannot throw', () {
      expect(TopupCardPage.preselectedIndex(const [], 'MLOAN-0002'), 0);
    });

    // Contract numbers carry Thai characters in the real data
    // (`ฮฮM680702003NF61X` is the contract the Extra path was proved against).
    test('matches a contract number containing Thai characters', () {
      final thai = [_contract('MLOAN-0001'), _contract('ฮฮM680702003NF61X')];
      expect(TopupCardPage.preselectedIndex(thai, 'ฮฮM680702003NF61X'), 1);
    });
  });
}
