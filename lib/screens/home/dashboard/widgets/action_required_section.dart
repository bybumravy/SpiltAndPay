import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/money.dart';
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
    final debtsToPay = debts.where((d) {
      return d.amountOwedBy(currentUid) > 0;
    }).toList()
      ..sort((a, b) =>
          b.amountOwedBy(currentUid).compareTo(a.amountOwedBy(currentUid)));

    final urgentItems = <Debt>[
      ...pendingConfirmation,
      ...debtsToPay,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.notification_important, size: 20, color: Colors.orange.shade800),
            const SizedBox(width: 8),
            Text(
              'Cần xử lý ngay',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Spacer(),
            if (urgentItems.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${urgentItems.length} việc',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade900,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (urgentItems.isEmpty)
          Card(
            color: Colors.green.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.green),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tuyệt vời! Bạn không có khoản nợ nào cần xử lý lúc này.',
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: urgentItems.take(4).length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final debt = urgentItems[i];
              return _ActionDebtTile(
                debt: debt,
                currentUid: currentUid,
                onTap: () => onSelectDebt(debt),
              );
            },
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

    // Xác định nội dung và trạng thái
    final String subtitle;
    final Color subtitleColor;
    final String actionText;
    final Color actionColor;
    final Color avatarBg;
    final Color avatarText;

    if (iAmDebtor) {
      if (debt.hasPendingPayment) {
        subtitle = 'Đang chờ chủ nợ xác nhận';
        subtitleColor = Colors.blue.shade700;
        actionText = 'Chờ duyệt';
        actionColor = Colors.blue.shade700;
        avatarBg = Colors.blue.shade100;
        avatarText = Colors.blue.shade900;
      } else {
        subtitle = 'Bạn cần thanh toán';
        subtitleColor = Colors.red.shade700;
        actionText = 'Trả ngay';
        actionColor = Theme.of(context).colorScheme.primary;
        avatarBg = Colors.red.shade100;
        avatarText = Colors.red.shade800;
      }
    } else {
      // Chủ nợ: Chỉ xuất hiện khi con nợ đã chuyển tiền chờ xác nhận
      subtitle = 'Đã chuyển tiền, chờ bạn xác nhận';
      subtitleColor = Colors.orange.shade900;
      actionText = 'Xác nhận';
      actionColor = Colors.orange.shade900;
      avatarBg = Colors.amber.shade100;
      avatarText = Colors.amber.shade900;
    }

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: avatarBg,
                child: Text(
                  otherName.isNotEmpty ? otherName[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: avatarText,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      otherName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: subtitleColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatVnd(netAmount.abs()),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: iAmDebtor ? Colors.red.shade700 : Colors.teal.shade700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        actionText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: actionColor,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: actionColor,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
