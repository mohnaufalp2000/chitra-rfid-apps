import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_uhf_rfid_example/pages/list_sn_page/list_sn_provider.dart';
import 'package:flutter_uhf_rfid_example/pages/register_page/register_provider.dart';
import 'package:flutter_uhf_rfid_example/styles/color.dart';
import 'package:flutter_uhf_rfid_example/styles/font.dart';
import 'package:flutter_uhf_rfid_example/widgets/section_card.dart';

/// Input ekspedisi untuk ban MASUK.
class EkspedisiCard extends ConsumerWidget {
  const EkspedisiCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(registerProvider.notifier);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Ekspedisi'),
          const SizedBox(height: 12),
          _ShipmentField(
            controller: notifier.ekspedisiController,
            label: 'Ekspedisi *',
            hint: 'Nama ekspedisi pengirim',
            icon: Icons.local_shipping_outlined,
          ),
        ],
      ),
    );
  }
}

/// Input plat truk, tujuan, dan nama driver untuk ban KELUAR.
class OutgoingShipmentCard extends ConsumerWidget {
  const OutgoingShipmentCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(listSnProvider.notifier);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Informasi Pengiriman'),
          const SizedBox(height: 12),
          _ShipmentField(
            controller: notifier.platTrukController,
            label: 'Plat Truk *',
            hint: 'KT 1234 AB',
            icon: Icons.local_shipping_outlined,
            capitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 10),
          _ShipmentField(
            controller: notifier.tujuanController,
            label: 'Tujuan *',
            hint: 'Alamat atau site tujuan',
            icon: Icons.location_on_outlined,
          ),
          const SizedBox(height: 10),
          _ShipmentField(
            controller: notifier.namaDriverController,
            label: 'Nama Driver *',
            hint: 'Nama driver',
            icon: Icons.person_outline,
            capitalization: TextCapitalization.words,
          ),
        ],
      ),
    );
  }
}

Widget _title(String text) {
  return Text(
    text,
    style: AppFont.style(
      size: 16,
      weight: FontWeight.w600,
      color: AppColor.primary,
    ),
  );
}

class _ShipmentField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextCapitalization capitalization;

  const _ShipmentField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.capitalization = TextCapitalization.words,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textCapitalization: capitalization,
      style: AppFont.style(size: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColor.border),
        ),
      ),
    );
  }
}
