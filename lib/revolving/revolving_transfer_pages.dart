/// **โอน / ถอนเงินสินเชื่อ** — design pages 3–5: pick a destination, enter
/// an amount, confirm, done.
///
/// ```
/// destination ─┬─ พร้อมเพย์ ──────────┐
///              └─ บัญชีธนาคารที่ผูกไว้ ─┴─ amount → confirm → success
/// ```
///
/// ⚠ **UI and navigation only** (2026-11-11). ยืนยัน files nothing; the
/// success screen shows what was entered.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
    void open(RevolvingTransferTarget target) => context.push(
          AppRoutes.revolvingTransferAmount,
          extra: RevolvingTransferDraft(card: view, target: target, amount: 0),
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
        _DestinationTile(
          badge: const RevolvingPromptPayBadge(),
          label: 'พร้อมเพย์',
          onTap: () => open(RevolvingTransferTarget.promptPay),
        ),
        _DestinationTile(
          badge: Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
                color: RevolvingPalette.blue, shape: BoxShape.circle),
            child: const Icon(Icons.credit_card, color: Colors.white, size: 20),
          ),
          label: 'บัญชีธนาคารที่ผูกไว้',
          onTap: () => open(RevolvingTransferTarget.bankAccount),
        ),
      ],
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.badge,
    required this.label,
    required this.onTap,
  });

  final Widget badge;
  final String label;
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
                    child: Text(label,
                        style: revolvingText(14,
                            weight: FontWeight.w700,
                            color: RevolvingPalette.navy)),
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
  late final RevolvingTransferDraft _draft = widget.draft ??
      RevolvingTransferDraft(
        card: RevolvingCardView.mock(),
        target: RevolvingTransferTarget.promptPay,
        amount: 0,
      );
  final TextEditingController _amount = TextEditingController();
  double _value = 0;
  bool _usePhone = true;

  RevolvingCardView get _card => _draft.card;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  bool get _canContinue => _value >= _card.minimumWithdrawal;

  void _continue() => context.push(
        AppRoutes.revolvingTransferConfirm,
        extra: RevolvingTransferDraft(
          card: _card,
          target: _draft.target,
          amount: _value,
          promptPayUsesPhone: _usePhone,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isPromptPay = _draft.target == RevolvingTransferTarget.promptPay;
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
                if (isPromptPay) ..._promptPay() else ..._bankAccount(),
                const SizedBox(height: 12),
                _amountBox(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _promptPay() => [
        Row(
          children: [
            const RevolvingPromptPayBadge(size: 32),
            const SizedBox(width: 10),
            Text('พร้อมเพย์',
                style: revolvingText(14,
                    weight: FontWeight.w700, color: RevolvingPalette.navy)),
          ],
        ),
        const SizedBox(height: 12),
        _IdChoice(
          label: 'เบอร์โทรศัพท์',
          value: _card.promptPayPhone,
          selected: _usePhone,
          onTap: () => setState(() => _usePhone = true),
        ),
        const SizedBox(height: 8),
        _IdChoice(
          label: 'เลขบัตรประชาชน',
          value: _card.promptPayCitizenId,
          selected: !_usePhone,
          onTap: () => setState(() => _usePhone = false),
        ),
      ];

  List<Widget> _bankAccount() => [
        Row(
          children: [
            RevolvingBankBadge(code: _card.bankShortCode, size: 32),
            const SizedBox(width: 10),
            Text(_card.bankName,
                style: revolvingText(14,
                    weight: FontWeight.w700, color: RevolvingPalette.navy)),
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
              Text('เลขที่บัญชี',
                  style: revolvingText(11, color: RevolvingPalette.text)),
              Text(_card.bankAccountNo,
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
          ],
        ),
      );
}

String formatWholeAmount(double value) =>
    revolvingMoney(value).replaceAll('.00', '');

class _IdChoice extends StatelessWidget {
  const _IdChoice({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? RevolvingPalette.blue : RevolvingPalette.label,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : const Color(0xFFF7F3EF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: revolvingText(11, color: RevolvingPalette.text)),
                    Text(value,
                        style: revolvingText(14,
                            weight: FontWeight.w500,
                            color: RevolvingPalette.navy)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

// ── 3. confirm + 4. success ───────────────────────────────────────────

/// The pale-blue ไปยัง box for a withdrawal: the bound bank account, or the
/// PromptPay id the customer picked.
Widget _destinationBox(RevolvingTransferDraft draft) {
  final card = draft.card;
  if (draft.target == RevolvingTransferTarget.promptPay) {
    return RevolvingAccountPartyBox(
      label: 'ไปยัง',
      badge: const RevolvingPromptPayBadge(size: 20),
      name: 'พร้อมเพย์',
      lines: [
        card.accountHolderPlaceholder,
        draft.promptPayUsesPhone ? card.promptPayPhone : card.promptPayCitizenId,
      ],
    );
  }
  return RevolvingAccountPartyBox(
    label: 'ไปยัง',
    badge: RevolvingBankBadge(code: card.bankShortCode, size: 20),
    name: card.bankName,
    lines: [card.accountHolderPlaceholder, card.bankAccountMasked],
  );
}

class RevolvingTransferConfirmPage extends StatelessWidget {
  const RevolvingTransferConfirmPage({super.key, this.draft});

  final RevolvingTransferDraft? draft;

  @override
  Widget build(BuildContext context) {
    final d = draft ??
        RevolvingTransferDraft(
          card: RevolvingCardView.mock(),
          target: RevolvingTransferTarget.bankAccount,
          amount: 2000,
        );
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
                value: '${revolvingMoney(d.card.transferFee)} บาท',
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
    final d = draft ??
        RevolvingTransferDraft(
          card: RevolvingCardView.mock(),
          target: RevolvingTransferTarget.bankAccount,
          amount: 2000,
        );
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
                value: '${revolvingMoney(d.card.transferFee)} บาท',
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
