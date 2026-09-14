import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/models/app_config.dart';
import 'package:sawad_loan_universal/models/comcode_config.dart';

/// The live `comcode_config`, copied from the srisawad mobile app's own
/// `application/configs` document (2026-09-14) and seeded into this project's
/// `application/public_config`.
///
/// The tests below are written against these exact values rather than an
/// invented fixture, because the rules are only meaningful as a pair with the
/// data: `this_comcode_is_contract` is index-aligned to `comcode`, so a test
/// that made its own arrays up could pass while the shipped document produced
/// the opposite answer.
const Map<String, dynamic> _liveComcodeConfig = {
  'comcode': ['S22', 'FM', 'S14', 'SDG'],
  'this_comcode_is_contract': [true, true, false, false],
  'button_name': ['คู่สัญญา', 'คู่สัญญา', 'คำขอออกตั๋ว', 'คำขอออกตั๋ว'],
  'loan_type_code': {
    'FM': ['C', 'T', 'V', 'M', 'A'],
    'SDG': ['C', 'T', 'H', 'L'],
    'S14': ['C', 'T', 'V', 'M', 'H', 'L'],
    'S22': ['C', 'T', 'V', 'M'],
    'S12': ['III'],
  },
  'check_contract_date': ['S14', 'SDG'],
  'exception_contract': ['HYL660902015LS47X', 'ContNo2'],
  'exception_contract_comcode': ['S14', 'SDG'],
  'contract_default_date': '2024-07-18',
};

ComcodeConfig get _config => ComcodeConfig.fromDecoded(_liveComcodeConfig);

void main() {
  group('the คู่สัญญา / คำขอออกตั๋ว button', () {
    test('shows for a contract-issuing company with a covered loan type', () {
      expect(
        _config.showsContractButton(comcode: 'S22', loanTypeCode: 'C'),
        isTrue,
      );
      expect(_config.contractButtonLabel('S22'), 'คู่สัญญา');
      expect(
        _config.showsContractButton(comcode: 'FM', loanTypeCode: 'A'),
        isTrue,
      );
    });

    test('is withheld for a loan type that company does not cover', () {
      // 'A' is on FM's list but not S22's.
      expect(
        _config.showsContractButton(comcode: 'S22', loanTypeCode: 'A'),
        isFalse,
      );
    });

    test('is withheld for a date-gated company, whatever its loan type', () {
      // S14 and SDG are in `check_contract_date`: their customers get the
      // header notice instead, never the button. This is the pair of
      // conditions most easily collapsed by mistake.
      for (final comcode in ['S14', 'SDG']) {
        expect(
          _config.showsContractButton(comcode: comcode, loanTypeCode: 'C'),
          isFalse,
          reason: '$comcode is date-gated',
        );
      }
    });

    test('is withheld for a company the config does not list', () {
      // S12 has a `loan_type_code` entry but is absent from `comcode`, so it
      // has no `this_comcode_is_contract` flag and no button name.
      expect(
        _config.showsContractButton(comcode: 'S12', loanTypeCode: 'III'),
        isFalse,
      );
      expect(_config.contractButtonLabel('S12'), isNull);
      expect(
        _config.showsContractButton(comcode: 'NOPE', loanTypeCode: 'C'),
        isFalse,
      );
    });

    test('labels are read at the comcode index, not by position of use', () {
      expect(_config.contractButtonLabel('S14'), 'คำขอออกตั๋ว');
      expect(_config.contractButtonLabel('SDG'), 'คำขอออกตั๋ว');
      expect(_config.contractButtonLabel('FM'), 'คู่สัญญา');
    });
  });

  group('the "ตั๋วสัญญาใช้เงิน … download" notice', () {
    bool notice({
      required String comcode,
      String loanTypeCode = 'C',
      String contractNo = 'ANY-CONTRACT',
      String contractDate = '2026-01-15',
    }) =>
        _config.showsContractNotIssuedNotice(
          comcode: comcode,
          loanTypeCode: loanTypeCode,
          contractNo: contractNo,
          contractDate: contractDate,
        );

    test('shows for a date-gated company signed after the cutoff', () {
      expect(notice(comcode: 'S14', contractDate: '2026-01-15'), isTrue);
      expect(notice(comcode: 'SDG', contractDate: '2024-07-19'), isTrue);
    });

    test('is withheld for a date-gated company signed before the cutoff', () {
      expect(notice(comcode: 'S14', contractDate: '2024-07-17'), isFalse);
      // The cutoff itself is exclusive — `isBefore`, not `isSameOrBefore`.
      expect(notice(comcode: 'S14', contractDate: '2024-07-18'), isFalse);
    });

    test('a listed exception overrides every other rule', () {
      // S22 is a contract-issuing, non-date-gated company: it would normally
      // get the button and no notice. A contract on the exception list gets
      // the notice regardless — but only against its own company.
      expect(
        notice(comcode: 'S14', contractNo: 'HYL660902015LS47X',
            contractDate: '2020-01-01'),
        isTrue,
        reason: 'listed, and before the cutoff — the exception still wins',
      );
      expect(
        _config.isExceptionContract(
            contractNo: 'HYL660902015LS47X', comcode: 'SDG'),
        isFalse,
        reason: 'that contract is listed against S14, not SDG',
      );
    });

    test('shows for a promissory-note company that is not date-gated', () {
      // None of the live comcodes is in this state — S14 and SDG are both
      // date-gated — so this arm is exercised against a config that is.
      final config = ComcodeConfig.fromDecoded({
        ..._liveComcodeConfig,
        'check_contract_date': <String>[],
      });
      expect(
        config.showsContractNotIssuedNotice(
          comcode: 'S14',
          loanTypeCode: 'C',
          contractNo: 'X',
          contractDate: '2020-01-01',
        ),
        isTrue,
      );
      // And its mirror image: the same config now offers the button, because
      // the two conditions are exclusive by construction.
      expect(
        config.showsContractButton(comcode: 'S22', loanTypeCode: 'C'),
        isTrue,
      );
      expect(
        config.showsContractButton(comcode: 'S14', loanTypeCode: 'C'),
        isFalse,
        reason: 'S14 issues a note, not a contract',
      );
    });

    test('an unreadable contract date withholds it rather than showing it', () {
      // A config typo must not put "chase your document" in front of every
      // customer of a date-gated company.
      expect(notice(comcode: 'S14', contractDate: ''), isFalse);
      expect(notice(comcode: 'S14', contractDate: 'not-a-date'), isFalse);
      final noCutoff = ComcodeConfig.fromDecoded({
        ..._liveComcodeConfig,
        'contract_default_date': '',
      });
      expect(
        noCutoff.showsContractNotIssuedNotice(
          comcode: 'S14',
          loanTypeCode: 'C',
          contractNo: 'X',
          contractDate: '2026-01-15',
        ),
        isFalse,
      );
    });
  });

  group('a missing or malformed document', () {
    test('every rule answers false, so nothing is offered', () {
      for (final config in [
        const ComcodeConfig(),
        ComcodeConfig.fromDecoded(null),
        ComcodeConfig.fromDecoded('nonsense'),
        ComcodeConfig.fromDecoded(const <String, dynamic>{}),
      ]) {
        expect(config.isEmpty, isTrue);
        expect(
          config.showsContractButton(comcode: 'S22', loanTypeCode: 'C'),
          isFalse,
        );
        expect(
          config.showsContractNotIssuedNotice(
            comcode: 'S22',
            loanTypeCode: 'C',
            contractNo: 'X',
            contractDate: '2026-01-15',
          ),
          isFalse,
        );
        expect(config.contractButtonLabel('S22'), isNull);
      }
    });

    test('arrays shorter than `comcode` degrade instead of throwing', () {
      // The four arrays are aligned by convention, not by the schema — one
      // short `button_name` is a single config edit away, and it must not
      // crash a screen the customer is looking at.
      final ragged = ComcodeConfig.fromDecoded({
        ..._liveComcodeConfig,
        'this_comcode_is_contract': [true],
        'button_name': ['คู่สัญญา'],
        'exception_contract': ['HYL660902015LS47X', 'ContNo2'],
        'exception_contract_comcode': ['S14'],
      });
      expect(ragged.contractButtonLabel('S22'), 'คู่สัญญา');
      expect(ragged.contractButtonLabel('FM'), isNull);
      expect(
        ragged.showsContractButton(comcode: 'FM', loanTypeCode: 'C'),
        isFalse,
        reason: 'no flag at that index means no button',
      );
      expect(
        ragged.isExceptionContract(contractNo: 'ContNo2', comcode: 'SDG'),
        isFalse,
        reason: 'the unpaired second entry is ignored, not guessed at',
      );
    });

    test('a non-boolean flag is not treated as true', () {
      final stringy = ComcodeConfig.fromDecoded({
        ..._liveComcodeConfig,
        'this_comcode_is_contract': ['true', 'true', 'false', 'false'],
      });
      expect(
        stringy.showsContractButton(comcode: 'S22', loanTypeCode: 'C'),
        isFalse,
      );
    });
  });

  group('AppConfig wiring', () {
    test('decodes comcode_config and contract_url from the document', () {
      final config = AppConfig.fromDecoded({
        'api_url': {'contract_url': 'https://pt.swpfin.com/portal/'},
        'comcode_config': _liveComcodeConfig,
      });
      // urlFor strips the trailing slash, so the page can append /contract.
      expect(config.contractUrl, 'https://pt.swpfin.com/portal');
      expect(config.comcodeConfig.comcodes, ['S22', 'FM', 'S14', 'SDG']);
      expect(
        config.comcodeConfig
            .showsContractButton(comcode: 'FM', loanTypeCode: 'M'),
        isTrue,
      );
    });

    test('a document without either key leaves both inert', () {
      final config = AppConfig.fromDecoded(const {'api_url': {}});
      expect(config.contractUrl, isNull);
      expect(config.comcodeConfig.isEmpty, isTrue);
    });
  });
}
