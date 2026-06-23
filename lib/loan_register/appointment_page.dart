import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../router/app_router.dart';
import 'components/loan_register_styles.dart';
import 'components/register_step_indicator.dart';
import 'components/save_next_bar.dart';
import 'models/loan_register_form.dart';

/// Step 5 of the loan-register wizard — นัดหมายส่งเอกสาร (Document-Delivery
/// Appointment). Second frame on slide 9.
///
/// The customer adds a branch + date/time appointment (the
/// "เพิ่ม สาขาและวันที่-เวลานัดหมาย" card opens the
/// [DocumentsToPreparePage] → branch/calendar pickers), then reviews their
/// appointment list. ถัดไป completes the (UI-only) flow.
class AppointmentPage extends StatefulWidget {
  const AppointmentPage({Key? key, this.form}) : super(key: key);

  final LoanRegisterForm? form;

  @override
  State<AppointmentPage> createState() => _AppointmentPageState();
}

class _AppointmentPageState extends State<AppointmentPage> {
  late final LoanRegisterForm _form = widget.form ?? LoanRegisterForm.mock();

  bool get _hasAppointment => _form.appointmentBranch.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: LoanRegisterStyles.primary),
        centerTitle: true,
        title: Text('5. นัดหมายส่งเอกสาร',
            style: LoanRegisterStyles.appBarTitleStyle()),
      ),
      body: Column(
        children: [
          const RegisterStepIndicator(currentStep: 5),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  horizontal: LoanRegisterStyles.padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text('กรุณาเลือกรายการ',
                      style: LoanRegisterStyles.labelStyle()),
                  const SizedBox(height: 12),
                  _MenuCard(
                    icon: Icons.event_outlined,
                    title: 'เพิ่ม สาขาและวันที่-เวลานัดหมาย',
                    subtitle: _hasAppointment
                        ? '${_form.appointmentBranch} • ${_form.appointmentDateTime}'
                        : null,
                    onTap: _addAppointment,
                  ),
                  const SizedBox(height: 12),
                  _MenuCard(
                    icon: Icons.list_alt_outlined,
                    title: 'รายการนัดหมาย',
                    trailing: Icon(Icons.edit_outlined,
                        size: 20, color: LoanRegisterStyles.label),
                    onTap: () {
                      if (!_hasAppointment) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('ยังไม่มีรายการนัดหมาย')),
                        );
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                'นัดหมาย: ${_form.appointmentBranch} ${_form.appointmentDateTime}')),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          SaveNextBar(
            onSaveDraft: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('บันทึกข้อมูลร่างแล้ว')),
            ),
            onNext: _onNext,
          ),
        ],
      ),
    );
  }

  /// Open the documents-to-prepare → branch/date appointment flow, then keep
  /// the chosen appointment for the list card.
  Future<void> _addAppointment() async {
    final result = await context.push<Map<String, String>>(
      AppRoutes.documentsToPrepare,
      extra: _form,
    );
    if (result != null && mounted) {
      setState(() {
        _form.appointmentBranch = result['branch'] ?? _form.appointmentBranch;
        _form.appointmentDateTime =
            result['dateTime'] ?? _form.appointmentDateTime;
      });
    }
  }

  void _onNext() {
    if (!_hasAppointment) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเพิ่มสาขาและวันที่นัดหมายก่อน')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('บันทึกข้อมูลเรียบร้อย')),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: LoanRegisterStyles.cardBorder),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: LoanRegisterStyles.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: LoanRegisterStyles.value,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: LoanRegisterStyles.labelStyle(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                Icon(Icons.chevron_right,
                    color: LoanRegisterStyles.label, size: 22),
          ],
        ),
      ),
    );
  }
}
