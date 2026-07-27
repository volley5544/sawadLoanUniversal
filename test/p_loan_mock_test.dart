import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/config/app_environment.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_documents.dart';
import 'package:sawad_loan_universal/p_loan/application/models/p_loan_flow.dart';
import 'package:sawad_loan_universal/p_loan/application/models/p_loan_mock.dart';
import 'package:sawad_loan_universal/services/p_loan_api.dart';

/// The flow runs against the live API; fixtures remain as a demo switch and as
/// the shared test data. These tests pin the two things that would be damaging
/// to get wrong: that the mock switch is **off**, so a real deployment can
/// never quietly serve fixtures, and that when it is deliberately turned on the
/// fixtures are completable and clearly identifiable as mock.
void main() {
  group('mock mode wiring', () {
    test('is OFF by default, so a deployment never serves fixtures', () {
      // The guard rail on this whole feature: if someone flips the default and
      // ships it, real customers would see invented contracts and a submit
      // that files nothing. Turn it on per-build with --dart-define instead.
      expect(kPLoanUseMockData, isFalse);
      expect(PLoanApi.isMocked, isFalse);
    });

    test('the mock banner is hidden when live', () {
      // PLoanMockBanner renders nothing unless PLoanApi.isMocked.
      expect(PLoanApi.isMocked, isFalse);
    });

    test('a mock submit would be identifiable by its transaction number', () {
      // Not routed through PLoanApi here: with the flag off that would make a
      // real network call. This pins the marker the mock path hands back.
      expect(mockTransNo(), startsWith('MOCK-'));
    });
  });

  group('mock fixtures are usable', () {
    test('offers both a motorcycle and a car, so step 4 branches are demoable',
        () {
      final contracts = mockContracts();
      final types =
          contracts.map((c) => c.contractDetails.loanTypeCode).toSet();
      expect(types, containsAll(<String>{'M', 'C'}));
      // Both must be selectable or step 1 shows an empty state.
      expect(contracts.every((c) => c.isSelectable), isTrue);
      expect(contracts.every((c) => c.isEligible), isTrue);
      expect(contracts.every((c) => c.hasNoRequestYet), isTrue);
    });

    test('limits are self-consistent with the contract they came from', () {
      for (final contract in mockContracts()) {
        final detail = mockAmountDetail(contract.contractNo);
        expect(detail.isOk, isTrue);
        expect(detail.contractNo, contract.contractNo);
        // The default must sit inside its own bounds, or step 2 opens already
        // showing a validation error and the Next button is dead.
        expect(detail.isAmountAllowed(detail.defaultTopupAmount), isTrue,
            reason: 'default outside bounds for ${contract.contractNo}');
        expect(detail.payoutFor(detail.defaultTopupAmount), greaterThan(0));
      }
    });

    test('installments recompute when the amount changes', () {
      final small = mockInstallmentPlan(10000);
      final large = mockInstallmentPlan(30000);
      expect(small.installments, isNotEmpty);
      expect(
        large.installments.first.regularPeriodAmt,
        greaterThan(small.installments.first.regularPeriodAmt),
        reason: 'a larger loan must mean a larger monthly payment',
      );
    });

    test('the ID card read matches the mock customer, so step 6 can pass', () {
      final flow = PLoanFlow(hashThaiId: 'x', customer: mockCustomer())
        ..verifiedThaiId = mockThaiIdOnCard;
      expect(flow.isThaiIdVerified, isTrue);
    });

    test('documents are complete and decode as real PDFs', () {
      final docs = mockDocuments();
      expect(docs.isComplete, isTrue);
      for (final kind in LoanDocumentKind.values) {
        final bytes = base64Decode(kind.base64From(docs));
        expect(utf8.decode(bytes.take(8).toList()), startsWith('%PDF-'),
            reason: '${kind.name} is not a PDF');
      }
    });

    test('document text says MOCK, so an opened file is self-identifying', () {
      final pdf = utf8.decode(base64Decode(mockDocuments().agreement));
      expect(pdf, contains('MOCK'));
    });
  });
}
