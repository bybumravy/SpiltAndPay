import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/money.dart';
import '../../../../ui/app_theme.dart';
import '../../../../ui/content_rows.dart';
import '../../../../models/debt.dart';
import '../../../../repositories/user_repository.dart';

class ActionRequiredSection extends ConsumerWidget {
  final List<Debt> debts;
  final String currentUid;
  final void Function(Debt debt) onSelectDebt;

  const ActionRequiredSection({
    super.key,
    required this.debts,
    required this.currentUid,
    required this.onSelectDebt,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Khoản nợ người khác báo đã chuyển, chờ mình xác nhận (Ưu tiên cao nhất)
    // CHỦ NỢ CHỈ CẦN XỬ LÝ KHI: con nợ đã chuyển tiền (có pendingPaymentId chờ xác nhận).
    // Nếu con nợ chưa chuyển tiền thì chủ nợ KHÔNG có hành động nào cần xử lý ngay.
    final pendingConfirmation = debts.where((d) {
      final isCreditor = d.amountOwedBy(currentUid) < 0;
      return isCreditor && d.hasPendingPayment;
    }).toList();

    // 2. Khoản nợ mình đang nợ người khác (Cần trả)
    final debtsToPay =
        debts.where((d) {
          return d.amountOwedBy(currentUid) > 0;
        }).toList()..sort(
          (a, b) =>
              b.amountOwedBy(currentUid).compareTo(a.amountOwedBy(currentUid)),
        );

    final urgentItems = <Debt>[...pendingConfirmation, ...debtsToPay];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'Cần xử lý',
          action: urgentItems.isEmpty
              ? null
              : Text(
                  '${urgentItems.length}',
                  style: const TextStyle(color: AppTheme.muted),
                ),
        ),
        if (urgentItems.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Không có khoản cần xử lý',
              style: TextStyle(color: AppTheme.muted),
            ),
          )
        else
          for (final debt in urgentItems.take(4))
            _ActionDebtTile(
              debt: debt,
              currentUid: currentUid,
              onTap: () => onSelectDebt(debt),
            ),
      ],
    );
  }
}

class _ActionDebtTile extends ConsumerWidget {
  final Debt debt;
  final String currentUid;
  final VoidCallback onTap;

  const _ActionDebtTile({
    required this.debt,
    required this.currentUid,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netAmount = debt.amountOwedBy(currentUid);
    final iAmDebtor = netAmount > 0;
    final otherUid = currentUid == debt.userA ? debt.userB : debt.userA;
    final otherUserAsync = ref.watch(currentUserProvider(otherUid));

    final otherName = otherUserAsync.maybeWhen(
      data: (u) => u?.name ?? otherUid,
      orElse: () => otherUid,
    );

    final status = !iAmDebtor
        ? 'Cần xác nhận'
        : debt.hasPendingPayment
        ? 'Chờ xác nhận'
        : 'Cần thanh toán';
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialAvatar(otherName, radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LabelValueRow(
                      label: Text(
                        otherName,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      value: Text(
                        formatVnd(netAmount.abs()),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: iAmDebtor ? AppTheme.red : AppTheme.green,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      status,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppTheme.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.muted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
