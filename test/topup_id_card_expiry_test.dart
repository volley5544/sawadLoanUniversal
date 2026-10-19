import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/p_loan/application/models/p_loan_mock.dart';
import 'package:sawad_loan_universal/topup/models/topup_flow.dart';

/// Step 6's ID-card expiry rule — LandAndHouseWeb's
/// `isCurrentDateBeforeDateInput` + `exception_date` check. When this answers
/// true the customer is asked for the expiry date instead of being refused.
void main() {
  final today = DateTime(2026, 10, 19);

  bool needs(String latestDate, {bool waived = false}) =>
      TopupFlow.idCardNeedsExpiryDate(
        latestDate: latestDate,
        expiryWaived: waived,
        today: today,
      );

  group('idCardNeedsExpiryDate', () {
    test('a card expiring after today passes without asking', () {
      expect(needs('2026-10-20'), isFalse);
      expect(needs('2033-04-12'), isFalse);
    });

    test('an expired card asks for the date', () {
      expect(needs('2026-10-18'), isTrue);
      expect(needs('2020-01-01'), isTrue);
    });

    test('a card expiring today asks — the source compares today < expiry',
        () {
      expect(needs('2026-10-19'), isTrue);
      expect(needs('2026-10-19 23:59:59'), isTrue);
    });

    test('a date the scan could not read asks', () {
      expect(needs(''), isTrue);
      expect(needs('null'), isTrue);
      expect(needs('ตลอดชีพ'), isTrue);
    });

    test('exception_date Y waives the check, even with no date', () {
      expect(needs('', waived: true), isFalse);
      expect(needs('2020-01-01', waived: true), isFalse);
    });

    test('time of day on the server clock does not move the boundary', () {
      expect(
        TopupFlow.idCardNeedsExpiryDate(
          latestDate: '2026-10-20',
          expiryWaived: false,
          today: DateTime(2026, 10, 19, 23, 59),
        ),
        isFalse,
      );
    });
  });

  group('isIdCardExpiryValid (the picked date)', () {
    test('only a date strictly after today is accepted', () {
      expect(TopupFlow.isIdCardExpiryValid(DateTime(2026, 10, 20), today: today),
          isTrue);
      expect(TopupFlow.isIdCardExpiryValid(DateTime(2026, 10, 19), today: today),
          isFalse);
      expect(TopupFlow.isIdCardExpiryValid(DateTime(2026, 1, 1), today: today),
          isFalse);
    });
  });

  test('serverToday is the contract\'s server date, time stripped', () {
    final flow = TopupFlow(hashThaiId: 'H', authToken: 'T')
      ..contract = mockContracts().first;
    final server =
        DateTime.parse(flow.contract!.paymentDetails.currentDateTime);
    expect(flow.serverToday, DateTime(server.year, server.month, server.day));
  });
}
