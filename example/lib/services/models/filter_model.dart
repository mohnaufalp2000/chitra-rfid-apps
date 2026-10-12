class FilterModel {
  List<String>? plants;
  String? category;
  String? material;

  FilterModel({this.plants, this.category, this.material});

  factory FilterModel.fromJson(Map<String, dynamic> json) {
    return FilterModel(
      plants: List<String>.from(json['plants'] ?? []),
      category: json['category'],
      material: json['material'],
    );
  }
}
