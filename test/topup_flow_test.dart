import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/config/app_environment.dart';
import 'package:sawad_loan_universal/models/app_config.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_amount_detail.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_contract.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_documents.dart';
import 'package:sawad_loan_universal/p_loan/application/models/p_loan_flow.dart';
import 'package:sawad_loan_universal/p_loan/application/models/p_loan_mock.dart';
import 'package:sawad_loan_universal/topup/models/topup_card_variant.dart';
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

    test('the collateral screen does NOT use the camera bridge', () {
      // Step 5 deliberately takes the plain `image_picker` camera: the host
      // applies its ID-card framing mask to every action but 'selfie', which
      // is the wrong frame for a vehicle, a tax disc or an odometer. Step 7
      // keeps the bridge, where the masks are right.
      //
      // Asserted on the source because the difference is a call site, not a
      // value — and it is the kind of thing a later "tidy up the two capture
      // paths" would quietly undo.
      final photos = File('lib/topup/topup_photos_page.dart').readAsStringSync();
      expect(photos.contains('NativeCameraBridge'), isFalse,
          reason: 'step 5 must not capture through the host camera bridge');
      expect(photos.contains('ImageDownscale.jpeg'), isTrue,
          reason: 'image_picker_for_web ignores maxWidth/imageQuality, so the '
              'capture has to be downscaled before it reaches the payload');

      final conclusion =
          File('lib/topup/topup_conclusion_page.dart').readAsStringSync();
      expect(conclusion.contains('NativeCameraBridge'), isTrue,
          reason: 'step 7 keeps the bridge for the ID-card and selfie masks');
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

  group('deduction list — the numbered rows on the amount screen', () {
    test('no unpaid interest: items 1 and 2 only', () {
      final flow = _flowFor('MOCK-C-6701002');
      expect(flow.deductionLines.map((l) => l.number), ['1', '2']);
      // จำนวนเงินที่จะได้รับ is then just the payout.
      expect(flow.receivableAmount, flow.payoutAmount);
      expect(flow.overdueDeduction, 0);
    });

    test('unpaid interest adds item 3 and item 5 with its two children', () {
      final flow = _flowFor(
        'MOCK-C-6701002',
        detailOverrides: {'interest_paid_flag': 'Y', 'collection_fee': 38.0},
      );
      final numbers = flow.deductionLines.map((l) => l.number).toList();
      // ⚠ 4 is absent because overdue_amount is 0 — the list really does read
      // 1, 2, 3, 5. See TopupFlow.deductionLines.
      expect(numbers, ['1', '2', '3', '5']);

      final item5 = flow.deductionLines.last;
      expect(item5.children.map((c) => c.number), ['5.1', '5.2']);
      expect(item5.amount, flow.overdueDeduction);
      expect(item5.amount, 1200 + 38.0);
    });

    test('item 4 appears only with a non-zero overdue amount', () {
      final flow = _flowFor(
        'MOCK-C-6701002',
        detailOverrides: {
          'interest_paid_flag': 'Y',
          'overdue_amount': 1250.0,
          'overdue_from': '3',
          'overdue_to': '5',
        },
      );
      final item4 =
          flow.deductionLines.firstWhere((l) => l.number == '4');
      expect(item4.amount, 1250);
      // The source prints overdue_to–overdue_from, in that order.
      expect(item4.label, contains('(5-3)'));
    });

    test('receivable is item 3 less item 5', () {
      final flow = _flowFor(
        'MOCK-C-6701002',
        detailOverrides: {'interest_paid_flag': 'Y', 'collection_fee': 38.0},
      );
      expect(flow.receivableAmount, flow.payoutAmount - flow.overdueDeduction);
    });

    test(
        'receivable and netTransfer differ when nothing is overdue — the '
        'collection fee is unconditional in the eligibility check only', () {
      final flow = _flowFor(
        'MOCK-C-6701002',
        detailOverrides: {'interest_paid_flag': 'N', 'collection_fee': 38.0},
      );
      expect(flow.receivableAmount, flow.payoutAmount);
      expect(flow.netTransferAmount, flow.payoutAmount - 38.0);
    });
  });

  group('decimal money fields', () {
    test('yield, collection fee and penalty fee keep their decimals', () {
      // Truncating these to int misstates what /payment/interest is billed
      // for and changes the JSON type the server is handed — which is what
      // made that call 500.
      final detail = LoanAmountDetail.fromJson(const {
        'code': '200',
        'yield': 2987.84,
        'collection_fee': 38.0,
        'penalty_fee': 12.5,
      });
      expect(detail.interestYield, 2987.84);
      expect(detail.collectionFee, 38.0);
      expect(detail.penaltyFee, 12.5);
    });

    test('the contract copy keeps them too', () {
      final contract = LoanContract.fromJson(const {
        'topup_detail': {
          'yield': 2987.84,
          'collection_fee': 38.0,
          'penalty_fee': 12.5,
        },
      });
      expect(contract.topupDetail.interestYield, 2987.84);
      expect(contract.topupDetail.collectionFee, 38.0);
      expect(contract.topupDetail.penaltyFee, 12.5);
    });

    test('a string amount still parses', () {
      final detail = LoanAmountDetail.fromJson(const {
        'code': '200',
        'yield': '2987.84',
      });
      expect(detail.interestYield, 2987.84);
    });
  });

  group('the product a tile picks rides on the flow', () {
    // There is no วัตถุประสงค์ screen — the card settles this, so the value
    // is constructed there rather than chosen on a page of its own.
    test('no product means a plain top-up, and an editable amount', () {
      final flow = _flowFor('MOCK-C-6701002');
      expect(flow.purpose, isNull);
      expect(flow.isAmountEditable, isTrue);
    });

    test('a picked product fixes the amount', () {
      final flow = _flowFor('MOCK-C-6701002')
        ..purpose = const TopupPurpose(
          productCode: 'INS001',
          productName: 'ประกันภัย',
          productDescription: '',
          productPrice: 3000,
        );
      // A named product is priced by the product, so the field locks.
      expect(flow.isAmountEditable, isFalse);
    });

    test('the catch-all code stays editable', () {
      final flow = _flowFor('MOCK-C-6701002')
        ..purpose = const TopupPurpose(
          productCode: kTopupOtherProductCode,
          productName: 'อื่นๆ',
          productDescription: '',
          productPrice: 20000,
        );
      expect(flow.isAmountEditable, isTrue);
    });
  });

  group('contract card — three header variants', () {
    LoanContract withTopupDetail(Map<String, dynamic> overrides) {
      final base = mockContracts().first.rawJson;
      return LoanContract.fromJson({
        ...base,
        'topup_detail': {
          ...(base['topup_detail'] as Map<String, dynamic>),
          ...overrides,
        },
      });
    }

    const product = {
      'product_code': 'INS001',
      'product_name': 'ประกันภัย',
      'product_description': '',
      'product_price': 3000,
    };

    test('can_topup N wins over everything, products included', () {
      final contract =
          withTopupDetail({'can_topup': 'N', 'products': [product]});
      expect(TopupCardVariant.of(contract), TopupCardVariant.ineligible);
      // …and the offer grid is withheld with it.
      expect(showsSpecialOffers(contract), isFalse);
    });

    test('products give the special-offer header', () {
      final contract = withTopupDetail({'products': [product]});
      expect(TopupCardVariant.of(contract), TopupCardVariant.specialOffer);
      expect(showsSpecialOffers(contract), isTrue);
    });

    test('no products gives the plain header', () {
      expect(
        TopupCardVariant.of(withTopupDetail(const {'products': []})),
        TopupCardVariant.plain,
      );
    });

    test('an all-empty product entry does not count as an offer', () {
      // The API pads the array; an entry with no code and no name is not a
      // product and must not flip the card into its offer layout.
      final contract = withTopupDetail(const {
        'products': [
          {'product_code': '', 'product_name': '', 'product_price': 0},
        ],
      });
      expect(TopupCardVariant.of(contract), TopupCardVariant.plain);
      expect(showsSpecialOffers(contract), isFalse);
    });

    test('a request already in flight withholds the grid but not the header',
        () {
      final base = mockContracts().first.rawJson;
      final contract = LoanContract.fromJson({
        ...base,
        'request_status': 'รอตรวจสอบ',
        'topup_detail': {
          ...(base['topup_detail'] as Map<String, dynamic>),
          'products': [product],
        },
      });
      expect(contract.hasNoRequestYet, isFalse);
      // Picking a product would start a request the contract cannot take.
      expect(showsSpecialOffers(contract), isFalse);
      expect(TopupCardVariant.of(contract), TopupCardVariant.specialOffer);
    });
  });

  group('product icons come from the runtime config', () {
    test('a mapped code resolves to its own icon', () {
      const config = AppConfig(
        topupProductIcons: {'PLD001': 'https://x/bag.svg'},
        topupProductIconDefault: 'https://x/default.svg',
      );
      expect(config.topupProductIcon('PLD001'), 'https://x/bag.svg');
    });

    test('an unmapped code falls back to the default', () {
      const config = AppConfig(
        topupProductIcons: {'PLD001': 'https://x/bag.svg'},
        topupProductIconDefault: 'https://x/default.svg',
      );
      expect(config.topupProductIcon('ZZZ999'), 'https://x/default.svg');
    });

    test('no config at all resolves to null, not an empty URL', () {
      // The tile renders its built-in icon rather than a broken image.
      expect(const AppConfig().topupProductIcon('PLD001'), isNull);
    });

    test('decodes the map and the default from the document', () {
      final config = AppConfig.fromDecoded(const {
        'topup_product_icons': {'PLD001': 'a', 'GLD001': 'b'},
        'topup_product_icon_default': 'd',
      });
      expect(config.topupProductIcons, {'PLD001': 'a', 'GLD001': 'b'});
      expect(config.topupProductIconDefault, 'd');
    });

    test('a document without the fields decodes to empty, not a throw', () {
      final config = AppConfig.fromDecoded(const {'api_url': {}});
      expect(config.topupProductIcons, isEmpty);
      expect(config.topupProductIconDefault, isNull);
    });
  });

  group('config keys separate uat from prod by field name', () {
    // The tests run with no ENV define, which resolves to uat — see
    // AppEnvironment.current. So `_uat` keys win here and bare keys are the
    // fallback, which is exactly the uat behaviour worth pinning.
    test('a _uat key beats the bare one', () {
      final config = AppConfig.fromDecoded(const {
        'api_url': {
          'ndid_url_base': 'https://prod.gateway',
          'ndid_url_base_uat': 'https://uat.gateway',
        },
      });
      expect(config.ndidUrlBase, 'https://uat.gateway');
    });

    test('the bare key is the fallback when no _uat variant exists', () {
      final config = AppConfig.fromDecoded(const {
        'api_url': {'ndid_url_base': 'https://only.one'},
      });
      expect(config.ndidUrlBase, 'https://only.one');
    });

    test('an empty _uat value does not shadow a real bare one', () {
      final config = AppConfig.fromDecoded(const {
        'api_url': {
          'ndid_url_base': 'https://real',
          'ndid_url_base_uat': '   ',
        },
      });
      expect(config.ndidUrlBase, 'https://real');
    });

    test('the mobile API prefers the per-environment pair over api_url_base',
        () {
      // api_url_base names no environment, so a document carrying both must
      // resolve to the one that does.
      final config = AppConfig.fromDecoded(const {
        'api_url': {
          'api_url_base': 'https://neutral',
          'api_url_prod': 'https://prod',
          'api_url_dev': 'https://dev',
        },
      });
      expect(config.apiUrlForEnvironment, 'https://dev');
      expect(config.apiUrlBase, 'https://neutral');
    });

    test('api_url_base still resolves when the pair is absent', () {
      final config = AppConfig.fromDecoded(const {
        'api_url': {'api_url_base': 'https://only-base'},
      });
      expect(config.apiUrlForEnvironment, isNull);
      expect(config.apiUrlBase, 'https://only-base');
    });

    test('a _uat icon map overrides the bare one', () {
      final config = AppConfig.fromDecoded(const {
        'topup_product_icons': {'PLD001': 'prod.svg'},
        'topup_product_icons_uat': {'PLD001': 'uat.svg'},
      });
      expect(config.topupProductIcon('PLD001'), 'uat.svg');
    });

    test('an empty _uat icon map falls back rather than blanking the tiles',
        () {
      final config = AppConfig.fromDecoded(const {
        'topup_product_icons': {'PLD001': 'prod.svg'},
        'topup_product_icons_uat': <String, dynamic>{},
      });
      expect(config.topupProductIcon('PLD001'), 'prod.svg');
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
