import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/image_tools.dart';
import '../../core/money.dart';
import '../../core/vietqr.dart';
import '../../core/vietqr_provider.dart';
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

    // Lấy khoản nợ MỚI NHẤT từ server (không dùng bản `debt` lúc mở màn hình,
    // vì sau khi trả xong nó đã cũ). Không còn trong danh sách = nợ đã về 0.
    final debtsAsync = ref.watch(userDebtsProvider(currentUid));
    final live = debtsAsync.valueOrNull
        ?.where((d) => Debt.docId(d.userA, d.userB) == debtId)
        .firstOrNull;
    final current = live ??
        (debtsAsync.hasValue
            ? Debt(
                userA: debt.userA,
                userB: debt.userB,
                balance: 0,
                updatedAt: DateTime.now())
            : debt);

    // Từ góc nhìn currentUser: dương = đang nợ, âm = người kia nợ mình.
    final netAmount = current.amountOwedBy(currentUid);
    final iAmDebtor = netAmount > 0;
    final isSettled = netAmount == 0;
    final otherUid = currentUid == debt.userA ? debt.userB : debt.userA;

    final otherUserAsync = ref.watch(currentUserProvider(otherUid));
    final myName = ref.watch(currentUserProvider(currentUid)).valueOrNull?.name ?? '';

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
                    isSettled
                        ? 'Đã thanh toán đủ với ${otherUser?.name ?? otherUid}'
                        : iAmDebtor
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
              child: isSettled
                  ? const Text('Không còn khoản nợ nào.',
                      style: TextStyle(color: Colors.green))
                  : iAmDebtor
                  ? _DebtorActions(
                      debt: current,
                      debtId: debtId,
                      currentUid: currentUid,
                      otherUid: otherUid,
                      netAmount: netAmount,
                      otherQrUrl: otherUser?.qrImageUrl,
                      myName: myName,
                      otherName: otherUser?.name ?? '',
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
  final String myName;
  final String otherName;

  const _DebtorActions({
    required this.debt,
    required this.debtId,
    required this.currentUid,
    required this.otherUid,
    required this.netAmount,
    required this.otherQrUrl,
    required this.myName,
    required this.otherName,
  });

  @override
  ConsumerState<_DebtorActions> createState() => _DebtorActionsState();
}

class _DebtorActionsState extends ConsumerState<_DebtorActions> {
  bool _isSending = false;
  bool _isSaving = false;

  /// Lưu ảnh QR của chủ nợ vào thư viện để mở app ngân hàng quét.
  Future<void> _saveQr() async {
    final url = widget.otherQrUrl;
    if (url == null) return;
    setState(() => _isSaving = true);
    try {
      final dynamicQr = _dynamicPayload();
      final bytes = dynamicQr != null
          ? await renderQrPng(dynamicQr) // QR đã điền sẵn số tiền + nội dung
          : await downloadImageBytes(url);
      await saveImageToGallery(bytes, name: 'qr_${widget.otherUid}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Đã lưu ảnh QR vào album "SplitPay" trong thư viện ảnh.'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(label: 'Mở thư viện', onPressed: openGallery),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không lưu được ảnh. Kiểm tra mạng và quyền ảnh.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Mã VietQR động (có sẵn số tiền + nội dung); null nếu chưa đọc được QR của chủ nợ.
  String? _dynamicPayload() {
    final url = widget.otherQrUrl;
    if (url == null) return null;
    final staticPayload = ref.read(staticQrPayloadProvider(url)).valueOrNull;
    if (staticPayload == null) return null;
    try {
      return buildDynamicVietQr(
        staticPayload,
        amount: widget.netAmount,
        note: transferNote(debtorName: widget.myName, creditorName: widget.otherName),
      );
    } on VietQrException {
      return null;
    }
  }

  Future<void> _markTransferred() async {
    setState(() => _isSending = true);
    try {
      await ref.read(debtRepositoryProvider).markTransferred(
            debtId: widget.debtId,
            fromUid: widget.currentUid,
            toUid: widget.otherUid,
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
          SnackBar(
              content: Text(e is StateError ? e.message : 'Có lỗi. Thử lại.')),
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
    // Đọc QR của chủ nợ để dựng mã có sẵn số tiền (watch để màn hình cập nhật khi đọc xong).
    if (widget.otherQrUrl != null) ref.watch(staticQrPayloadProvider(widget.otherQrUrl!));
    final dynamicQr = _dynamicPayload();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hướng dẫn: QR tĩnh không có số tiền / nội dung nên người nợ tự nhập.
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bạn cần chuyển số tiền:'),
                Text(
                  formatVnd(widget.netAmount),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('Nội dung chuyển khoản nên ghi:'),
                SelectableText(
                  transferNote(
                    debtorName: widget.myName,
                    creditorName: widget.otherName,
                  ),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (widget.otherQrUrl != null) ...[
          const Text('QR chuyển tiền:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (dynamicQr != null) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: QrImageView(
                  data: dynamicQr,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Mã này đã điền sẵn số tiền và nội dung. Lưu ảnh, mở app ngân hàng và quét là xong.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ] else
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
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isSaving ? null : _saveQr,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            label: const Text('Lưu ảnh QR vào máy'),
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
