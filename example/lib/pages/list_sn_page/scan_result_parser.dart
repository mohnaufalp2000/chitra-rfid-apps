import 'package:flutter_uhf_rfid/flutter_uhf_rfid.dart';
import 'package:flutter_uhf_rfid_example/providers.dart';

List<String> parseScannedEpcs(List<RFIDTag> tags, {required ScanMode mode}) {
  final uniqueEpcs = <String, String>{};

  // scannedTagsProvider menyimpan hasil terbaru di depan. Balik urutannya
  // agar Single Scan mengambil tag pertama yang benar-benar terbaca.
  for (final tag in tags.reversed) {
    final epc = tag.epcHex.trim();
    if (epc.isNotEmpty) {
      uniqueEpcs.putIfAbsent(epc.toUpperCase(), () => epc);
    }
  }

  if (mode == ScanMode.single) {
    return uniqueEpcs.values.take(1).toList();
  }

  return uniqueEpcs.values.toList();
}
