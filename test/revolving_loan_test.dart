import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_contract.dart';

/// `revolving_loans` on a `/loan/list` row (บัตรศรีสวัสดิ์, added 2026-11-11).
void main() {
  test('the zero-filled sample parses as no revolving line', () {
    // Verbatim from the 2026-11-11 uat sample (1YC680101001NE56X).
    final r = LoanContract.fromJson({
      'contract_no': '1YC680101001NE56X',
      'revolving_loans': {
        'contract_id': 0,
        'revolving_flag': false,
        'revolving_limit': 0.00,
        'utilization_amount': 0.00,
        'revolving_status': '',
        'reserved_limit': 0.00,
        'utilization_percentage': 0.00,
        'maximum_withdrawal_amount': 0.00,
        'minimum_withdrawal_amount': 0.00,
        'remaining_request_limit': 0,
        'remaining_daily_available_limit': 0.00,
        'acceptance_flag': '',
        'bank_accounts': null,
      },
    }).revolvingLoan;
    expect(r.revolvingFlag, isFalse);
    expect(r.revolvingLimit, 0);
    expect(r.bankAccounts, isEmpty);
  });

  test('a populated line keeps decimals and tolerates string numbers', () {
    final r = RevolvingLoan.fromJson({
      'contract_id': '123',
      'revolving_flag': true,
      'revolving_limit': 50000.5,
      'utilization_amount': '12345.67',
      'revolving_status': ' A ',
      'reserved_limit': 1000,
      'utilization_percentage': 24.69,
      'maximum_withdrawal_amount': 30000,
      'minimum_withdrawal_amount': 500,
      'remaining_request_limit': 3,
      'remaining_daily_available_limit': 20000.25,
      'acceptance_flag': 'Y',
      'bank_accounts': [
        {'bank_code': 'KTB'},
        'not-an-object',
      ],
    });
    expect(r.contractId, 123);
    expect(r.revolvingFlag, isTrue);
    expect(r.revolvingLimit, 50000.5);
    expect(r.utilizationAmount, 12345.67);
    expect(r.revolvingStatus, 'A');
    expect(r.reservedLimit, 1000);
    expect(r.utilizationPercentage, 24.69);
    expect(r.maximumWithdrawalAmount, 30000);
    expect(r.minimumWithdrawalAmount, 500);
    expect(r.remainingRequestLimit, 3);
    expect(r.remainingDailyAvailableLimit, 20000.25);
    expect(r.acceptanceFlag, 'Y');
    expect(r.bankAccounts, [
      {'bank_code': 'KTB'},
    ]);
  });

  test('an absent block defaults to no revolving line', () {
    final r = LoanContract.fromJson({'contract_no': 'X'}).revolvingLoan;
    expect(r.revolvingFlag, isFalse);
    expect(r.contractId, 0);
    expect(r.bankAccounts, isEmpty);
  });
}
