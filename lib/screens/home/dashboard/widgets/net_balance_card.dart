import 'package:flutter/material.dart';

import '../../../../core/money.dart';
import '../../../../ui/app_theme.dart';

class NetBalanceCard extends StatelessWidget {
  final int totalOwed;
  final int totalReceivable;

  const NetBalanceCard({
    super.key,
    required this.totalOwed,
    required this.totalReceivable,
  });

  @override
  Widget build(BuildContext context) {
    final net = totalReceivable - totalOwed;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.soft,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Công nợ ròng',
            style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '${net > 0
                    ? '+'
                    : net < 0
                    ? '-'
                    : ''}${formatVnd(net.abs())}',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: AppTheme.purple,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final entries = [
                _Amount(
                  label: 'Cần trả',
                  amount: totalOwed,
                  color: AppTheme.red,
                ),
                _Amount(
                  label: 'Cần thu',
                  amount: totalReceivable,
                  color: AppTheme.green,
                ),
              ];
              final stack =
                  constraints.maxWidth < 250 ||
                  MediaQuery.textScalerOf(context).scale(15) > 18;
              return stack
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        entries[0],
                        const SizedBox(height: 16),
                        entries[1],
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: entries[0]),
                        const SizedBox(width: 16),
                        Expanded(child: entries[1]),
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  final String label;
  final int amount;
  final Color color;
  const _Amount({
    required this.label,
    required this.amount,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: AppTheme.muted),
      ),
      const SizedBox(height: 4),
      Text(
        formatVnd(amount),
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    ],
  );
}
