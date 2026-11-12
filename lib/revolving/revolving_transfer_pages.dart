/// **โอน / ถอนเงินสินเชื่อ** — design pages 3–5: pick a destination, enter
/// an amount, confirm, done.
///
/// ```
/// destination (one tile per bank_accounts entry) → amount → confirm → success
/// ```
///
/// The destinations are **generated from `revolving_loans.bank_accounts`**
/// (decided 2026-11-12): one tile per entry, in the backend's order, so a
/// single account is a single tile. The design's two fixed tiles —
/// พร้อมเพย์ and บัญชีธนาคารที่ผูกไว้ — are just what two entries look like.
/// A PromptPay entry already says whether it is a phone or a citizen id
/// (`transfer_type`), so the amount screen no longer asks.
///
/// The amount screen applies the *Withdrawal process* spec's validation
/// (`RevolvingCardView.withdrawalRefusal`) and says which rule failed.
///
/// ⚠ **No money moves** (2026-11-11). ยืนยัน files nothing — the
/// `applyForWithdrawal` body is only *built* (`RevolvingWithdrawalRequest`) —
/// and the success screen shows what was entered.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../p_loan/application/models/loan_contract.dart';
import '../router/app_router.dart';
import 'components/revolving_components.dart';
import 'models/revolving_mock.dart';

// ── 1. destination ────────────────────────────────────────────────────

class RevolvingTransferPage extends StatelessWidget {
  const RevolvingTransferPage({super.key, this.card});

  final RevolvingCardView? card;

  @override
  Widget build(BuildContext context) {
    final view = card ?? RevolvingCardView.mock();
    void open(RevolvingBankAccount account) => context.push(
          AppRoutes.revolvingTransferAmount,
          extra:
              RevolvingTransferDraft(card: view, account: account, amount: 0),
        );
    return RevolvingOrangePage(
      title: 'โอน / ถอนเงินสินเชื่อ',
      subtitle: 'จาก',
      orangeHeight: 190,
      background: RevolvingPalette.peach,
      onBack: () => revolvingBack(context),
      card: RevolvingSummaryCard(card: view, mode: RevolvingCardMode.limits),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
          child: Text('ไปยัง',
              style: revolvingText(16,
                  weight: FontWeight.w700, color: RevolvingPalette.navy)),
        ),
        if (view.bankAccounts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RevolvingPanel(
              child: Text('ไม่พบบัญชีรับเงินของสัญญานี้',
                  textAlign: TextAlign.center,
                  style: revolvingText(13, color: RevolvingPalette.text)),
            ),
          ),
        for (final account in view.bankAccounts)
          _DestinationTile(
            badge: RevolvingAccountBadge(account: account),
            label: revolvingAccountTitle(account),
            detail: [
              if (account.accountType.trim().isNotEmpty)
                account.accountType.trim(),
              revolvingFormatAccountNumber(account),
            ].join(' · '),
            onTap: () => open(account),
          ),
      ],
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.badge,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final Widget badge;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
              child: Row(
                children: [
                  badge,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: revolvingText(14,
                                weight: FontWeight.w700,
                                color: RevolvingPalette.navy)),
                        Text(detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: revolvingText(12,
                                color: RevolvingPalette.text)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      color: RevolvingPalette.navy),
                ],
              ),
            ),
          ),
        ),
      );
}

// ── 2. amount ─────────────────────────────────────────────────────────

class RevolvingTransferAmountPage extends StatefulWidget {
  const RevolvingTransferAmountPage({super.key, this.draft});

  final RevolvingTransferDraft? draft;

  @override
  State<RevolvingTransferAmountPage> createState() =>
      _RevolvingTransferAmountPageState();
}

class _RevolvingTransferAmountPageState
    extends State<RevolvingTransferAmountPage> {
  late final RevolvingTransferDraft _draft =
      widget.draft ?? _mockDraft(amount: 0);
  final TextEditingController _amount = TextEditingController();
  double _value = 0;

  RevolvingCardView get _card => _draft.card;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  bool get _canContinue => _card.canWithdraw(_value);

  String? get _refusal => _card.withdrawalRefusal(_value);

  void _continue() => context.push(
        AppRoutes.revolvingTransferConfirm,
        extra: RevolvingTransferDraft(
          card: _card,
          account: _draft.account,
          amount: _value,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return RevolvingOrangePage(
      title: 'โอน / ถอนเงินสินเชื่อ',
      subtitle: 'จาก',
      orangeHeight: 190,
      onBack: () => revolvingBack(context),
      card: RevolvingSummaryCard(card: _card, mode: RevolvingCardMode.limits),
      bottom: RevolvingButton(
        label: 'ดำเนินการต่อ',
        onTap: _canContinue ? _continue : null,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: RevolvingPanel(
            color: RevolvingPalette.peach,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('ไปยัง',
                    style: revolvingText(16,
                        weight: FontWeight.w700,
                        color: RevolvingPalette.navy)),
                const SizedBox(height: 12),
                ..._account(),
                const SizedBox(height: 12),
                _amountBox(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _account() => [
        Row(
          children: [
            RevolvingAccountBadge(account: _draft.account, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Text(revolvingAccountTitle(_draft.account),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: revolvingText(14,
                      weight: FontWeight.w700,
                      color: RevolvingPalette.navy)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(revolvingAccountNumberLabel(_draft.account),
                  style: revolvingText(11, color: RevolvingPalette.text)),
              Text(revolvingFormatAccountNumber(_draft.account),
                  style: revolvingText(17,
                      weight: FontWeight.w600, color: RevolvingPalette.navy)),
            ],
          ),
        ),
      ];

  Widget _amountBox() => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                'จำนวนเงิน (ขั้นต่ำ ${formatWholeAmount(_card.minimumWithdrawal)} บาท)',
                style: revolvingText(12,
                    weight: FontWeight.w600, color: RevolvingPalette.navy)),
            const SizedBox(height: 12),
            RevolvingAmountField(
              controller: _amount,
              onChanged: (v) => setState(() => _value = v),
            ),
            if (_refusal != null) ...[
              const SizedBox(height: 10),
              Text(_refusal!,
                  key: const ValueKey('revolving-amount-refusal'),
                  style: revolvingText(12, color: RevolvingPalette.red)),
            ],
          ],
        ),
      );
}

String formatWholeAmount(double value) =>
    revolvingMoney(value).replaceAll('.00', '');

// ── 3. confirm + 4. success ───────────────────────────────────────────

/// The pale-blue ไปยัง box for a withdrawal: the chosen destination, its
/// holder, and its number masked to the last four digits.
Widget _destinationBox(RevolvingTransferDraft draft) {
  final a = draft.account;
  final holder = a.accountName.trim();
  return RevolvingAccountPartyBox(
    label: 'ไปยัง',
    badge: RevolvingAccountBadge(account: a, size: 20),
    name: revolvingAccountTitle(a),
    lines: [holder.isEmpty ? '-' : holder, revolvingMaskAccountNumber(a)],
  );
}

/// The draft a screen opened without one falls back to: the mock card's
/// default account.
RevolvingTransferDraft _mockDraft({required double amount}) {
  final card = RevolvingCardView.mock();
  return RevolvingTransferDraft(
    card: card,
    account: card.bankAccounts.firstWhere((a) => a.isDefault,
        orElse: () => card.bankAccounts.first),
    amount: amount,
  );
}

class RevolvingTransferConfirmPage extends StatelessWidget {
  const RevolvingTransferConfirmPage({super.key, this.draft});

  final RevolvingTransferDraft? draft;

  @override
  Widget build(BuildContext context) {
    final d = draft ?? _mockDraft(amount: 2000);
    return RevolvingPeachPage(
      onBack: () => revolvingBack(context),
      bottom: RevolvingButton(
        label: 'ยืนยัน',
        onTap: () => context.pushReplacement(
            AppRoutes.revolvingTransferSuccess,
            extra: d),
      ),
      children: [
        RevolvingPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('ยืนยันการโอน / ถอนเงิน',
                  style: revolvingText(16,
                      weight: FontWeight.w700, color: RevolvingPalette.blue)),
              const SizedBox(height: 16),
              RevolvingCardPartyBox(label: 'จาก', card: d.card),
              const RevolvingFlowArrow(),
              _destinationBox(d),
              RevolvingBigAmountRow(amount: d.amount),
              const Divider(color: RevolvingPalette.divider),
              RevolvingKeyValue(
                label: 'ค่าธรรมเนียม',
                value: revolvingMoneyOrDash(d.card.transferFee),
              ),
            ],
          ),
        ),
        const RevolvingTransferDisclosure(),
      ],
    );
  }
}

class RevolvingTransferSuccessPage extends StatelessWidget {
  const RevolvingTransferSuccessPage({super.key, this.draft});

  final RevolvingTransferDraft? draft;

  @override
  Widget build(BuildContext context) {
    final d = draft ?? _mockDraft(amount: 2000);
    return RevolvingPeachPage(
      bottom: const RevolvingHomeButton(),
      children: [
        RevolvingPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('โอน/ถอนเงินสำเร็จ',
                  style: revolvingText(16,
                      weight: FontWeight.w700, color: RevolvingPalette.blue)),
              Text(revolvingStampNow(),
                  style: revolvingText(11, color: RevolvingPalette.text)),
              const SizedBox(height: 14),
              RevolvingCardPartyBox(label: 'จาก', card: d.card),
              const RevolvingFlowArrow(),
              _destinationBox(d),
              RevolvingBigAmountRow(amount: d.amount),
              const Divider(color: RevolvingPalette.divider),
              RevolvingKeyValue(
                label: 'ค่าธรรมเนียม',
                value: revolvingMoneyOrDash(d.card.transferFee),
              ),
            ],
          ),
        ),
        const RevolvingTransferDisclosure(),
      ],
    );
  }
}

/// `15 ม.ค.69, 15.38 น.` — the moment a success screen opened. A stand-in
/// for the server's transaction time, which will replace it.
String revolvingStampNow([DateTime? at]) {
  const months = [
    'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', //
    'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
  ];
  final t = at ?? DateTime.now();
  final yy = ((t.year + 543) % 100).toString().padLeft(2, '0');
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '${t.day} ${months[t.month - 1]}$yy, $hh.$mm น.';
}
