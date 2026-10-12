import 'package:flutter_uhf_rfid_example/services/models/filter_model.dart';
import 'package:flutter_uhf_rfid_example/services/models/material_model.dart';

class MaterialResponse {
  String? status;
  FilterModel? filters;
  List<MaterialModel>? result;
  int? count;

  MaterialResponse({this.status, this.filters, this.result, this.count});

  factory MaterialResponse.fromJson(Map<String, dynamic> json) {
    return MaterialResponse(
      status: json['status'],

      filters: json['filters'] == null
          ? null
          : FilterModel.fromJson(json['filters']),

      result: (json['result'] as List<dynamic>)
          .map((e) => MaterialModel.fromJson(e))
          .toList(),

      count: json['count'],
    );
  }
}
