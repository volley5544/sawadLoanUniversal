/// **ข้อมูลสัญญา — บัตรศรีสวัสดิ์**, design page 10.
///
/// Rows mapped per the BA's *Contract detail* spec — see
/// `RevolvingCardView._contractRows`. **สัญญาเงินกู้** opens the same
/// document the loan detail screen does, by the same `comcode_config` rule
/// ([revolvingContractDocumentUrl]); a contract the rule doesn't offer it for
/// says so.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';
import '../services/app_config_api.dart';
import '../services/external_url.dart';
import 'components/revolving_bill_dialogs.dart';
import 'components/revolving_components.dart';
import 'models/revolving_mock.dart';

Future<void> _openContractDocument(
    BuildContext context, RevolvingCardView card) async {
  if (card.isDemo) return showRevolvingNotYet(context, 'สัญญาเงินกู้');
  // Memoised and never throws: an outage leaves the rule false.
  final config = await AppConfigApi.ensureLoaded();
  if (!context.mounted) return;
  final url = revolvingContractDocumentUrl(
    card: card,
    contractUrl: config.contractUrl,
    allowed: config.comcodeConfig.showsContractButton(
      comcode: card.contractComcode,
      loanTypeCode: card.loanTypeCode,
    ),
  );
  if (url == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('ไม่มีเอกสารสัญญาเงินกู้สำหรับสัญญานี้ในแอป '
            'กรุณาติดต่อสาขา')));
    return;
  }
  await openExternalDocument(context, url);
}

class RevolvingContractPage extends StatelessWidget {
  const RevolvingContractPage({super.key, this.card});

  final RevolvingCardView? card;

  @override
  Widget build(BuildContext context) {
    final view = card ?? RevolvingCardView.mock();
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
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('สัญญาเงินกู้', style: revolvingText(13)),
                      ),
                      GestureDetector(
                        onTap: () => _openContractDocument(context, view),
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
