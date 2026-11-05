import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase_providers.dart';
import '../../core/money.dart';
import '../../ui/app_theme.dart';
import '../../ui/content_rows.dart';
import '../../ui/app_tabs.dart';
import '../../models/debt.dart';
import '../../repositories/guest_receivables_provider.dart';
import '../debt/widgets/guest_receivable_tile.dart';
import '../../repositories/debt_repository.dart';
import '../../repositories/user_repository.dart';
import '../debt/debt_detail_screen.dart';

class DebtsTab extends ConsumerWidget {
  const DebtsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).currentUser;
    if (user == null) return const SizedBox.shrink();

    final guestsAsync = ref.watch(guestReceivablesProvider(user.uid));
    final guests = guestsAsync.valueOrNull ?? <GuestReceivable>[];
    final debtsAsync = ref.watch(userDebtsProvider(user.uid));

    return Scaffold(
      appBar: AppBar(title: const Text('Công nợ')),
      body: debtsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (debts) {
          if (debts.isEmpty && guests.isEmpty && guestsAsync.hasValue) {
            return const Center(
              child: AppEmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Không có công nợ nào',
              ),
            );
          }
          final owed = debts.fold<int>(
            0,
            (total, d) =>
                total +
                (d.amountOwedBy(user.uid) > 0 ? d.amountOwedBy(user.uid) : 0),
          );
          final receivable =
              pendingGuestTotal(guests) +
              debts.fold<int>(
                0,
                (total, d) =>
                    total +
                    (d.amountOwedBy(user.uid) < 0
                        ? -d.amountOwedBy(user.uid)
                        : 0),
              );
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Bạn nợ',
                            style: TextStyle(color: AppTheme.muted),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              formatVnd(owed),
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(color: AppTheme.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Cần thu',
                            style: TextStyle(color: AppTheme.muted),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              formatVnd(receivable),
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(color: AppTheme.green),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (guestsAsync.isLoading) const LinearProgressIndicator(),
              if (guestsAsync.hasError)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: TextButton(
                    onPressed: () =>
                        ref.invalidate(guestReceivablesProvider(user.uid)),
                    child: const Text('Chưa tải được khoản khách nợ. Thử lại'),
                  ),
                ),
              const Divider(indent: 24, endIndent: 24),
              for (final debt in debts) ...[
                _DebtTile(debt: debt, currentUid: user.uid),
                const Divider(indent: 24, endIndent: 24),
              ],
              if (guests.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: SectionHeading('Khách vãng lai'),
                ),
              for (final item in guests) ...[
                GuestReceivableTile(item: item),
                const Divider(indent: 24, endIndent: 24),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DebtTile extends ConsumerWidget {
  final Debt debt;
  final String currentUid;

  const _DebtTile({required this.debt, required this.currentUid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netAmount = debt.amountOwedBy(currentUid);
    final iAmDebtor = netAmount > 0;
    final otherUid = currentUid == debt.userA ? debt.userB : debt.userA;
    final otherAsync = ref.watch(currentUserProvider(otherUid));

    final otherName = otherAsync.maybeWhen(
      data: (u) => u?.name ?? otherUid,
      orElse: () => otherUid,
    );

    return ListTile(
      titleAlignment: ListTileTitleAlignment.top,
      leading: InitialAvatar(otherName),
      title: LabelValueRow(
        label: Text(otherName, style: Theme.of(context).textTheme.titleMedium),
        value: Text(
          formatVnd(netAmount.abs()),
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(color: iAmDebtor ? AppTheme.red : AppTheme.green),
        ),
      ),
      subtitle: Text(
        iAmDebtor ? 'Bạn nợ' : 'Cần thu',
        style: TextStyle(
          color: iAmDebtor ? AppTheme.red : AppTheme.green,
          fontSize: 12,
        ),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DebtDetailScreen(debt: debt, currentUid: currentUid),
        ),
      ),
    );
  }
}
