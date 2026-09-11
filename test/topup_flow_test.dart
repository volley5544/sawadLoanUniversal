import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/config/app_environment.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_amount_detail.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_contract.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_documents.dart';
import 'package:sawad_loan_universal/p_loan/application/models/p_loan_flow.dart';
import 'package:sawad_loan_universal/p_loan/application/models/p_loan_mock.dart';
import 'package:sawad_loan_universal/topup/models/topup_flow.dart';
import 'package:sawad_loan_universal/topup/models/topup_photo.dart';
import 'package:sawad_loan_universal/topup/models/topup_purpose.dart';
import 'package:sawad_loan_universal/topup/models/topup_status.dart';

/// The mock contracts carry no `max_transfer_amount`, and **0 means every
/// contract files a lead** — `netTransferAmount > 0` is always true. That is
/// the source's rule reproduced exactly (see [TopupFlow.outcome]), so the
/// fixture has to supply a realistic ceiling for the ordinary path to be
/// reachable at all.
const int _maxTransferAmount = 5000000;

/// A flow priced against [contractNo], ready for the assertions below.
TopupFlow _flowFor(String contractNo, {Map<String, dynamic>? detailOverrides}) {
  final base =
      mockContracts().firstWhere((c) => c.contractNo == contractNo).rawJson;
  final contract = LoanContract.fromJson({
    ...base,
    'topup_detail': {
      ...(base['topup_detail'] as Map<String, dynamic>),
      'max_transfer_amount': _maxTransferAmount,
    },
  });
  var detail = mockAmountDetail(contractNo);
  if (detailOverrides != null) {
    detail = LoanAmountDetail.fromJson({
      ..._detailJson(contractNo),
      ...detailOverrides,
    });
  }
  final plan = mockInstallmentPlan(detail.defaultTopupAmount);
  final flow = TopupFlow(hashThaiId: 'HASH', authToken: 'TOKEN')
    ..contract = contract
    ..customer = mockCustomer()
    // Step 3 folds the calculator's duty back into the detail (it is the duty
    // for the amount actually requested, not for the contract's default), so
    // the fixture has to do the same or the two disagree about `feeAmount`.
    ..amountDetail = detail.copyWith(feeAmount: plan.feeAmount)
    ..requestedAmount = detail.defaultTopupAmount
    ..plan = plan;
  flow.installment = plan.installments.first;
  return flow;
}

/// The raw `/topup/detail` JSON the mock builds, so a test can vary one field
/// without restating the other twenty.
Map<String, dynamic> _detailJson(String contractNo) {
  final detail = mockAmountDetail(contractNo);
  final contract =
      mockContracts().firstWhere((c) => c.contractNo == contractNo);
  return {
    'code': '200',
    'db_name': detail.dbName,
    'contract_no': detail.contractNo,
    'contract_details': contract.rawJson['contract_details'],
    'car_details': contract.rawJson['car_details'],
    'first_due_date': detail.firstDueDate,
    'due_day': detail.dueDay,
    'contract_date': detail.contractDate,
    'default_topup_amount': detail.defaultTopupAmount,
    'min_topup_amount': detail.minTopupAmount,
    'max_topup_amount': detail.maxTopupAmount,
    'interest_rate': detail.interestRate,
    'fee_amount': detail.feeAmount,
    'balance_receivable': detail.balanceReceivable,
    'topup_extra': detail.topupExtra,
    'interest_paid_flag': detail.interestPaidFlag,
    'yield': detail.interestYield,
    'life_insure_amt': detail.lifeInsureAmt,
  };
}

/// Fills every photo the flow requires plus both identity shots.
void _captureAllPhotos(TopupFlow flow) {
  final bytes = Uint8List.fromList([1, 2, 3]);
  for (final slot in [...flow.requiredPhotos, ...TopupPhoto.identity]) {
    flow.photos[slot] = bytes;
  }
}

/// Brings a flow to the point where only [canSubmit]'s last gate is missing.
TopupFlow _submittableFlow() {
  final flow = _flowFor('MOCK-C-6701002')
    ..documents = mockDocuments()
    ..verifiedThaiId = mockCustomer().thaiId
    ..sensitiveConsent = true;
  flow.consentedDocuments.addAll(LoanDocumentKind.values);
  _captureAllPhotos(flow);
  return flow;
}

void main() {
  group('payout — a top-up is not a P-Loan Extra', () {
    test('payoutAmount deducts the old principal and the duty', () {
      final flow = _flowFor('MOCK-C-6701002');
      // 400,000 requested − 180,000 closing balance − 100 duty.
      expect(flow.calculatedAmount, 400000);
      expect(flow.closingBalance, 180000);
      expect(flow.feeAmount, 100);
      expect(flow.payoutAmount, 400000 - 180000 - 100);
    });

    test(
        'it differs from PLoanFlow.payoutAmount, which deducts no principal '
        '— the two products price differently and must not be merged', () {
      final contract =
          mockContracts().firstWhere((c) => c.contractNo == 'MOCK-C-6701002');
      final detail = mockAmountDetail('MOCK-C-6701002');

      final plan = mockInstallmentPlan(detail.defaultTopupAmount);
      final topup = _flowFor('MOCK-C-6701002');
      final extra = PLoanFlow(
        hashThaiId: 'HASH',
        kind: PLoanKind.extra,
        authToken: 'TOKEN',
        contract: contract,
      )
        ..amountDetail = detail.copyWith(feeAmount: plan.feeAmount)
        ..requestedAmount = detail.defaultTopupAmount
        ..plan = plan;

      // Same amount, same duty — the only difference is the old principal.
      expect(extra.payoutAmount, topup.calculatedAmount - topup.feeAmount);
      expect(topup.payoutAmount, extra.payoutAmount - topup.closingBalance);
      expect(topup.payoutAmount, lessThan(extra.payoutAmount));
    });

    test('netTransferAmount additionally nets off interest and the fee', () {
      final flow = _flowFor(
        'MOCK-C-6701002',
        detailOverrides: {'interest_paid_flag': 'Y', 'collection_fee': 300},
      );
      expect(flow.outstandingInterest, 1200);
      expect(flow.netTransferAmount, flow.payoutAmount - 1200 - 300);
    });
  });

  group('amount range — unlike a P-Loan Extra, min/max apply', () {
    test('accepts an amount inside the contract range', () {
      final flow = _flowFor('MOCK-C-6701002')..requestedAmount = 100000;
      expect(flow.isRequestedAmountAllowed, isTrue);
    });

    test('rejects below the floor and above the ceiling', () {
      final flow = _flowFor('MOCK-C-6701002');
      final detail = flow.amountDetail!;
      flow.requestedAmount = detail.minTopupAmount - 100;
      expect(flow.isRequestedAmountAllowed, isFalse);
      flow.requestedAmount = detail.maxTopupAmount + 100;
      expect(flow.isRequestedAmountAllowed, isFalse);
    });
  });

  group('special limit', () {
    test('applySpecialLimit raises both the default and the ceiling', () {
      final contract = LoanContract.fromJson({
        ...mockContracts().first.rawJson,
        'topup_special_flag': true,
        'topup_detail': {
          ...(mockContracts().first.rawJson['topup_detail']
              as Map<String, dynamic>),
          'topup_specials': 5000,
        },
      });
      final flow = TopupFlow(hashThaiId: 'H', authToken: 'T')
        ..contract = contract
        ..amountDetail = mockAmountDetail('MOCK-M-6701001');
      final before = flow.amountDetail!;
      flow.applySpecialLimit();
      final after = flow.amountDetail!;

      expect(after.defaultTopupAmount, before.defaultTopupAmount + 5000);
      expect(after.maxTopupAmount, before.maxTopupAmount + 5000);
      expect(after.topupSpecials, 5000);
    });

    test('does nothing when the contract carries no special flag', () {
      final flow = TopupFlow(hashThaiId: 'H', authToken: 'T')
        ..contract = mockContracts().first
        ..amountDetail = mockAmountDetail('MOCK-M-6701001');
      final before = flow.amountDetail!.defaultTopupAmount;
      flow.applySpecialLimit();
      expect(flow.amountDetail!.defaultTopupAmount, before);
    });
  });

  group('outcome — which of the three things the primary button does', () {
    test('a healthy contract continues into the wizard', () {
      expect(_flowFor('MOCK-C-6701002').outcome, TopupOutcome.topup);
      expect(_flowFor('MOCK-C-6701002').primaryActionLabel, 'ถัดไป');
    });

    test('unpaid accrued interest must be settled first', () {
      final flow = _flowFor(
        'MOCK-C-6701002',
        detailOverrides: {'interest_paid_flag': 'Y'},
      );
      expect(flow.hasUnpaidInterest, isTrue);
      expect(flow.outcome, TopupOutcome.payInterest);
      expect(flow.primaryActionLabel, 'ชำระเงิน');
      // The field locks, so the amount cannot be edited into a top-up.
      expect(flow.isAmountEditable, isFalse);
    });

    test('a can_topup refusal after the detail call files a lead', () {
      final flow = _flowFor(
        'MOCK-C-6701002',
        detailOverrides: {
          'contract_details': {
            ...(mockContracts()
                .firstWhere((c) => c.contractNo == 'MOCK-C-6701002')
                .rawJson['contract_details'] as Map<String, dynamic>),
            'can_topup': 'N',
          },
        },
      );
      expect(flow.outcome, TopupOutcome.lead);
      expect(flow.primaryActionLabel, 'ส่งข้อมูล');
    });

    test('land and house loan types are never self-served', () {
      for (final code in ['L', 'H']) {
        final base = mockContracts()
            .firstWhere((c) => c.contractNo == 'MOCK-C-6701002')
            .rawJson;
        final contract = LoanContract.fromJson({
          ...base,
          'contract_details': {
            ...(base['contract_details'] as Map<String, dynamic>),
            'loan_type_code': code,
          },
        });
        final flow = _flowFor('MOCK-C-6701002')..contract = contract;
        expect(flow.outcome, TopupOutcome.lead, reason: 'loan type $code');
      }
    });

    test('a payout above max_transfer_amount files a lead', () {
      final base = mockContracts()
          .firstWhere((c) => c.contractNo == 'MOCK-C-6701002')
          .rawJson;
      final contract = LoanContract.fromJson({
        ...base,
        'topup_detail': {
          ...(base['topup_detail'] as Map<String, dynamic>),
          'max_transfer_amount': 1000,
        },
      });
      final flow = _flowFor('MOCK-C-6701002')..contract = contract;
      expect(flow.netTransferAmount, greaterThan(1000));
      expect(flow.outcome, TopupOutcome.lead);
    });

    test('an absent max_transfer_amount means 0, so everything is a lead', () {
      // Reproduced from the source, and easy to mistake for a bug: with the
      // field missing the ceiling is 0 and no payout can be under it. Worth a
      // test so the behaviour is a decision on record rather than a surprise.
      final flow = _flowFor('MOCK-C-6701002')
        ..contract = mockContracts()
            .firstWhere((c) => c.contractNo == 'MOCK-C-6701002');
      expect(flow.maxTransferAmount, 0);
      expect(flow.outcome, TopupOutcome.lead);
    });
  });

  group('required photos follow the loan type', () {
    test('a motorcycle needs the whole vehicle and the tax disc', () {
      expect(
        _flowFor('MOCK-M-6701001').requiredPhotos,
        [TopupPhoto.fullVehicle, TopupPhoto.taxDisc],
      );
    });

    test('a car needs four sides, the odometer and the tax disc', () {
      expect(_flowFor('MOCK-C-6701002').requiredPhotos, hasLength(6));
    });

    test('any other loan type stays completable with the tax disc alone', () {
      final base = mockContracts().first.rawJson;
      final contract = LoanContract.fromJson({
        ...base,
        'contract_details': {
          ...(base['contract_details'] as Map<String, dynamic>),
          'loan_type_code': 'X',
        },
      });
      final flow = TopupFlow(hashThaiId: 'H', authToken: 'T')
        ..contract = contract;
      expect(flow.requiredPhotos, [TopupPhoto.taxDisc]);
    });
  });

  group('camera actions must match the host vocabulary exactly', () {
    // The host compares `action.toLowerCase() == 'selfie'` and falls through to
    // the rear ID-card mask for everything else, so a near-miss here fails
    // silently with the wrong camera. That exact bug cost the P-Loan flow its
    // front camera once already.
    test('the selfie slot asks for the front camera', () {
      expect(TopupPhoto.selfieWithIdCard.cameraAction, 'selfie');
    });

    test('every action is non-empty and distinct', () {
      final actions = TopupPhoto.values.map((p) => p.cameraAction).toList();
      expect(actions.where((a) => a.isEmpty), isEmpty);
      expect(actions.toSet(), hasLength(actions.length));
    });
  });

  group('identity', () {
    test('the scanned card must match the customer on file', () {
      final flow = _flowFor('MOCK-C-6701002')
        ..verifiedThaiId = mockCustomer().thaiId;
      expect(flow.isThaiIdVerified, isTrue);
    });

    test('the source\'s four hardcoded Thai IDs are NOT accepted', () {
      // These let anyone holding one of those cards verify for *any* account.
      const backdoorIds = [
        '1103000101931',
        '1103701967986',
        '1331400042203',
        '3401700351967',
      ];
      for (final id in backdoorIds) {
        final flow = _flowFor('MOCK-C-6701002')..verifiedThaiId = id;
        expect(flow.isThaiIdVerified, isFalse, reason: id);
      }
    });

    test('an unverified id blocks submit', () {
      final flow = _submittableFlow()..verifiedThaiId = '';
      expect(flow.canSubmit, isFalse);
    });
  });

  group('canSubmit and its reasons', () {
    test('a complete flow can submit', () {
      expect(_submittableFlow().canSubmit, isTrue);
      expect(_submittableFlow().submitBlockedReason, isNull);
    });

    test('missing documents block first', () {
      final flow = _submittableFlow()..documents = null;
      expect(flow.canSubmit, isFalse);
      expect(flow.submitBlockedReason, contains('เอกสาร'));
    });

    test('an unaccepted document names that document', () {
      final flow = _submittableFlow()
        ..consentedDocuments.remove(LoanDocumentKind.agreement);
      expect(flow.canSubmit, isFalse);
      expect(flow.submitBlockedReason,
          LoanDocumentKind.agreement.consentPrompt);
    });

    test('a missing collateral photo names that photo', () {
      final flow = _submittableFlow()..photos.remove(TopupPhoto.carMile);
      expect(flow.canSubmit, isFalse);
      expect(flow.submitBlockedReason, TopupPhoto.carMile.missingMessage);
    });

    test('the sensitive-data consent is required and marketing is not', () {
      final blocked = _submittableFlow()..sensitiveConsent = false;
      expect(blocked.canSubmit, isFalse);

      final optedOut = _submittableFlow()..marketingConsent = false;
      expect(optedOut.canSubmit, isTrue);
    });
  });

  group('purpose options', () {
    test('the contract\'s products are offered plus a synthesised อื่นๆ', () {
      final base = mockContracts().first.rawJson;
      final contract = LoanContract.fromJson({
        ...base,
        'topup_detail': {
          ...(base['topup_detail'] as Map<String, dynamic>),
          'products': [
            {
              'product_code': 'INS001',
              'product_name': 'ประกันภัย',
              'product_description': '',
              'product_price': 3000,
            },
          ],
        },
      });
      final options = TopupPurpose.forContract(contract);
      expect(options, hasLength(2));
      expect(options.first.productCode, 'INS001');
      expect(options.last.productCode, kTopupOtherProductCode);
      expect(options.last.isOther, isTrue);
      // อื่นๆ is priced at the contract's default limit.
      expect(options.last.productPrice,
          contract.topupDetail.defaultTopupAmount);
    });

    test('building the list twice does not grow the contract\'s own list', () {
      // The source appended อื่นๆ straight onto `topup_detail.products`, so the
      // option list grew by one every time the screen was opened.
      final contract = mockContracts().first;
      final before = contract.topupDetail.products.length;
      TopupPurpose.forContract(contract);
      TopupPurpose.forContract(contract);
      expect(contract.topupDetail.products.length, before);
    });
  });

  group('status model', () {
    test('parses the wire keys, misspelling included', () {
      final status = TopupStatus.fromJson(const {
        'code': '200',
        'contract_no': 'C-1',
        'request_status': 'รอตรวจสอบ',
        'amount': '25000',
        'actual_receive_amount': 12000,
        'installment_number': 24,
        'interest_rate': '1.09',
        'topup_request_file': 'UkVR',
        'topup_argeement_file': 'QUdS',
        'topup_receipt_file': 'UkNQ',
      });
      expect(status.isOk, isTrue);
      expect(status.amount, 25000);
      expect(status.interestRate, 1.09);
      // `topup_argeement_file` is the real key — not a typo on our side.
      expect(status.agreementFile, 'QUdS');
      expect(status.hasDocuments, isTrue);
      expect(status.documents.agreement, 'QUdS');
    });

    test('a non-200 code is not ok', () {
      expect(
        TopupStatus.fromJson(const {'code': '404', 'message': 'Not Found'})
            .isOk,
        isFalse,
      );
    });
  });

  group('mock mode', () {
    test('is off by default, so a deployment cannot serve fixtures', () {
      expect(kPLoanUseMockData, isFalse);
    });

    test('every top-up write path is behind the same guard', () {
      // The guard that matters: without it a `P_LOAN_MOCK=true` demo build
      // would really file a top-up, really raise an interest payment and
      // really create a lead. Asserted on the source rather than by calling
      // the methods, since calling them would need a live base URL.
      final source = File('lib/services/topup_api.dart').readAsStringSync();
      for (final method in [
        'submit(',
        'payInterest(',
        'saveLead(',
        'fetchDetail(',
        'calculateInstallments(',
        'fetchStatusDetail(',
      ]) {
        final at = source.indexOf('static Future');
        expect(at, greaterThan(-1));
        final body = source.substring(source.indexOf(method));
        final guardAt = body.indexOf('if (kPLoanUseMockData)');
        final nextMethod = body.indexOf('static Future', 1);
        expect(
          guardAt >= 0 && (nextMethod < 0 || guardAt < nextMethod),
          isTrue,
          reason: '$method has no kPLoanUseMockData guard before its request',
        );
      }
    });
  });

  group('security posture', () {
    test('no lead-service credential ships in the bundle', () {
      // The source hardcoded an x-api-key and a bearer for the lead endpoint.
      // Shipping either would put a shared service credential in a web build
      // anyone can read — the finding that deleting kPLoanSaveApiAuth closed.
      expect(kTopupLeadApiKey, isEmpty);
      expect(kTopupLeadApiAuth, isEmpty);
      expect(kTopupLeadApiConfigured, isFalse);
    });
  });
}
