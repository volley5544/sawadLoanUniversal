import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_application_srisawad/bloc/user_profile/user_profile_bloc.dart';

import 'collateral_info_page.dart';
import 'components/address_card.dart';
import 'components/loan_register_styles.dart';
import 'components/register_field_row.dart';
import 'components/register_step_indicator.dart';
import 'components/register_text_field.dart';
import 'components/save_next_bar.dart';
import 'models/loan_register_form.dart';

/// Step 1 of the loan-register wizard — ข้อมูลลูกค้า (Customer Information).
/// Screen #1 on slide 7.
class CustomerInfoPage extends StatefulWidget {
  const CustomerInfoPage({Key? key, this.form}) : super(key: key);

  /// Shared wizard form. Defaults to the mock data so the page can be opened
  /// standalone for preview.
  final LoanRegisterForm? form;

  @override
  State<CustomerInfoPage> createState() => _CustomerInfoPageState();
}

class _CustomerInfoPageState extends State<CustomerInfoPage> {
  late final LoanRegisterForm _form;

  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _phone;
  late final TextEditingController _thaiId;

  @override
  void initState() {
    super.initState();
    // When opened from the menu (no form passed), auto-fill from the signed-in
    // user's profile via UserProfileBloc.
    _form = widget.form ??
        LoanRegisterForm.fromProfile(
            context.read<UserProfileBloc>().state.userProfileData);

    _firstName = TextEditingController(text: _form.firstName);
    _lastName = TextEditingController(text: _form.lastName);
    _phone = TextEditingController(text: _form.phone);
    _thaiId = TextEditingController(text: _form.thaiId);
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _thaiId.dispose();
    super.dispose();
  }

  void _save() {
    _form
      ..firstName = _firstName.text
      ..lastName = _lastName.text
      ..phone = _phone.text
      ..thaiId = _thaiId.text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: LoanRegisterStyles.primary),
        centerTitle: true,
        title: Text('ข้อมูลลูกค้า', style: LoanRegisterStyles.appBarTitleStyle()),
      ),
      body: Column(
        children: [
          const RegisterStepIndicator(currentStep: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  horizontal: LoanRegisterStyles.padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const RegisterSectionTitle('ข้อมูลลูกค้า'),
                  RegisterTextField(
                      label: 'ชื่อ',
                      controller: _firstName,
                      hint: 'กรุณากรอกชื่อ'),
                  RegisterTextField(
                      label: 'นามสกุล',
                      controller: _lastName,
                      hint: 'กรุณากรอกนามสกุล'),
                  RegisterTextField(
                    label: 'เบอร์โทรศัพท์',
                    controller: _phone,
                    hint: 'กรุณากรอกเบอร์โทรศัพท์',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                    ],
                  ),
                  RegisterFieldRow(
                    label: 'วัน เดือน ปีเกิด (พ.ศ.)',
                    value: _form.birthDate,
                    placeholder: 'กรุณาเลือกวัน เดือน ปีเกิด (พ.ศ.)',
                    trailing: _calendarIcon(),
                    onTap: () => _pickDate((d) => _form.birthDate = d),
                  ),
                  RegisterTextField(
                    label: 'หมายเลขบัตรประชาชน',
                    controller: _thaiId,
                    hint: 'กรุณากรอกหมายเลขบัตรประชาชน',
                    keyboardType: TextInputType.number,
                  ),
                  RegisterFieldRow(
                    label: 'เพศ',
                    value: _form.gender,
                    placeholder: 'กรุณาเลือกเพศ',
                    onTap: () => _pickOption('เพศ', ['ชาย', 'หญิง'],
                        _form.gender, (v) => _form.gender = v),
                  ),
                  RegisterFieldRow(
                    label: 'สัญชาติ',
                    value: _form.nationality,
                    placeholder: 'กรุณาเลือกสัญชาติ',
                    onTap: () => _pickOption('สัญชาติ', ['ไทย', 'อื่นๆ'],
                        _form.nationality, (v) => _form.nationality = v),
                  ),
                  RegisterFieldRow(
                    label: 'วันออกบัตร',
                    value: _form.cardIssueDate,
                    placeholder: 'กรุณาเลือกวันออกบัตร',
                    trailing: _calendarIcon(),
                    onTap: () => _pickDate((d) => _form.cardIssueDate = d),
                  ),
                  RegisterFieldRow(
                    label: 'วันหมดอายุบัตร',
                    value: _form.cardExpiryDate,
                    placeholder: 'กรุณาเลือกวันหมดอายุบัตร',
                    trailing: _calendarIcon(),
                    onTap: () => _pickDate((d) => _form.cardExpiryDate = d),
                  ),

                  // ── ข้อมูลที่อยู่ ───────────────────────────────
                  const RegisterSectionTitle('ข้อมูลที่อยู่'),
                  const SizedBox(height: 6),
                  AddressCard(
                    title: 'ที่อยู่ตามบัตรประชาชน',
                    address: _form.idCardAddress,
                    onTap: () {},
                  ),
                  const SizedBox(height: 10),
                  AddressCard(
                    title: 'ที่อยู่ที่ทำงาน',
                    address: _form.workAddress,
                    onTap: () {},
                  ),
                  const SizedBox(height: 10),
                  _addressChoiceCard(),

                  // ── ข้อมูลอาชีพ ─────────────────────────────────
                  const RegisterSectionTitle('ข้อมูลอาชีพ'),
                  RegisterFieldRow(
                    label: 'กลุ่มอาชีพ',
                    value: _form.occupationGroup,
                    placeholder: 'กรุณาเลือกกลุ่มอาชีพ',
                    onTap: () => _pickOption(
                        'กลุ่มอาชีพ',
                        ['พนักงานบริษัท', 'ข้าราชการ', 'ธุรกิจส่วนตัว', 'อื่นๆ'],
                        _form.occupationGroup,
                        (v) => _form.occupationGroup = v),
                  ),
                  RegisterFieldRow(
                    label: 'รายได้ต่อเดือน',
                    value: _form.monthlyIncome,
                    placeholder: 'กรุณาเลือกรายได้ต่อเดือน',
                    onTap: () => _pickOption(
                        'รายได้ต่อเดือน',
                        ['ต่ำกว่า 15,000', '15,000 - 30,000', 'มากกว่า 30,000'],
                        _form.monthlyIncome,
                        (v) => _form.monthlyIncome = v),
                  ),
                  RegisterFieldRow(
                    label: 'อายุงาน',
                    value: _form.workTenure,
                    placeholder: 'กรุณาเลือกอายุงาน',
                    showDivider: false,
                    onTap: () => _pickOption(
                        'อายุงาน',
                        ['น้อยกว่า 1 ปี', '1 - 3 ปี', 'มากกว่า 3 ปี'],
                        _form.workTenure,
                        (v) => _form.workTenure = v),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          SaveNextBar(
            onSaveDraft: () {
              _save();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('บันทึกข้อมูลร่างแล้ว')),
              );
            },
            onNext: () {
              _save();
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CollateralInfoPage(form: _form),
              ));
            },
          ),
        ],
      ),
    );
  }

  Widget _addressChoiceCard() {
    Widget tile(AddressChoice choice, String label) => AddressRadioTile(
          label: label,
          selected: _form.addressChoice == choice,
          onTap: () => setState(() => _form.addressChoice = choice),
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LoanRegisterStyles.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          tile(AddressChoice.idCard, 'ที่อยู่ตามบัตรประชาชน'),
          tile(AddressChoice.work, 'ที่อยู่ที่ทำงาน'),
          tile(AddressChoice.custom, 'ระบุที่อยู่ใหม่'),
          const SizedBox(height: 8),
          AddressCard(
            title: 'ที่อยู่ปัจจุบัน',
            address: _form.currentAddress,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _calendarIcon() => Icon(Icons.calendar_month_outlined,
      color: LoanRegisterStyles.label, size: 22);

  // ── Selector / date helpers (mock) ─────────────────────────────────

  void _pickOption(String title, List<String> options, String current,
      ValueChanged<String> onPick) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: LoanRegisterStyles.appBarTitleStyle()),
            ),
            ...options.map((o) => ListTile(
                  title: Text(o, style: LoanRegisterStyles.valueStyle()),
                  trailing: o == current
                      ? Icon(Icons.check, color: LoanRegisterStyles.primary)
                      : null,
                  onTap: () => Navigator.of(context).pop(o),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (result != null) setState(() => onPick(result));
  }

  void _pickDate(ValueChanged<String> onPick) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(1940),
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null) {
      final buddhistYear = picked.year + 543;
      final formatted =
          '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/$buddhistYear';
      setState(() => onPick(formatted));
    }
  }
}
