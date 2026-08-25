import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_amount_detail.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_documents.dart';
import 'package:sawad_loan_universal/p_loan/application/models/p_loan_flow.dart';
import 'package:sawad_loan_universal/p_loan/application/models/p_loan_mock.dart';
import 'package:sawad_loan_universal/p_loan/application/models/p_loan_submission.dart';

/// The 34 scalar fields `regmast_ploan.php` takes, copied from `_sections` in
/// `p_loan/submit_form/p_loan_form_page.dart`. The point of this file is that
/// the wizard can produce every one of them, so the two lists must not drift.
const _formFields = <String>{
  // ข้อมูลรายการ
  'transNo', 'transDate', 'statusCode', 'empId', 'branchID', 'refContractNo',
  'mktChannel', 'customerSource',
  // ข้อมูลลูกค้า
  'citizenId', 'test', 'mobileNo', 'registerYear',
  // ข้อมูลสินเชื่อ
  'requestCredit', 'creditAmt', 'loanAmt', 'termPeriod', 'totalAmt', 'intAmt',
  'intRate', 'regularPeriod', 'lastPeriod', 'lastPeriodPromo', 'payDay',
  'initialDate',
  // ข้อมูลการโอนเงิน
  'bankCode', 'bankAccNo', 'transferAmt',
  // ตำแหน่ง GPS
  'gpsProvinceId', 'gpsAumphurId', 'longitude', 'latitude',
  // ความยินยอมและอื่น ๆ
  'marketingConsent', 'sensitiveConsent', 'remark',
};

/// The 30 form fields `POST /SavePloanContract` takes, copied from the API's
/// own sample call in `etc/api.txt`. Near-identical to the regmast set above,
/// but not the same — hence a second mapper rather than reusing one.
const _saveApiFields = <String>{
  'refContractNo', 'citizenId', 'mobileNo', 'firstName', 'lastName',
  'creditAmt', 'loanAmt', 'requestCredit', 'termPeriod', 'totalAmt', 'intAmt',
  'intRate', 'regularPeriod', 'lastPeriod', 'bankCode', 'bankAccNo',
  'bankAccName', 'transferAmt', 'statusCode', 'gpsAumphurId', 'gpsProvinceId',
  'latitude', 'longitude', 'empId', 'branchId', 'mktChannel', 'customerSource',
  'registerYear', 'marketingConsent', 'sensitiveConsent',
};

/// The 31st field, added 2026-08-14 — not in the sample call, so it is listed
/// separately rather than folded into the set above. That keeps the sample's own
/// 30 pinned as the sample's, and makes any future addition visible as an
/// addition.
///
/// **snake_case on purpose**, unlike its 30 camelCase neighbours: it is the name
/// the API asked for.
const _saveApiNdidFields = <String>{'ndid_reference_id'};

const _saveApiAllFields = <String>{..._saveApiFields, ..._saveApiNdidFields};

/// Those 30 stay **form fields**; the files added on 2026-08-07 go as real
/// multipart file parts beside them — `cardIdImage`, `customerImage` and
/// `documentImage[]` ×3 (the contract PDFs). See the `file parts` group.

/// The 12 image groups from `_imageGroups` in the same file.
const _formImageGroups = <String>{
  'documentImage', 'eSignatureImage', 'bookBankImage', 'cardIdImage',
  'carBookImage', 'carImage', 'requestDocImage', 'customerImage',
  'coBorrowCenSusImage', 'coBorrowCardIdImage', 'coCustomerImage',
  'coBorrowRequestDocImage',
};

Uint8List _bytes(int seed) => Uint8List.fromList([seed, seed + 1, seed + 2]);

/// A flow filled the way a completed motorcycle application would be.
PLoanFlow _completedFlow({PLoanKind kind = PLoanKind.extra}) {
  final contract = mockContracts().firstWhere(
      (c) => c.contractDetails.loanTypeCode == 'M');
  final detail = mockAmountDetail(contract.contractNo);
  final plan = mockInstallmentPlan(30000);

  final flow = PLoanFlow(
    hashThaiId: 'HASH',
    kind: kind,
    authToken: 'TOKEN',
    source: 'app',
    referId: 'REF',
    customer: mockCustomer(),
    // Extra only — a new P-Loan is raised against no contract.
    contract: kind == PLoanKind.extra ? contract : null,
    amountDetail: detail,
    empId: '9472',
    mktChannel: '065',
    customerSource: '9',
    gpsProvinceId: '10',
    gpsAumphurId: '1041',
  )
    ..requestedAmount = 30000
    ..plan = plan
    ..latitude = '13.8890019'
    ..longitude = '100.5755956'
    ..documents = mockDocuments()
    ..transNo = 'TX-1'
    // A completed application has been through NDID, so it holds the
    // reference that proves it — the value `POST /ploan` gets as
    // `ndid_reference_id`.
    ..ndidReferenceId = '9bcc18bb-9bb4-4302-8c48-514a17c08e08'
    ..marketingConsent = true
    ..sensitiveConsent = true;
  flow.installment = plan.installments.firstWhere((i) => i.tenor == 24);
  flow.photos[PLoanPhoto.fullVehicle] = _bytes(1);
  flow.photos[PLoanPhoto.taxDisc] = _bytes(10);
  flow.photos[PLoanPhoto.idCard] = _bytes(20);
  flow.photos[PLoanPhoto.selfieWithIdCard] = _bytes(30);
  return flow;
}

void main() {
  group('field coverage', () {
    test('produces exactly the fields the submit form sends — no more, no less',
        () {
      final produced = PLoanSubmission.fromFlow(_completedFlow()).fields.keys;
      expect(produced.toSet(), equals(_formFields));
      expect(produced.length, 34);
    });

    test('every photo slot maps to a real regmast image group', () {
      for (final slot in PLoanPhoto.values) {
        expect(_formImageGroups, contains(slot.pLoanGroup),
            reason: '${slot.name} -> ${slot.pLoanGroup} is not a form group');
      }
    });

    test('groups with no capture step are declared, not silently missing', () {
      // Every form group is either reachable from a photo slot or explicitly
      // listed as unsupported. A new group must land in one bucket or other.
      final reachable =
          PLoanPhoto.values.map((p) => p.pLoanGroup).toSet();
      final declared = {
        ...reachable,
        ...PLoanSubmission.unsupportedImageGroups,
      };
      expect(declared, containsAll(_formImageGroups));
    });
  });

  group('field values', () {
    test('maps loan terms off the chosen installment and the contract', () {
      final flow = _completedFlow();
      final f = PLoanSubmission.fromFlow(flow).fields;
      final installment = flow.installment!;

      expect(f['refContractNo'], flow.contract!.contractNo);
      expect(f['branchID'], flow.contract!.branchCode);
      expect(f['citizenId'], '1670200003359');
      expect(f['test'], 'สมชาย ใจดี');
      expect(f['mobileNo'], '0863652156');
      expect(f['loanAmt'], '30000.00');
      expect(f['termPeriod'], '24');
      expect(f['regularPeriod'], installment.regularPeriodAmt.toStringAsFixed(2));
      expect(f['intAmt'], installment.intAmt.toStringAsFixed(2));
      expect(f['totalAmt'], installment.totalAmt.toStringAsFixed(2));
      expect(f['bankCode'], 'KBANK');
      expect(f['bankAccNo'], '1234567890');
      expect(f['transferAmt'], flow.payoutAmount.toStringAsFixed(2));
      expect(f['latitude'], '13.8890019');
      expect(f['marketingConsent'], 'Y');
      expect(f['sensitiveConsent'], 'Y');
      expect(f['statusCode'], 'A');
    });

    test('transDate is formatted the way the sample payload is', () {
      final f = PLoanSubmission.fromFlow(
        _completedFlow(),
        now: DateTime(2026, 6, 4, 16, 3, 58),
      ).fields;
      expect(f['transDate'], '2026-06-04 16:03:58');
    });

    test('registerYear is converted to Buddhist era only when needed', () {
      final flow = _completedFlow();
      // Gregorian in, B.E. out.
      flow.amountDetail = LoanAmountDetail.fromJson({
        'code': '200',
        'car_details': {'car_manufacture_year': '2016'},
      });
      expect(PLoanSubmission.fromFlow(flow).fields['registerYear'], '2559');

      // Already B.E. — left alone.
      flow.amountDetail = LoanAmountDetail.fromJson({
        'code': '200',
        'car_details': {'car_manufacture_year': '2559'},
      });
      expect(PLoanSubmission.fromFlow(flow).fields['registerYear'], '2559');
    });

    test('host-supplied codes are carried through, not invented', () {
      final f = PLoanSubmission.fromFlow(_completedFlow()).fields;
      expect(f['empId'], '9472');
      expect(f['mktChannel'], '065');
      expect(f['customerSource'], '9');
      expect(f['gpsProvinceId'], '10');
      expect(f['gpsAumphurId'], '1041');
    });
  });

  group('images', () {
    test('the six vehicle angles collapse into one repeated carImage group',
        () {
      final flow = _completedFlow();
      flow.photos[PLoanPhoto.carFront] = _bytes(40);
      flow.photos[PLoanPhoto.carBack] = _bytes(50);
      final groups = PLoanSubmission.fromFlow(flow).imageGroups;

      // fullVehicle + front + back all belong to carImage.
      expect(groups['carImage']!.length, 3);
      expect(groups['cardIdImage']!.length, 1);
      expect(groups['customerImage']!.length, 1);
      expect(groups['documentImage']!.length, 1); // tax disc
    });

    test('optional attachments reach their own groups when captured', () {
      final flow = _completedFlow();
      flow.photos[PLoanPhoto.bookBank] = _bytes(60);
      flow.photos[PLoanPhoto.vehicleRegistrationBook] = _bytes(70);
      final groups = PLoanSubmission.fromFlow(flow).imageGroups;
      expect(groups['bookBankImage']!.length, 1);
      expect(groups['carBookImage']!.length, 1);
    });

    test('empty slots produce no part at all, rather than a zero-byte file', () {
      final groups = PLoanSubmission.fromFlow(_completedFlow()).imageGroups;
      expect(groups.containsKey('bookBankImage'), isFalse);
      expect(groups.containsKey('coCustomerImage'), isFalse);
    });
  });

  group('missing data is reported, never guessed', () {
    test('a fully-supplied flow reports nothing unresolved', () {
      final submission = PLoanSubmission.fromFlow(_completedFlow());
      expect(submission.unresolvedFields, isEmpty);
      expect(submission.isComplete, isTrue);
    });

    test('codes the host did not supply are named, not silently blank', () {
      final flow = _completedFlow()
        ..empId = ''
        ..mktChannel = ''
        ..gpsProvinceId = '';
      final submission = PLoanSubmission.fromFlow(flow);
      expect(submission.isComplete, isFalse);
      expect(submission.unresolvedFields,
          containsAll(<String>['empId', 'mktChannel', 'gpsProvinceId']));
    });

    test('fields that are legitimately blank are not flagged', () {
      final flow = _completedFlow()
        ..transNo = '' // assigned by the server
        ..remark = ''; // optional
      final unresolved = PLoanSubmission.fromFlow(flow).unresolvedFields;
      expect(unresolved, isNot(contains('transNo')));
      expect(unresolved, isNot(contains('remark')));
    });

    test('an incomplete flow still builds a payload instead of throwing', () {
      // Unlike the /topup payload, this must be inspectable mid-flow so the
      // preview on step 6 works before everything is filled in.
      final partial = PLoanFlow(hashThaiId: 'H');
      final submission = PLoanSubmission.fromFlow(partial);
      expect(submission.fields.keys.toSet(), equals(_formFields));
      expect(submission.isComplete, isFalse);
    });
  });

  group('P-Loan save API payload (POST /SavePloanContract)', () {
    test('sends the 30 fields the API sample sends, plus ndid_reference_id', () {
      final produced =
          PLoanContractSubmission.fromFlow(_completedFlow()).fields;
      expect(produced.keys.toSet(), equals(_saveApiAllFields));
      expect(produced.length, 31);
      // Nothing else crept in alongside the NDID field.
      expect(produced.keys.toSet().difference(_saveApiFields),
          equals(_saveApiNdidFields));
    });

    test('omits the regmast-only fields rather than sending them anyway', () {
      final produced =
          PLoanContractSubmission.fromFlow(_completedFlow()).fields;
      // Server-assigned, or simply not part of this contract. `branchID` is
      // spelled `branchId` here, and `test` is split into first/last name.
      for (final key in const [
        'transNo',
        'transDate',
        'test',
        'payDay',
        'initialDate',
        'lastPeriodPromo',
        'remark',
        'branchID',
      ]) {
        expect(produced.containsKey(key), isFalse, reason: '$key must not go');
      }
    });

    group('ndid_reference_id', () {
      // The only field on this payload the backend can independently check:
      // it can ask NDID about this reference instead of trusting the client's
      // "verification succeeded". So it has to arrive verbatim, and a missing
      // one must be visible rather than papered over.
      test('carries NDID\'s reference for the accepted verification', () {
        final flow = _completedFlow();
        final fields = PLoanContractSubmission.fromFlow(flow).fields;
        expect(fields['ndid_reference_id'], flow.ndidReferenceId);
        expect(fields['ndid_reference_id'],
            '9bcc18bb-9bb4-4302-8c48-514a17c08e08');
      });

      test('is reported unresolved when no real NDID hop happened', () {
        // A simulated verification records no reference. The field still goes
        // out — present and empty, like the rest of this payload — but it is
        // named, so a refusal says which proof was missing.
        final flow = _completedFlow()..ndidReferenceId = '';
        final submission = PLoanContractSubmission.fromFlow(flow);
        expect(submission.fields.containsKey('ndid_reference_id'), isTrue);
        expect(submission.fields['ndid_reference_id'], '');
        expect(submission.unresolvedFields, contains('ndid_reference_id'));
        expect(submission.isComplete, isFalse);
      });

      test('is not in the regmast payload, which has no slot for it', () {
        final regmast = PLoanSubmission.fromFlow(_completedFlow()).fields;
        expect(regmast.containsKey('ndid_reference_id'), isFalse);
      });

      test('reaches a new P-Loan payload too, not just an Extra', () {
        final fields = PLoanContractSubmission.fromFlow(
                _completedFlow(kind: PLoanKind.newLoan))
            .fields;
        expect(fields['ndid_reference_id'],
            '9bcc18bb-9bb4-4302-8c48-514a17c08e08');
      });
    });

    test('splits the customer name and names the account holder', () {
      final flow = _completedFlow();
      final f = PLoanContractSubmission.fromFlow(flow).fields;
      expect(f['firstName'], 'สมชาย');
      expect(f['lastName'], 'ใจดี');
      // The contract carries no account-holder name; it is the customer's own
      // account, which is what the API sample shows.
      expect(f['bankAccName'], 'สมชาย ใจดี');
    });

    test('shared values agree with the regmast payload, digit for digit', () {
      final flow = _completedFlow();
      final save = PLoanContractSubmission.fromFlow(flow).fields;
      final regmast = PLoanSubmission.fromFlow(flow).fields;

      for (final key in const [
        'refContractNo', 'citizenId', 'mobileNo', 'creditAmt', 'loanAmt',
        'requestCredit', 'termPeriod', 'totalAmt', 'intAmt', 'intRate',
        'regularPeriod', 'lastPeriod', 'bankCode', 'bankAccNo', 'transferAmt',
        'statusCode', 'gpsAumphurId', 'gpsProvinceId', 'latitude', 'longitude',
        'empId', 'mktChannel', 'customerSource', 'registerYear',
        'marketingConsent', 'sensitiveConsent',
      ]) {
        expect(save[key], regmast[key], reason: '$key drifted');
      }
      // Renamed, same value.
      expect(save['branchId'], regmast['branchID']);
    });

    test('carries the same photos, as repeated group parts', () {
      final flow = _completedFlow();
      flow.photos[PLoanPhoto.carFront] = _bytes(40);
      final save = PLoanContractSubmission.fromFlow(flow);
      expect(save.imageGroups['carImage']!.length, 2); // fullVehicle + front
      expect(save.imageGroups['cardIdImage']!.length, 1);
      expect(save.imageGroups['documentImage']!.length, 1);
    });

    group('file parts', () {
      test('sends five parts: two photos and the three contract PDFs', () {
        final files = PLoanContractSubmission.fromFlow(_completedFlow()).files;
        expect(files.map((f) => f.field).toList(), [
          'cardIdImage',
          'customerImage',
          'documentImage[]',
          'documentImage[]',
          'documentImage[]',
        ]);
        // The scalar fields are unaffected by the files — still exactly 31.
        expect(PLoanContractSubmission.fromFlow(_completedFlow()).fields.length,
            31);
      });

      test('the identity photos carry their bytes and an image type', () {
        final flow = _completedFlow();
        final files = PLoanContractSubmission.fromFlow(flow).files;
        final card = files.firstWhere((f) => f.field == 'cardIdImage');
        final selfie = files.firstWhere((f) => f.field == 'customerImage');

        expect(card.bytes, flow.photos[PLoanPhoto.idCard]);
        expect(selfie.bytes, flow.photos[PLoanPhoto.selfieWithIdCard]);
        for (final f in [card, selfie]) {
          expect(f.contentType, 'image/jpeg');
          expect(f.filename, endsWith('.jpg'));
        }
      });

      test('the PDFs are decoded, in screen order, as application/pdf', () {
        final flow = _completedFlow();
        final docs = flow.documents!;
        final pdfs = PLoanContractSubmission.fromFlow(flow)
            .files
            .where((f) => f.field == 'documentImage[]')
            .toList();

        // The same order the summary screen lists and consents to them, and the
        // same bytes — what is filed must be byte-identical to what was read.
        expect(pdfs.map((f) => f.bytes).toList(), [
          base64Decode(docs.request),
          base64Decode(docs.receipt),
          base64Decode(docs.agreement),
        ]);
        expect(pdfs.map((f) => f.filename).toList(),
            ['request.pdf', 'receipt.pdf', 'agreement.pdf']);
        for (final f in pdfs) {
          expect(f.contentType, 'application/pdf');
        }
      });

      test('a data: prefix is stripped before decoding, not sent as bytes', () {
        // Live, /pdf/loan returns these as `data:application/pdf;base64,…`; the
        // mock fixtures build bare base64. Both must upload the same bytes, or
        // mock mode would exercise a request production never sends.
        final raw = base64Encode(const [1, 2, 3, 4]);
        final flow = _completedFlow()
          ..documents = LoanDocuments(
            request: 'data:application/pdf;base64,$raw',
            receipt: raw,
            agreement: raw,
          );
        final pdfs = PLoanContractSubmission.fromFlow(flow)
            .files
            .where((f) => f.field == 'documentImage[]');
        expect(pdfs.length, 3);
        for (final f in pdfs) {
          expect(f.bytes, [1, 2, 3, 4]);
        }
      });

      test('a missing file sends no part at all, and is reported', () {
        final flow = _completedFlow();
        flow.photos.remove(PLoanPhoto.idCard);
        flow.documents = null;
        final submission = PLoanContractSubmission.fromFlow(flow);

        // An empty part is worse than no part — it looks like a zero-byte file.
        expect(submission.files.map((f) => f.field), ['customerImage']);
        expect(submission.unresolvedFields,
            containsAll(<String>['cardIdImage', 'documentImage']));
        // The selfie is still there, so it must not be reported.
        expect(submission.unresolvedFields, isNot(contains('customerImage')));
      });

      test('an undecodable document is reported, not thrown', () {
        final flow = _completedFlow()
          ..documents = const LoanDocuments(
            request: 'not base64 at all!!',
            receipt: '',
            agreement: '',
          );
        final submission = PLoanContractSubmission.fromFlow(flow);
        expect(submission.files.where((f) => f.field == 'documentImage[]'),
            isEmpty);
        expect(submission.unresolvedFields, contains('documentImage'));
      });

      test('a complete flow reports no missing file', () {
        final submission = PLoanContractSubmission.fromFlow(_completedFlow());
        for (final key in PLoanContractSubmission.fileFieldNames) {
          expect(submission.unresolvedFields, isNot(contains(key)));
        }
        expect(submission.isComplete, isTrue);
      });
    });

    group('fields accepted blank', () {
      test('all five are sent as empty strings, present not omitted', () {
        final flow = _completedFlow()
          ..empId = ''
          ..mktChannel = ''
          ..customerSource = ''
          ..gpsProvinceId = ''
          ..gpsAumphurId = '';
        final fields = PLoanContractSubmission.fromFlow(flow).fields;

        for (final key in PLoanContractSubmission.acceptedBlank) {
          // Present-with-empty-value, never absent: the server sees the field.
          expect(fields.containsKey(key), isTrue, reason: '$key was omitted');
          expect(fields[key], '');
        }
        // The payload is still the full 31.
        expect(fields.length, 31);
      });

      test('a blank one is not reported as unresolved', () {
        final flow = _completedFlow()
          ..empId = ''
          ..mktChannel = ''
          ..customerSource = ''
          ..gpsProvinceId = ''
          ..gpsAumphurId = '';
        final submission = PLoanContractSubmission.fromFlow(flow);
        for (final key in PLoanContractSubmission.acceptedBlank) {
          expect(submission.unresolvedFields, isNot(contains(key)));
        }
        // Nothing else went missing, so the payload reads as complete.
        expect(submission.isComplete, isTrue);
      });

      test('a host-supplied value is still sent, not blanked', () {
        // The rule is "blank is acceptable", not "always blank" — discarding a
        // value the host went to the trouble of passing would be a regression.
        final fields = PLoanContractSubmission.fromFlow(_completedFlow()).fields;
        expect(fields['empId'], '9472');
        expect(fields['mktChannel'], '065');
        expect(fields['customerSource'], '9');
        expect(fields['gpsProvinceId'], '10');
        expect(fields['gpsAumphurId'], '1041');
      });

      test('genuinely missing data is still reported', () {
        // The blanket must not swallow a real gap: a new P-Loan has no approved
        // limit, and that still has to surface.
        final fresh = PLoanContractSubmission.fromFlow(
            _completedFlow(kind: PLoanKind.newLoan));
        expect(fresh.unresolvedFields, contains('creditAmt'));
      });
    });

    test('a new P-Loan has no approved limit, and reports it', () {
      final fresh = PLoanContractSubmission.fromFlow(
          _completedFlow(kind: PLoanKind.newLoan));
      expect(fresh.fields['creditAmt'], isEmpty);
      expect(fresh.unresolvedFields, contains('creditAmt'));
      expect(fresh.isComplete, isFalse);

      final extra = PLoanContractSubmission.fromFlow(_completedFlow());
      expect(extra.unresolvedFields, isEmpty);
      expect(extra.isComplete, isTrue);
    });
  });

  group('new P-Loan', () {
    test('keeps the same 34 fields — the API is the same either way', () {
      final produced =
          PLoanSubmission.fromFlow(_completedFlow(kind: PLoanKind.newLoan))
              .fields
              .keys;
      expect(produced.toSet(), equals(_formFields));
    });

    test('sends no refContractNo, and does not report one as missing', () {
      // 'เลขที่สัญญาอ้างอิง' identifies the contract an Extra is raised
      // against. A new P-Loan is raised against nothing, so the field is empty
      // by design — reporting it would send someone looking for a value that
      // is not supposed to exist.
      final fresh = PLoanSubmission.fromFlow(
          _completedFlow(kind: PLoanKind.newLoan));
      expect(fresh.fields['refContractNo'], isEmpty);
      expect(fresh.unresolvedFields, isNot(contains('refContractNo')));

      final extra = PLoanSubmission.fromFlow(_completedFlow());
      expect(extra.fields['refContractNo'], isNotEmpty);
    });

    test('the save-API payload applies the same rule', () {
      final fresh = PLoanContractSubmission.fromFlow(
          _completedFlow(kind: PLoanKind.newLoan));
      expect(fresh.fields['refContractNo'], isEmpty);
      expect(fresh.unresolvedFields, isNot(contains('refContractNo')));
    });

    test('branchId has no source without a contract, and is reported', () {
      // Unlike refContractNo this one is a real gap: the application is filed
      // by some branch, we just have no way to know which.
      final fresh = PLoanSubmission.fromFlow(
          _completedFlow(kind: PLoanKind.newLoan));
      expect(fresh.fields['branchID'], isEmpty);
      expect(fresh.unresolvedFields, contains('branchID'));

      expect(
        PLoanContractSubmission.fromFlow(
                _completedFlow(kind: PLoanKind.newLoan))
            .unresolvedFields,
        contains('branchId'),
      );
    });

    test('no old principal comes off a new loan\'s payout', () {
      final flow = _completedFlow(kind: PLoanKind.newLoan);
      final f = PLoanSubmission.fromFlow(flow).fields;
      expect(f['transferAmt'], flow.payoutAmount.toStringAsFixed(2));
    });

    test('does not borrow the reference contract\'s vehicle or bank account',
        () {
      // The reference contract has a KBANK account and a 2016 Wave; none of it
      // describes the loan being applied for.
      final f = PLoanSubmission.fromFlow(
          _completedFlow(kind: PLoanKind.newLoan)).fields;
      expect(f['bankCode'], isEmpty);
      expect(f['bankAccNo'], isEmpty);
      expect(f['registerYear'], isEmpty);

      final extra = PLoanSubmission.fromFlow(_completedFlow()).fields;
      expect(extra['bankCode'], 'KBANK');
      expect(extra['bankAccNo'], '1234567890');
    });

    test('sends the collateral and account the customer gave instead', () {
      final flow = _completedFlow(kind: PLoanKind.newLoan);
      flow.newLoan
        ..collateralType = PLoanCollateralType.car
        ..brand = 'TOYOTA'
        ..series = 'Yaris'
        // Gregorian in, B.E. out — same rule as an Extra's.
        ..manufactureYear = '2019'
        ..bankCode = 'SCB'
        ..bankAccountNo = '9876543210'
        ..bankAccountName = 'สมหญิง รักดี';

      final regmast = PLoanSubmission.fromFlow(flow).fields;
      expect(regmast['bankCode'], 'SCB');
      expect(regmast['bankAccNo'], '9876543210');
      expect(regmast['registerYear'], '2562');

      final save = PLoanContractSubmission.fromFlow(flow).fields;
      expect(save['bankCode'], 'SCB');
      expect(save['bankAccNo'], '9876543210');
      // The holder is the customer's to state — it may not be their own name.
      expect(save['bankAccName'], 'สมหญิง รักดี');
    });

    test('has no approved limit yet, and says so instead of borrowing one', () {
      final fresh = PLoanSubmission.fromFlow(
          _completedFlow(kind: PLoanKind.newLoan));
      // creditAmt is the already-approved limit; underwriting has not set one.
      // Reporting it beats filling it with the reference contract's headroom.
      expect(fresh.fields['creditAmt'], isEmpty);
      expect(fresh.unresolvedFields, contains('creditAmt'));
      expect(fresh.fields['requestCredit'], '30000.00');

      // An Extra does have one, so this is not a blanket blank.
      final extra = PLoanSubmission.fromFlow(_completedFlow());
      expect(extra.fields['creditAmt'], isNotEmpty);
      expect(extra.unresolvedFields, isNot(contains('creditAmt')));
    });
  });

  group('PDPA consents', () {
    test('are sent as the customer answered, not assumed Y', () {
      final flow = _completedFlow()
        ..marketingConsent = false
        ..sensitiveConsent = true;
      final f = PLoanSubmission.fromFlow(flow).fields;
      expect(f['marketingConsent'], 'N');
      expect(f['sensitiveConsent'], 'Y');
    });

    test("'N' is a real answer and never counts as unresolved", () {
      final flow = _completedFlow()
        ..marketingConsent = false
        ..sensitiveConsent = false;
      final submission = PLoanSubmission.fromFlow(flow);
      expect(submission.fields['marketingConsent'], 'N');
      expect(submission.unresolvedFields, isNot(contains('marketingConsent')));
      expect(submission.unresolvedFields, isNot(contains('sensitiveConsent')));
    });

    test('sensitive-data consent gates submit; marketing does not', () {
      final flow = _completedFlow()
        ..consented.addAll(LoanDocumentKind.values)
        // Step 6 also requires NDID signing; granted here so this test
        // isolates the consent gates.
        ..ndidVerified = true
        ..marketingConsent = false
        ..sensitiveConsent = true;
      expect(flow.canSubmit, isTrue,
          reason: 'declining marketing must not block the application');

      flow.sensitiveConsent = false;
      expect(flow.canSubmit, isFalse,
          reason: 'the application cannot be assessed without it');
    });
  });
}
