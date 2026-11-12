/// **ดูบิล** — design page 6. Two branches, decided by whether this cycle's
/// statement has been issued:
///
/// | | Shows |
/// | --- | --- |
/// | ยังไม่ถึงวันสรุปยอด | a "not yet" dialog naming the issue and due dates |
/// | ถึงวันสรุปยอด | the statement (ใบแจ้งหนี้), opened in the host's in-app browser |
///
/// The statement arrives from the API **as a URL** (confirmed 2026-11-11) and
/// is opened through `openExternalUrl` — the same path the loan detail
/// screen's documents take, since `window.open` is inert inside the host. The
/// design draws it in a ✕ dialog; that frame is the in-app browser's.
///
/// ⚠ No URL exists yet (the API isn't built), so an issued bill with an empty
/// [RevolvingCardView.billUrl] says so instead of opening nothing.
///
/// **A real card** (one built from `/loan/list`) does not show the demo
/// dates: its ดูบิล needs `createFileRequest`, which node-api has no route
/// for yet, so it says "not yet". [showRevolvingBillStatement] is what that
/// call's mapped response ([RevolvingBillStatement]) will drive.
library;

import 'package:flutter/material.dart';

import '../../services/external_url.dart';
import '../models/revolving_bill.dart';
import '../models/revolving_mock.dart';
import 'revolving_components.dart';

Future<void> showRevolvingBill(BuildContext context, RevolvingCardView card) =>
    !card.isDemo
        ? Future.sync(() => showRevolvingNotYet(context, 'ใบแจ้งหนี้'))
        : !card.billReady
        ? showDialog<void>(
            context: context,
            builder: (_) => _NotIssuedDialog(card: card),
          )
        : card.billUrl.trim().isEmpty
            ? Future.sync(() => showRevolvingNotYet(context, 'ใบแจ้งหนี้'))
            : openExternalDocument(context, card.billUrl.trim());

/// `createFileRequest`'s answer on screen: 200 opens `data.url`, anything
/// else shows the API's `detail` verbatim in the not-issued popup.
Future<void> showRevolvingBillStatement(
        BuildContext context, RevolvingBillStatement statement) =>
    statement.hasFile
        ? openExternalDocument(context, statement.url)
        : showDialog<void>(
            context: context,
            builder: (_) => _NotIssuedDialog(message: statement.message),
          );

class _NotIssuedDialog extends StatelessWidget {
  const _NotIssuedDialog({this.card, this.message});

  /// The demo: title + the design's composed sentence with its dates.
  final RevolvingCardView? card;

  /// The API's `detail`, shown alone.
  final String? message;

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message == null) ...[
                Text('ยังไม่สามารถออกใบแจ้งหนี้ได้',
                    textAlign: TextAlign.center,
                    style: revolvingText(15,
                        weight: FontWeight.w700,
                        color: RevolvingPalette.navy)),
                const SizedBox(height: 4),
              ],
              Text(
                message ??
                    'ระบบออกใบแจ้งหนี้ตั้งแต่วันที่ ${card!.billIssueDate}\n'
                        '(กำหนดออกใบแจ้งหนี้ล่วงหน้า 5 วัน\n'
                        'ก่อนวันครบกำหนดชำระ ${card!.billDueDate})',
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
