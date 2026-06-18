import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';
import 'components/loan_register_styles.dart';
import 'components/register_field_row.dart';
import 'components/register_step_indicator.dart';
import 'components/register_text_field.dart';
import 'components/save_next_bar.dart';
import 'models/loan_register_form.dart';

/// Step 3 of the loan-register wizard — ข้อมูลสินเชื่อ (Loan Information) and
/// ข้อมูลการโอนเงิน (Transfer Information). Screen #3 on slide 7; opens the
/// จำนวนงวด (screen #4) and ประเภทการโอน (screen #5) selectors.
class LoanInfoPage extends StatefulWidget {
  const LoanInfoPage({Key? key, this.form}) : super(key: key);

  final LoanRegisterForm? form;

  @override
  State<LoanInfoPage> createState() => _LoanInfoPageState();
}

class _LoanInfoPageState extends State<LoanInfoPage> {
  late final LoanRegisterForm _form = widget.form ?? LoanRegisterForm.mock();

  late final TextEditingController _requested =
      TextEditingController(text: _form.requestedAmount);

  @override
  void dispose() {
    _requested.dispose();
    super.dispose();
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
        title:
            Text('3. ข้อมูลสินเชื่อ', style: LoanRegisterStyles.appBarTitleStyle()),
      ),
      body: Column(
        children: [
          const RegisterStepIndicator(currentStep: 3),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  horizontal: LoanRegisterStyles.padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const RegisterSectionTitle('ข้อมูลสินเชื่อ'),
                  RegisterFieldRow(
                    label: 'วงเงินสูงสุดที่จะได้รับ',
                    value: _form.maxAmount,
                  ),
                  RegisterTextField(
                    label: 'วงเงินที่ต้องการ',
                    controller: _requested,
                    keyboardType: TextInputType.number,
                    requiredHint: '*กรอกได้ไม่เกินวงเงินสูงสุดที่จะได้รับ',
                  ),
                  RegisterFieldRow(
                    label: 'จำนวนงวด',
                    value: '${_form.installments}',
                    onTap: _pickInstallments,
                  ),
                  RegisterFieldRow(
                    label: 'ค่างวดแต่ละงวด',
                    value: _form.installmentAmount,
                  ),
                  RegisterFieldRow(
                    label: 'ค่างวดงวดสุดท้าย',
                    value: _form.lastInstallmentAmount,
                  ),
                  RegisterFieldRow(
                    label: 'วันที่ทำสัญญา',
                    value: _form.contractDate,
                  ),
                  RegisterFieldRow(
                    label: 'ชำระงวดแรก',
                    value: _form.firstPaymentDate,
                  ),
                  RegisterFieldRow(
                    label: 'จำนวนเงินที่ได้รับ',
                    value: _form.amountReceived,
                    showDivider: false,
                  ),

                  // ── ข้อมูลการโอนเงิน ───────────────────────────
                  const RegisterSectionTitle('ข้อมูลการโอนเงิน'),
                  RegisterFieldRow(
                    label: 'ประเภทการโอนเงิน',
                    value: _form.transferType,
                    onTap: _pickTransferType,
                  ),
                  RegisterFieldRow(
                    label: 'บัญชีธนาคารลูกค้า',
                    value: _form.bankAccount,
                    onTap: () {},
                  ),
                  RegisterFieldRow(
                    label: 'ชื่อบัญชี',
                    value: _form.accountName,
                    onTap: () {},
                  ),
                  RegisterFieldRow(
                    label: 'ประเภทบัญชี',
                    value: _form.accountType,
                    onTap: () {},
                  ),
                  RegisterFieldRow(
                    label: 'เลขบัญชี',
                    value: _form.accountNumber,
                    showDivider: false,
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
            onNext: () {
              _form.requestedAmount = _requested.text;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ไปยังขั้นตอนถัดไป')),
              );
            },
          ),
        ],
      ),
    );
  }

  void _pickInstallments() async {
    final result = await context.push<int>(
      AppRoutes.installmentPicker,
      extra: _form.installments,
    );
    if (result != null) setState(() => _form.installments = result);
  }

  void _pickTransferType() async {
    final result = await context.push<String>(
      AppRoutes.transferTypePicker,
      extra: _form.transferType,
    );
    if (result != null) setState(() => _form.transferType = result);
  }
}
