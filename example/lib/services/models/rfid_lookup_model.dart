class RfidLookupModel {
  final String sn;
  final String material;
  final String description;
  final String epc;
  final String plant;
  final String stockLocation;

  const RfidLookupModel({
    required this.sn,
    required this.material,
    required this.description,
    required this.epc,
    required this.plant,
    required this.stockLocation,
  });

  factory RfidLookupModel.fromJson(Map<String, dynamic> json) {
    return RfidLookupModel(
      sn: json['sn']?.toString() ?? '',
      material: json['material']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      epc: json['epc']?.toString() ?? '',
      plant: json['plant']?.toString() ?? '',
      stockLocation: json['stockLocation']?.toString() ?? '',
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
    };
  }
}
