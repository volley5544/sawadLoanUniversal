/// `comcode_config` — the per-comcode rules that decide what the **loan detail**
/// screen offers a given contract.
///
/// Three questions, all answered from this one document (see
/// `services/app_config_api.dart`):
///
///   * does the bottom button show, and what does it say — **คู่สัญญา** for a
///     company that issues a contract document, **คำขอออกตั๋ว** for one that
///     issues a promissory-note request;
///   * does the header carry the red *"ถ้าลูกค้ายังไม่ได้รับตั๋วสัญญาใช้เงิน …
///     download"* notice;
///   * is this specific contract an exception that always carries it.
///
/// ⚠ **Four of the fields are index-aligned arrays**, not a map: `comcode`
/// supplies the order and `this_comcode_is_contract` / `button_name` are read
/// at the same index. That is the shape the srisawad mobile app's config
/// already has, and it is reproduced rather than reshaped so one document can
/// keep serving both clients. Every read here is bounds-checked, because a
/// `button_name` list one shorter than `comcode` is a single config edit away
/// and must degrade rather than throw on a screen the customer is looking at.
///
/// An absent or unreadable document leaves every predicate `false` — the
/// screen renders without the button and without the notice, which is the
/// safe direction: it withholds an action rather than offering one the
/// company does not support.
library;

/// Decoded `comcode_config`.
class ComcodeConfig {
  const ComcodeConfig({
    this.comcodes = const [],
    this.thisComcodeIsContract = const [],
    this.buttonNames = const [],
    this.loanTypeCodes = const {},
    this.checkContractDate = const [],
    this.exceptionContracts = const [],
    this.exceptionContractComcodes = const [],
    this.contractDefaultDate = '',
  });

  /// `comcode` — the companies this config knows about, and the index order
  /// the two arrays below are read at.
  final List<String> comcodes;

  /// `this_comcode_is_contract` — true when the company issues a **contract**
  /// document (คู่สัญญา), false when it issues a promissory-note request
  /// (คำขอออกตั๋ว). Aligned to [comcodes].
  final List<bool> thisComcodeIsContract;

  /// `button_name` — the bottom button's label. Aligned to [comcodes].
  final List<String> buttonNames;

  /// `loan_type_code` — per comcode, the `contract_details.loan_type_code`
  /// values the document is available for. This one **is** a map.
  final Map<String, List<String>> loanTypeCodes;

  /// `check_contract_date` — comcodes whose document only exists for contracts
  /// signed after [contractDefaultDate]. For these the bottom button is
  /// withheld and the header notice is date-gated instead.
  final List<String> checkContractDate;

  /// `exception_contract` / `exception_contract_comcode` — individual contracts
  /// that always carry the header notice, whatever the rules above say.
  /// The two are a pair: entry *i* of one goes with entry *i* of the other.
  final List<String> exceptionContracts;
  final List<String> exceptionContractComcodes;

  /// `contract_default_date` — the cutoff for [checkContractDate] comcodes.
  final String contractDefaultDate;

  bool get isEmpty => comcodes.isEmpty;

  /// Index of [comcode] in [comcodes], or -1.
  int _indexOf(String comcode) => comcodes.indexOf(comcode.trim());

  static T? _at<T>(List<T> list, int index) =>
      (index >= 0 && index < list.length) ? list[index] : null;

  /// The bottom button's label for [comcode], or null when this config does
  /// not name one. Callers that show the button should fall back to `คู่สัญญา`,
  /// matching the source's `valueOrDefault`.
  String? contractButtonLabel(String comcode) =>
      _at(buttonNames, _indexOf(comcode));

  /// Whether the document is offered at all for this comcode + loan type.
  bool _documentOffered(String comcode, String loanTypeCode) {
    final code = comcode.trim();
    if (_indexOf(code) < 0) return false;
    return loanTypeCodes[code]?.contains(loanTypeCode.trim()) ?? false;
  }

  /// Whether the bottom **คู่สัญญา / คำขอออกตั๋ว** button is shown.
  ///
  /// Only for a company that issues a contract document
  /// ([thisComcodeIsContract]) and is not date-gated — a date-gated one gets
  /// the header notice instead, never the button.
  bool showsContractButton({
    required String comcode,
    required String loanTypeCode,
  }) {
    if (!_documentOffered(comcode, loanTypeCode)) return false;
    if (_at(thisComcodeIsContract, _indexOf(comcode)) != true) return false;
    return !checkContractDate.contains(comcode.trim());
  }

  /// Whether this exact contract is listed as an exception.
  ///
  /// The two arrays are walked as pairs, so a contract number listed against a
  /// *different* company does not match — contract numbers are unique only
  /// within a company.
  bool isExceptionContract({
    required String contractNo,
    required String comcode,
  }) {
    final contract = contractNo.trim();
    final code = comcode.trim();
    final pairs =
        exceptionContracts.length < exceptionContractComcodes.length
            ? exceptionContracts.length
            : exceptionContractComcodes.length;
    for (var i = 0; i < pairs; i++) {
      if (exceptionContracts[i].trim() == contract &&
          exceptionContractComcodes[i].trim() == code) {
        return true;
      }
    }
    return false;
  }

  /// Whether the header carries the red *"ถ้าลูกค้ายังไม่ได้รับตั๋วสัญญาใช้เงิน
  /// ณ วันที่ทำสัญญา กรุณา download"* notice.
  ///
  /// Three independent reasons, any one of which shows it:
  ///
  ///   1. the contract is an [isExceptionContract];
  ///   2. the company issues a **promissory-note request** rather than a
  ///      contract (`this_comcode_is_contract == false`) and is not date-gated
  ///      — the mirror image of [showsContractButton];
  ///   3. the company **is** date-gated and this contract was signed after
  ///      [contractDefaultDate].
  ///
  /// The source writes these as an `if / else if / else if` chain, but all
  /// three arms render the same widget, so an OR is the same output.
  bool showsContractNotIssuedNotice({
    required String comcode,
    required String loanTypeCode,
    required String contractNo,
    required String contractDate,
  }) {
    if (isExceptionContract(contractNo: contractNo, comcode: comcode)) {
      return true;
    }
    if (!_documentOffered(comcode, loanTypeCode)) return false;
    final dateGated = checkContractDate.contains(comcode.trim());
    if (!dateGated) {
      return _at(thisComcodeIsContract, _indexOf(comcode)) == false;
    }
    return _isAfterDefaultDate(contractDate);
  }

  /// `contract_default_date` < `contractDate`.
  ///
  /// Either side being absent or unparseable reads as **false** — the notice
  /// tells the customer to chase a document, so a config typo must not put it
  /// in front of every contract.
  bool _isAfterDefaultDate(String contractDate) {
    final cutoff = DateTime.tryParse(contractDefaultDate.trim());
    final signed = DateTime.tryParse(contractDate.trim());
    if (cutoff == null || signed == null) return false;
    return cutoff.isBefore(signed);
  }

  /// Builds from the decoded `comcode_config` map. Tolerant of every field
  /// being missing or oddly typed — see the class comment.
  factory ComcodeConfig.fromDecoded(dynamic decoded) {
    if (decoded is! Map) return const ComcodeConfig();
    final map = decoded;
    return ComcodeConfig(
      comcodes: _stringList(map['comcode']),
      thisComcodeIsContract: _boolList(map['this_comcode_is_contract']),
      buttonNames: _stringList(map['button_name']),
      loanTypeCodes: switch (map['loan_type_code']) {
        final Map raw => {
            for (final entry in raw.entries)
              '${entry.key}': _stringList(entry.value),
          },
        _ => const {},
      },
      checkContractDate: _stringList(map['check_contract_date']),
      exceptionContracts: _stringList(map['exception_contract']),
      exceptionContractComcodes:
          _stringList(map['exception_contract_comcode']),
      contractDefaultDate: '${map['contract_default_date'] ?? ''}',
    );
  }

  static List<String> _stringList(dynamic value) => switch (value) {
        final List list => [
            for (final item in list)
              if (item != null) '$item',
          ],
        _ => const [],
      };

  /// Anything that isn't literally `true` is `false` — a config carrying the
  /// string `'true'` would otherwise silently grant a button.
  static List<bool> _boolList(dynamic value) => switch (value) {
        final List list => [for (final item in list) item == true],
        _ => const [],
      };

  @override
  String toString() => 'ComcodeConfig(${comcodes.length} comcodes)';
}
