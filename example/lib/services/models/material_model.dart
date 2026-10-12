import 'dart:convert';

class MaterialModel {
  String? plnt;
  String? category;
  String? material;
  String? description;
  String? sloc;
  String? slocDescription;
  int? actStock;

  MaterialModel({
    this.plnt,
    this.category,
    this.material,
    this.description,
    this.sloc,
    this.slocDescription,
    this.actStock,
  });

  MaterialModel copyWith({
    String? plnt,
    String? category,
    String? material,
    String? description,
    String? sloc,
    String? slocDescription,
    int? actStock,
  }) => MaterialModel(
    plnt: plnt ?? this.plnt,
    category: category ?? this.category,
    material: material ?? this.material,
    description: description ?? this.description,
    sloc: sloc ?? this.sloc,
    slocDescription: slocDescription ?? this.slocDescription,
    actStock: actStock ?? this.actStock,
  );

  @override
  String toString() {
    return '$material - $description';
  }

  factory MaterialModel.fromRawJson(String str) =>
      MaterialModel.fromJson(json.decode(str));

  String toRawJson() => json.encode(toJson());

  factory MaterialModel.fromJson(Map<String, dynamic> json) => MaterialModel(
    plnt: json["plnt"],
    category: json["category"],
    material: json["material"],
    description: json["description"],
    sloc: json["sloc"],
    slocDescription: json["slocDescription"],
    actStock: json["actStock"],
  );

  Map<String, dynamic> toJson() => {
    "plnt": plnt,
    "category": category,
    "material": material,
    "description": description,
    "sloc": sloc,
    "slocDescription": slocDescription,
    "actStock": actStock,
  };
}
