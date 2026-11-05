import 'package:flutter/material.dart';

import '../../../../ui/app_theme.dart';

class QuickActionsBar extends StatelessWidget {
  final VoidCallback onNewSession;
  final VoidCallback onAddFriend;
  final VoidCallback onNavigateToDebts;
  const QuickActionsBar({
    super.key,
    required this.onNewSession,
    required this.onAddFriend,
    required this.onNavigateToDebts,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: _Action(
          icon: Icons.add_rounded,
          label: 'Tạo phiên',
          onTap: onNewSession,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _Action(
          icon: Icons.person_add_alt_outlined,
          label: 'Kết bạn',
          onTap: onAddFriend,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _Action(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Công nợ',
          onTap: onNavigateToDebts,
        ),
      ),
    ],
  );
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Action({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppTheme.soft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: AppTheme.purple, size: 24),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppTheme.ink, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );
}
