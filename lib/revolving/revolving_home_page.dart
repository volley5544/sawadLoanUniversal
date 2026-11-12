/// **สินเชื่อของฉัน — บัตรศรีสวัสดิ์**: the revolving card's home screen.
///
/// The summary card, the four actions (โอน/ถอนเงิน · ดูบิล · ชำระเงิน ·
/// ข้อมูลสัญญา) and the two history tabs. Design pages 2–6, 10.
///
/// **One card per revolving contract** (2026-11-12). The cards are the
/// customer's `/loan/list` rows with `revolving_loans.revolving_flag` true;
/// with more than one, the customer switches by swiping the card or with the
/// arrows/dots under it. The srisawad app opens this route two ways:
///
/// | Tapped in the app | `?contNo=` | Opens on |
/// | --- | --- | --- |
/// | home menu **บัตรศรีสวัสดิ์** | its first revolving contract | that card |
/// | a loan card's **ถอนเงิน** (host side not built yet) | that card's contract | that card |
///
/// An unmatched or empty `contNo` opens the first card.
///
/// ⚠ **UI and navigation only**: only each card's identity is real (see
/// [RevolvingCardView.fromContract]); figures and history are the design's.
/// In a plain browser (no `hashThaiId`) it shows [RevolvingCardView.demo].
/// `?bill=ready` shows the issued-statement branch of ดูบิล.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_state.dart';
import '../p_loan/application/components/p_loan_components.dart';
import '../router/app_router.dart';
import '../services/p_loan_api.dart';
import '../services/srisawad_api.dart';
import 'components/revolving_bill_dialogs.dart';
import 'components/revolving_components.dart';
import 'models/revolving_mock.dart';

class RevolvingHomePage extends StatefulWidget {
  const RevolvingHomePage({
    super.key,
    this.contractNo = '',
    this.fromHost = false,
    this.billReady = false,
    this.cards,
  });

  /// The contract to open on — see the table above.
  final String contractNo;

  /// The host opened this route directly, so back closes the WebView.
  final bool fromHost;

  /// Demo switch for ดูบิล's two branches (ยังไม่ถึง / ถึงวันสรุปยอด).
  final bool billReady;

  /// Cards to show instead of loading them (tests).
  final List<RevolvingCardView>? cards;

  @override
  State<RevolvingHomePage> createState() => _RevolvingHomePageState();
}

class _RevolvingHomePageState extends State<RevolvingHomePage> {
  List<RevolvingCardView>? _cards;
  String? _error;
  int _index = 0;

  /// 0 = ประวัติการถอน/โอน, 1 = ประวัติการชำระ.
  int _tab = 0;

  RevolvingCardView get _card => _cards![_index];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _show(List<RevolvingCardView> cards) {
    setState(() {
      _cards = [for (final c in cards) c.copyWith(billReady: widget.billReady)];
      _index = RevolvingCardView.initialIndex(_cards!, widget.contractNo);
    });
  }

  Future<void> _load() async {
    setState(() {
      _cards = null;
      _error = null;
    });
    final given = widget.cards;
    if (given != null) return _show(given);
    final appState = AppState();
    if (appState.hashThaiId.isEmpty) {
      return _show(RevolvingCardView.demo(contractNo: widget.contractNo));
    }
    try {
      final contracts = await PLoanApi.listContracts(
        hashThaiId: appState.hashThaiId,
        token: appState.authToken,
      );
      if (!mounted) return;
      final cards = RevolvingCardView.listFrom(contracts);
      if (cards.isEmpty) {
        setState(() => _error = 'ไม่พบบัตรศรีสวัสดิ์');
        return;
      }
      _show(cards);
    } on SrisawadApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _select(int index) {
    final cards = _cards;
    if (cards == null || index < 0 || index >= cards.length) return;
    setState(() => _index = index);
  }

  void _back() => revolvingBack(context, fromHost: widget.fromHost);

  @override
  Widget build(BuildContext context) {
    if (_cards == null) {
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _back),
          title: const Text('สินเชื่อของฉัน'),
        ),
        body: _error == null
            ? const PLoanLoadingView()
            : PLoanErrorView(message: _error!, onRetry: _load),
      );
    }
    final card = _card;
    final cards = _cards!;
    final history = _tab == 0 ? card.withdrawals : card.payments;
    void openPayment() => revolvingOpenPayment(context, card);
    return RevolvingOrangePage(
      title: 'สินเชื่อของฉัน',
      subtitle: 'ข้อมูลวันที่ ${card.dataDateLabel}',
      onBack: _back,
      card: GestureDetector(
        // Swipe left → next card, right → previous.
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -200) _select(_index + 1);
          if (v > 200) _select(_index - 1);
        },
        child: RevolvingSummaryCard(
            key: ValueKey(card.contractNo), card: card, onPay: openPayment),
      ),
      children: [
        if (cards.length > 1)
          RevolvingCardPager(
            count: cards.length,
            index: _index,
            onChanged: _select,
          ),
        RevolvingActionRow(
          onTransfer: () =>
              context.push(AppRoutes.revolvingTransfer, extra: card),
          onBill: () => showRevolvingBill(context, card),
          onPay: openPayment,
          onContract: () =>
              context.push(AppRoutes.revolvingContract, extra: card),
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

/// `‹ ● ○ ○ ›` under the summary card when the customer has more than one
/// บัตรศรีสวัสดิ์. Dots are tappable; the arrows dim at either end.
class RevolvingCardPager extends StatelessWidget {
  const RevolvingCardPager({
    super.key,
    required this.count,
    required this.index,
    required this.onChanged,
  });

  final int count;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData icon, String tip, int target, bool enabled) =>
        IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: enabled ? () => onChanged(target) : null,
          icon: Icon(icon, size: 22),
          color: RevolvingPalette.navy,
          disabledColor: RevolvingPalette.divider,
        );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          arrow(Icons.chevron_left, 'บัตรก่อนหน้า', index - 1, index > 0),
          for (var i = 0; i < count; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                key: ValueKey('revolving-dot-$i'),
                width: i == index ? 18 : 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i == index
                      ? RevolvingPalette.orange
                      : RevolvingPalette.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          arrow(Icons.chevron_right, 'บัตรถัดไป', index + 1, index < count - 1),
        ],
      ),
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
