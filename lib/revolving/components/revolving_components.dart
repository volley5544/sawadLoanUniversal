/// Shared building blocks for the บัตรศรีสวัสดิ์ (revolving) screens.
///
/// ⚠ **This feature carries its own palette** ([RevolvingPalette]), like the
/// top-up redesign and the loan detail screen: the design is the BA's, handed
/// over as renders (`etc/revolving_feature/`), and its orange header and blue
/// figures are not [LoanRegisterStyles]. Don't copy the palette elsewhere.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../loan_register/components/env_version_tag.dart';
import '../../p_loan/application/components/p_loan_components.dart';
import '../../router/app_router.dart';
import '../../services/native_bridge.dart';
import '../models/revolving_mock.dart';

abstract final class RevolvingPalette {
  static const Color orange = Color(0xFFF7871F);
  static const Color orangeLight = Color(0xFFFFA347);
  static const Color navy = Color(0xFF16284F);
  static const Color blue = Color(0xFF1F5FD1);
  static const Color tabBlue = Color(0xFF0D4FA8);
  static const Color progress = Color(0xFF6E74E0);
  static const Color label = Color(0xFF8A8F98);
  static const Color text = Color(0xFF3C4250);
  static const Color pageBg = Color(0xFFF6F7F9);
  static const Color peach = Color(0xFFFBEFE4);
  static const Color softBlue = Color(0xFFE9F0FB);
  static const Color divider = Color(0xFFE6E8EC);
  static const Color red = Color(0xFFE53935);
}

TextStyle revolvingText(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = RevolvingPalette.text,
  double? height,
}) =>
    GoogleFonts.notoSansThai(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );

/// `2500.25` → `2,500.25`.
String revolvingMoney(num value) => formatMoney(value);

/// "Not wired yet" — every action button in this feature is navigation-only
/// for now (2026-11-11), so the ones that would *do* something say so.
void showRevolvingNotYet(BuildContext context, [String what = '']) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(
        '${what.isEmpty ? 'ฟังก์ชันนี้' : what} ยังไม่เปิดใช้งาน (UI เท่านั้น)'),
  ));
}

/// Back out of a revolving screen: pop when something is beneath it, else —
/// the host opened this route directly — close the WebView (or go home in a
/// plain browser).
void revolvingBack(BuildContext context, {bool fromHost = false}) {
  if (!fromHost && context.canPop()) {
    context.pop();
    return;
  }
  if (NativeCameraBridge.isSupported) {
    NativeCameraBridge.closeWebview();
  } else {
    context.go(AppRoutes.home);
  }
}

/// กลับหน้าหลัก on the two success screens: back to the card's home screen,
/// dropping the confirm/amount screens beneath it.
void revolvingBackToHome(BuildContext context) {
  var found = false;
  Navigator.of(context).popUntil((route) {
    if (route.settings.name == AppRoutes.revolving) {
      found = true;
      return true;
    }
    return route.isFirst;
  });
  if (!found) context.go(AppRoutes.revolving);
}

// ── page shell ────────────────────────────────────────────────────────

/// The orange-topped page every main revolving screen uses: a title and
/// `ข้อมูลวันที่ …` on orange, and [card] overlapping the orange's lower edge.
class RevolvingOrangePage extends StatelessWidget {
  const RevolvingOrangePage({
    super.key,
    required this.title,
    required this.card,
    required this.children,
    this.subtitle,
    this.onBack,
    this.bottom,
    this.orangeHeight = 200,
    this.background = RevolvingPalette.pageBg,
  });

  final String title;
  final String? subtitle;
  final Widget card;
  final List<Widget> children;
  final VoidCallback? onBack;
  final Widget? bottom;
  final double orangeHeight;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: background,
        bottomNavigationBar: bottom == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: bottom,
                ),
              ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Stack(
            children: [
              Container(
                height: orangeHeight + top,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      RevolvingPalette.orange,
                      RevolvingPalette.orangeLight
                    ],
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: top),
                  _Header(title: title, subtitle: subtitle, onBack: onBack),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: card,
                  ),
                  ...children,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.subtitle, this.onBack});

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 0, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onBack != null)
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_ios_new,
                    size: 18, color: Colors.white),
              )
            else
              const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: revolvingText(20,
                            weight: FontWeight.w700, color: Colors.white)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(subtitle!,
                          style: revolvingText(12,
                              color: Colors.white.withValues(alpha: 0.9))),
                  ],
                ),
              ),
            ),
            const EnvVersionTag(),
          ],
        ),
      );
}

/// The peach page the confirm and success screens use: the company mark on
/// top, then a white card.
class RevolvingPeachPage extends StatelessWidget {
  const RevolvingPeachPage({
    super.key,
    required this.children,
    this.onBack,
    this.bottom,
  });

  final List<Widget> children;
  final VoidCallback? onBack;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: RevolvingPalette.peach,
        appBar: AppBar(
          backgroundColor: RevolvingPalette.peach,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: onBack == null
              ? null
              : IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_ios_new,
                      size: 18, color: RevolvingPalette.navy),
                ),
          centerTitle: true,
          title: const RevolvingLogo(),
          actions: const [EnvVersionTag()],
        ),
        bottomNavigationBar: bottom == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: bottom,
                ),
              ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );
}

/// The ศรีสวัสดิ์ mark.
///
/// ⚠ A text stand-in: the repo has no logo asset. Swap for the real SVG/PNG
/// when one is supplied.
class RevolvingLogo extends StatelessWidget {
  const RevolvingLogo({super.key});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: RevolvingPalette.navy,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: RevolvingPalette.orange, width: 2),
            ),
            child: Text('ศ',
                style: revolvingText(14,
                    weight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text('ศรีสวัสดิ์',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: revolvingText(20,
                    weight: FontWeight.w800, color: RevolvingPalette.blue)),
          ),
        ],
      );
}

// ── the card ──────────────────────────────────────────────────────────

/// The orange card picture.
///
/// ⚠ Drawn, not an image — no card artwork was supplied with the design.
class RevolvingCardImage extends StatelessWidget {
  const RevolvingCardImage({super.key, this.width = 64});

  final double width;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: width * 0.62,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE2681B), Color(0xFFF7B04A), Color(0xFFD9561A)],
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x22000000), blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
        padding: EdgeInsets.all(width * 0.08),
        alignment: Alignment.topLeft,
        child: Container(
          width: width * 0.16,
          height: width * 0.12,
          decoration: BoxDecoration(
            color: const Color(0xFFF3D27A),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

/// Picture + `บัตรศรีสวัสดิ์ …` + `เลขทะเบียน กพ 5161`.
class RevolvingCardTitle extends StatelessWidget {
  const RevolvingCardTitle({super.key, required this.card});

  final RevolvingCardView card;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const RevolvingCardImage(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.title,
                    style: revolvingText(15,
                        weight: FontWeight.w700, color: RevolvingPalette.navy)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text('เลขทะเบียน',
                        style: revolvingText(12, color: RevolvingPalette.navy)),
                    const SizedBox(width: 24),
                    Flexible(
                      child: Text(card.plate,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: revolvingText(13,
                              weight: FontWeight.w700,
                              color: RevolvingPalette.navy)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
}

/// A figure with its small grey label above it.
class RevolvingFigure extends StatelessWidget {
  const RevolvingFigure({
    super.key,
    required this.label,
    required this.amount,
    this.alignEnd = false,
    this.size = 17,
  });

  final String label;
  final double amount;
  final bool alignEnd;
  final double size;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(label, style: revolvingText(11, color: RevolvingPalette.label)),
          Text.rich(TextSpan(children: [
            TextSpan(
                text: revolvingMoney(amount),
                style: revolvingText(size,
                    weight: FontWeight.w700, color: RevolvingPalette.navy)),
            TextSpan(
                text: ' บาท',
                style: revolvingText(12, color: RevolvingPalette.navy)),
          ])),
        ],
      );
}

enum RevolvingCardMode {
  /// Limits, progress bar and the suggested payment with its ชำระเงิน button.
  full,

  /// Limits only — the withdrawal screens.
  limits,

  /// Suggested payment and due date only — the QR screen.
  qr,
}

/// The white summary card under every orange header.
class RevolvingSummaryCard extends StatelessWidget {
  const RevolvingSummaryCard({
    super.key,
    required this.card,
    this.mode = RevolvingCardMode.full,
    this.onPay,
  });

  final RevolvingCardView card;
  final RevolvingCardMode mode;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[RevolvingCardTitle(card: card)];
    if (mode == RevolvingCardMode.qr) {
      children.addAll([
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text('กำหนดชำระ ${card.dueDateLabel}',
                  style: revolvingText(11, color: RevolvingPalette.label)),
            ),
            RevolvingFigure(
              label: 'ยอดที่แนะนำให้ชำระ',
              amount: card.suggestedPayment,
              alignEnd: true,
            ),
          ],
        ),
      ]);
    } else {
      children.addAll([
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: RevolvingFigure(
                  label: 'วงเงินคงเหลือ', amount: card.availableLimit),
            ),
            RevolvingFigure(
              label: 'วงเงินอนุมัติ',
              amount: card.approvedLimit,
              alignEnd: true,
            ),
          ],
        ),
      ]);
    }
    if (mode == RevolvingCardMode.full) {
      children.addAll([
        const SizedBox(height: 10),
        RevolvingProgressBar(ratio: card.usedRatio),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RevolvingFigure(
                    label: 'ยอดที่แนะนำให้ชำระ',
                    amount: card.suggestedPayment,
                  ),
                  const SizedBox(height: 2),
                  Text('กำหนดชำระ ${card.dueDateLabel}',
                      style: revolvingText(11, color: RevolvingPalette.label)),
                ],
              ),
            ),
            SizedBox(
              width: 120,
              child: RevolvingButton(label: 'ชำระเงิน', onTap: onPay, height: 42),
            ),
          ],
        ),
      ]);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// The line under the limits — how much of the line is drawn.
class RevolvingProgressBar extends StatelessWidget {
  const RevolvingProgressBar({super.key, required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final knob = (width - 12) * ratio.clamp(0, 1);
          return SizedBox(
            height: 12,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                    height: 3,
                    decoration: BoxDecoration(
                        color: RevolvingPalette.divider,
                        borderRadius: BorderRadius.circular(2))),
                Container(
                    width: knob + 6,
                    height: 3,
                    decoration: BoxDecoration(
                        color: RevolvingPalette.progress,
                        borderRadius: BorderRadius.circular(2))),
                Positioned(
                  left: knob,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: RevolvingPalette.progress, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

/// โอน/ถอนเงิน · ดูบิล · ชำระเงิน · ข้อมูลสัญญา.
class RevolvingActionRow extends StatelessWidget {
  const RevolvingActionRow({
    super.key,
    required this.onTransfer,
    required this.onBill,
    required this.onPay,
    required this.onContract,
  });

  final VoidCallback onTransfer;
  final VoidCallback onBill;
  final VoidCallback onPay;
  final VoidCallback onContract;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Action(Icons.swap_horiz, 'โอน/ถอนเงิน', onTransfer),
            _Action(Icons.description_outlined, 'ดูบิล', onBill),
            _Action(Icons.payments_outlined, 'ชำระเงิน', onPay),
            _Action(Icons.assignment_outlined, 'ข้อมูลสัญญา', onContract),
          ],
        ),
      );
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x10000000),
                        blurRadius: 6,
                        offset: Offset(0, 2)),
                  ],
                ),
                child: Icon(icon, color: RevolvingPalette.orange, size: 24),
              ),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  style: revolvingText(11, color: RevolvingPalette.navy)),
            ],
          ),
        ),
      );
}

// ── controls ──────────────────────────────────────────────────────────

/// The orange button.
class RevolvingButton extends StatelessWidget {
  const RevolvingButton({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? RevolvingPalette.orange : const Color(0xFFF5C597),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: height,
          child: Center(
            child: Text(label,
                style: revolvingText(16,
                    weight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}

/// A white rounded section.
class RevolvingPanel extends StatelessWidget {
  const RevolvingPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = Colors.white,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: child,
      );
}

/// Label left, value right.
class RevolvingKeyValue extends StatelessWidget {
  const RevolvingKeyValue({
    super.key,
    required this.label,
    required this.value,
    this.bold = false,
    this.padding = const EdgeInsets.symmetric(vertical: 5),
  });

  final String label;
  final String value;
  final bool bold;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: revolvingText(13,
                      weight: bold ? FontWeight.w700 : FontWeight.w400,
                      color: bold ? RevolvingPalette.navy : RevolvingPalette.text)),
            ),
            Text(value,
                style: revolvingText(13,
                    weight: bold ? FontWeight.w700 : FontWeight.w500,
                    color: RevolvingPalette.navy)),
          ],
        ),
      );
}

/// A bank's round badge.
///
/// ⚠ Initials on the bank's colour — no bank logos ship with this repo.
class RevolvingBankBadge extends StatelessWidget {
  const RevolvingBankBadge({super.key, required this.code, this.size = 22});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = switch (code) {
      'BAY' => const Color(0xFFFFD100),
      'KTB' => const Color(0xFF00A6E6),
      'SCB' => const Color(0xFF4E2A84),
      'KBANK' => const Color(0xFF138F2D),
      'BBL' => const Color(0xFF1E4598),
      _ => RevolvingPalette.label,
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        code.length > 3 ? code.substring(0, 3) : code,
        style: revolvingText(size * 0.32,
            weight: FontWeight.w700,
            color: code == 'BAY' ? const Color(0xFF5B4A00) : Colors.white),
      ),
    );
  }
}

/// The พร้อมเพย์ badge (a text stand-in for the PromptPay mark).
class RevolvingPromptPayBadge extends StatelessWidget {
  const RevolvingPromptPayBadge({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
            color: Color(0xFF113566), shape: BoxShape.circle),
        child: Text('Pay',
            style: revolvingText(size * 0.3,
                weight: FontWeight.w800, color: Colors.white)),
      );
}

/// The big blue amount, and the quick-amount chips under it.
class RevolvingAmountField extends StatelessWidget {
  const RevolvingAmountField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.chips = RevolvingCardView.quickAmounts,
  });

  final TextEditingController controller;
  final ValueChanged<double> onChanged;
  final List<double> chips;

  double get _value =>
      double.tryParse(controller.text.replaceAll(',', '')) ?? 0;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textAlign: TextAlign.right,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => onChanged(_value),
                  onEditingComplete: () {
                    controller.text = revolvingMoney(_value);
                    onChanged(_value);
                    FocusScope.of(context).unfocus();
                  },
                  style: revolvingText(26,
                      weight: FontWeight.w700, color: RevolvingPalette.blue),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '0.00',
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Text('บาท',
                    style: revolvingText(12, color: RevolvingPalette.blue)),
              ),
            ],
          ),
          const Divider(color: RevolvingPalette.divider, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final chip in chips)
                _Chip(
                  label: formatWholeMoney(chip),
                  selected: _value == chip,
                  onTap: () {
                    controller.text = revolvingMoney(chip);
                    onChanged(chip);
                  },
                ),
            ],
          ),
        ],
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 64,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white : RevolvingPalette.softBlue,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? RevolvingPalette.blue : Colors.transparent),
          ),
          child: Text(label,
              style: revolvingText(13,
                  weight: FontWeight.w600, color: RevolvingPalette.blue)),
        ),
      );
}

/// The orange จาก / ไปยัง box that names the card.
class RevolvingCardPartyBox extends StatelessWidget {
  const RevolvingCardPartyBox({
    super.key,
    required this.label,
    required this.card,
  });

  final String label;
  final RevolvingCardView card;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: RevolvingPalette.orange,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: revolvingText(13, color: Colors.white)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(card.title,
                      textAlign: TextAlign.right,
                      style: revolvingText(13,
                          weight: FontWeight.w700, color: Colors.white)),
                  Text('เลขทะเบียน ${card.plateLong}',
                      style: revolvingText(12, color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// The pale-blue จาก / ไปยัง box that names a bank account or PromptPay id.
class RevolvingAccountPartyBox extends StatelessWidget {
  const RevolvingAccountPartyBox({
    super.key,
    required this.label,
    required this.badge,
    required this.name,
    required this.lines,
  });

  final String label;
  final Widget badge;
  final String name;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: RevolvingPalette.softBlue,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: revolvingText(13, color: RevolvingPalette.navy)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      badge,
                      const SizedBox(width: 6),
                      Text(name,
                          style: revolvingText(13,
                              weight: FontWeight.w700,
                              color: RevolvingPalette.navy)),
                    ],
                  ),
                  for (final line in lines)
                    Text(line,
                        textAlign: TextAlign.right,
                        style:
                            revolvingText(12, color: RevolvingPalette.navy)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// The small blue arrow between a จาก and a ไปยัง box.
class RevolvingFlowArrow extends StatelessWidget {
  const RevolvingFlowArrow({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: const BoxDecoration(
              color: Colors.white, shape: BoxShape.circle),
          child: const Icon(Icons.arrow_downward,
              size: 14, color: RevolvingPalette.blue),
        ),
      );
}

/// `จำนวนเงิน   2,000.00 บาท` — the big figure on the confirm/success screens.
class RevolvingBigAmountRow extends StatelessWidget {
  const RevolvingBigAmountRow({super.key, required this.amount});

  final double amount;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text('จำนวนเงิน',
                  style: revolvingText(15,
                      weight: FontWeight.w700, color: RevolvingPalette.navy)),
            ),
            Text(revolvingMoney(amount),
                style: revolvingText(24,
                    weight: FontWeight.w700, color: RevolvingPalette.blue)),
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 4),
              child: Text('บาท',
                  style: revolvingText(11, color: RevolvingPalette.blue)),
            ),
          ],
        ),
      );
}

/// The interest-rate disclosure under a withdrawal.
///
/// Copied from the design verbatim, as are its figures; it is a regulatory
/// text, so confirm it with the business before go-live rather than editing.
class RevolvingTransferDisclosure extends StatelessWidget {
  const RevolvingTransferDisclosure({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: Text(
          'การโอนเงินทำให้เงินต้นคงเหลือเพิ่ม และส่งผลให้ผ่อนนานขึ้น\n\n'
          'กู้เท่าที่จำเป็นและชำระคืนไหว อัตราดอกเบี้ย\n'
          'สินเชื่อส่วนบุคคล หรือสินเชื่อทะเบียนรถ 12–24 % ต่อปี\n'
          'และสินเชื่อรายย่อยเพื่อการประกอบอาชีพ 33% ต่อปี\n'
          '(ณ วันที่ 18 เม.ย. 68)',
          textAlign: TextAlign.center,
          style: revolvingText(11, color: RevolvingPalette.label, height: 1.5),
        ),
      );
}

/// กลับหน้าหลัก, under a success screen.
class RevolvingHomeButton extends StatelessWidget {
  const RevolvingHomeButton({super.key});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => revolvingBackToHome(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: RevolvingPalette.blue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.home_outlined,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(height: 4),
              Text('กลับหน้าหลัก',
                  style: revolvingText(12, color: RevolvingPalette.blue)),
            ],
          ),
        ),
      );
}
