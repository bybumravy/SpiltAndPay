import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../models/debt.dart';
import '../../models/payment.dart';
import '../../repositories/debt_repository.dart';
import '../../repositories/session_repository.dart';
import '../../repositories/user_repository.dart';

class DebtDetailScreen extends ConsumerWidget {
  final Debt debt;
  final String currentUid;

  const DebtDetailScreen({
    super.key,
    required this.debt,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debtId = Debt.docId(debt.userA, debt.userB);
    final paymentsAsync = ref.watch(paymentsProvider(debtId));

    // Từ góc nhìn currentUser: dương = đang nợ, âm = người kia nợ mình.
    final netAmount = debt.amountOwedBy(currentUid);
    final iAmDebtor = netAmount > 0;
    final otherUid = currentUid == debt.userA ? debt.userB : debt.userA;

    final otherUserAsync = ref.watch(currentUserProvider(otherUid));

    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết nợ')),
      body: otherUserAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (otherUser) => Column(
          children: [
            // Tổng quan
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    iAmDebtor
                        ? 'Bạn đang nợ ${otherUser?.name ?? otherUid}'
                        : '${otherUser?.name ?? otherUid} đang nợ bạn',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatVnd(netAmount.abs()),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: iAmDebtor ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Nút hành động
            Padding(
              padding: const EdgeInsets.all(16),
              child: iAmDebtor
                  ? _DebtorActions(
                      debt: debt,
                      debtId: debtId,
                      currentUid: currentUid,
                      otherUid: otherUid,
                      netAmount: netAmount,
                      otherQrUrl: otherUser?.qrImageUrl,
                    )
                  : _CreditorSection(otherUserName: otherUser?.name ?? otherUid),
            ),
            const Divider(height: 1),

            // Lịch sử payments
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Lịch sử thanh toán',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
            ),
            Expanded(
              child: paymentsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Lỗi: $e')),
                data: (payments) {
                  if (payments.isEmpty) {
                    return const Center(
                        child: Text('Chưa có giao dịch nào',
                            style: TextStyle(color: Colors.grey)));
                  }
                  return ListView.builder(
                    itemCount: payments.length,
                    itemBuilder: (_, i) => _PaymentTile(
                      payment: payments[i],
                      currentUid: currentUid,
                      debtId: debtId,
                      debtorIsUserA: debt.userA == payments[i].fromUserId,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Con nợ: xem QR + bấm "Tôi đã chuyển" ──────────────────────────────────

class _DebtorActions extends ConsumerStatefulWidget {
  final Debt debt;
  final String debtId;
  final String currentUid;
  final String otherUid;
  final int netAmount;
  final String? otherQrUrl;

  const _DebtorActions({
    required this.debt,
    required this.debtId,
    required this.currentUid,
    required this.otherUid,
    required this.netAmount,
    required this.otherQrUrl,
  });

  @override
  ConsumerState<_DebtorActions> createState() => _DebtorActionsState();
}

class _DebtorActionsState extends ConsumerState<_DebtorActions> {
  bool _isSending = false;

  Future<void> _markTransferred() async {
    setState(() => _isSending = true);
    try {
      await ref.read(debtRepositoryProvider).markTransferred(
            debtId: widget.debtId,
            fromUid: widget.currentUid,
            toUid: widget.otherUid,
            amount: widget.netAmount,
            paymentId: newUuid(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Đã ghi nhận. Chờ chủ nợ xác nhận.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Có lỗi. Thử lại.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Kiểm tra xem đã có payment pending chưa — nếu có thì khoá nút.
    final hasPending = ref.watch(paymentsProvider(widget.debtId)).maybeWhen(
      data: (ps) => ps.any((p) => p.status == PaymentStatus.pending),
      orElse: () => false,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.otherQrUrl != null) ...[
          const Text('QR chuyển tiền:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: widget.otherQrUrl!,
              height: 200,
              fit: BoxFit.contain,
              placeholder: (ctx, url) =>
                  const Center(child: CircularProgressIndicator()),
              errorWidget: (ctx, url, err) =>
                  const Icon(Icons.broken_image, size: 64),
            ),
          ),
          const SizedBox(height: 12),
        ] else
          const Text('Chủ nợ chưa có QR.',
              style: TextStyle(color: Colors.grey)),
        if (hasPending)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Đang chờ chủ nợ xác nhận giao dịch trước.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.orange),
            ),
          ),
        FilledButton(
          onPressed: (_isSending || hasPending) ? null : _markTransferred,
          child: _isSending
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  hasPending
                      ? 'Đang chờ xác nhận...'
                      : 'Tôi đã chuyển ${formatVnd(widget.netAmount)}',
                ),
        ),
      ],
    );
  }
}

// ── Chủ nợ: hướng dẫn ──────────────────────────────────────────────────────

class _CreditorSection extends StatelessWidget {
  final String otherUserName;
  const _CreditorSection({required this.otherUserName});

  @override
  Widget build(BuildContext context) {
    return Text(
      '$otherUserName sẽ chuyển tiền cho bạn. Xác nhận khi nhận được.',
      style: const TextStyle(color: Colors.grey),
    );
  }
}

// ── Một dòng payment ────────────────────────────────────────────────────────

class _PaymentTile extends ConsumerWidget {
  final Payment payment;
  final String currentUid;
  final String debtId;
  final bool debtorIsUserA;

  const _PaymentTile({
    required this.payment,
    required this.currentUid,
    required this.debtId,
    required this.debtorIsUserA,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iAmCreditor = payment.toUserId == currentUid;
    final isPending = payment.status == PaymentStatus.pending;

    return ListTile(
      leading: Icon(
        isPending ? Icons.schedule : Icons.check_circle,
        color: isPending ? Colors.orange : Colors.green,
      ),
      title: Text(formatVnd(payment.amount)),
      subtitle: Text(
        isPending ? 'Chờ xác nhận' : 'Đã xác nhận',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: (iAmCreditor && isPending)
          ? TextButton(
              onPressed: () => _confirm(context, ref),
              child: const Text('Đã nhận'),
            )
          : null,
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(debtRepositoryProvider).confirmPayment(
            debtId: debtId,
            paymentId: payment.paymentId,
            amount: payment.amount,
            debtorIsUserA: debtorIsUserA,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Xác nhận thất bại. Thử lại.')),
        );
      }
    }
  }
}
