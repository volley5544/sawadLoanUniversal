import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_contract.dart';
import 'package:sawad_loan_universal/p_loan/application/models/p_loan_mock.dart';
import 'package:sawad_loan_universal/topup/models/topup_card_variant.dart';

/// Which contracts the top-up card offers a **เติมวงเงิน** button for.
///
/// Two conditions, both required (instructed 2026-09-17): the loan type is
/// `M` or `C`, **and** `can_topup == 'Y'`. Anything else gets the refusal
/// card — including a contract the API says is eligible whose loan type this
/// flow cannot service.
LoanContract _contract({String loanTypeCode = 'M', String canTopup = 'Y'}) {
  final base = mockContracts()
      .firstWhere((c) => c.contractNo == 'MOCK-C-6701002')
      .rawJson;
  return LoanContract.fromJson({
    ...base,
    'contract_details': {
      ...(base['contract_details'] as Map<String, dynamic>),
      'loan_type_code': loanTypeCode,
    },
    'topup_detail': {
      ...(base['topup_detail'] as Map<String, dynamic>),
      'can_topup': canTopup,
    },
  });
}

void main() {
  group('canTopupInApp — loan type AND can_topup', () {
    test('M and C with can_topup Y are the only offers', () {
      expect(canTopupInApp(_contract(loanTypeCode: 'M')), isTrue);
      expect(canTopupInApp(_contract(loanTypeCode: 'C')), isTrue);
    });

    // The point of the change: `can_topup == 'Y'` alone is no longer enough.
    test('an eligible contract of the wrong loan type is refused', () {
      for (final code in ['L', 'H', 'O', 'X', '']) {
        expect(
          canTopupInApp(_contract(loanTypeCode: code)),
          isFalse,
          reason: 'loan_type_code $code must not offer a top-up',
        );
      }
    });

    test('the right loan type does not rescue a refused can_topup', () {
      for (final flag in ['N', 'A', '']) {
        expect(
          canTopupInApp(_contract(canTopup: flag)),
          isFalse,
          reason: 'can_topup $flag must not offer a top-up',
        );
      }
    });

    // Blank is silence, not permission — the same direction `canTopupFlag`
    // takes for a missing `can_topup`, and the safe one for an action.
    test('a blank loan type refuses rather than defaulting open', () {
      expect(canTopupInApp(_contract(loanTypeCode: '')), isFalse);
    });

    test('a padded loan type still matches', () {
      expect(canTopupInApp(_contract(loanTypeCode: ' M ')), isTrue);
    });

    // ⚠ Exact-case, matching TopupFlow.requiredPhotos, which switches on the
    // same two codes. If the API ever sends lowercase, both this gate and the
    // photo list have to change together — a card that opened on 'm' while
    // requiredPhotos fell through to tax-disc-only would be worse than a
    // visible refusal.
    test('matching is case-sensitive, like requiredPhotos', () {
      expect(canTopupInApp(_contract(loanTypeCode: 'm')), isFalse);
    });

    test('the supported set is exactly M and C', () {
      expect(kTopupSelfServiceLoanTypes, {'M', 'C'});
    });
  });

  group('canTopupInApp is not LoanContract.isEligible', () {
    // isEligible is shared with the P-Loan Extra flow, which is a different
    // product that only *references* the contract. Widening it would refuse
    // P-Loan Extra applications on land/house contracts too.
    test('isEligible still tests can_topup alone', () {
      final landButEligible = _contract(loanTypeCode: 'L');
      expect(landButEligible.isEligible, isTrue);
      expect(canTopupInApp(landButEligible), isFalse);
    });
  });

  group('topupRefusalReason', () {
    test('quotes can_topup_msg when can_topup is what refused', () {
      final base = mockContracts()
          .firstWhere((c) => c.contractNo == 'MOCK-C-6701002')
          .rawJson;
      final refused = LoanContract.fromJson({
        ...base,
        'topup_detail': {
          ...(base['topup_detail'] as Map<String, dynamic>),
          'can_topup': 'N',
          'can_topup_msg': 'ยอดค้างชำระเกินกำหนด',
        },
      });
      expect(topupRefusalReason(refused), 'ยอดค้างชำระเกินกำหนด');
    });

    // ⚠ On a loan-type refusal the contract is `can_topup == 'Y'`, so any
    // `can_topup_msg` it carries describes something else — the same reason
    // the amount screen withholds that message above a working button.
    test('a loan-type refusal does not borrow an unrelated can_topup_msg', () {
      final base = mockContracts()
          .firstWhere((c) => c.contractNo == 'MOCK-C-6701002')
          .rawJson;
      final wrongType = LoanContract.fromJson({
        ...base,
        'contract_details': {
          ...(base['contract_details'] as Map<String, dynamic>),
          'loan_type_code': 'L',
        },
        'topup_detail': {
          ...(base['topup_detail'] as Map<String, dynamic>),
          'can_topup': 'Y',
          'can_topup_msg': 'ข้อความที่ไม่เกี่ยวกับการปฏิเสธ',
        },
      });
      expect(canTopupInApp(wrongType), isFalse);
      expect(topupRefusalReason(wrongType), TopupDetail.contactBranchFallback);
    });

    test('a can_topup refusal with no message falls back to the branch line',
        () {
      expect(
        topupRefusalReason(_contract(canTopup: 'N')),
        TopupDetail.contactBranchFallback,
      );
    });
  });
}
