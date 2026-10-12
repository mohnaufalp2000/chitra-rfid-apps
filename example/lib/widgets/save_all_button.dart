import 'package:flutter/material.dart';
import 'package:flutter_uhf_rfid_example/styles/color.dart';
import 'package:flutter_uhf_rfid_example/styles/font.dart';

class SaveAllButton extends StatelessWidget {
  final VoidCallback onPressed;

  const SaveAllButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onPressed,

          icon: const Icon(Icons.save_outlined, color: Colors.white),

          label: Text(
            'SAVE',
            style: AppFont.style(
              color: Colors.white,
              weight: FontWeight.w600,
              size: 16,
            ),
          ),

          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: AppColor.primary,

            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}
