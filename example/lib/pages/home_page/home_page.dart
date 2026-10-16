import 'package:flutter/material.dart';
import 'package:flutter_uhf_rfid_example/pages/list_sn_page/list_sn_page.dart';
import 'package:flutter_uhf_rfid_example/pages/register_page/register_page.dart';
import 'package:flutter_uhf_rfid_example/pages/rfid_history_page/rfid_history_page.dart';
import 'package:flutter_uhf_rfid_example/styles/color.dart';
import 'package:flutter_uhf_rfid_example/styles/font.dart';
import 'package:flutter_uhf_rfid_example/widgets/home_header.dart';
import 'package:flutter_uhf_rfid_example/widgets/info_card.dart';
import 'package:flutter_uhf_rfid_example/widgets/menu_card.dart';
import 'package:flutter_uhf_rfid_example/widgets/reader_settings_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    final bool isSmallDevice = width < 450;

    return Scaffold(
      backgroundColor: AppColor.white,
      body: SafeArea(
        child: Column(
          children: [
            const HomeHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isSmallDevice ? 16 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: isSmallDevice ? 4 : 10),

                    Text(
                      'Selamat Datang!',
                      style: AppFont.style(
                        size: 24,
                        weight: FontWeight.w600,
                        color: AppColor.primary,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      'Pilih proses sesuai pergerakan ban yang sedang dikerjakan.',
                      style: AppFont.style(size: 14, color: AppColor.textGrey),
                    ),

                    const SizedBox(height: 24),

                    _sectionTitle(
                      icon: Icons.tune_rounded,
                      title: 'Daya Pancar Reader',
                      subtitle: 'Atur jarak baca RFID di perangkat ini.',
                    ),

                    const SizedBox(height: 12),

                    const ReaderSettingsCard(),

                    const SizedBox(height: 24),

                    _sectionTitle(
                      icon: Icons.swap_vert_circle_outlined,
                      title: 'Proses Operasional',
                      subtitle: 'Tentukan apakah ban masuk atau keluar.',
                    ),

                    const SizedBox(height: 12),

                    MenuCard(
                      accentColor: const Color(0xFF2E7D32),
                      circleColor: const Color(0xFFE8F5E9),
                      icon: Icons.move_to_inbox_rounded,
                      iconColor: const Color(0xFF2E7D32),
                      badge: "BAN MASUK",
                      title: "Terima Ban Masuk",
                      description:
                          "Daftarkan SN dan pasangkan RFID pada ban yang baru diterima.",
                      workflow: "Pilih material → Input SN → Scan RFID → Save",
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => RegisterPage(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    MenuCard(
                      accentColor: const Color(0xFFE65100),
                      circleColor: const Color(0xFFFFF3E0),
                      icon: Icons.outbox_rounded,
                      iconColor: const Color(0xFFE65100),
                      badge: "BAN KELUAR",
                      title: "Proses Ban Keluar",
                      description:
                          "Scan dan simpan RFID ban yang keluar dari lokasi.",
                      workflow: "Scan RFID → Review ban → Save",
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ListSnPage()),
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    _sectionTitle(
                      icon: Icons.folder_copy_outlined,
                      title: 'Data & Riwayat',
                      subtitle: 'Lihat data RFID yang sudah tersimpan.',
                    ),

                    const SizedBox(height: 12),

                    MenuCard(
                      accentColor: const Color(0xFF2E7D32),
                      circleColor: const Color(0xFFE8F5E9),
                      icon: Icons.history_rounded,
                      iconColor: const Color(0xFF2E7D32),
                      title: "Riwayat RFID",
                      description:
                          "Cari dan lihat seluruh RFID ban yang telah diregistrasikan.",
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RfidHistoryPage(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    const InfoCard(),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF1FF),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: AppColor.primary, size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppFont.style(
                  size: 16,
                  weight: FontWeight.w600,
                  color: AppColor.primary,
                ),
              ),
              Text(
                subtitle,
                style: AppFont.style(size: 11, color: AppColor.textGrey),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
