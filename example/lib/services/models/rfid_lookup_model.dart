class RfidLookupModel {
  final String sn;
  final String material;
  final String description;
  final String epc;
  final String plant;
  final String stockLocation;

  /// Ekspedisi yang dicatat saat ban masuk. Null kalau backend tidak
  /// mengirimnya.
  final String? ekspedisi;

  const RfidLookupModel({
    required this.sn,
    required this.material,
    required this.description,
    required this.epc,
    required this.plant,
    required this.stockLocation,
    this.ekspedisi,
  });

  factory RfidLookupModel.fromJson(Map<String, dynamic> json) {
    final ekspedisi = json['ekspedisi']?.toString().trim();

    return RfidLookupModel(
      sn: json['sn']?.toString() ?? '',
      material: json['material']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      epc: json['epc']?.toString() ?? '',
      plant: json['plant']?.toString() ?? '',
      stockLocation: json['stockLocation']?.toString() ?? '',
      ekspedisi: (ekspedisi == null || ekspedisi.isEmpty) ? null : ekspedisi,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sn': sn,
      'material': material,
      'description': description,
      'epc': epc,
      'plant': plant,
      'stockLocation': stockLocation,
      if (ekspedisi != null) 'ekspedisi': ekspedisi,
    };
  }
}
