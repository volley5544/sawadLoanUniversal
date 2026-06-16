import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'loan_register_styles.dart';

/// A bordered address card (pin icon + title + address + chevron) used in the
/// ข้อมูลที่อยู่ section of step 1.
class AddressCard extends StatelessWidget {
  const AddressCard({
    Key? key,
    required this.title,
    required this.address,
    this.onTap,
    this.showChevron = true,
  }) : super(key: key);

  final String title;
  final String address;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: LoanRegisterStyles.cardBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: LoanRegisterStyles.primarySoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.location_on,
                  color: LoanRegisterStyles.primary, size: 20),
            ),
            const SizedBox(width: 10),
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
                  const SizedBox(height: 2),
                  Text(
                    address,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 12,
                      color: LoanRegisterStyles.label,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (showChevron)
              Icon(Icons.chevron_right,
                  color: LoanRegisterStyles.label, size: 22),
          ],
        ),
      ),
    );
  }
}

/// A radio row (ที่อยู่ตามบัตร / ที่อยู่ที่ทำงาน / ระบุที่อยู่ใหม่) for choosing
/// which address to use.
class AddressRadioTile extends StatelessWidget {
  const AddressRadioTile({
    Key? key,
    required this.label,
    required this.selected,
    required this.onTap,
  }) : super(key: key);

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: selected
                  ? LoanRegisterStyles.primary
                  : LoanRegisterStyles.label,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.notoSansThai(
                fontSize: 14,
                color: LoanRegisterStyles.value,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
