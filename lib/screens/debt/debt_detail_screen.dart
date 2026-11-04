import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/image_tools.dart';
import '../../ui/app_theme.dart';
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
    final current =
        live ??
        (debtsAsync.hasValue
            ? Debt(
                userA: debt.userA,
                userB: debt.userB,
                balance: 0,
                updatedAt: DateTime.now(),
              )
            : debt);

    // Từ góc nhìn currentUser: dương = đang nợ, âm = người kia nợ mình.
    final netAmount = current.amountOwedBy(currentUid);
    final iAmDebtor = netAmount > 0;
    final isSettled = netAmount == 0;
    final otherUid = currentUid == debt.userA ? debt.userB : debt.userA;

    final otherUserAsync = ref.watch(currentUserProvider(otherUid));
    final myName =
        ref.watch(currentUserProvider(currentUid)).valueOrNull?.name ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết nợ')),
      body: otherUserAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (otherUser) => ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            Text(
              otherUser?.name ?? otherUid,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            Text(
              isSettled
                  ? 'Đã thanh toán'
                  : iAmDebtor
                  ? 'Bạn nợ'
                  : 'Cần thu',
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: AppTheme.muted),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatVnd(netAmount.abs()),
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: isSettled
                      ? AppTheme.green
                      : iAmDebtor
                      ? AppTheme.ink
                      : AppTheme.purple,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),
            if (!isSettled && iAmDebtor)
              _DebtorActions(
                debt: current,
                debtId: debtId,
                currentUid: currentUid,
                otherUid: otherUid,
                netAmount: netAmount,
                otherQrUrl: otherUser?.qrImageUrl,
                myName: myName,
                otherName: otherUser?.name ?? '',
              ),
            if (!isSettled && !iAmDebtor)
              const Text(
                'Chờ thanh toán',
                style: TextStyle(color: AppTheme.muted),
              ),
            const SizedBox(height: 28),
            const SectionHeading('Lịch sử thanh toán'),
            paymentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Lỗi: $e'),
              data: (payments) => payments.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'Chưa có giao dịch',
                        style: TextStyle(color: AppTheme.muted),
                      ),
                    )
                  : Column(
                      children: [
                        for (final payment in payments)
                          _PaymentTile(
                            payment: payment,
                            currentUid: currentUid,
                            debtId: debtId,
                            debtorIsUserA: debt.userA == payment.fromUserId,
                          ),
                      ],
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
            content: const Text('Đã lưu QR'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Mở thư viện',
              onPressed: openGallery,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không lưu được ảnh. Kiểm tra mạng và quyền ảnh.'),
          ),
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
        note: transferNote(
          debtorName: widget.myName,
          creditorName: widget.otherName,
        ),
      );
    } on VietQrException {
      return null;
    }
  }

  Future<void> _markTransferred() async {
    setState(() => _isSending = true);
    try {
      await ref
          .read(debtRepositoryProvider)
          .markTransferred(
            debtId: widget.debtId,
            fromUid: widget.currentUid,
            toUid: widget.otherUid,
            paymentId: newUuid(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã ghi nhận. Chờ chủ nợ xác nhận.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is StateError ? e.message : 'Có lỗi. Thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Kiểm tra xem đã có payment pending chưa — nếu có thì khoá nút.
    final hasPending = ref
        .watch(paymentsProvider(widget.debtId))
        .maybeWhen(
          data: (ps) => ps.any((p) => p.status == PaymentStatus.pending),
          orElse: () => false,
        );
    // Đọc QR của chủ nợ để dựng mã có sẵn số tiền (watch để màn hình cập nhật khi đọc xong).
    if (widget.otherQrUrl != null) {
      ref.watch(staticQrPayloadProvider(widget.otherQrUrl!));
    }
    final dynamicQr = _dynamicPayload();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Nội dung chuyển khoản',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        SelectableText(
          transferNote(
            debtorName: widget.myName,
            creditorName: widget.otherName,
          ),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 24),
        if (widget.otherQrUrl != null) ...[
          if (dynamicQr != null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.line),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: dynamicQr,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CachedNetworkImage(
                imageUrl: widget.otherQrUrl!,
                height: 240,
                fit: BoxFit.contain,
                placeholder: (_, _) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined, size: 64),
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _isSaving ? null : _saveQr,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined, size: 20),
            label: const Text('Lưu QR'),
          ),
          const SizedBox(height: 12),
        ] else
          const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Text(
              'Chưa có QR nhận tiền',
              style: TextStyle(color: AppTheme.muted),
            ),
          ),
        FilledButton(
          onPressed: _isSending || hasPending ? null : _markTransferred,
          child: _isSending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(hasPending ? 'Chờ xác nhận' : 'Tôi đã chuyển'),
        ),
      ],
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
        color: isPending ? AppTheme.muted : AppTheme.green,
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
      await ref
          .read(debtRepositoryProvider)
          .confirmPayment(
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
