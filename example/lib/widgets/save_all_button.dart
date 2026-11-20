import 'package:flutter/material.dart';
import 'package:flutter_uhf_rfid_example/styles/color.dart';
import 'package:flutter_uhf_rfid_example/styles/font.dart';

class SaveAllButton extends StatelessWidget {
  final VoidCallback onPressed;

  /// Selama true tombol nonaktif dan menampilkan indikator loading.
  final bool isLoading;

  const SaveAllButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: isLoading ? null : onPressed,

          icon: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_outlined, color: Colors.white),

          label: Text(
            isLoading ? 'MENYIMPAN...' : 'SAVE',
            style: AppFont.style(
              color: Colors.white,
              weight: FontWeight.w600,
              size: 16,
            ),
          ),

          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: AppColor.primary,
            disabledBackgroundColor: AppColor.primary.withValues(alpha: 0.6),

            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}
