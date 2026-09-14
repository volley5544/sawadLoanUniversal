import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/loan_detail/components/loan_detail_components.dart';
import 'package:sawad_loan_universal/loan_detail/models/loan_detail_summary.dart';
import 'package:sawad_loan_universal/loan_detail/models/payment_history_entry.dart';
import 'package:sawad_loan_universal/config/app_environment.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_contract.dart';
import 'package:sawad_loan_universal/p_loan/application/models/p_loan_mock.dart';
import 'package:sawad_loan_universal/services/p_loan_api.dart';
import 'package:sawad_loan_universal/services/loan_detail_api.dart';

/// A `/loan/list` row shaped like the ones this screen reads, overridable per
/// test. Built through the real `fromJson` so a wire-key change breaks these
/// too rather than letting them drift.
LoanContract _contract({
  int currentInstallment = 5,
  num totalInstallment = 24,
  String currentDueDate = '2026-10-05',
  String currentDateTime = '2026-09-14T09:00:00',
  num overdueAmount = 0,
  String overdueFrom = '0',
  String overdueTo = '0',
  num contractInstallmentAmount = 3250,
  num currentDueAmount = 3250,
  String carSeries = 'WAVE 110i',
  String carCc = '110',
  List<Map<String, dynamic>> insurances = const [],
}) =>
    LoanContract.fromJson({
      'contract_no': 'MLOAN-TEST-01',
      'db_name': 'MLOAN',
      'contract_date': '2025-02-01',
      'contract_details': {
        'installment_amount': contractInstallmentAmount,
        'loan_type_name': 'สินเชื่อมอเตอร์ไซค์',
        'loan_type_code': 'M',
      },
      'payment_details': {
        'current_installment_number': currentInstallment,
        'total_installment_number': totalInstallment,
        'current_due_date': currentDueDate,
        'current_date_time': currentDateTime,
        'overdue_amount': overdueAmount,
        'overdue_from': overdueFrom,
        'overdue_to': overdueTo,
        'current_due_amount': currentDueAmount,
      },
      'car_details': {'car_series': carSeries, 'car_cc': carCc},
      'insurances': insurances,
    });

void main() {
  group('the last installment changes the whole card', () {
    test('it is detected by count, with the total rounded to an int', () {
      // `total_installment_number` is parsed as a double (the top-up endpoints
      // send it that way). Compared raw, 24 would never equal 24.0 and the
      // last installment would never be recognised.
      final summary = LoanDetailSummary(
          _contract(currentInstallment: 24, totalInstallment: 24.0));
      expect(summary.totalInstallmentNumber, 24);
      expect(summary.isFinalInstallment, isTrue);
      expect(LoanDetailSummary(_contract()).isFinalInstallment, isFalse);
    });

    test('งวดสุดท้าย drops the denominator, งวดปัจจุบัน keeps it', () {
      final last = LoanDetailSummary(
          _contract(currentInstallment: 24, totalInstallment: 24));
      expect(last.installmentLabel, 'งวดสุดท้าย');
      expect(last.installmentValue, '24');

      final mid = LoanDetailSummary(_contract());
      expect(mid.installmentLabel, 'งวดปัจจุบัน');
      expect(mid.installmentValue, '5/24');
    });

    test('รวมต้องชำระ is withheld on the last installment', () {
      expect(LoanDetailSummary(_contract()).showsTotalDueRow, isTrue);
      expect(
        LoanDetailSummary(
                _contract(currentInstallment: 24, totalInstallment: 24))
            .showsTotalDueRow,
        isFalse,
      );
      // …and on any installment where there is nothing due.
      expect(
        LoanDetailSummary(_contract(currentDueAmount: 0)).showsTotalDueRow,
        isFalse,
      );
    });

    test('the "not a payoff" caveat appears only there', () {
      expect(
        LoanDetailSummary(
                _contract(currentInstallment: 24, totalInstallment: 24))
            .showsNotAClosingBalanceNote,
        isTrue,
      );
      expect(
        LoanDetailSummary(_contract()).showsNotAClosingBalanceNote,
        isFalse,
      );
      // A contract with no installment schedule at all shows neither the
      // counter row nor the caveat, even though 0 == 0.
      final empty = LoanDetailSummary(
          _contract(currentInstallment: 0, totalInstallment: 0));
      expect(empty.isFinalInstallment, isTrue);
      expect(empty.showsInstallmentRow, isFalse);
      expect(empty.showsNotAClosingBalanceNote, isFalse);
    });
  });

  group('the due date is judged against the server clock', () {
    test('a due date still ahead is neither red nor past due', () {
      final summary = LoanDetailSummary(_contract(
        currentDueDate: '2026-10-05',
        currentDateTime: '2026-09-14T09:00:00',
      ));
      expect(summary.dueDateInFuture, isTrue);
      expect(summary.payByDateIsOverdue, isFalse);
      expect(summary.payByDateLabel, '05/10/2569');
    });

    test('a due date already passed turns the row red', () {
      final summary = LoanDetailSummary(_contract(
        currentDueDate: '2026-09-05',
        currentDateTime: '2026-09-14T09:00:00',
      ));
      expect(summary.dueDateInFuture, isFalse);
      expect(summary.payByDateIsOverdue, isTrue);
    });

    test('on the last installment past due, it shows the server date', () {
      // The amount quoted is what is owed today, so the date beside it has to
      // be today's — not a due date already gone.
      final summary = LoanDetailSummary(_contract(
        currentInstallment: 24,
        totalInstallment: 24,
        currentDueDate: '2026-09-05',
        currentDateTime: '2026-09-14T09:00:00',
      ));
      expect(summary.payByDateLabel, '14/09/2569');
    });

    test('before the last installment it always shows the due date', () {
      final summary = LoanDetailSummary(_contract(
        currentDueDate: '2026-09-05',
        currentDateTime: '2026-09-14T09:00:00',
      ));
      expect(summary.payByDateLabel, '05/09/2569');
    });

    test('an unreadable date reads as due, not as time remaining', () {
      expect(
        LoanDetailSummary(_contract(currentDateTime: '')).dueDateInFuture,
        isFalse,
      );
      expect(
        LoanDetailSummary(_contract(currentDueDate: '')).dueDateInFuture,
        isFalse,
      );
    });
  });

  group('เกินกำหนดชำระ replaces a figure only in one state', () {
    test('last installment + past due: both money rows say it', () {
      final summary = LoanDetailSummary(_contract(
        currentInstallment: 24,
        totalInstallment: 24,
        currentDueDate: '2026-09-05',
        currentDateTime: '2026-09-14T09:00:00',
        overdueFrom: '20',
        overdueTo: '23',
        overdueAmount: 9750,
      ));
      expect(summary.showsPastDueInsteadOfAmount, isTrue);
      expect(summary.overdueValueLabel, 'เกินกำหนดชำระ');
      expect(summary.currentInstallmentAmountLabel, 'เกินกำหนดชำระ');
    });

    test('last installment still in time: real figures', () {
      final summary = LoanDetailSummary(_contract(
        currentInstallment: 24,
        totalInstallment: 24,
        currentDueDate: '2026-10-05',
        currentDateTime: '2026-09-14T09:00:00',
        overdueFrom: '20',
        overdueTo: '23',
        overdueAmount: 9750,
      ));
      expect(summary.showsPastDueInsteadOfAmount, isFalse);
      expect(summary.overdueValueLabel, '9,750.00');
      expect(summary.currentInstallmentAmountLabel, '3,250.00');
    });

    test('mid-contract and past due: still real figures', () {
      // The trap: "overdue" alone does not produce the words. Only the last
      // installment does, because only there is the amount on file stale.
      final summary = LoanDetailSummary(_contract(
        currentDueDate: '2026-09-05',
        currentDateTime: '2026-09-14T09:00:00',
        overdueFrom: '3',
        overdueTo: '4',
        overdueAmount: 6500,
      ));
      expect(summary.payByDateIsOverdue, isTrue);
      expect(summary.showsPastDueInsteadOfAmount, isFalse);
      expect(summary.overdueValueLabel, '6,500.00');
    });
  });

  group('rows that hide themselves', () {
    test('ค้างชำระ needs a real range, not 0-0', () {
      expect(LoanDetailSummary(_contract()).showsOverdueRow, isFalse);
      expect(
        LoanDetailSummary(_contract(overdueFrom: '3', overdueTo: '0'))
            .showsOverdueRow,
        isFalse,
      );
      final ranged =
          LoanDetailSummary(_contract(overdueFrom: '3', overdueTo: '4'));
      expect(ranged.showsOverdueRow, isTrue);
      expect(ranged.overdueRangeLabel, 'ค้างชำระ (งวดที่3-4)');
    });

    test('a blank overdue bound is 0, not a crash', () {
      // The source calls int.parse on these and would throw on ''.
      final summary =
          LoanDetailSummary(_contract(overdueFrom: '', overdueTo: ''));
      expect(summary.overdueFrom, 0);
      expect(summary.showsOverdueRow, isFalse);
    });

    test('ค่างวดปัจจุบัน comes off contract_details, not payment_details', () {
      // The two fields share a name and differ in meaning: the contract's is
      // the scheduled installment, payment_details' is what is due now.
      final summary = LoanDetailSummary(
          _contract(contractInstallmentAmount: 3250, currentDueAmount: 9750));
      expect(summary.currentInstallmentAmount, 3250);
      expect(summary.currentInstallmentAmountLabel, '3,250.00');
      expect(summary.totalDueLabel, '9,750.00');
      expect(
        LoanDetailSummary(_contract(contractInstallmentAmount: 0))
            .showsCurrentInstallmentAmountRow,
        isFalse,
      );
    });

    test('กรมธรรม์ appears only when the contract carries a policy', () {
      expect(LoanDetailSummary(_contract()).showsInsuranceRow, isFalse);
      expect(
        LoanDetailSummary(_contract(insurances: const [
          {'ins_name': 'ประกันภัยรถจักรยานยนต์', 'ins_url': 'https://x/y.pdf'},
        ])).showsInsuranceRow,
        isTrue,
      );
    });
  });

  group('รายละเอียดสินค้า carries its unit only when there is a value', () {
    test('a real displacement gets the cc unit', () {
      final summary = LoanDetailSummary(_contract(carCc: '1500'));
      expect(summary.productDetail, '1500');
      expect(summary.productDetailSuffix, 'cc');
      expect(LoanDetailSummary(_contract(carCc: ' 125 ')).productDetailSuffix,
          'cc');
    });

    test('an absent one renders as - with no unit', () {
      // `- cc` would claim a measurement that isn't there.
      for (final blank in ['', '   ']) {
        final summary = LoanDetailSummary(_contract(carCc: blank));
        expect(summary.productDetail, '-');
        expect(summary.productDetailSuffix, '');
      }
    });

    test('รุ่นสินค้า falls back to - and never takes a unit', () {
      expect(LoanDetailSummary(_contract(carSeries: '')).productModel, '-');
      expect(
          LoanDetailSummary(_contract(carSeries: 'CLICK 125i')).productModel,
          'CLICK 125i');
    });
  });

  group('formatting', () {
    test('the data-date footer uses a dot for the time, as the source does',
        () {
      expect(formatLoanDetailTime('2026-09-14T20:43:00'), '20.43');
      expect(formatLoanDetailTime('2026-09-14T09:05:00'), '09.05');
      expect(formatLoanDetailTime(''), '');
      expect(formatLoanDetailTime('nonsense'), '');
    });

    test('the payment-history heading is a two-digit Buddhist year', () {
      // `14 ก.ค. 68`, not `14 ก.ค. 2568` — the source slices the year.
      expect(formatThaiShortDate(DateTime(2025, 7, 14)), '14 ก.ค. 68');
      expect(formatThaiShortDate(DateTime(2026, 1, 3)), '03 ม.ค. 69');
      expect(formatThaiShortDate(DateTime(2026, 12, 31)), '31 ธ.ค. 69');
      expect(formatThaiShortDate(null), '');
    });
  });

  group('payment history rows', () {
    test('the day comes first on the wire, as both references read it', () {
      final entry = PaymentHistoryEntry.fromJson(const {
        'date': '05-08-2026 14:12',
        'paid_amount': 3250.0,
        'payment_channel_code': 'CTR',
        'payment_channel_name': 'เคาน์เตอร์เซอร์วิส',
      });
      expect(entry.paidOn, DateTime(2026, 8, 5));
      expect(entry.paidAtTime, '14:12');
      expect(formatThaiShortDate(entry.paidOn), '05 ส.ค. 69');
    });

    test('an ISO date is read as ISO, not as a day-first one', () {
      // A four-digit leading segment cannot be a day, so this is unambiguous —
      // and it means a backend that switches format renders correctly instead
      // of reading the day as a year.
      final entry =
          PaymentHistoryEntry.fromJson(const {'date': '2026-08-05 14:12'});
      expect(entry.paidOn, DateTime(2026, 8, 5));
    });

    test('a date with no time part yields no time, not a crash', () {
      final entry = PaymentHistoryEntry.fromJson(const {'date': '05-08-2026'});
      expect(entry.paidOn, DateTime(2026, 8, 5));
      expect(entry.paidAtTime, '');
      expect(PaymentHistoryEntry.fromJson(const {}).paidOn, isNull);
    });

    test('mock mode serves this screen too, and is off by default', () {
      // The screen looks up its contract through PLoanApi, the seam carrying
      // the kPLoanUseMockData guard — not SrisawadApi directly. Without that a
      // build wearing PLoanMockBanner on every screen would quietly call the
      // live API behind the banner on this one.
      expect(PLoanApi.isMocked, isFalse);
      expect(kPLoanUseMockData, isFalse);
      expect(
        mockContracts().map((c) => c.contractNo),
        containsAll(<String>['MOCK-M-6701001', 'MOCK-C-6701002']),
        reason: 'the two fixtures the ?contNo= recipe names',
      );
    });

    test('db_name is truncated to two characters for this endpoint', () {
      // Not a typo: `MLOAN` -> `ML`. Sending it whole returned a 200 with an
      // empty `data` on a contract that has payments. `substring(0, 2)` occurs
      // exactly once in all of LandAndHouseWeb — on this endpoint — so the
      // truncation is deliberate there, and that client is the one whose
      // history tab is known to populate. See LoanDetailApi.
      expect(LoanDetailApi.useDbNamePrefix, isTrue);
      expect(LoanDetailApi.wireDbName('MLOAN'), 'ML');
      expect(LoanDetailApi.wireDbName('LLOAN'), 'LL');
      // Shorter than the prefix, or padded — neither may throw or pad.
      expect(LoanDetailApi.wireDbName('M'), 'M');
      expect(LoanDetailApi.wireDbName(''), '');
      expect(LoanDetailApi.wireDbName('  MLOAN  '), 'ML');
    });
  });
}
