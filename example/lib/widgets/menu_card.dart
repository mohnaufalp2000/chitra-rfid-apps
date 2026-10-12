import 'package:flutter/material.dart';
import 'package:flutter_uhf_rfid_example/styles/color.dart';
import 'package:flutter_uhf_rfid_example/styles/font.dart';

class MenuCard extends StatelessWidget {
  final Color accentColor;
  final Color circleColor;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final String? badge;
  final String? workflow;
  final VoidCallback onTap;

  const MenuCard({
    super.key,
    required this.accentColor,
    required this.circleColor,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    this.badge,
    this.workflow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: workflow == null ? 132 : 166),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .08),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(28),
                    bottomLeft: Radius.circular(28),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          color: circleColor,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 32, color: iconColor),
                      ),

                      const SizedBox(width: 16),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (badge != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: circleColor,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  badge!,
                                  style: AppFont.style(
                                    size: 9,
                                    weight: FontWeight.w700,
                                    color: accentColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                            ],
                            Text(
                              title,
                              style: AppFont.style(
                                size: 19,
                                weight: FontWeight.bold,
                                color: AppColor.primary,
                              ),
                            ),

                            const SizedBox(height: 3),

                            Text(
                              description,
                              style: AppFont.style(
                                size: 11,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            if (workflow != null) ...[
                              const SizedBox(height: 7),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.route_outlined,
                                    size: 14,
                                    color: accentColor,
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      workflow!,
                                      style: AppFont.style(
                                        size: 9,
                                        weight: FontWeight.w500,
                                        color: accentColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      Icon(Icons.chevron_right, size: 30, color: accentColor),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
