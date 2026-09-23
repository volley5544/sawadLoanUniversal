import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/loan_payment/models/loan_payment_option.dart';
import 'package:sawad_loan_universal/loan_payment/models/loan_payment_seed.dart';
import 'package:sawad_loan_universal/models/app_config.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_contract.dart';

/// A `/loan/list` row shaped like the ones the payment screen reads.
LoanContract _contract({
  num currentDueAmount = 4585,
  num overdueAmount = 0,
  num collectionFee = 0,
  num penaltyFee = 0,
  num installmentAmount = 4585,
  num osBalance = 86217.08,
  int currentInstallment = 7,
  String overdueFrom = '0',
  String overdueTo = '0',
  String overdueDate = '',
  String currentDueDate = '2026-10-05',
}) =>
    LoanContract.fromJson({
      'contract_no': '000จYC69020100002NFX',
      'db_name': 'MLOAN',
      'contract_details': {
        'os_balance': osBalance,
        'loan_type_code': 'M',
        'loan_type_name': 'สินเชื่อมอเตอร์ไซค์',
      },
      'payment_details': {
        'current_due_amount': currentDueAmount,
        'overdue_amount': overdueAmount,
        'collection_fee': collectionFee,
        'penalty_fee': penaltyFee,
        'installment_amount': installmentAmount,
        'current_installment_number': currentInstallment,
        'overdue_from': overdueFrom,
        'overdue_to': overdueTo,
        'overdue_date': overdueDate,
        'current_due_date': currentDueDate,
      },
    });

void main() {
  group('the three options compute three different amounts', () {
    final summary = LoanPaymentSummary(_contract(
      currentDueAmount: 4585,
      overdueAmount: 9170,
      collectionFee: 50,
    ));

    // ⚠ **Changed 2026-09-17 with the redesign, and it is a billing change.**
    // `current_due_amount` "includes all the customer need to pay", so adding
    // the collection fee on top double-counted it. It is also the field the
    // loan detail screen shows as `รวมต้องชำระ` one tap away, and the two must
    // not disagree. `loan_payment_page_old.dart` keeps the old formula through
    // its own copy of this class.
    test('ชำระเต็มจำนวน is current_due_amount alone', () {
      expect(summary.fullAmount, 4585);
      expect(summary.amountFor(LoanPaymentOption.full, ''), 4585);
    });

    test('ยอดค้างชำระ is the arrears plus both fees', () {
      expect(summary.overdueTotal, 9220);
      expect(summary.amountFor(LoanPaymentOption.overdue, ''), 9220);

      final withPenalty = LoanPaymentSummary(_contract(
          overdueAmount: 9170, collectionFee: 50, penaltyFee: 10.25));
      expect(withPenalty.overdueTotal, 9230.25);
    });

    // The redesign's own figures only reconcile this way: the arrears block
    // sums to the ยอดค้างชำระ headline, and that plus the instalment is the
    // ชำระเต็มจำนวน headline.
    test("the design's figures reconcile", () {
      final s = LoanPaymentSummary(_contract(
        currentDueAmount: 2500.25,
        overdueAmount: 1000,
        collectionFee: 50,
        penaltyFee: 10.25,
        installmentAmount: 1440,
      ));
      expect(s.overdueTotal, 1060.25);
      expect(s.fullAmount, 2500.25);
      expect(s.overdueTotal + s.installmentAmount, s.fullAmount);
    });

    test('กำหนดยอดชำระเอง is whatever was typed, separators stripped', () {
      expect(summary.amountFor(LoanPaymentOption.custom, '1,234.50'), 1234.5);
      expect(summary.amountFor(LoanPaymentOption.custom, '2000'), 2000);
      // The source's removeCommaFromNumText falls back to zero rather than
      // throwing, so a field holding only punctuation is zero, not an error.
      expect(summary.amountFor(LoanPaymentOption.custom, ',,,'), 0);
      expect(summary.amountFor(LoanPaymentOption.custom, ''), 0);
    });

    // ⚠ The fees ride on the **arrears** option only now. They used to ride on
    // both — see the note on fullAmount; current_due_amount already contains
    // them, so ชำระเต็มจำนวน must not add them a second time.
    test('the fees ride on the arrears option, not on ชำระเต็มจำนวน', () {
      final noArrears = LoanPaymentSummary(_contract(
          currentDueAmount: 4585, collectionFee: 50, penaltyFee: 10));
      expect(noArrears.fullAmount, 4585);
      expect(noArrears.overdueTotal, 60);
    });

    // penalty_fee is unconfirmed on payment_details, so a response without it
    // must leave every figure and row exactly as it was.
    test('a contract with no penalty_fee bills as before', () {
      final s = LoanPaymentSummary(
          _contract(overdueAmount: 9170, collectionFee: 50));
      expect(s.penaltyFee, 0);
      expect(s.showsPenaltyFee, isFalse);
      expect(s.overdueTotal, 9220);
    });

    // The รวม row's rule widened with the new penalty row: a contract with a
    // penalty and no collection fee still has more than one row to total.
    test('รวม shows for either fee, and for neither it does not', () {
      expect(
          LoanPaymentSummary(_contract(overdueAmount: 9170)).showsArrearsTotal,
          isFalse);
      expect(
          LoanPaymentSummary(_contract(overdueAmount: 9170, collectionFee: 50))
              .showsArrearsTotal,
          isTrue);
      expect(
          LoanPaymentSummary(_contract(overdueAmount: 9170, penaltyFee: 10))
              .showsArrearsTotal,
          isTrue);
    });
  });

  group('which rows an option shows', () {
    test('the arrears block is withheld when there are none', () {
      final none = LoanPaymentSummary(_contract());
      expect(none.showsOverdueBlock, isFalse);
      expect(none.showsNoOverdueNotice, isTrue);

      final some = LoanPaymentSummary(_contract(overdueAmount: 9170));
      expect(some.showsOverdueBlock, isTrue);
      expect(some.showsNoOverdueNotice, isFalse);
    });

    test('คุณไม่มียอดค้างชำระ is the exact complement of the arrears block',
        () {
      for (final amount in [0, 1, -50, 9170]) {
        final summary = LoanPaymentSummary(_contract(overdueAmount: amount));
        expect(summary.showsOverdueBlock, isNot(summary.showsNoOverdueNotice),
            reason: 'overdue_amount $amount');
      }
    });

    test('ค่าติดตามทวงถาม is withheld when no fee was charged', () {
      expect(LoanPaymentSummary(_contract()).showsCollectionFee, isFalse);
      expect(
        LoanPaymentSummary(_contract(collectionFee: 50)).showsCollectionFee,
        isTrue,
      );
    });

    test('the two due dates come from two different fields', () {
      // overdue_date dates the arrears; current_due_date dates the instalment
      // coming up. Rendering one for the other would misdate a bill.
      final summary = LoanPaymentSummary(_contract(
        overdueDate: '2026-08-05',
        currentDueDate: '2026-10-05',
      ));
      expect(summary.overdueDueDate, '05/08/2569');
      expect(summary.currentDueDate, '05/10/2569');
    });

    // ⚠ **No borrowed date since 2026-09-19.** An empty or unreadable
    // overdue_date reads ชำระทันที since 2026-09-23.
    test('an empty or unreadable overdue_date reads ชำระทันที', () {
      expect(
        LoanPaymentSummary(_contract(overdueDate: '', currentDueDate: '2026-09-11'))
            .overdueDueDate,
        'ชำระทันที',
      );
      expect(
        LoanPaymentSummary(_contract(overdueDate: '  ')).overdueDueDate,
        'ชำระทันที',
      );
      expect(
        LoanPaymentSummary(_contract(
                overdueDate: 'nonsense', currentDueDate: '2026-09-11'))
            .overdueDueDate,
        'ชำระทันที',
      );
      // The instalment block's own date is unaffected.
      expect(
        LoanPaymentSummary(_contract(overdueDate: '', currentDueDate: '2026-09-11'))
            .currentDueDate,
        '11/09/2569',
      );
    });

    test('รวม is shown for ชำระเต็มจำนวน but gated for ยอดค้างชำระ', () {
      // ⚠ The source guards this option's total behind a fee being present
      // and the other option's not at all, so with no fee the two arrears
      // blocks legitimately differ by a row. Pinned because it reads as a bug.
      // The gate itself is `showsArrearsTotal`, tested above.
      final noFee = LoanPaymentSummary(
          _contract(overdueAmount: 9170, collectionFee: 0));
      expect(noFee.showsCollectionFee, isFalse);

      final withFee = LoanPaymentSummary(
          _contract(overdueAmount: 9170, collectionFee: 50));
      expect(withFee.showsCollectionFee, isTrue);
      // And the total it would show is the sum, not the arrears alone.
      expect(withFee.overdueTotal, 9220);
    });

    test('ค่างวดปัจจุบัน reads installment_amount, not current_due_amount', () {
      // They differ on a contract in arrears: one is the schedule, the other
      // is what is owed now.
      final summary = LoanPaymentSummary(
          _contract(installmentAmount: 4585, currentDueAmount: 13755));
      expect(summary.installmentAmount, 4585);
      expect(summary.currentDueAmount, 13755);
      expect(summary.currentInstallmentLabel, 'งวดที่ 7');
    });
  });

  group('when the ชำระเงิน button refuses', () {
    final summary = LoanPaymentSummary(
        _contract(currentDueAmount: 4585, overdueAmount: 0, collectionFee: 0));

    test('a fixed option with nothing to pay is disabled', () {
      expect(summary.isDisabled(LoanPaymentOption.overdue, ''), isTrue,
          reason: 'no arrears and no fee — there is no bill to raise');
      expect(summary.isDisabled(LoanPaymentOption.full, ''), isFalse);
      final paidUp = LoanPaymentSummary(_contract(currentDueAmount: 0));
      expect(paidUp.isDisabled(LoanPaymentOption.full, ''), isTrue);
    });

    test('an empty typed field leaves the button enabled, then prompts', () {
      // The source's behaviour, and the better one: a prompt naming what is
      // missing beats a dead button that explains nothing.
      expect(summary.isDisabled(LoanPaymentOption.custom, ''), isFalse);
      expect(
        summary.rejectionFor(LoanPaymentOption.custom, ''),
        'กรอกจำนวนเงินที่ต้องการจ่ายค่างวด',
      );
    });

    test('a typed zero disables it outright', () {
      expect(summary.isDisabled(LoanPaymentOption.custom, '0'), isTrue);
      expect(summary.isDisabled(LoanPaymentOption.custom, '0.00'), isTrue);
    });

    test('below one baht is refused, exactly one baht is not', () {
      expect(
        summary.rejectionFor(LoanPaymentOption.custom, '0.50'),
        'จำนวนที่จ่ายต้องมากกว่า 1 บาท',
      );
      // ⚠ The message says "more than 1" but the rule is `>= 1`. Both are the
      // source's, and the boundary is what a customer would hit.
      expect(summary.rejectionFor(LoanPaymentOption.custom, '1'), isNull);
      expect(summary.rejectionFor(LoanPaymentOption.custom, '1000'), isNull);
    });

    test('the two fixed options are never rejected once enabled', () {
      expect(summary.rejectionFor(LoanPaymentOption.full, ''), isNull);
      expect(summary.rejectionFor(LoanPaymentOption.overdue, ''), isNull);
    });
  });

  group('the typed field on blur', () {
    final summary = LoanPaymentSummary(_contract(osBalance: 40000));

    test('formats what was typed', () {
      expect(summary.blurredFieldText('1234.5'), '1,234.50');
      expect(summary.blurredFieldText('1,234.5'), '1,234.50');
    });

    test('clamps silently to the outstanding balance', () {
      // ⚠ No message — the source corrects in place, and the screen carries a
      // standing note saying the balance is the ceiling. Pinned because the
      // silence is the surprising half.
      expect(summary.blurredFieldText('999999'), '40,000.00');
      expect(summary.blurredFieldText('40000'), '40,000.00');
      expect(summary.blurredFieldText('39999.99'), '39,999.99');
    });

    test('the balance still caps the field even though it is not shown', () {
      // The ยอดหนี้คงเหลือ row was removed from the screen on 2026-09-14, but
      // os_balance is still the ceiling. Pinned so nobody deletes the getter
      // on the grounds that nothing renders it.
      expect(summary.osBalance, 40000);
      expect(summary.blurredFieldText('50000'), '40,000.00');
    });

    test('an empty field becomes 0.0, not 0.00', () {
      // The source writes the shorter literal here; the comma formatter never
      // runs on this branch.
      expect(summary.blurredFieldText(''), '0.0');
    });
  });

  group('is_show_payButton gates the button, not the route', () {
    test('an unseeded config withholds it', () {
      expect(const AppConfig().isShowPayButton, isFalse);
      expect(AppConfig.fromDecoded(const {}).isShowPayButton, isFalse);
    });

    test('the document spells it with a capital B', () {
      expect(
        AppConfig.fromDecoded(const {'is_show_payButton': true})
            .isShowPayButton,
        isTrue,
      );
      // A snake_case spelling is accepted too, so a tidied config still works.
      expect(
        AppConfig.fromDecoded(const {'is_show_pay_button': true})
            .isShowPayButton,
        isTrue,
      );
      expect(
        AppConfig.fromDecoded(const {'is_show_payButton': 'true'})
            .isShowPayButton,
        isFalse,
        reason: 'a string is not a boolean — do not grant a payment path on it',
      );
    });
  });

  group('the contract is handed on, not re-fetched', () {
    // Reached from inside this build, both payment screens already have the
    // row: the loan detail screen loaded it to draw the card, and the payment
    // screen hands the same one to the QR screen. Neither should ask
    // /loan/list for something it is holding.
    final seed = LoanPaymentSeed(contract: _contract());

    test('a seed for the named contract is used', () {
      expect(
        seed.matches(contractNo: '000จYC69020100002NFX', dbName: 'MLOAN'),
        isTrue,
      );
    });

    test('db_name is optional, exactly as it is on the fetching path', () {
      // The routes let dbName be omitted, and the fetch matches on the
      // contract number alone when it is. A seed must apply the same rule, or
      // a seeded and an unseeded run could resolve different contracts.
      expect(
        seed.matches(contractNo: '000จYC69020100002NFX', dbName: ''),
        isTrue,
      );
      expect(
        seed.matches(contractNo: '000จYC69020100002NFX', dbName: '   '),
        isTrue,
      );
    });

    test('a seed that disagrees with the URL is ignored', () {
      // ⚠ The query string is the authority: it is what a reload would use,
      // and the two must never resolve differently.
      expect(
        seed.matches(contractNo: 'SOME-OTHER-CONTRACT', dbName: 'MLOAN'),
        isFalse,
      );
      expect(
        seed.matches(contractNo: '000จYC69020100002NFX', dbName: 'LLOAN'),
        isFalse,
        reason: 'contract numbers are unique only within a database',
      );
    });

    test('surrounding whitespace does not defeat the match', () {
      expect(
        seed.matches(
            contractNo: '  000จYC69020100002NFX  ', dbName: ' MLOAN '),
        isTrue,
      );
    });
  });
}
