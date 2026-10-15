import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase_providers.dart';
import '../../core/money.dart';
import '../../models/debt.dart';
import '../../repositories/debt_repository.dart';
import '../../repositories/user_repository.dart';
import '../debt/debt_detail_screen.dart';

class DebtsTab extends ConsumerWidget {
  const DebtsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).currentUser;
    if (user == null) return const SizedBox.shrink();

    final debtsAsync = ref.watch(userDebtsProvider(user.uid));

    return Scaffold(
      appBar: AppBar(title: const Text('Công nợ')),
      body: debtsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (debts) {
          if (debts.isEmpty) {
            return const Center(child: Text('Không có công nợ nào'));
          }
          return ListView.builder(
            itemCount: debts.length,
            itemBuilder: (_, i) => _DebtTile(
              debt: debts[i],
              currentUid: user.uid,
            ),
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
      leading: CircleAvatar(
        child: Text(otherName.isNotEmpty ? otherName[0].toUpperCase() : '?'),
      ),
      title: Text(otherName),
      subtitle: Text(
        iAmDebtor ? 'Bạn nợ' : 'Được nợ',
        style: TextStyle(
          color: iAmDebtor ? Colors.red : Colors.green,
          fontSize: 12,
        ),
      ),
      trailing: Text(
        formatVnd(netAmount.abs()),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: iAmDebtor ? Colors.red : Colors.green,
        ),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DebtDetailScreen(
            debt: debt,
            currentUid: currentUid,
          ),
        ),
      ),
    );
  }
}
