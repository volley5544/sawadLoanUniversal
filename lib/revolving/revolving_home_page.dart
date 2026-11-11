/// **สินเชื่อของฉัน — บัตรศรีสวัสดิ์**: the revolving card's home screen.
///
/// The summary card, the four actions (โอน/ถอนเงิน · ดูบิล · ชำระเงิน ·
/// ข้อมูลสัญญา) and the two history tabs. Design pages 2–6, 10.
///
/// ⚠ **UI and navigation only** (2026-11-11): renders
/// [RevolvingCardView.mock]. `?contNo=` is carried for when the data is wired;
/// `?bill=ready` shows the issued-statement branch of ดูบิล, which the mock
/// otherwise answers with "not yet".
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';
import 'components/revolving_bill_dialogs.dart';
import 'components/revolving_components.dart';
import 'models/revolving_mock.dart';

class RevolvingHomePage extends StatefulWidget {
  const RevolvingHomePage({
    super.key,
    this.contractNo = '',
    this.fromHost = false,
    this.billReady = false,
  });

  final String contractNo;

  /// The host opened this route directly, so back closes the WebView.
  final bool fromHost;

  /// Demo switch for ดูบิล's two branches (ยังไม่ถึง / ถึงวันสรุปยอด).
  final bool billReady;

  @override
  State<RevolvingHomePage> createState() => _RevolvingHomePageState();
}

class _RevolvingHomePageState extends State<RevolvingHomePage> {
  late final RevolvingCardView _card =
      RevolvingCardView.mock(contractNo: widget.contractNo)
          .copyWith(billReady: widget.billReady);

  /// 0 = ประวัติการถอน/โอน, 1 = ประวัติการชำระ.
  int _tab = 0;

  void _openPayment() =>
      context.push(AppRoutes.revolvingPayment, extra: _card);

  @override
  Widget build(BuildContext context) {
    final history = _tab == 0 ? _card.withdrawals : _card.payments;
    return RevolvingOrangePage(
      title: 'สินเชื่อของฉัน',
      subtitle: 'ข้อมูลวันที่ ${_card.dataDateLabel}',
      onBack: () => revolvingBack(context, fromHost: widget.fromHost),
      card: RevolvingSummaryCard(card: _card, onPay: _openPayment),
      children: [
        RevolvingActionRow(
          onTransfer: () =>
              context.push(AppRoutes.revolvingTransfer, extra: _card),
          onBill: () => showRevolvingBill(context, _card),
          onPay: _openPayment,
          onContract: () =>
              context.push(AppRoutes.revolvingContract, extra: _card),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: RevolvingHistoryTabs(
            selected: _tab,
            onChanged: (tab) => setState(() => _tab = tab),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Text(
            _tab == 0 ? 'ประวัติการถอน/โอน' : 'ประวัติการชำระ',
            style: revolvingText(16,
                weight: FontWeight.w700, color: RevolvingPalette.navy),
          ),
        ),
        RevolvingHistoryList(entries: history),
      ],
    );
  }
}

/// The two-segment toggle above the history list.
class RevolvingHistoryTabs extends StatelessWidget {
  const RevolvingHistoryTabs({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final int selected;
  final ValueChanged<int> onChanged;

  static const List<String> labels = ['ประวัติการถอน / โอน', 'ประวัติการชำระ'];

  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF2F7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected == i
                          ? RevolvingPalette.tabBlue
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      labels[i],
                      style: revolvingText(12,
                          weight: FontWeight.w600,
                          color: selected == i
                              ? Colors.white
                              : RevolvingPalette.label),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// History rows grouped under their month heading, in the order given.
class RevolvingHistoryList extends StatelessWidget {
  const RevolvingHistoryList({super.key, required this.entries});

  final List<RevolvingHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('ไม่มีรายการ',
              style: revolvingText(13, color: RevolvingPalette.label)),
        ),
      );
    }
    final children = <Widget>[];
    String? month;
    for (final entry in entries) {
      if (entry.monthLabel != month) {
        month = entry.monthLabel;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
          child: Text(month,
              style: revolvingText(13,
                  weight: FontWeight.w700, color: RevolvingPalette.navy)),
        ));
      }
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: RevolvingPanel(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.dateLabel,
                  style: revolvingText(13,
                      weight: FontWeight.w700, color: RevolvingPalette.navy)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text('จำนวนเงิน',
                        style:
                            revolvingText(12, color: RevolvingPalette.label)),
                  ),
                  Text('${revolvingMoney(entry.amount)} บาท',
                      style: revolvingText(12, color: RevolvingPalette.text)),
                ],
              ),
            ],
          ),
        ),
      ));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
