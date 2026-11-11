import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/revolving/components/revolving_bill_dialogs.dart';
import 'package:sawad_loan_universal/revolving/models/revolving_mock.dart';
import 'package:sawad_loan_universal/revolving/revolving_contract_page.dart';
import 'package:sawad_loan_universal/revolving/revolving_home_page.dart';
import 'package:sawad_loan_universal/revolving/revolving_payment_pages.dart';
import 'package:sawad_loan_universal/revolving/revolving_transfer_pages.dart';

/// บัตรศรีสวัสดิ์ screens (UI only, 2026-11-11): each renders at phone width
/// without a layout overflow, which the test binding reports as an exception.
void main() {
  final card = RevolvingCardView.mock(contractNo: 'X');
  final pages = <String, Widget>{
    'home': const RevolvingHomePage(),
    'contract': RevolvingContractPage(card: card),
    'transfer': RevolvingTransferPage(card: card),
    'amount promptpay': RevolvingTransferAmountPage(
        draft: RevolvingTransferDraft(
            card: card,
            target: RevolvingTransferTarget.promptPay,
            amount: 0)),
    'amount bank': RevolvingTransferAmountPage(
        draft: RevolvingTransferDraft(
            card: card,
            target: RevolvingTransferTarget.bankAccount,
            amount: 0)),
    'transfer confirm': const RevolvingTransferConfirmPage(),
    'transfer success': const RevolvingTransferSuccessPage(),
    'payment': RevolvingPaymentPage(card: card),
    'payment confirm': const RevolvingPaymentConfirmPage(),
    'payment success': const RevolvingPaymentSuccessPage(),
    'qr': const RevolvingQrPage(),
  };

  for (final entry in pages.entries) {
    testWidgets('${entry.key} renders at 360 px', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: entry.value));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('history tabs switch lists', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RevolvingHomePage()));
    await tester.pump();
    expect(find.text('15 ม.ค. 69'), findsOneWidget);
    await tester.tap(find.text('ประวัติการชำระ').first);
    await tester.pump();
    expect(find.text('15 ม.ค. 69'), findsNothing);
    expect(find.text('20 ม.ค. 69'), findsOneWidget);
  });

  testWidgets('a payment option expands its breakdown', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: RevolvingPaymentPage(card: card)));
    await tester.pump();
    expect(find.text('ยอดที่แนะนำชำระ'), findsNothing);
    await tester.tap(find.text('ยอดแนะนำให้ชำระขั้นต่ำ'));
    await tester.pump();
    expect(find.text('ยอดที่แนะนำชำระ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Future<void> openBill(WidgetTester tester, RevolvingCardView view) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showRevolvingBill(context, view),
            child: const Text('bill'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('bill'));
    await tester.pump();
  }

  testWidgets('ดูบิล before the statement date explains when it issues',
      (tester) async {
    await openBill(tester, card);
    expect(find.text('ยังไม่สามารถออกใบแจ้งหนี้ได้'), findsOneWidget);
  });

  testWidgets('an issued bill with no URL yet says so rather than opening',
      (tester) async {
    await openBill(tester, card.copyWith(billReady: true));
    expect(find.text('ยังไม่สามารถออกใบแจ้งหนี้ได้'), findsNothing);
    expect(find.textContaining('ใบแจ้งหนี้ ยังไม่เปิดใช้งาน'), findsOneWidget);
  });

  test('used ratio is the drawn share of the line', () {
    expect(card.usedRatio, closeTo(0.8, 1e-9));
  });
}
