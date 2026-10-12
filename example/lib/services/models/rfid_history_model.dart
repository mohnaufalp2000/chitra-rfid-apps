class RfidHistoryModel {
  final int id;
  final DateTime? createdAt;
  final String material;
  final String category;
  final String description;
  final String sloc;
  final String slocDescription;
  final String serialNumber;
  final String epc;
  final String rssi;
  final bool linked;
  final int actStock;
  final String createdBy;
  final String plant;

  const RfidHistoryModel({
    required this.id,
    required this.createdAt,
    required this.material,
    required this.category,
    required this.description,
    required this.sloc,
    required this.slocDescription,
    required this.serialNumber,
    required this.epc,
    required this.rssi,
    required this.linked,
    required this.actStock,
    required this.createdBy,
    required this.plant,
  });

  factory RfidHistoryModel.fromJson(Map<String, dynamic> json) {
    return RfidHistoryModel(
      id: _toInt(json['id']),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      material: json['material']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      sloc: json['sloc']?.toString() ?? '',
      slocDescription: json['slocDescription']?.toString() ?? '',
      serialNumber: json['serialNumber']?.toString() ?? '',
      epc: json['epc']?.toString() ?? '',
      rssi: json['rssi']?.toString() ?? '',
      linked: json['linked'] == true || json['linked']?.toString() == 'true',
      actStock: _toInt(json['actStock']),
      createdBy: json['createdBy']?.toString() ?? '',
      plant: json['plant']?.toString() ?? '',
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
