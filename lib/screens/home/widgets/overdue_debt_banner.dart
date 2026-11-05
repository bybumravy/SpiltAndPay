import 'package:flutter/material.dart';

import '../../../../core/money.dart';

class OverdueDebtBanner extends StatelessWidget {
  final int totalOwed;
  final int count;
  final VoidCallback onTap;

  const OverdueDebtBanner({
    super.key,
    required this.totalOwed,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (totalOwed <= 0 || count <= 0) return const SizedBox.shrink();

    return Material(
      color: Colors.orange.shade50,
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Bạn có $count khoản nợ chưa thanh toán (tổng ${formatVnd(totalOwed)}).',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade900,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: Colors.orange.shade900),
            ],
          ),
        ),
      ),
    );
  }
}
