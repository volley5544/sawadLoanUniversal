import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/loan_detail/components/loan_detail_components.dart';
import 'package:sawad_loan_universal/loan_detail/components/loan_detail_header_card.dart';
import 'package:sawad_loan_universal/p_loan/application/components/p_loan_components.dart';
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
  _headerCardRowSwitchTests();
  _totalPayableTests();
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

    test('the history tab dates itself from the response, not the contract', () {
      // `data_date` rides on the history response and is quoted under that
      // list; the two tabs above it quote /loan/list's. Separate reads, taken
      // at different moments.
      const history = PaymentHistory(dataDate: '2026-09-09 13:05:04');
      expect(formatThaiDate(history.dataDate), '09/09/2569');
      expect(formatLoanDetailTime(history.dataDate), '13.05');
    });

    test('a response with no data_date withholds the footer', () {
      // Rendering `ข้อมูลวันที่  เวลา  น.` would be worse than no line at all.
      expect(const PaymentHistory().dataDate, isEmpty);
      expect(LoanDetailApi.mockPaymentHistory.dataDate, isNotEmpty);
      expect(LoanDetailApi.mockPaymentHistory.isEmpty, isFalse);
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

/// A row shaped for the **ยอดรวมต้องชำระ** breakdown on the ข้อมูลการชำระ tab.
///
/// `current_due_amount` is the grand total — "this field is sum of all to
/// current" (settled 2026-09-17) — so these fixtures set it to the intended
/// total and let the upcoming row fall out as the remainder.
LoanContract _payable({
  num currentDueAmount = 2500.25,
  num overdueAmount = 1000,
  num collectionFee = 50,
  num penaltyFee = 10.25,
  String overdueDate = '2026-08-20',
  String currentDueDate = '2026-09-20',
}) =>
    LoanContract.fromJson({
      'contract_no': 'MLOAN-TEST-02',
      'db_name': 'MLOAN',
      'contract_details': {'loan_type_code': 'M', 'installment_amount': 1440},
      'payment_details': {
        'current_due_amount': currentDueAmount,
        'overdue_amount': overdueAmount,
        'collection_fee': collectionFee,
        'penalty_fee': penaltyFee,
        'overdue_date': overdueDate,
        'current_due_date': currentDueDate,
        'current_installment_number': 7,
        'total_installment_number': 48,
      },
    });

void _totalPayableTests() {
  group('ยอดรวมต้องชำระ — the five shapes from the design', () {
    test('arrears with both fees, plus an upcoming instalment', () {
      final s = LoanDetailSummary(_payable());
      expect(s.showsOverdueSection, isTrue);
      expect(s.overdueInstallmentAmount, 1000);
      expect(s.overdueCollectionFee, 50);
      expect(s.overduePenaltyFee, 10.25);
      expect(s.overdueSubtotal, 1060.25);
      expect(s.showsUpcomingSection, isTrue);
      expect(s.upcomingDueAmount, 1440);
      expect(s.totalPayableAmount, 2500.25);
      expect(s.showsTotalPayableRow, isTrue);
    });

    // The design's "กรณีมีค่างวดค้าง และค่างวดงวดถัดไป แต่ไม่มีค่าธรรมเนียม".
    test('no fees leaves the arrears block a single row', () {
      final s = LoanDetailSummary(
          _payable(collectionFee: 0, penaltyFee: 0, currentDueAmount: 2440));
      expect(s.showsOverdueCollectionFeeRow, isFalse);
      expect(s.showsOverduePenaltyFeeRow, isFalse);
      expect(s.overdueSubtotal, 1000);
      expect(s.upcomingDueAmount, 1440);
    });

    // "กรณีมีค่างวดค้างอย่างเดียว" — and the asymmetry worth pinning: the
    // grand total is withheld, because รวมค้างชำระ already states the same
    // figure one line above it.
    test('arrears only withholds the grand-total row', () {
      final s = LoanDetailSummary(_payable(
          collectionFee: 0, penaltyFee: 0, currentDueAmount: 1000));
      expect(s.showsOverdueSection, isTrue);
      expect(s.showsUpcomingSection, isFalse);
      expect(s.showsTotalPayableRow, isFalse);
    });

    // "กรณีมีค่างวดงวดถัดไปอย่างเดียว" — which *does* show it, since the
    // upcoming block carries no subtotal of its own.
    test('upcoming only still shows the grand total', () {
      final s = LoanDetailSummary(_payable(
          overdueAmount: 0,
          collectionFee: 0,
          penaltyFee: 0,
          currentDueAmount: 1440));
      expect(s.showsOverdueSection, isFalse);
      expect(s.showsUpcomingSection, isTrue);
      expect(s.upcomingDueAmount, 1440);
      expect(s.showsTotalPayableRow, isTrue);
      expect(s.totalPayableAmount, 1440);
    });

    test('"ไม่มียอด" shows the grand total alone, at zero', () {
      final s = LoanDetailSummary(_payable(
          overdueAmount: 0,
          collectionFee: 0,
          penaltyFee: 0,
          currentDueAmount: 0));
      expect(s.showsOverdueSection, isFalse);
      expect(s.showsUpcomingSection, isFalse);
      expect(s.showsTotalPayableRow, isTrue);
      expect(s.totalPayableAmount, 0);
    });

    // ⚠ The whole reason the upcoming row is a remainder rather than
    // `installment_amount`: the rows must add up to the total under them.
    test('the rows always sum to the grand total', () {
      for (final due in [2500.25, 1500, 1060.25, 0]) {
        final s = LoanDetailSummary(_payable(currentDueAmount: due));
        if (s.showsUpcomingSection) {
          expect(s.overdueSubtotal + s.upcomingDueAmount, s.totalPayableAmount,
              reason: 'current_due_amount $due');
        }
      }
    });

    // current_due_amount below the arrears it contains would otherwise render
    // a negative instalment under "ส่วนที่จะครบกำหนดชำระ".
    test('an upcoming amount never goes negative', () {
      final s = LoanDetailSummary(_payable(currentDueAmount: 500));
      expect(s.upcomingDueAmount, 0);
      expect(s.showsUpcomingSection, isFalse);
    });

    // One screen must not carry two numbers for one thing: the section's grand
    // total and the header card's รวมต้องชำระ are the same field.
    test('the grand total is the header card figure', () {
      final s = LoanDetailSummary(_payable());
      expect(s.totalPayableAmount, s.totalDueAmount);
    });

    // penalty_fee is unconfirmed on payment_details, so it must degrade to a
    // withheld row rather than a zero one.
    test('a response with no penalty_fee withholds that row', () {
      final c = LoanContract.fromJson({
        'contract_no': 'X',
        'payment_details': {'overdue_amount': 100, 'current_due_amount': 100},
      });
      expect(c.paymentDetails.penaltyFee, 0);
      expect(LoanDetailSummary(c).showsOverduePenaltyFeeRow, isFalse);
    });

    test('the arrears block dates off overdue_date, falling back to the due date',
        () {
      expect(LoanDetailSummary(_payable()).overdueSectionDate, '2026-08-20');
      expect(LoanDetailSummary(_payable(overdueDate: '')).overdueSectionDate,
          '2026-09-20');
    });
  });
}

void _headerCardRowSwitchTests() {
  group('the header card\'s ค้างชำระ / ค่างวดปัจจุบัน switch', () {
    LoanDetailHeaderCard card({bool? shows}) => LoanDetailHeaderCard(
          contract: _contract(),
          showsNotIssuedNotice: false,
          onDownloadContract: null,
          onViewInsurances: () {},
          showsArrearsAndInstalmentRows: shows ?? true,
        );

    // ⚠ The default must stay `true`. `loan_payment_page_old.dart` is the only
    // other caller and is frozen for comparison against the redesigned payment
    // screen — a default of `false` would silently restyle the very thing the
    // `_old` pair exists to be compared against.
    test('defaults to showing them, so the _old payment page is untouched', () {
      expect(
        LoanDetailHeaderCard(
          contract: _contract(),
          showsNotIssuedNotice: false,
          onDownloadContract: null,
          onViewInsurances: _noop,
        ).showsArrearsAndInstalmentRows,
        isTrue,
      );
    });

    test('the loan detail screen opts out', () {
      expect(card(shows: false).showsArrearsAndInstalmentRows, isFalse);
      expect(card().showsArrearsAndInstalmentRows, isTrue);
    });

    // The rules themselves are untouched — only whether the card consults
    // them. งวดปัจจุบัน (the instalment *number*) is a separate row and stays.
    test('the underlying summary rules are unchanged', () {
      // `showsOverdueRow` keys on the instalment *range*, not the amount —
      // `0-0` is the API's way of saying nothing is overdue.
      final s = LoanDetailSummary(
          _contract(overdueAmount: 9170, overdueFrom: '5', overdueTo: '6'));
      expect(s.showsOverdueRow, isTrue);
      expect(s.showsCurrentInstallmentAmountRow, isTrue);
      expect(s.showsInstallmentRow, isTrue);
    });
  });
}

void _noop() {}
