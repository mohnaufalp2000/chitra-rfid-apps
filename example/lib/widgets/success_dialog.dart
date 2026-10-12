import 'package:flutter/material.dart';
import 'package:flutter_uhf_rfid_example/styles/color.dart';
import 'package:flutter_uhf_rfid_example/styles/font.dart';

class SuccessDialog {
  static Future<void> show(
    BuildContext context, {
    String title = 'Berhasil!',
    String message = 'Semua data RFID telah berhasil disimpan ke sistem.',
    String buttonText = 'TUTUP',
    VoidCallback? onClose,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // HEADER GREEN WAVE
                  SizedBox(
                    height: 145,
                    child: Stack(
                      children: [
                        Container(
                          height: 105,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.green.shade300,
                                Colors.green.shade500,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),

                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: ClipPath(
                            clipper: _WaveClipper(),
                            child: Container(height: 70, color: Colors.white),
                          ),
                        ),

                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 18,
                          child: Center(
                            child: Container(
                              width: 78,
                              height: 78,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.12),
                                    blurRadius: 15,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                size: 48,
                                color: Colors.green.shade600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppFont.style(
                      size: 26,
                      weight: FontWeight.w700,
                      color: const Color(0xFF1F2937),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: AppFont.style(
                        size: 14,
                        color: Colors.grey.shade700,
                        weight: FontWeight.w400,
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);

                          if (onClose != null) {
                            onClose();
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.green.shade600,
                            width: 1.4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          buttonText,
                          style: AppFont.style(
                            size: 15,
                            weight: FontWeight.w700,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();

    path.lineTo(0, 25);

    path.quadraticBezierTo(size.width * 0.25, 0, size.width * 0.50, 25);

    path.quadraticBezierTo(size.width * 0.75, 50, size.width, 20);

    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) {
    return false;
  }
}
