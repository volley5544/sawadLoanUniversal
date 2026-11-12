import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_contract.dart';
import 'package:sawad_loan_universal/revolving/models/revolving_bill.dart';
import 'package:sawad_loan_universal/revolving/models/revolving_mock.dart';
import 'package:sawad_loan_universal/revolving/models/revolving_withdrawal.dart';

/// The BA's field mapping (Loan details / Withdrawal process / Billing
/// statement, 2026-11-12) onto node-api's revolving data. QA values are
/// placeholders, so these pin *where* a field comes from, not its value.
void main() {
  // QA /loan/list row, contract 2881 (revolving-api-test-result.md).
  LoanContract qaContract() => LoanContract.fromJson({
        'contract_no': '000ICM691005S0004NFX',
        'branch_code': 'B042',
        'contract_date': '2026-03-01',
        'data_date': '2026-11-12 10:08:00',
        'contract_details': {
          'loan_type_code': 'M',
          'loan_type_name': 'รถมอเตอร์ไซค์',
          'collateral_information': 'กพ 5161',
        },
        'payment_details': {'current_date_time': '2026-11-12T10:08:00'},
        'barcode_details': {'comcode': 'S22'},
        'revolving_loans': {
          'contract_id': 2881,
          'revolving_flag': true,
          'revolving_limit': 0,
          'utilization_amount': 60000,
          'revolving_status': 'Hard block',
          'reserved_limit': 0,
          'utilization_percentage': 52.02,
          'maximum_withdrawal_amount': 0,
          'minimum_withdrawal_amount': 0,
          'remaining_request_limit': 0,
          'remaining_daily_available_limit': 0,
          'acceptance_flag': 'Skip',
          'bank_accounts': [
            {
              'bank_name': '',
              'bank_code': 'KBANK',
              'transfer_type': 'CUSTOMER_BANK',
              'account_type': 'OTHERS',
              'account_number': '1142425676',
              'account_name': '20052026',
              'is_default': true,
            },
          ],
        },
      });

  // QA revolvingLoan/withdrawal/2881.
  final qaWithdrawal = RevolvingWithdrawalInfo.fromJson({
    'results': {
      'revolving_loan_summary': {
        'revolving_flag': false,
        'revolving_status': '',
        'revolving_limit': 0,
        'maximum_revolving_limit': 0,
        'reserved_limit': 0,
        'utilization_amount': 0,
        'utilization_percentage': 0,
        'withdrawal_expiry_date': '',
      },
      'withdrawal_transactions': [
        {
          'contract_no': '000ICM691005S0004NFX',
          'withdrawal_amount': 50000,
          'withdrawal_status': 'Success',
          'withdrawal_date': '2026-05-20T16:59:59.999999Z',
        },
        {
          'contract_no': '000ICM691005S0004NFX',
          'withdrawal_amount': 10000,
          'withdrawal_status': 'Success',
          'withdrawal_date': '2026-03-31T16:59:59.999999Z',
        },
      ],
    },
  });

  group('transfer_type → withdrawal transfer_type', () {
    String map(String t) =>
        RevolvingBankAccount(transferType: t).withdrawalTransferType;

    test('the spec\'s three values', () {
      expect(map('PROMPT_PAY_MOBILE_NUMBER'), 'promptpay_phone');
      expect(map('PROMPT_PAY_CITIZEN_ID'), 'promptpay_citizen');
      expect(map('CUSTOMER_BANK'), 'customer_bank');
    });

    test('already-mapped spellings map to themselves', () {
      expect(map('promptpay_phone'), 'promptpay_phone');
      expect(map('promptpay_citizen'), 'promptpay_citizen');
      expect(map('customer_bank'), 'customer_bank');
    });

    test('PromptPay is recognised in the spec spelling', () {
      expect(
          const RevolvingBankAccount(transferType: 'PROMPT_PAY_CITIZEN_ID')
              .isPromptPay,
          isTrue);
      expect(const RevolvingBankAccount(transferType: 'CUSTOMER_BANK')
          .isPromptPay, isFalse);
    });
  });

  group('My loan card', () {
    test('figures from revolving_loans; payment schedule has no source', () {
      final card = RevolvingCardView.fromContract(qaContract());
      expect(card.contractId, 2881);
      expect(card.availableLimit, 0); // revolving_limit
      expect(card.approvedLimit, isNull); // not until withdrawal/{id}
      expect(card.suggestedPayment, isNull);
      expect(card.dueDateLabel, '-');
      expect(card.transferFee, isNull);
      expect(card.withdrawals, isNull);
      expect(card.payments, isNull);
      expect(card.isDemo, isFalse);
      expect(card.dataDateLabel, '12 พ.ย. 69, 10:08 น.');
      expect(card.contractInfoDateLabel, '12/11/2569 เวลา 10.08 น.');
    });

    test('withdrawal summary supplies วงเงินอนุมัติ and the history', () {
      final card =
          RevolvingCardView.fromContract(qaContract()).withWithdrawalInfo(
              qaWithdrawal);
      expect(card.approvedLimit, 0); // maximum_revolving_limit
      expect(card.withdrawalInfoLoaded, isTrue);
      final h = card.withdrawals!;
      expect(h, hasLength(2));
      // 16:59:59Z is 23:59 Thai time the same day.
      expect(h[0].dateLabel, '20 พ.ค. 69');
      expect(h[0].monthLabel, 'พฤษภาคม 69');
      expect(h[0].amount, 50000);
      expect(h[1].dateLabel, '31 มี.ค. 69');
      expect(
          card.contractInfo.firstWhere((r) => r.label == 'วงเงินอนุมัติ').value,
          '0 บาท');
    });

    test('contract-info rows: mapped fields, `-` where no source', () {
      final rows = {
        for (final r in RevolvingCardView.fromContract(qaContract())
            .contractInfo)
          r.label: r.value,
      };
      expect(rows['วงเงินอนุมัติ'], '-');
      expect(rows['ยอดชำระขั้นต่ำ'], '-');
      expect(rows['วันครบกำหนดชำระ'], '-');
      expect(rows['วันที่ทำสัญญา'], '01/03/2569');
      expect(rows['จำนวนครั้งที่ถอนได้/วัน'], '0 ครั้ง'); // remaining_request_limit
      expect(rows['ยอดเงินที่ถอนไป'], '60,000 บาท');
    });
  });

  test('สัญญาเงินกู้ reuses the loan detail document link and rule', () {
    final card = RevolvingCardView.fromContract(qaContract());
    expect(card.contractComcode, 'S22');
    expect(card.loanTypeCode, 'M');
    expect(
        revolvingContractDocumentUrl(
            card: card, contractUrl: 'https://pt.swpfin.com/portal', allowed: true),
        'https://pt.swpfin.com/portal/contract'
        '?contno=000ICM691005S0004NFX&comcode=S22');
    expect(
        revolvingContractDocumentUrl(
            card: card, contractUrl: 'https://pt.swpfin.com/portal', allowed: false),
        isNull);
    expect(revolvingContractDocumentUrl(card: card, contractUrl: '', allowed: true),
        isNull);
    expect(
        revolvingContractDocumentUrl(
            card: RevolvingCardView.mock(),
            contractUrl: 'https://pt.swpfin.com/portal',
            allowed: true),
        isNull);
  });

  group('withdrawal amount validation (spec\'s seven rules)', () {
    final today = DateTime(2026, 11, 12);
    final mock = RevolvingCardView.mock(); // min 500, max 5,000, limit 10,000

    test('an amount inside every bound passes', () {
      expect(mock.withdrawalRefusal(2000, today), isNull);
      expect(mock.canWithdraw(2000, today), isTrue);
      expect(mock.canWithdraw(0, today), isFalse);
    });

    test('amount bounds', () {
      expect(mock.withdrawalRefusal(400, today), contains('ขั้นต่ำ 500'));
      expect(mock.withdrawalRefusal(6000, today), contains('สูงสุด 5,000'));
    });

    test('Hard block refuses before anything else', () {
      final card = RevolvingCardView.fromContract(qaContract());
      expect(card.withdrawalRefusal(0, today), 'วงเงินถูกระงับ ไม่สามารถถอนเงินได้');
      expect(card.canWithdraw(1000, today), isFalse);
    });

    test('expiry: past or unknown refuses', () {
      final active = LoanContract.fromJson({
        'revolving_loans': {
          'contract_id': 1,
          'revolving_flag': true,
          'revolving_status': 'Active',
          'revolving_limit': 10000,
          'maximum_withdrawal_amount': 5000,
          'minimum_withdrawal_amount': 500,
          'remaining_request_limit': 1,
          'remaining_daily_available_limit': 3000,
        },
      });
      final card = RevolvingCardView.fromContract(active);
      expect(card.withdrawalBlock(today), contains('วันสิ้นสุด'));
      RevolvingCardView withExpiry(String d) => card.withWithdrawalInfo(
          RevolvingWithdrawalInfo(
              summary: RevolvingLoanSummary(withdrawalExpiryDate: d)));
      expect(withExpiry('2026-11-11').withdrawalBlock(today), contains('หมด'));
      final ok = withExpiry('2026-11-12');
      expect(ok.withdrawalBlock(today), isNull);
      expect(ok.withdrawalRefusal(4000, today), contains('3,000'));
    });
  });

  test('applyForWithdrawal body follows the spec mapping', () {
    final card = RevolvingCardView.fromContract(qaContract());
    final at = DateTime.utc(2026, 11, 12, 3);
    final bank = RevolvingTransferDraft(
            card: card, account: card.bankAccounts.single, amount: 1500)
        .withdrawalRequest(now: at);
    expect(bank['contract_id'], 2881);
    expect(bank['withdrawal'], {
      'channel': 'Mobile',
      'transaction_date': '2026-11-12T03:00:00.000Z',
      'requesting_branch': 'B042', // /loan/list branch_code
      'transfer_type': 'customer_bank',
      'bank_code': 'KBANK',
      'bank_account_number': '1142425676',
      'bank_account_name': '20052026',
      'withdrawal_amount': 1500.0,
    });
    final pp = RevolvingTransferDraft(
      card: card,
      account: const RevolvingBankAccount(
          bankCode: 'X',
          transferType: 'PROMPT_PAY_CITIZEN_ID',
          accountNumber: '1234567890123'),
      amount: 500,
    ).withdrawalRequest(now: at)['withdrawal'] as Map;
    expect(pp['transfer_type'], 'promptpay_citizen');
    expect(pp['bank_code'], ''); // customer_bank only
  });

  group('createFileRequest (ดูบิล)', () {
    test('request body', () {
      expect(RevolvingBillStatement.requestBody(2881),
          {'type': 'BILLING_STATEMENT', 'contract_id': 2881});
    });

    test('200 → data.url; 400 → message', () {
      final ok = RevolvingBillStatement.fromResponse(200, {
        'data': {'url': 'https://s.swpfin.com/x/files/3336'},
      });
      expect(ok.hasFile, isTrue);
      expect(ok.url, 'https://s.swpfin.com/x/files/3336');
      final early = RevolvingBillStatement.fromResponse(
          400, {'detail': 'ยังไม่ถึงรอบออกใบแจ้งหนี้'});
      expect(early.hasFile, isFalse);
      expect(early.message, 'ยังไม่ถึงรอบออกใบแจ้งหนี้');
    });

    test('v02: popup text is detail, not message; Thai header', () {
      expect(RevolvingBillStatement.requestHeaders, {'Accept-Language': 'th'});
      final r = RevolvingBillStatement.fromResponse(
          400, {'message': 'Bad Request', 'detail': 'ยังไม่ออกใบแจ้งหนี้'});
      expect(r.message, 'ยังไม่ออกใบแจ้งหนี้');
      expect(RevolvingBillStatement.fromResponse(400, {'message': 'x'}).message,
          '-');
    });

    test('a 200 without a url is not a file', () {
      final r = RevolvingBillStatement.fromResponse(200, {'data': {}});
      expect(r.hasFile, isFalse);
      expect(r.message, '-');
    });
  });
}
