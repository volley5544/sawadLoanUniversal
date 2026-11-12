import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_contract.dart';
import 'package:sawad_loan_universal/revolving/components/revolving_components.dart';
import 'package:sawad_loan_universal/router/app_router.dart';
import 'package:sawad_loan_universal/revolving/components/revolving_bill_dialogs.dart';
import 'package:sawad_loan_universal/revolving/models/revolving_mock.dart';
import 'package:sawad_loan_universal/revolving/revolving_contract_page.dart';
import 'package:sawad_loan_universal/revolving/revolving_home_page.dart';
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
            card: card, account: card.bankAccounts.first, amount: 0)),
    'amount bank': RevolvingTransferAmountPage(
        draft: RevolvingTransferDraft(
            card: card, account: card.bankAccounts.last, amount: 0)),
    'transfer confirm': const RevolvingTransferConfirmPage(),
    'transfer success': const RevolvingTransferSuccessPage(),
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

  testWidgets('ชำระเงิน goes to the loan payment screen for this contract',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, _) => const RevolvingHomePage(contractNo: 'C-1')),
      GoRoute(
          path: AppRoutes.loanPayment,
          builder: (_, state) =>
              Text('loanPayment ${state.uri.queryParameters['contNo']}')),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.tap(find.text('ชำระเงิน').first);
    await tester.pumpAndSettle();
    expect(find.text('loanPayment C-1'), findsOneWidget);
  });

  Future<void> pumpDestinations(
      WidgetTester tester, List<RevolvingBankAccount> accounts) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: RevolvingTransferPage(
            card: card.copyWith(bankAccounts: accounts))));
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  const bbl = RevolvingBankAccount(
    bankName: 'Bangkok Bank',
    bankCode: 'BBL',
    transferType: 'customer_bank',
    accountType: 'SAVING ACCOUNT',
    accountNumber: '1234567890',
    accountName: 'John Doe',
    isDefault: true,
  );

  testWidgets('one bank account → exactly one destination tile',
      (tester) async {
    await pumpDestinations(tester, const [bbl]);
    expect(find.text('Bangkok Bank'), findsOneWidget);
    expect(find.text('SAVING ACCOUNT · 123-4-56789-0'), findsOneWidget);
    expect(find.text('พร้อมเพย์'), findsNothing);
  });

  testWidgets('every bank_accounts entry gets its own tile', (tester) async {
    await pumpDestinations(tester, const [
      bbl,
      RevolvingBankAccount(
          transferType: 'promptpay_citizen', accountNumber: '1234567890123'),
    ]);
    expect(find.text('Bangkok Bank'), findsOneWidget);
    expect(find.text('พร้อมเพย์'), findsOneWidget);
    expect(find.text('1-2345-67890-12-3'), findsOneWidget);
  });

  testWidgets('no bank accounts says so instead of offering a tile',
      (tester) async {
    await pumpDestinations(tester, const []);
    expect(find.text('ไม่พบบัญชีรับเงินของสัญญานี้'), findsOneWidget);
  });

  test('destination numbers are grouped and masked', () {
    expect(revolvingFormatAccountNumber(bbl), '123-4-56789-0');
    expect(revolvingMaskAccountNumber(bbl), 'XXX-X-XX789-0');
    const phone = RevolvingBankAccount(
        transferType: 'promptpay_phone', accountNumber: '0888888888');
    expect(revolvingFormatAccountNumber(phone), '088-888-8888');
    expect(revolvingAccountNumberLabel(phone), 'เบอร์โทรศัพท์');
    // An unexpected shape is shown as sent; nothing is `-`.
    expect(
        revolvingFormatAccountNumber(
            const RevolvingBankAccount(accountNumber: '12345')),
        '12345');
    expect(revolvingFormatAccountNumber(const RevolvingBankAccount()), '-');
  });

  test('used ratio is the drawn share of the line', () {
    expect(card.usedRatio, closeTo(0.8, 1e-9));
  });
}
