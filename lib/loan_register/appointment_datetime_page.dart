import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'components/env_version_tag.dart';
import 'components/loan_register_styles.dart';

/// วันที่-เวลา นัดหมาย — appointment date + time-slot picker (slide 9,
/// calendar frame).
///
/// Reached after the branch is chosen (native map via `openBranchPicker`, or
/// the web fallback [BranchSelectPage]). Shows a calendar and the day's time
/// slots (mock availability — a real build would fetch the branch's slots).
/// บันทึกข้อมูล pops the picked moment as a Buddhist-era string
/// `dd/MM/yyyy HH:mm น.`.
class AppointmentDateTimePage extends StatefulWidget {
  const AppointmentDateTimePage({Key? key, this.branchName}) : super(key: key);

  /// Shown in the summary bar so the user sees what they're booking.
  final String? branchName;

  @override
  State<AppointmentDateTimePage> createState() =>
      _AppointmentDateTimePageState();
}

class _AppointmentDateTimePageState extends State<AppointmentDateTimePage> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String? _selectedTime;

  /// Mock branch time slots. `false` = ไม่ว่าง (already booked).
  static const Map<String, bool> _slots = {
    '09:00': true,
    '10:00': true,
    '11:00': true,
    '12:00': false,
    '13:00': true,
    '14:00': false,
    '15:00': true,
    '16:00': true,
  };

  String get _buddhistDate =>
      '${_selectedDate.day.toString().padLeft(2, '0')}/'
      '${_selectedDate.month.toString().padLeft(2, '0')}/'
      '${_selectedDate.year + 543}';

  void _save() {
    context.pop('$_buddhistDate $_selectedTime น.');
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        actions: const [EnvVersionTag()],
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: LoanRegisterStyles.primary),
        centerTitle: true,
        title: Text('วันที่-เวลา นัดหมาย',
            style: LoanRegisterStyles.appBarTitleStyle()),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                  horizontal: LoanRegisterStyles.padding),
              children: [
                Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: Theme.of(context)
                        .colorScheme
                        .copyWith(primary: LoanRegisterStyles.primary),
                  ),
                  child: CalendarDatePicker(
                    initialDate: _selectedDate,
                    firstDate: today,
                    lastDate: today.add(const Duration(days: 60)),
                    onDateChanged: (date) => setState(() {
                      _selectedDate = date;
                      _selectedTime = null;
                    }),
                  ),
                ),
                Text('เวลานัดหมาย', style: LoanRegisterStyles.labelStyle()),
                const SizedBox(height: 8),
                for (final entry in _slots.entries) _slotRow(entry),
                const SizedBox(height: 12),
              ],
            ),
          ),
          _summaryBar(),
        ],
      ),
    );
  }

  Widget _slotRow(MapEntry<String, bool> slot) {
    final available = slot.value;
    final selected = slot.key == _selectedTime;
    return InkWell(
      onTap: available
          ? () => setState(() => _selectedTime = slot.key)
          : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? LoanRegisterStyles.primarySoft : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? LoanRegisterStyles.primary
                : LoanRegisterStyles.cardBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule,
                size: 18,
                color: available
                    ? LoanRegisterStyles.value
                    : LoanRegisterStyles.label),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${slot.key} น.',
                style: GoogleFonts.notoSansThai(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: available
                      ? LoanRegisterStyles.value
                      : LoanRegisterStyles.label,
                ),
              ),
            ),
            if (!available)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCE4EC),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'ไม่ว่าง',
                  style: GoogleFonts.notoSansThai(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFD81B60)),
                ),
              )
            else if (selected)
              Icon(Icons.check_circle,
                  size: 20, color: LoanRegisterStyles.primary),
          ],
        ),
      ),
    );
  }

  /// Bottom summary of the picked appointment + บันทึกข้อมูล (design's purple
  /// summary bar, restyled to the app's orange).
  Widget _summaryBar() {
    final canSave = _selectedTime != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(LoanRegisterStyles.padding, 4,
            LoanRegisterStyles.padding, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canSave)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: LoanRegisterStyles.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  [
                    if (widget.branchName?.isNotEmpty ?? false)
                      'สาขา${widget.branchName}',
                    '$_buddhistDate $_selectedTime น.',
                  ].join(' • '),
                  style: GoogleFonts.notoSansThai(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: LoanRegisterStyles.value,
                  ),
                ),
              ),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: canSave ? _save : null,
                style: FilledButton.styleFrom(
                  backgroundColor: LoanRegisterStyles.primary,
                  disabledBackgroundColor: LoanRegisterStyles.cardBorder,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  'บันทึกข้อมูล',
                  style: GoogleFonts.notoSansThai(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
