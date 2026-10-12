import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppFont {
  static TextStyle style({
    double size = 14,
    FontWeight weight = FontWeight.normal,
    Color color = Colors.black,
  }) {
    return GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }
}
