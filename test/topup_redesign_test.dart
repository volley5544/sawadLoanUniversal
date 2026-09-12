import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_contract.dart';
import 'package:sawad_loan_universal/topup/components/topup_redesign.dart';

void main() {
  group('formatTopupMoney — always two decimals', () {
    test('groups thousands', () {
      expect(formatTopupMoney(91000), '91,000.00');
      expect(formatTopupMoney(176400), '176,400.00');
    });

    test('keeps the satang the wire sends', () {
      expect(formatTopupMoney(82574.87), '82,574.87');
      expect(formatTopupMoney(8374.13), '8,374.13');
      expect(formatTopupMoney(2.49), '2.49');
    });

    test('signs a negative once, outside the grouping', () {
      expect(formatTopupMoney(-82574.87), '-82,574.87');
    });

    test('small and zero values still carry both decimals', () {
      expect(formatTopupMoney(0), '0.00');
      expect(formatTopupMoney(51), '51.00');
      expect(formatTopupMoney(999), '999.00');
      expect(formatTopupMoney(1000), '1,000.00');
    });

    // The card shows offered − principal − duty and then the same figure in
    // the strip; rows that round independently stop adding up.
    test('the design\'s own arithmetic renders consistently', () {
      const offered = 91000.0;
      const principal = 82574.87;
      const duty = 51.0;
      expect(formatTopupMoney(offered - principal - duty), '8,374.13');
    });

    test('the M35 case adds the special limit before deducting', () {
      const offered = 91000.0 + 5000;
      expect(formatTopupMoney(offered - 82574.87 - 53), '13,372.13');
    });
  });

  group('TopupContractHeader.iconFor', () {
    test('maps the loan types the design draws', () {
      expect(TopupContractHeader.iconFor('M'),
          isNot(TopupContractHeader.iconFor('C')));
      expect(TopupContractHeader.iconFor('L'),
          TopupContractHeader.iconFor('H'));
    });

    test('an unknown code gets the neutral mark, not a guess', () {
      expect(TopupContractHeader.iconFor('ZZ'),
          isNot(TopupContractHeader.iconFor('C')));
      expect(TopupContractHeader.iconFor(''),
          TopupContractHeader.iconFor('ZZ'));
    });

    test('matching is case-insensitive', () {
      expect(TopupContractHeader.iconFor('m'),
          TopupContractHeader.iconFor('M'));
    });
  });

  // TopupConditionsCard is a near-copy of TopupConditionsPanel — the _old card
  // page still renders the original, so the redesign restyles rather than
  // mutates. Duplicated wording can drift, so it is pinned here; when the _old
  // pages are deleted the original goes with them and this becomes the only
  // copy.
  group('TopupConditionsCard wording', () {
    test('both bullets are the manual\'s, verbatim', () {
      expect(TopupConditionsCard.bullets, [
        'จ่ายตรง -> เครดิตดี -> ได้วงเงินเพิ่ม',
        'จ่ายช้า -> ขอปรับสัญญาที่สาขา -> รักษาเครดิต -> ปรับวงเงินเพิ่ม',
      ]);
    });

    test('all three notes survive, with their asterisk levels', () {
      expect(TopupConditionsCard.notes, hasLength(3));
      expect(TopupConditionsCard.notes[0], startsWith('* '));
      expect(TopupConditionsCard.notes[1], startsWith('** '));
      expect(TopupConditionsCard.notes[2], startsWith('*** '));
    });

    test('the business hours are stated, since the API enforces them', () {
      expect(TopupConditionsCard.notes.first, contains('07.00 - 20.30'));
    });
  });

  group('TopupDetail.canTopupCode — the Code : xxx line', () {
    TopupDetail parse(Map<String, dynamic> json) => TopupDetail.fromJson(json);

    test('reads can_topup_code when present', () {
      expect(parse({'can_topup_code': 'E204'}).canTopupCode, 'E204');
    });

    test('falls back to a bare code', () {
      expect(parse({'code': 'E204'}).canTopupCode, 'E204');
    });

    test('is empty when the API sends neither — the line is then hidden', () {
      expect(parse({'can_topup': 'N'}).canTopupCode, isEmpty);
    });
  });
}
