/// **ดูบิล** — design page 6. Two branches, decided by whether this cycle's
/// statement has been issued:
///
/// | | Shows |
/// | --- | --- |
/// | ยังไม่ถึงวันสรุปยอด | a "not yet" dialog naming the issue and due dates |
/// | ถึงวันสรุปยอด | the statement (ใบแจ้งหนี้), zoomable, with ✕ |
///
/// ⚠ The statement is a **drawn placeholder** — the real one is presumably a
/// PDF or image from an endpoint that does not exist yet.
library;

import 'package:flutter/material.dart';

import '../models/revolving_mock.dart';
import 'revolving_components.dart';

Future<void> showRevolvingBill(BuildContext context, RevolvingCardView card) =>
    showDialog<void>(
      context: context,
      builder: (_) => card.billReady
          ? _StatementDialog(card: card)
          : _NotIssuedDialog(card: card),
    );

class _NotIssuedDialog extends StatelessWidget {
  const _NotIssuedDialog({required this.card});

  final RevolvingCardView card;

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ยังไม่สามารถออกใบแจ้งหนี้ได้',
                  textAlign: TextAlign.center,
                  style: revolvingText(15,
                      weight: FontWeight.w700, color: RevolvingPalette.navy)),
              const SizedBox(height: 4),
              Text(
                'ระบบออกใบแจ้งหนี้ตั้งแต่วันที่ ${card.billIssueDate}\n'
                '(กำหนดออกใบแจ้งหนี้ล่วงหน้า 5 วัน\n'
                'ก่อนวันครบกำหนดชำระ ${card.billDueDate})',
                textAlign: TextAlign.center,
                style: revolvingText(13,
                    color: RevolvingPalette.navy, height: 1.5),
              ),
              const SizedBox(height: 20),
              Container(
                width: 130,
                height: 130,
                decoration: const BoxDecoration(
                  color: Color(0xFFFCE4EC),
                  shape: BoxShape.circle,
                ),
                child: const Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.description_outlined,
                        size: 64, color: Color(0xFF7986CB)),
                    Positioned(
                      right: 28,
                      bottom: 28,
                      child: Icon(Icons.search,
                          size: 34, color: Color(0xFFE57373)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: RevolvingPalette.tabBlue),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('ปิด',
                      style: revolvingText(14, color: RevolvingPalette.tabBlue)),
                ),
              ),
            ],
          ),
        ),
      );
}

class _StatementDialog extends StatelessWidget {
  const _StatementDialog({required this.card});

  final RevolvingCardView card;

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 40),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 28, color: Colors.black),
                ),
              ),
              InteractiveViewer(
                maxScale: 4,
                child: _StatementPlaceholder(card: card),
              ),
            ],
          ),
        ),
      );
}

/// A stand-in ใบแจ้งหนี้ laid out like the design's, so the dialog has the
/// right proportions until the real document is wired.
class _StatementPlaceholder extends StatelessWidget {
  const _StatementPlaceholder({required this.card});

  final RevolvingCardView card;

  @override
  Widget build(BuildContext context) {
    TextStyle s(double size, [FontWeight w = FontWeight.w400]) =>
        revolvingText(size, weight: w, color: Colors.black87);
    Widget row(String label, String a, String b, String total,
            {bool bold = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(
            children: [
              Expanded(
                  flex: 4,
                  child: Text(label,
                      style: s(7, bold ? FontWeight.w700 : FontWeight.w400))),
              Expanded(flex: 2, child: Text(a, textAlign: TextAlign.right, style: s(7))),
              Expanded(flex: 2, child: Text(b, textAlign: TextAlign.right, style: s(7))),
              Expanded(
                  flex: 2,
                  child: Text(total,
                      textAlign: TextAlign.right,
                      style: s(7, bold ? FontWeight.w700 : FontWeight.w400))),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: Colors.black54)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const RevolvingLogo(),
              const SizedBox(width: 6),
              Expanded(child: Text('บริษัท เงินสดทันใจ จำกัด', style: s(9, FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 6),
          Center(child: Text('ใบแจ้งหนี้', style: s(13, FontWeight.w700))),
          Center(child: Text('OFFICIAL INVOICE', style: s(7))),
          const Divider(height: 12),
          Text('เลขที่สัญญา: ${card.contractNo.isEmpty ? '-' : card.contractNo}',
              style: s(7)),
          Text('ประเภทสินเชื่อ: ${card.title}', style: s(7)),
          Text('แจ้งยอดครบกำหนดชำระ: ${card.dueDateLabel}', style: s(7)),
          const Divider(height: 12),
          row('', 'เงินต้น', 'ดอกเบี้ย', 'ยอดรวม', bold: true),
          row('ยอดยกมา', '0.00', '0.00', '0.00'),
          row('ยอดใช้วงเงินในรอบ', '40,000.00', '0.00', '40,000.00'),
          row('ดอกเบี้ยในรอบ', '0.00', '657.53', '657.53'),
          row('จำนวนเงินที่ต้องชำระ', '40,000.00', '657.53', '40,657.53',
              bold: true),
          row('จำนวนเงินขั้นต่ำที่ต้องชำระ', '', '',
              revolvingMoney(card.suggestedPayment),
              bold: true),
          const SizedBox(height: 8),
          Text('* ตัวอย่างเอกสาร — ยังไม่เชื่อมต่อข้อมูลจริง',
              style: revolvingText(7, color: RevolvingPalette.red)),
        ],
      ),
    );
  }
}
