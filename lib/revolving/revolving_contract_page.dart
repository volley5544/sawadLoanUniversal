/// **ข้อมูลสัญญา — บัตรศรีสวัสดิ์**, design page 10.
///
/// Rows mapped per the BA's *Contract detail* spec — see
/// `RevolvingCardView._contractRows`.
///
/// **สัญญาเงินกู้ is the loan detail screen's row, rule for rule** (on
/// request, 2026-11-12): the same `contract_url` link, shown only when
/// `comcode_config.showsContractButton` allows it (otherwise the row is
/// absent, as there), labelled with the config's `button_name` for the
/// comcode (`สัญญาเงินกู้` when none), and loan type `O` asks
/// [confirmBranchIssuedDocument] first. The demo card keeps the row and says
/// "not yet".
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../loan_detail/loan_detail_page.dart';
import '../models/comcode_config.dart';
import '../router/app_router.dart';
import '../services/diagnostics.dart';
import '../services/app_config_api.dart';
import '../services/external_url.dart';
import 'components/revolving_bill_dialogs.dart';
import 'components/revolving_components.dart';
import 'models/revolving_mock.dart';

class RevolvingContractPage extends StatefulWidget {
  const RevolvingContractPage({super.key, this.card});

  final RevolvingCardView? card;

  @override
  State<RevolvingContractPage> createState() => _RevolvingContractPageState();
}

class _RevolvingContractPageState extends State<RevolvingContractPage> {
  late final RevolvingCardView view = widget.card ?? RevolvingCardView.mock();

  String? _contractUrl;
  ComcodeConfig _comcodeConfig = const ComcodeConfig();

  @override
  void initState() {
    super.initState();
    if (!view.isDemo) _loadConfig();
  }

  /// Memoised and never throws: an outage leaves the rule false, so the row
  /// is withheld — the loan detail screen's behaviour.
  Future<void> _loadConfig() async {
    final config = await AppConfigApi.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _contractUrl = config.contractUrl;
      _comcodeConfig = config.comcodeConfig;
    });
  }

  String? get _documentUrl => revolvingContractDocumentUrl(
        card: view,
        contractUrl: _contractUrl,
        allowed: _comcodeConfig.showsContractButton(
          comcode: view.contractComcode,
          loanTypeCode: view.loanTypeCode,
        ),
      );

  bool get _showsDocument => view.isDemo || _documentUrl != null;

  String get _documentLabel =>
      _comcodeConfig.contractButtonLabel(view.contractComcode) ?? 'สัญญาเงินกู้';

  Future<void> _onDocument() async {
    if (view.isDemo) return showRevolvingNotYet(context, 'สัญญาเงินกู้');
    final url = _documentUrl;
    if (url == null) return;
    if (view.loanTypeCode == kBranchIssuedLoanTypeCode) {
      final ok = await confirmBranchIssuedDocument(context);
      if (ok != true || !mounted) return;
      Diagnostics.log('contract party acknowledged ${view.contractNo}');
    }
    if (!mounted) return;
    await openExternalDocument(context, url);
  }

  @override
  Widget build(BuildContext context) {
    void pay() => revolvingOpenPayment(context, view);
    return RevolvingOrangePage(
      title: 'ข้อมูลสัญญา',
      subtitle: 'ข้อมูลวันที่ ${view.dataDateLabel}',
      onBack: () => revolvingBack(context),
      card: RevolvingSummaryCard(card: view, onPay: pay),
      children: [
        RevolvingActionRow(
          onTransfer: () =>
              context.push(AppRoutes.revolvingTransfer, extra: view),
          onBill: () => showRevolvingBill(context, view),
          onPay: pay,
          // Already here.
          onContract: () {},
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Text('ข้อมูลสัญญา',
              style: revolvingText(16,
                  weight: FontWeight.w700, color: RevolvingPalette.navy)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: RevolvingPanel(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in view.contractInfo) ...[
                  RevolvingKeyValue(
                    label: row.label,
                    value: row.value,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  const Divider(height: 1, color: RevolvingPalette.divider),
                ],
                if (_showsDocument)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_documentLabel, style: revolvingText(13)),
                      ),
                      GestureDetector(
                        onTap: _onDocument,
                        child: Text(
                          'ดูรายละเอียด',
                          style: revolvingText(13,
                                  weight: FontWeight.w600,
                                  color: RevolvingPalette.blue)
                              .copyWith(
                                  decoration: TextDecoration.underline,
                                  decorationColor: RevolvingPalette.blue),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text('ข้อมูลวันที่ ${view.contractInfoDateLabel}',
                    textAlign: TextAlign.center,
                    style: revolvingText(12, color: RevolvingPalette.text)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
