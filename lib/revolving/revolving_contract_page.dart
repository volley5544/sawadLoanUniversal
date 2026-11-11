/// **ข้อมูลสัญญา — บัตรศรีสวัสดิ์**, design page 10.
///
/// ⚠ **UI and navigation only** (2026-11-11). The สัญญาเงินกู้ link opens
/// nothing yet; when wired it should go through `openExternalUrl`, the way the
/// loan detail screen's document link does.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';
import 'components/revolving_bill_dialogs.dart';
import 'components/revolving_components.dart';
import 'models/revolving_mock.dart';

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
                        onTap: () =>
                            showRevolvingNotYet(context, 'สัญญาเงินกู้'),
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
