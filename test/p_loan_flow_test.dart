import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/config/app_environment.dart';
import 'package:sawad_loan_universal/models/customer_detail.dart';
import 'package:sawad_loan_universal/models/ndid_subject.dart';
import 'package:sawad_loan_universal/loan_register/models/loan_register_form.dart';
import 'package:sawad_loan_universal/p_loan/application/components/p_loan_components.dart';
import 'package:sawad_loan_universal/p_loan/application/models/installment_plan.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_amount_detail.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_contract.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_documents.dart';
import 'package:sawad_loan_universal/p_loan/application/models/p_loan_flow.dart';

/// Fixtures shaped like the real API payloads, including the quirks worth
/// pinning down: `car_chassisNo` mixed casing, camelCase installment keys, and
/// numbers arriving as ints, doubles or strings interchangeably.
const _contractJson = <String, dynamic>{
  'contract_no': 'ญฟC670301001NE54X',
  'db_name': 'SAWAD01',
  'contract_bank_account': '1234567890',
  'contract_bank_brandname': 'KBANK',
  'contract_bank_type': 'S',
  'request_status': 'ยังไม่ได้ทำรายการเติมเงิน',
  'transno': '',
  'contract_details': {
    'account_status': 'A',
    'account_type': 'C',
    'loan_type_code': 'M',
    'loan_type_name': 'สินเชื่อรถจักรยานยนต์',
    'collateral_information': 'ฮอนด้า เวฟ 110i',
    'closing_balance': 12000,
    'credit_limit': '35000.0',
    'comcode': '1C',
  },
  'topup_detail': {
    'can_topup': 'Y',
    'default_topup_amount': 35000,
    'fee_amount': 100,
    'balance_receivable': 12500,
    'yield': 250,
  },
  'car_details': {
    'car_chassisNo': 'CHASSIS-1',
    'car_engineNo': 'ENGINE-1',
    'car_series': 'Wave 110i',
    'car_province': 'กรุงเทพมหานคร',
  },
  'payment_details': {
    'current_date_time': '2026-07-27T10:00:00',
    'total_installment_number': 24.0,
  },
};

const _amountDetailJson = <String, dynamic>{
  'code': '200',
  'db_name': 'SAWAD01',
  'contract_no': 'ญฟC670301001NE54X',
  'default_topup_amount': 35000,
  'min_topup_amount': 5000,
  'max_topup_amount': 50000,
  'interest_rate': 1.09,
  'fee_amount': 100,
  'due_day': 15,
  'interest_paid_flag': 'N',
  'yield': 250,
  'contract_details': {'closing_balance': 12000, 'credit_limit': 35000.0},
  'car_details': {'car_series': 'Wave 110i'},
};

const _planJson = <String, dynamic>{
  'code': '200',
  'amount': 30000,
  'fee_amount': 100,
  'first_due_date': '2026-08-15',
  'installments': [
    {
      'tenor': 12,
      'regularPeriodAmt': 2800,
      'lastPeriodAmt': 2795.5,
      'totalAmt': 33600.0,
      'intAmt': 3600.0,
      'lastPeriodPromo': 0.0,
    },
    {
      'tenor': 24,
      'regularPeriodAmt': 1500,
      'lastPeriodAmt': 1495.7,
      'totalAmt': 36000.0,
      'intAmt': 6000.0,
      'lastPeriodPromo': 0.0,
    },
  ],
};

PLoanFlow _completeFlow({PLoanKind kind = PLoanKind.extra}) {
  final flow = PLoanFlow(
    hashThaiId: 'HASH123',
    kind: kind,
    authToken: 'TOKEN',
    source: 'app',
    referId: 'REF1',
    customer: CustomerDetail.fromJson(const {'thai_id': '1234567890123'}),
    // Extra only: a new P-Loan is raised against nothing, so it carries no
    // contract through the flow at all.
    contract: kind == PLoanKind.extra
        ? LoanContract.fromJson(_contractJson)
        : null,
    amountDetail: LoanAmountDetail.fromJson(_amountDetailJson),
  )
    ..requestedAmount = 30000
    ..plan = InstallmentPlan.fromJson(_planJson)
    ..documents = const LoanDocuments(
      request: 'REQ_B64',
      receipt: 'RCP_B64',
      agreement: 'AGR_B64',
    )
    ..latitude = '13.88'
    ..longitude = '100.57';
  flow.installment = flow.plan!.installments.last; // 24 months
  flow.photos[PLoanPhoto.fullVehicle] = Uint8List.fromList([1, 2, 3]);
  flow.photos[PLoanPhoto.taxDisc] = Uint8List.fromList([4, 5, 6]);
  flow.photos[PLoanPhoto.idCard] = Uint8List.fromList([7, 8, 9]);
  flow.photos[PLoanPhoto.selfieWithIdCard] = Uint8List.fromList([10, 11]);
  return flow;
}

void main() {
  group('response parsing', () {
    test('tolerates ints, doubles and numeric strings for the same field', () {
      final contract = LoanContract.fromJson(_contractJson);
      // credit_limit arrives as the string '35000.0' here.
      expect(contract.contractDetails.creditLimit, 35000.0);
      expect(contract.contractDetails.closingBalance, 12000);
      expect(contract.paymentDetails.totalInstallmentNumber, 24.0);
    });

    test('reads the mixed-case car keys the API really sends', () {
      final car = LoanContract.fromJson(_contractJson).carDetails;
      expect(car.chassisNo, 'CHASSIS-1');
      expect(car.engineNo, 'ENGINE-1');
    });

    test('installment options use camelCase wire keys', () {
      final plan = InstallmentPlan.fromJson(_planJson);
      expect(plan.installments, hasLength(2));
      expect(plan.installments.first.regularPeriodAmt, 2800);
      expect(plan.installments.last.intAmt, 6000.0);
    });

    test('longestFirst reverses the API order for the picker', () {
      final plan = InstallmentPlan.fromJson(_planJson);
      expect(plan.longestFirst.first.tenor, 24);
      expect(plan.longestFirst.last.tenor, 12);
    });

    test('missing nested objects yield defaults instead of throwing', () {
      final contract = LoanContract.fromJson(const {'contract_no': 'X'});
      expect(contract.contractDetails.creditLimit, 0);
      expect(contract.insurances, isEmpty);
      expect(contract.carDetails.series, '');
    });
  });

  group('eligibility', () {
    test('an active, eligible, request-free contract is selectable', () {
      final contract = LoanContract.fromJson(_contractJson);
      expect(contract.isActive, isTrue);
      expect(contract.isEligible, isTrue);
      expect(contract.hasNoRequestYet, isTrue);
      expect(contract.isSelectable, isTrue);
    });

    test('promissory-note accounts are excluded', () {
      final contract = LoanContract.fromJson({
        ..._contractJson,
        'contract_details': {
          ..._contractJson['contract_details'] as Map<String, dynamic>,
          'account_type': 'L',
        },
      });
      expect(contract.isPromissoryNote, isTrue);
      expect(contract.isSelectable, isFalse);
    });
  });

  group('amount rules', () {
    test('payout deducts the stamp duty and nothing else', () {
      // ยอดโอนเงินเข้าบัญชี = ยอดจัดวงเงินอเนกประสงค์ − ค่าอากรแสตมป์, on the
      // full amount. The old contract's closing balance (12000 here) is NOT
      // deducted: this loan does not replace that contract.
      final flow = _completeFlow()..requestedAmount = 30000;
      expect(flow.payoutAmount, 29900);
    });

    test('requested amount must sit inside the API bounds', () {
      final detail = LoanAmountDetail.fromJson(_amountDetailJson);
      expect(detail.isAmountAllowed(5000), isTrue);
      expect(detail.isAmountAllowed(50000), isTrue);
      expect(detail.isAmountAllowed(4999), isFalse);
      expect(detail.isAmountAllowed(50001), isFalse);
    });

    test('amounts round down to a whole hundred', () {
      expect(roundDownToHundred(30099), 30000);
      expect(roundDownToHundred(30100), 30100);
      expect(roundDownToHundred(99), 0);
    });
  });

  group('new P-Loan vs P-Loan Extra', () {
    test('an Extra is the default, so existing behaviour is unchanged', () {
      expect(PLoanFlow(hashThaiId: 'H').kind, PLoanKind.extra);
      expect(PLoanFlow(hashThaiId: 'H').isNewPLoan, isFalse);
    });

    test('neither kind deducts an old principal — only the duty', () {
      final extra = _completeFlow();
      final fresh = _completeFlow(kind: PLoanKind.newLoan);
      // Both 30000 - 100 fee. An Extra used to come to 17900 here, deducting
      // the 12000 closing balance the way a top-up does; it does not replace
      // that contract, and on a real one (topup_extra 2000 vs balance 7740)
      // that deduction made the payout negative.
      expect(extra.payoutAmount, 29900);
      expect(fresh.payoutAmount, 29900);
    });

    test('a small Extra offer still pays out positive', () {
      // The MLOAN/ฮฮM680702003NF61X shape: offer far below the balance.
      final extra = _completeFlow()..requestedAmount = 2000;
      expect(extra.payoutAmount, 1900, reason: '2000 - 100 duty');
      expect(extra.payoutAmount, greaterThan(0));
    });

    test('neither kind is bounded by the contract\'s top-up range', () {
      // 80000 is well above the reference contract's max_topup_amount (50000),
      // and neither product cares: an Extra requests the fixed topup_extra
      // offer, and min/max_topup_amount bound the *top-up* product rather than
      // either of these — while a new P-Loan's amount is the customer's to name.
      final extra = _completeFlow()..requestedAmount = 80000;
      final fresh = _completeFlow(kind: PLoanKind.newLoan)
        ..requestedAmount = 80000;
      expect(extra.isRequestedAmountAllowed, isTrue);
      expect(fresh.isRequestedAmountAllowed, isTrue,
          reason: 'the customer names the amount for a new loan');
    });

    test('an Extra with no topup_extra offer cannot proceed', () {
      // 0 is the "no offer" signal, and there is no fallback to substitute.
      final extra = _completeFlow()..requestedAmount = 0;
      expect(extra.isRequestedAmountAllowed, isFalse);
    });

    test('a new P-Loan still needs an amount to have been entered', () {
      final fresh = _completeFlow(kind: PLoanKind.newLoan)
        ..requestedAmount = 0;
      expect(fresh.isRequestedAmountAllowed, isFalse);

      fresh.requestedAmount = PLoanFlow.newLoanMinimumAmount;
      expect(fresh.isRequestedAmountAllowed, isTrue);
    });

    test('a new P-Loan refuses to be posted as a top-up', () {
      // POST /topup books against contract_no. For a new P-Loan that contract
      // is only a data reference, so building this body would file a top-up of
      // the customer's existing loan for an amount never approved against it.
      // It goes to the P-Loan save API instead.
      final fresh = _completeFlow(kind: PLoanKind.newLoan);
      expect(fresh.submitTarget, PLoanSubmitTarget.pLoanSaveApi);
      expect(fresh.toSubmissionJson, throwsStateError);

      final extra = _completeFlow();
      expect(extra.submitTarget, PLoanSubmitTarget.topup);
      expect(extra.toSubmissionJson()['contract_no'], isNotEmpty);
    });
  });

  group('a new P-Loan is raised against no contract', () {
    test('it carries none at all — refContractNo is an Extra\'s field', () {
      expect(_completeFlow().contract, isNotNull);
      expect(_completeFlow(kind: PLoanKind.newLoan).contract, isNull);
    });

    test('it cannot produce contract documents, so it cannot submit yet', () {
      // POST /pdf/loan is keyed by contract_no + db_name + from +
      // contract_date, all of which come from the contract.
      final fresh = _completeFlow(kind: PLoanKind.newLoan);
      expect(fresh.canGenerateDocuments, isFalse);
      expect(_completeFlow().canGenerateDocuments, isTrue);
    });

    test('submit needs the documents, which is what blocks a new loan', () {
      // Everything else satisfied; only the documents are missing.
      final fresh = _completeFlow(kind: PLoanKind.newLoan)
        ..verifiedThaiId = '1234567890123'
        ..consented.addAll(LoanDocumentKind.values)
        ..ndidVerified = true
        ..sensitiveConsent = true
        ..documents = null;
      fresh.newLoan
        ..collateralType = PLoanCollateralType.motorcycle
        ..brand = 'HONDA'
        ..series = 'Wave 110i'
        ..manufactureYear = '2562'
        ..bankCode = 'SCB'
        ..bankAccountNo = '9876543210'
        ..bankAccountName = 'สมชาย ใจดี';
      expect(fresh.canSubmit, isFalse);
    });

    test('an Extra with no contract is a broken flow, not a new product', () {
      final broken = _completeFlow()
        ..contract = null
        ..verifiedThaiId = '1234567890123'
        ..consented.addAll(LoanDocumentKind.values)
        ..ndidVerified = true
        ..sensitiveConsent = true;
      expect(broken.canSubmit, isFalse);
      expect(broken.canGenerateDocuments, isFalse);
    });
  });

  group('a new P-Loan states its own collateral and payout account', () {
    test('an Extra still reads both off the contract it draws on', () {
      final extra = _completeFlow();
      expect(extra.loanTypeCode, 'M');
      expect(extra.collateralSeries, 'Wave 110i');
      expect(extra.bankCode, 'KBANK');
      expect(extra.bankAccountNo, '1234567890');
    });

    test('a new P-Loan inherits none of it — blank until the customer says',
        () {
      // The bug this replaced: a contract's vehicle (ยี่ห้อสินค้า HONDA) and
      // its payout account were shown as this application's.
      final fresh = _completeFlow(kind: PLoanKind.newLoan);
      expect(fresh.loanTypeCode, isEmpty);
      expect(fresh.collateralBrand, isEmpty);
      expect(fresh.collateralSeries, isEmpty);
      expect(fresh.bankCode, isEmpty);
      expect(fresh.bankAccountNo, isEmpty);
      expect(fresh.bankAccountName, isEmpty);
    });

    test('what the customer enters is what the flow reports', () {
      final fresh = _completeFlow(kind: PLoanKind.newLoan);
      fresh.newLoan
        ..collateralType = PLoanCollateralType.car
        ..brand = 'TOYOTA'
        ..series = 'Yaris'
        ..manufactureYear = '2562'
        ..bankCode = 'SCB'
        ..bankAccountNo = '9876543210'
        ..bankAccountName = 'สมหญิง รักดี';

      expect(fresh.loanTypeCode, 'C');
      expect(fresh.loanTypeName, 'รถยนต์');
      expect(fresh.collateralBrand, 'TOYOTA');
      expect(fresh.collateralManufactureYear, '2562');
      expect(fresh.bankCode, 'SCB');
      expect(fresh.bankAccountName, 'สมหญิง รักดี');
    });

    test('the chosen type drives which photos step 4 requires', () {
      // For an Extra this comes from the contract; for a new loan the customer
      // picks it, so the same switch has to follow their choice.
      final fresh = _completeFlow(kind: PLoanKind.newLoan);
      // Nothing picked yet: neither M nor C, so only the tax disc.
      expect(fresh.requiredPhotos, [PLoanPhoto.taxDisc]);

      fresh.newLoan.collateralType = PLoanCollateralType.car;
      expect(fresh.requiredPhotos, hasLength(6));
      expect(fresh.requiredPhotos, contains(PLoanPhoto.carMile));

      fresh.newLoan.collateralType = PLoanCollateralType.motorcycle;
      expect(fresh.requiredPhotos, [PLoanPhoto.fullVehicle, PLoanPhoto.taxDisc]);
    });

    test('submit is gated on both, and only for a new P-Loan', () {
      PLoanFlow ready(PLoanKind kind) => _completeFlow(kind: kind)
        ..verifiedThaiId = '1234567890123'
        ..consented.addAll(LoanDocumentKind.values)
        ..ndidVerified = true
        ..sensitiveConsent = true;

      // An Extra takes both off its contract, so nothing extra is required.
      expect(ready(PLoanKind.extra).canSubmit, isTrue);

      final fresh = ready(PLoanKind.newLoan);
      expect(fresh.canSubmit, isFalse, reason: 'no collateral, no account');

      fresh.newLoan
        ..collateralType = PLoanCollateralType.motorcycle
        ..brand = 'HONDA'
        ..series = 'Wave 110i'
        ..manufactureYear = '2562';
      expect(fresh.canSubmit, isFalse, reason: 'still no payout account');

      fresh.newLoan
        ..bankCode = 'SCB'
        ..bankAccountNo = '9876543210'
        ..bankAccountName = 'สมชาย ใจดี';
      expect(fresh.canSubmit, isTrue);
    });

    test('a non-vehicle collateral type asks for no vehicle details', () {
      final details = NewLoanDetails()
        ..collateralType = PLoanCollateralType.other;
      expect(details.hasCollateral, isTrue);

      details.collateralType = PLoanCollateralType.car;
      expect(details.hasCollateral, isFalse);
    });
  });

  group("an Extra's request amount is the fixed topup_extra offer", () {
    // min 5000 / max 50000 / default 35000 from _amountDetailJson — none of
    // which may influence the answer.
    LoanAmountDetail detail({int? topupExtra}) =>
        LoanAmountDetail.fromJson(<String, dynamic>{
          ..._amountDetailJson,
          'topup_extra': ?topupExtra,
        });

    test('is topup_extra, not default_topup_amount', () {
      expect(detail(topupExtra: 20000).extraRequestAmount, 20000);
    });

    test('ignores min/max_topup_amount — they bound the top-up product', () {
      // Regression: MLOAN/ฮฮM680702003NF61X offers topup_extra 2,000 against a
      // top-up floor of 8,000. Range-checking it filed the top-up total instead.
      expect(detail(topupExtra: 2000).extraRequestAmount, 2000);
      expect(detail(topupExtra: 90000).extraRequestAmount, 90000);
    });

    test('never substitutes the top-up total', () {
      for (final extra in [1, 2000, 90000]) {
        expect(detail(topupExtra: extra).extraRequestAmount, isNot(35000),
            reason: 'topup_extra=$extra');
      }
    });

    test('0 means no offer, and does not fall back', () {
      expect(detail(topupExtra: 0).extraRequestAmount, 0);
      expect(detail().extraRequestAmount, 0);
      // The deep link reports it as "nothing to request" rather than sending 0.
      expect(detail(topupExtra: 0).topupCardRequestAmount(), isNull);
    });

    test('the deep link requests the same offer step 2 does', () {
      for (final extra in [1, 2000, 20000, 90000]) {
        final d = detail(topupExtra: extra);
        expect(d.topupCardRequestAmount(), d.extraRequestAmount,
            reason: 'topup_extra=$extra');
      }
    });

    test('an amount the card passed wins, rounded down to the nearest 100', () {
      final d = detail(topupExtra: 20000);
      expect(d.topupCardRequestAmount(requested: 30099), 30000);
      // No longer refused for being outside min/max — there is no such range.
      expect(d.topupCardRequestAmount(requested: 4000), 4000);
      expect(d.topupCardRequestAmount(requested: 60000), 60000);
      // But nothing is still nothing.
      expect(d.topupCardRequestAmount(requested: 50), isNull);
    });
  });

  group('top-up-card entry (deep link into step 3)', () {
    PLoanFlow fromCard() => PLoanFlow(
          hashThaiId: 'H',
          entry: PLoanEntry.topupCard,
          contract: LoanContract.fromJson(_contractJson),
          amountDetail: LoanAmountDetail.fromJson(_amountDetailJson),
        );

    test('the full wizard is the default, so nothing else changes', () {
      expect(PLoanFlow(hashThaiId: 'H').entry, PLoanEntry.wizard);
      expect(PLoanFlow(hashThaiId: 'H').skipsCollateralPhotos, isFalse);
      expect(PLoanFlow(hashThaiId: 'H').totalSteps, 6);
    });

    test('visits only จำนวนงวด → ตรวจสอบข้อมูล → สรุป', () {
      expect(PLoanEntry.topupCard.visitedSteps, [3, 5, 6]);
      // Three screens here, plus the top-up card the customer came from.
      expect(fromCard().totalSteps, 4);
      expect(PLoanEntry.wizard.precedingSteps, 0);
    });

    test('counts the top-up card as step 1, so this build starts at 2', () {
      final card = fromCard();
      // The card is where the contract was picked and the amount shown — the
      // wizard's steps 1–2. Starting at "1 of 3" disowned it.
      expect(card.stepNumber(3), 2);
      expect(card.stepNumber(5), 3);
      expect(card.stepNumber(6), 4);

      // The wizard is untouched: its numbers are already its positions.
      final wizard = _completeFlow();
      for (final step in [1, 2, 3, 4, 5, 6]) {
        expect(wizard.stepNumber(step), step);
      }
    });

    test('a step it does not visit falls back to its own number', () {
      // Step 4 is skipped; asking for its position must not return -1+1 = 0.
      expect(fromCard().stepNumber(4), 4);
    });

    test('skips step 4, so step 3 continues to step 5', () {
      expect(fromCard().skipsCollateralPhotos, isTrue);
      expect(_completeFlow().skipsCollateralPhotos, isFalse);
    });

    test('missing collateral photos never block the submit', () {
      // Step 4 is skipped, so the flow submits with no vehicle photos at all.
      // canSubmit gates on the *identity* photos only — this pins that the
      // skip cannot deadlock the final button.
      final card = fromCard()
        ..customer = CustomerDetail.fromJson(const {'thai_id': '1234567890123'})
        ..verifiedThaiId = '1234567890123'
        ..documents = const LoanDocuments(
            request: 'R', receipt: 'C', agreement: 'A')
        ..consented.addAll(LoanDocumentKind.values)
        ..ndidVerified = true
        ..sensitiveConsent = true;
      card.photos[PLoanPhoto.idCard] = Uint8List.fromList([1]);
      card.photos[PLoanPhoto.selfieWithIdCard] = Uint8List.fromList([2]);

      expect(card.missingVehiclePhoto, isNotNull,
          reason: 'the vehicle shots really are absent');
      expect(card.canSubmit, isTrue,
          reason: 'but step 4 was skipped on purpose, so they must not gate');
    });

    test('it is an Extra, so it keeps the contract and posts to /topup', () {
      final card = fromCard();
      expect(card.kind, PLoanKind.extra);
      expect(card.isNewPLoan, isFalse);
      expect(card.submitTarget, PLoanSubmitTarget.topup);
      expect(card.canGenerateDocuments, isTrue,
          reason: 'an Extra has the contract /pdf/loan is keyed by');
    });
  });

  group('identity verification', () {
    test('accepts only the customer\'s own Thai ID', () {
      final flow = _completeFlow()..verifiedThaiId = '1234567890123';
      expect(flow.isThaiIdVerified, isTrue);
    });

    test('rejects the test IDs the source hardcoded as a bypass', () {
      // These four were whitelisted in the source's step 6, which let anyone
      // holding one of those cards verify against any account.
      for (final id in const [
        '1103000101931',
        '1103701967986',
        '1331400042203',
        '3401700351967',
      ]) {
        final flow = _completeFlow()..verifiedThaiId = id;
        expect(flow.isThaiIdVerified, isFalse, reason: 'ID $id must not pass');
      }
    });

    test('an unverified flow cannot submit', () {
      final flow = _completeFlow();
      flow.photos.remove(PLoanPhoto.idCard);
      expect(flow.canSubmit, isFalse);
      expect(flow.missingIdentityPhoto, PLoanPhoto.idCard);
    });
  });

  group('required photos per loan type', () {
    test('motorcycles need the whole vehicle and the tax disc', () {
      final flow = _completeFlow();
      expect(flow.requiredPhotos,
          [PLoanPhoto.fullVehicle, PLoanPhoto.taxDisc]);
      expect(flow.missingVehiclePhoto, isNull);
    });

    test('cars need four sides, the odometer and the tax disc', () {
      final flow = PLoanFlow(
        hashThaiId: 'H',
        contract: LoanContract.fromJson({
          ..._contractJson,
          'contract_details': {
            ..._contractJson['contract_details'] as Map<String, dynamic>,
            'loan_type_code': 'C',
          },
        }),
      );
      expect(flow.requiredPhotos, hasLength(6));
      expect(flow.requiredPhotos, contains(PLoanPhoto.carMile));
      expect(flow.missingVehiclePhoto, PLoanPhoto.carRight);
    });
  });

  group('consent gating', () {
    test('all three documents must be accepted', () {
      final flow = _completeFlow()
        ..verifiedThaiId = '1234567890123'
        // Step 6 also requires the sensitive-data consent and NDID signing;
        // both granted here so this test isolates the document gate.
        ..sensitiveConsent = true
        ..ndidVerified = true;
      expect(flow.missingConsent, LoanDocumentKind.request);
      expect(flow.canSubmit, isFalse);

      flow.consented.addAll(LoanDocumentKind.values);
      expect(flow.missingConsent, isNull);
      expect(flow.canSubmit, isTrue);
    });

    test('NDID signing gates submit', () {
      final flow = _completeFlow()
        ..consented.addAll(LoanDocumentKind.values)
        ..sensitiveConsent = true
        ..ndidVerified = false;
      expect(flow.canSubmit, isFalse,
          reason: 'the contract documents are not signed yet');

      flow.ndidVerified = true;
      expect(flow.canSubmit, isTrue);
    });
  });

  group('camera actions the host has to recognise', () {
    test('the selfie slot asks for the idCardPlusSelfie mask', () {
      // The host compares this literally: `action.toLowerCase() == 'selfie'`
      // selects the idCardPlusSelfie framing mask and the front camera.
      // 'selfieCamera' did not match, so it silently got the rear-facing
      // idCard mask instead.
      expect(PLoanPhoto.selfieWithIdCard.cameraAction, 'selfie');
    });

    test('every slot names a non-empty action', () {
      for (final slot in PLoanPhoto.values) {
        expect(slot.cameraAction, isNotEmpty, reason: slot.name);
      }
    });
  });

  group('NDID subject', () {
    test('the flow can drive the shared NDID screens', () {
      // The bank-select and verify pages take an NdidSubject, so both this flow
      // and the wizard's LoanRegisterForm can push to them.
      final NdidSubject subject = _completeFlow();
      expect(subject.ndidThaiId, '1234567890123');
      expect(subject.ndidIdpId, isNull);

      subject.ndidIdpId = 'idp1';
      expect((subject as PLoanFlow).ndidIdpId, 'idp1');
    });

    test('the Thai ID falls back to the card read when the profile has none',
        () {
      final flow = PLoanFlow(hashThaiId: 'H')..verifiedThaiId = '9876543210987';
      expect(flow.customerThaiIdDigits, '9876543210987');
    });

    test('prod never substitutes the NDID test identity', () {
      // The uat DAP node only has an identity for kNdidTestThaiId, so non-prod
      // builds verify that instead. On prod the applicant's own id is the only
      // thing NDID may ever be asked about — whatever the define says.
      expect(AppEnvironment.prod.ndidThaiIdOverride, isNull);
      expect(AppEnvironment.uat.ndidThaiIdOverride, kNdidTestThaiId);
    });

    test('the substitution cannot weaken the ID-card check', () {
      // /vision/thai-id-validate is matched against the profile, not against
      // ndidThaiId, so a card belonging to the NDID test identity still fails.
      final flow = _completeFlow()
        ..customer = CustomerDetail.fromJson(const {'thai_id': '9876543210987'})
        ..verifiedThaiId = kNdidTestThaiId;
      expect(flow.isThaiIdVerified, isFalse);

      flow.verifiedThaiId = '9876543210987';
      expect(flow.isThaiIdVerified, isTrue);
    });

    test('a formatted wizard Thai ID is reduced to digits', () {
      // The wizard holds it as 1-2345-... for display; the node wants digits.
      final NdidSubject form = LoanRegisterForm.mock()..thaiId = '1-2345-67890-12-3';
      expect(form.ndidThaiId, '1234567890123');
    });
  });

  group('submission payload', () {
    test('maps the flow onto the wire keys the API expects', () {
      final json = _completeFlow().toSubmissionJson();

      expect(json['db_name'], 'SAWAD01');
      expect(json['contract_no'], 'ญฟC670301001NE54X');
      expect(json['hash_thai_id'], 'HASH123');
      expect(json['loan_amount'], 30000);
      // 30000 - 100 duty. The old contract's 12000 principal is not deducted —
      // this is what used to make transfer_amount negative on a real Extra.
      expect(json['transfer_amount'], 29900);
      expect(json['term_period'], 24);
      expect(json['regular_period'], 1500);
      expect(json['interest_amount'], 6000.0);
      expect(json['total_amount'], 36000.0);
      expect(json['source'], 'app');
      expect(json['refer_id'], 'REF1');
      expect(json['latitude'], '13.88');
      expect(json['longitude'], '100.57');
    });

    test('keeps the API\'s topup_argeement_file misspelling', () {
      final json = _completeFlow().toSubmissionJson();
      // The wire key really is misspelled; "correcting" it drops the document.
      expect(json.containsKey('topup_argeement_file'), isTrue);
      expect(json['topup_argeement_file'], 'AGR_B64');
      expect(json.containsKey('topup_agreement_file'), isFalse);
    });

    test('sends photos as base64 data URLs and blanks the unused slots', () {
      final json = _completeFlow().toSubmissionJson();
      final expected = base64Encode(Uint8List.fromList([1, 2, 3]));
      expect(json['property_image'], 'data:image/jpeg;base64,$expected');
      expect(json['customer_image_2'], startsWith('data:image/jpeg;base64,'));
      // A motorcycle has no car-side photos.
      expect(json['car_image_front'], '');
      expect(json['car_image_mile'], '');
    });

    test('refuses to build a payload from an incomplete flow', () {
      final flow = _completeFlow()..installment = null;
      expect(flow.toSubmissionJson, throwsStateError);
    });
  });

  group('formatting', () {
    test('money uses thousands separators and two decimals', () {
      expect(formatMoney(1234567.5), '1,234,567.50');
      expect(formatMoney(0), '0.00');
      expect(formatMoney(null), '0.00');
      expect(formatMoney(-2500), '-2,500.00');
    });

    test('whole-baht formatting drops the decimals', () {
      expect(formatWholeMoney(35000), '35,000');
      expect(formatWholeMoney(999), '999');
    });

    test('phone numbers group as ###-###-####', () {
      expect(formatPhone('0863652156'), '086-365-2156');
    });

    test('anything not a bare 10-digit number passes through unchanged', () {
      // Forcing the pattern on these would mangle them, so they are left be.
      expect(formatPhone('021234567'), '021234567'); // 9-digit landline
      expect(formatPhone('086-365-2156'), '086-365-2156'); // already grouped
      expect(formatPhone('+66863652156'), '+66863652156'); // country code
      expect(formatPhone(''), '');
      expect(formatPhone(null), '');
    });

    test('dates render Buddhist-era, and bad input renders empty', () {
      expect(formatThaiDate('2026-07-27T10:00:00'), '27/07/2569');
      expect(formatThaiDate(''), '');
      expect(formatThaiDate('null'), '');
      expect(formatThaiDate('not a date'), '');
    });

    test('bank codes map to Thai names, unknown codes pass through', () {
      expect(bankDisplayName('KBANK'), 'ธนาคารกสิกรไทย');
      expect(bankDisplayName('bbl'), 'ธนาคารกรุงเทพ');
      expect(bankDisplayName('MYSTERY'), 'MYSTERY');
    });

    test('typed amounts survive thousands separators', () {
      expect(parseAmount('30,000'), 30000);
      expect(parseAmount(' 30000 '), 30000);
      expect(parseAmount('abc'), 0);
    });
  });
}
