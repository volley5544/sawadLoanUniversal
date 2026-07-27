import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
    contract: LoanContract.fromJson(_contractJson),
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
    test('payout deducts old principal and stamp duty', () {
      final detail = LoanAmountDetail.fromJson(_amountDetailJson);
      // 30000 - 12000 closing balance - 100 fee
      expect(detail.payoutFor(30000), 17900);
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

    test('a new P-Loan deducts only the duty, not an old principal', () {
      final extra = _completeFlow();
      final fresh = _completeFlow(kind: PLoanKind.newLoan);
      // 30000 - 12000 closing balance - 100 fee
      expect(extra.payoutAmount, 17900);
      // 30000 - 100 fee; there is no old contract to clear.
      expect(fresh.payoutAmount, 29900);
    });

    test('a new P-Loan does not inherit the contract\'s top-up bounds', () {
      // 80000 is well above the reference contract's max_topup_amount (50000).
      final extra = _completeFlow()..requestedAmount = 80000;
      final fresh = _completeFlow(kind: PLoanKind.newLoan)
        ..requestedAmount = 80000;
      expect(extra.isRequestedAmountAllowed, isFalse);
      expect(fresh.isRequestedAmountAllowed, isTrue,
          reason: 'the customer names the amount for a new loan');
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
      expect(flow.ndidThaiId, '9876543210987');
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
      // 30000 - 12000 - 100
      expect(json['transfer_amount'], 17900);
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
