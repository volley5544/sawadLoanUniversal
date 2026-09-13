import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/config/app_environment.dart';
import 'package:sawad_loan_universal/topup/models/topup_settlement.dart';

/// The supplied sample body (`etc/new_topup_api.txt`), trimmed to the fields
/// this model reads.
Map<String, dynamic> _sample() => {
      'code': '200',
      'message': 'success',
      'default_topup_amount': 88500,
      'min_topup_amount': 86500,
      'max_topup_amount': 91000,
      'closing_balance': 86217.08,
      'fee_amount': 45,
      'topup_extra': 0,
      'overdue_day': 0,
      'overdue_principal_amount': 0.00,
      'topup_discount_amount': 0.00,
      'payoff_before_settlement_amount': 2282.92,
      'default_transfer_amount': 2282.92,
      'settlement_items': [
        {
          'seq': 2,
          'field_name': 'collection_fee',
          'description': 'ค่าติดตามทวงถาม',
          'amount': 50.00,
        },
        {
          'seq': 1,
          'field_name': 'yield',
          'description': 'ดอกเบี้ย',
          'amount': 2589.72,
        },
        {
          'seq': 3,
          'field_name': 'penalty_fee',
          'description': 'ค่าเบี้ยปรับ',
          'amount': 2.49,
        },
      ],
      'settlement_total_amount': 2642.21,
      'campaign_code': '',
    };

/// A **real** `results` payload, MLOAN / `1สM681102002NF63C`, captured
/// 2026-09-13. Kept verbatim apart from the sub-objects this model does not
/// read: one settlement row rather than the sample's three, which is the case
/// that matters — the section must appear for a single row.
Map<String, dynamic> _mloanResponse() => {
      'code': '200',
      'message': 'success',
      'db_name': 'MLOAN',
      'contract_no': '1สM681102002NF63C',
      'default_topup_amount': 38900,
      'min_topup_amount': 16400,
      'max_topup_amount': 38900,
      'max_transfer_amount': 0,
      'closing_balance': 16124,
      'fee_amount': 20,
      'topup_extra': 0,
      'overdue_day': 0,
      'overdue_principal_amount': 0.00,
      'topup_discount_amount': 0.00,
      'payoff_before_settlement_amount': 22776.00,
      'default_transfer_amount': 22776.00,
      'settlement_items': [
        {
          'seq': 1,
          'field_name': 'yield',
          'description': 'ดอกเบี้ย',
          'amount': 11.00,
        },
      ],
      'settlement_total_amount': 11.00,
      'campaign_code': '',
    };

void main() {
  group('TopupRecalculation.fromJson', () {
    test('reads the sample body', () {
      final r = TopupRecalculation.fromJson(_sample());
      expect(r.isOk, isTrue);
      expect(r.settlementTotalAmount, 2642.21);
      expect(r.payoffBeforeSettlementAmount, 2282.92);
      expect(r.closingBalance, 86217.08);
      expect(r.minTopupAmount, 86500);
      expect(r.maxTopupAmount, 91000);
    });

    test('rows come back in seq order however they arrive', () {
      final r = TopupRecalculation.fromJson(_sample());
      expect(r.settlementItems.map((i) => i.seq), [1, 2, 3]);
      expect(r.settlementItems.map((i) => i.fieldName),
          ['yield', 'collection_fee', 'penalty_fee']);
    });

    test('the Thai label is the server\'s, shown verbatim', () {
      final r = TopupRecalculation.fromJson(_sample());
      expect(r.settlementItems.first.description, 'ดอกเบี้ย');
    });

    test('the row count is variable — three here, not the design\'s six', () {
      expect(TopupRecalculation.fromJson(_sample()).settlementItems, hasLength(3));
    });
  });

  group('hasSettlement — what shows the ยอดที่ต้องชำระ section', () {
    test('rows present → shown', () {
      expect(TopupRecalculation.fromJson(_sample()).hasSettlement, isTrue);
    });

    test('no settlement_items → hidden', () {
      final json = _sample()..['settlement_items'] = <dynamic>[];
      expect(TopupRecalculation.fromJson(json).hasSettlement, isFalse);
    });

    test('the field absent entirely → hidden', () {
      final json = _sample()..remove('settlement_items');
      expect(TopupRecalculation.fromJson(json).hasSettlement, isFalse);
    });

    test('a total with no rows is still hidden — the rows decide, not the '
        'total', () {
      final json = _sample()
        ..['settlement_items'] = <dynamic>[]
        ..['settlement_total_amount'] = 2642.21;
      expect(TopupRecalculation.fromJson(json).hasSettlement, isFalse);
    });

    test('a single row is enough — the real MLOAN response, 2026-09-13', () {
      // Captured by hand against the test host while chasing "the section
      // never appears on uat". It does not: that build makes no call at all
      // (see the group below). This pins that the moment one is made, this
      // exact body renders — one row, not the sample's three, and a total of
      // 11.00 where the design's mock-ups all show four figures.
      final r = TopupRecalculation.fromJson(_mloanResponse());
      expect(r.isOk, isTrue);
      expect(r.hasSettlement, isTrue);
      expect(r.settlementItems, hasLength(1));
      expect(r.settlementItems.single.description, 'ดอกเบี้ย');
      expect(r.settlementTotalAmount, 11.00);
      expect(r.itemsSumMatchesTotal, isTrue);
    });
  });

  group('itemsSumMatchesTotal', () {
    test('the sample adds up', () {
      expect(TopupRecalculation.fromJson(_sample()).itemsSumMatchesTotal,
          isTrue);
    });

    test('notices a mismatch without correcting the total', () {
      final json = _sample()..['settlement_total_amount'] = 9999.0;
      final r = TopupRecalculation.fromJson(json);
      expect(r.itemsSumMatchesTotal, isFalse);
      // The server's figure is what the customer owes — never re-derived.
      expect(r.settlementTotalAmount, 9999.0);
    });

    test('an empty list cannot mismatch', () {
      final json = _sample()..['settlement_items'] = <dynamic>[];
      expect(TopupRecalculation.fromJson(json).itemsSumMatchesTotal, isTrue);
    });
  });

  test('a non-200 body is not OK', () {
    final json = _sample()
      ..['code'] = '503'
      ..['message'] = 'ท่านสามารถขอสินเชื่อได้ในเวลา 07:00 ถึง 20:30 เท่านั้น';
    expect(TopupRecalculation.fromJson(json).isOk, isFalse);
  });

  test('the mock fixture parses through the real constructor', () {
    final r = mockRecalculation(88500);
    expect(r.isOk, isTrue);
    expect(r.hasSettlement, isTrue);
    expect(r.defaultTopupAmount, 88500);
  });

  // The supplied curl carries a shared `Basic` service account. Baking one
  // into a web bundle is the finding deleting `kPLoanSaveApiAuth` closed —
  // anyone who opens the app can read it. Same rule as the lead fallback.
  test('no recalculation credential ships in the bundle', () {
    expect(kTopupRecalApiAuth, isEmpty);
    expect(kTopupRecalConfigured, isFalse);
  });
}
