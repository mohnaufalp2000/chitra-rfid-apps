import 'package:flutter/material.dart';
import 'package:flutter_uhf_rfid_example/styles/color.dart';
import 'package:flutter_uhf_rfid_example/styles/font.dart';

class InfoCard extends StatelessWidget {
  const InfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 40, color: Color(0xFF0B3A7E)),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Informasi",
                  style: AppFont.style(
                    weight: FontWeight.bold,
                    size: 16,
                    color: Color(0xFF0B3A7E),
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  "Ban masuk digunakan untuk registrasi RFID. Ban keluar digunakan untuk scan dan verifikasi. Pastikan tekan SAVE setelah registrasi selesai.",
                  style: AppFont.style(color: AppColor.textGrey, size: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
