/// **ชำระเงิน — บัตรศรีสวัสดิ์**, design pages 7–9.
///
/// ```
/// ชำระเงิน ─┬─ ยอดแนะนำให้ชำระขั้นต่ำ → ยืนยันการชำระเงิน → ชำระเงินสำเร็จ
///           └─ กำหนดยอดชำระเอง      → ชำระด้วย QR
/// ```
///
/// ⚠ **The branch split is read off the design's arrows**, which draw the
/// suggested amount into the confirm screen (page 8) and the typed amount
/// into the QR (page 9). Confirm with the BA — it may instead be that both go
/// to either, depending on whether the customer has a bound account.
///
/// ⚠ **UI and navigation only** (2026-11-11). Nothing is debited and the QR
/// carries mock references.
library;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../loan_register/components/env_version_tag.dart';
import '../router/app_router.dart';
import 'components/revolving_components.dart';
import 'models/revolving_mock.dart';
import 'revolving_transfer_pages.dart' show revolvingStampNow;

enum _PayOption { suggested, custom }

class RevolvingPaymentPage extends StatefulWidget {
  const RevolvingPaymentPage({super.key, this.card});

  final RevolvingCardView? card;

  @override
  State<RevolvingPaymentPage> createState() => _RevolvingPaymentPageState();
}

class _RevolvingPaymentPageState extends State<RevolvingPaymentPage> {
  late final RevolvingCardView _card = widget.card ?? RevolvingCardView.mock();
  final TextEditingController _custom = TextEditingController();
  _PayOption? _option;
  double _customValue = 0;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  bool get _canPay => switch (_option) {
        _PayOption.suggested => true,
        _PayOption.custom => _customValue > 0,
        null => false,
      };

  void _pay() {
    switch (_option) {
      case _PayOption.suggested:
        context.push(
          AppRoutes.revolvingPaymentConfirm,
          extra: RevolvingPaymentDraft(
              card: _card, amount: _card.suggestedPayment),
        );
      case _PayOption.custom:
        context.push(
          AppRoutes.revolvingQr,
          extra: RevolvingPaymentDraft(card: _card, amount: _customValue),
        );
      case null:
        break;
    }
  }

  void _select(_PayOption option) =>
      setState(() => _option = _option == option ? null : option);

  @override
  Widget build(BuildContext context) => RevolvingOrangePage(
        title: 'ชำระเงิน',
        subtitle: 'ข้อมูลวันที่ ${_card.dataDateLabel}',
        onBack: () => revolvingBack(context),
        card: RevolvingSummaryCard(
          card: _card,
          // The card's own ชำระเงิน is the suggested amount — the same thing
          // the first option offers.
          onPay: () {
            setState(() => _option = _PayOption.suggested);
            _pay();
          },
        ),
        bottom: RevolvingButton(label: 'ชำระเงิน', onTap: _canPay ? _pay : null),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
            child: Text('กรุณาเลือกจำนวนเงินที่ต้องการชำระ',
                style: revolvingText(14,
                    weight: FontWeight.w600, color: RevolvingPalette.navy)),
          ),
          _OptionCard(
            selected: _option == _PayOption.suggested,
            onTap: () => _select(_PayOption.suggested),
            title: 'ยอดแนะนำให้ชำระขั้นต่ำ',
            trailing: '${revolvingMoney(_card.suggestedPayment)} บาท',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('ยอดที่แนะนำชำระ',
                    style: revolvingText(14,
                        weight: FontWeight.w700,
                        color: RevolvingPalette.navy)),
                const SizedBox(height: 4),
                for (final row in _card.suggestedBreakdown)
                  RevolvingKeyValue(
                    label: row.label,
                    value: row.value,
                    padding: const EdgeInsets.symmetric(vertical: 3),
                  ),
              ],
            ),
          ),
          _OptionCard(
            selected: _option == _PayOption.custom,
            onTap: () => _select(_PayOption.custom),
            title: 'กำหนดยอดชำระเอง',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('กำหนดยอดชำระ',
                    style: revolvingText(13,
                        weight: FontWeight.w600,
                        color: RevolvingPalette.navy)),
                const SizedBox(height: 10),
                _redNote('*หากจ่ายไม่ครบหรือจ่ายช้า\n'
                    'จะถูกเรียกเก็บดอกเบี้ยและค่าธรรมเนียม'),
                _redNote('**ถ้าจ่ายขั้นต่ำทำให้ต้องเสียดอกเบี้ยสูงและเป็นหนี้นาน\n'
                    'ถ้าจ่ายมากกว่าขั้นต่ำจะช่วยลดดอกเบี้ยและปิดหนี้เร็วขึ้น'),
                _redNote('***ไม่สามารถระบุจำนวนเงินเกินยอดหนี้คงเหลือได้'),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _custom,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]')),
                        ],
                        onChanged: (text) => setState(() => _customValue =
                            double.tryParse(text.replaceAll(',', '')) ?? 0),
                        onEditingComplete: () {
                          _custom.text = revolvingMoney(_customValue);
                          FocusScope.of(context).unfocus();
                        },
                        style: revolvingText(28,
                            weight: FontWeight.w700,
                            color: RevolvingPalette.navy),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: '0.00',
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('บาท',
                          style: revolvingText(14,
                              color: RevolvingPalette.navy)),
                    ),
                  ],
                ),
                const Divider(color: RevolvingPalette.divider),
              ],
            ),
          ),
        ],
      );

  Widget _redNote(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: revolvingText(11,
                weight: FontWeight.w600,
                color: RevolvingPalette.red,
                height: 1.4)),
      );
}

/// One payment choice: a header that selects it, and a body shown while it is
/// selected.
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.selected,
    required this.onTap,
    required this.title,
    required this.body,
    this.trailing,
  });

  final bool selected;
  final VoidCallback onTap;
  final String title;
  final String? trailing;
  final Widget body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: RevolvingPanel(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 16, 12, 16),
                  child: Row(
                    children: [
                      selected
                          ? Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: RevolvingPalette.orange, width: 2),
                              ),
                              child: const Icon(Icons.check,
                                  size: 14, color: RevolvingPalette.orange),
                            )
                          : Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: RevolvingPalette.text, width: 1.5),
                              ),
                            ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(title,
                            style: revolvingText(13,
                                weight: FontWeight.w700,
                                color: RevolvingPalette.navy)),
                      ),
                      if (trailing != null)
                        Text(trailing!,
                            style: revolvingText(14,
                                weight: FontWeight.w700,
                                color: RevolvingPalette.navy)),
                      Icon(
                        selected
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: RevolvingPalette.label,
                      ),
                    ],
                  ),
                ),
              ),
              if (selected)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: body,
                ),
            ],
          ),
        ),
      );
}

// ── confirm + success ─────────────────────────────────────────────────

RevolvingPaymentDraft _fallbackDraft() {
  final card = RevolvingCardView.mock();
  return RevolvingPaymentDraft(card: card, amount: card.suggestedPayment);
}

class RevolvingPaymentConfirmPage extends StatelessWidget {
  const RevolvingPaymentConfirmPage({super.key, this.draft});

  final RevolvingPaymentDraft? draft;

  @override
  Widget build(BuildContext context) {
    final d = draft ?? _fallbackDraft();
    return RevolvingPeachPage(
      onBack: () => revolvingBack(context),
      bottom: RevolvingButton(
        label: 'ยืนยัน',
        onTap: () => context.pushReplacement(
            AppRoutes.revolvingPaymentSuccess,
            extra: d),
      ),
      children: [
        RevolvingPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('ยืนยันการชำระเงิน',
                  style: revolvingText(16,
                      weight: FontWeight.w700, color: RevolvingPalette.blue)),
              const SizedBox(height: 16),
              RevolvingAccountPartyBox(
                label: 'จาก',
                badge: RevolvingBankBadge(code: d.card.bankShortCode, size: 20),
                name: d.card.bankName,
                lines: [d.card.payerPlaceholder, d.card.bankAccountMasked],
              ),
              const RevolvingFlowArrow(),
              RevolvingCardPartyBox(label: 'ไปยัง', card: d.card),
              RevolvingBigAmountRow(amount: d.amount),
            ],
          ),
        ),
      ],
    );
  }
}

class RevolvingPaymentSuccessPage extends StatelessWidget {
  const RevolvingPaymentSuccessPage({super.key, this.draft});

  final RevolvingPaymentDraft? draft;

  /// Mock split of the amount — the real one comes back from the payment.
  static const double _mockInterest = 100.25;

  @override
  Widget build(BuildContext context) {
    final d = draft ?? _fallbackDraft();
    final interest = d.amount < _mockInterest ? d.amount : _mockInterest;
    return RevolvingPeachPage(
      bottom: const RevolvingHomeButton(),
      children: [
        RevolvingPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('ชำระเงินสำเร็จ',
                  style: revolvingText(16,
                      weight: FontWeight.w700, color: RevolvingPalette.blue)),
              Text(revolvingStampNow(),
                  style: revolvingText(11, color: RevolvingPalette.text)),
              const SizedBox(height: 12),
              Row(
                children: [
                  const RevolvingCardImage(width: 70),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.card.title,
                            style: revolvingText(14,
                                weight: FontWeight.w700,
                                color: RevolvingPalette.blue)),
                        Text('เลขทะเบียน ${d.card.plateLong}',
                            style: revolvingText(13,
                                color: RevolvingPalette.blue)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('รายละเอียดการชำระ',
                  style: revolvingText(14,
                      weight: FontWeight.w700, color: RevolvingPalette.navy)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F8FA),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('ช่องทางชำระ',
                                style: revolvingText(13)),
                          ),
                          RevolvingBankBadge(
                              code: d.card.bankShortCode, size: 18),
                          const SizedBox(width: 6),
                          Text(d.card.bankName,
                              style: revolvingText(13,
                                  weight: FontWeight.w700,
                                  color: RevolvingPalette.navy)),
                        ],
                      ),
                    ),
                    RevolvingKeyValue(
                        label: 'เงินต้น',
                        value: '${revolvingMoney(d.amount - interest)} บาท'),
                    RevolvingKeyValue(
                        label: 'ดอกเบี้ย',
                        value: '${revolvingMoney(interest)} บาท'),
                    const Divider(color: RevolvingPalette.divider),
                    RevolvingKeyValue(
                      label: 'ยอดที่ชำระ',
                      value: '${revolvingMoney(d.amount)} บาท',
                      bold: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── QR ────────────────────────────────────────────────────────────────

/// **ชำระด้วย QR** for a typed amount.
///
/// ⚠ Mock references and a mock payload. When wired, reuse the loan-payment
/// QR screen's payload rule (`genQRCodePayment`, Outstanding #29) and its
/// capture/save (`services/qr_image_capture.dart`) rather than a third copy.
class RevolvingQrPage extends StatelessWidget {
  const RevolvingQrPage({super.key, this.draft});

  final RevolvingPaymentDraft? draft;

  @override
  Widget build(BuildContext context) {
    final d = draft ?? _fallbackDraft();
    final card = d.card;
    final payload = '|0105563150452 01\n${card.qrRef1}\n${card.qrRef2}\n'
        '${(d.amount * 100).round()}\n';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => revolvingBack(context),
          icon: const Icon(Icons.arrow_back, color: RevolvingPalette.orange),
        ),
        title: Text('ชำระด้วย QR',
            style: revolvingText(15,
                weight: FontWeight.w700, color: RevolvingPalette.navy)),
        actions: const [EnvVersionTag()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: RevolvingPalette.orange,
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
              child: RevolvingSummaryCard(
                card: card,
                mode: RevolvingCardMode.qr,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '*กรุณาชำระเงินภายในวัน 00:05 ถึง 22:45 เท่านั้น\n'
              'เพื่อหลีกเลี่ยงการเสียดอกเบี้ยเพิ่มเติม',
              textAlign: TextAlign.center,
              style: revolvingText(12,
                  color: RevolvingPalette.red, height: 1.4),
            ),
            const SizedBox(height: 14),
            Center(
              child: Container(
                width: 150,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B2347),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('คิวอาร์โค้ด',
                    style: revolvingText(13,
                        weight: FontWeight.w600, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F5F7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: BarcodeWidget(
                  barcode: Barcode.qrCode(),
                  data: payload,
                  width: 180,
                  height: 180,
                  drawText: false,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => showRevolvingNotYet(context, 'บันทึกรูป QR'),
                icon: const Icon(Icons.download, size: 16),
                label: Text('บันทึกรูป QR', style: revolvingText(12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: RevolvingPalette.navy,
                  side: const BorderSide(color: RevolvingPalette.divider),
                  shape: const StadiumBorder(),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _RefLine(label: 'R1', value: card.qrRef1),
            _RefLine(label: 'R2', value: card.qrRef2),
            const SizedBox(height: 18),
            Text(
              'สามารถสแกนชำระค่างวด ผ่านโมบายแอปได้ทุกธนาคาร\n'
              'ยกเว้นธนาคาร ธ.ก.ส. และ ออมสิน',
              textAlign: TextAlign.center,
              style: revolvingText(12, color: RevolvingPalette.label),
            ),
          ],
        ),
      ),
    );
  }
}

class _RefLine extends StatelessWidget {
  const _RefLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$label : $value',
              style: revolvingText(12, color: RevolvingPalette.text)),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 14,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('คัดลอก $label แล้ว')));
            },
            icon: const Icon(Icons.copy, color: RevolvingPalette.label),
          ),
        ],
      );
}
