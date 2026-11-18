import 'package:flutter/material.dart';

import '../../../core/di/injection.dart';
import '../../../core/network/api_traffic_log.dart';

class DevApiButton extends StatelessWidget {
  const DevApiButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final log = getIt<ApiTrafficLog>();
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, left: 8),
          child: AnimatedBuilder(
            animation: log,
            builder: (context, _) {
              return Material(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onPressed,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bug_report, color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          '${log.count}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
