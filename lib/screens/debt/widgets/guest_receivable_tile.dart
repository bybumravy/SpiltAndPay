import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/firebase_providers.dart';
import '../../../core/image_tools.dart';
import '../../../core/money.dart';
import '../../../core/vietqr.dart';
import '../../../core/vietqr_provider.dart';
import '../../../models/expense.dart';
import '../../../repositories/guest_obligation_repository.dart';
import '../../../repositories/guest_receivables_provider.dart';
import '../../../repositories/user_repository.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/content_rows.dart';

class GuestReceivableTile extends StatelessWidget {
  final GuestReceivable item;
  const GuestReceivableTile({super.key, required this.item});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: InitialAvatar(item.guestName),
    title: LabelValueRow(
      label: Text(item.guestName),
      value: Text(
        formatVnd(item.obligation.amount),
        style: const TextStyle(
          color: AppTheme.green,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    subtitle: Text(
      '${item.sessionTitle} · ${item.obligation.status == GuestObligationStatus.collected ? 'Đã thu' : 'Chưa thu'}',
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => show(context, item),
  );
  static Future<void> show(BuildContext context, GuestReceivable item) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _GuestPaymentSheet(item: item),
      );
}

class _GuestPaymentSheet extends ConsumerStatefulWidget {
  final GuestReceivable item;
  const _GuestPaymentSheet({required this.item});
  @override
  ConsumerState<_GuestPaymentSheet> createState() => _GuestPaymentSheetState();
}

class _GuestPaymentSheetState extends ConsumerState<_GuestPaymentSheet> {
  bool _busy = false;
  Future<void> _collect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận đã thu?'),
        content: Text(
          'Đã nhận ${formatVnd(widget.item.obligation.amount)} từ ${widget.item.guestName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đã nhận'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(guestObligationRepositoryProvider)
          .markCollected(
            sessionId: widget.item.obligation.sessionId,
            obligationId: widget.item.obligation.obligationId,
          );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa xác nhận được khoản thu. Thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(String payload) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    try {
      final message =
          '${widget.item.sessionTitle}\n${widget.item.guestName}: ${formatVnd(widget.item.obligation.amount)}';
      final card = await buildPaymentCard(
        qrPng: await renderQrPng(payload, size: 700, margin: 40),
        message: message,
      );
      final path = await writeTempImage(
        card,
        'guest_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(path, mimeType: 'image/png')],
        text: message,
        sharePositionOrigin: origin,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không chia sẻ được QR. Thử lại.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final obligation = widget.item.obligation;
    final uid = ref.watch(authProvider).currentUser?.uid;
    if (uid != obligation.payerId) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Bạn không có quyền thu khoản này.'),
      );
    }
    final live = ref.watch(
      sessionGuestObligationsProvider(obligation.sessionId),
    );
    final current = live.valueOrNull
        ?.where((o) => o.obligationId == obligation.obligationId)
        .firstOrNull;
    final collected =
        (current ?? obligation).status == GuestObligationStatus.collected;
    final profile = ref.watch(currentUserProvider(obligation.payerId));
    final url = profile.valueOrNull?.qrImageUrl;
    String? payload;
    Widget qr;
    if (collected) {
      qr = const Text('Đã thu', style: TextStyle(color: AppTheme.green));
    } else if (profile.isLoading) {
      qr = const CircularProgressIndicator();
    } else if (url == null || url.isEmpty) {
      qr = Text(
        profile.hasError
            ? 'Chưa tải được QR nhận tiền'
            : 'Thêm QR nhận tiền trong Hồ sơ để chia sẻ.',
      );
    } else {
      final parsed = ref.watch(staticQrPayloadProvider(url));
      try {
        if (parsed.valueOrNull != null) {
          payload = buildDynamicVietQr(
            parsed.requireValue!,
            amount: obligation.amount,
            note: transferNote(
              debtorName: widget.item.guestName,
              creditorName: profile.valueOrNull?.name ?? '',
            ),
          );
        }
      } catch (_) {
        payload = null;
      }
      qr = parsed.isLoading
          ? const CircularProgressIndicator()
          : payload == null
          ? TextButton(
              onPressed: () => ref.invalidate(staticQrPayloadProvider(url)),
              child: const Text('Không đọc được QR. Thử lại'),
            )
          : QrImageView(
              key: ValueKey(payload),
              data: payload,
              size: 230,
              backgroundColor: Colors.white,
            );
    }
    final sharePayload = payload;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.item.guestName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(widget.item.sessionTitle),
            const SizedBox(height: 12),
            Text(
              formatVnd(obligation.amount),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            Center(child: qr),
            const SizedBox(height: 20),
            if (!collected) ...[
              OutlinedButton.icon(
                onPressed: _busy || sharePayload == null
                    ? null
                    : () => _share(sharePayload),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Chia sẻ QR'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy || !live.hasValue || current == null
                    ? null
                    : _collect,
                child: Text(_busy ? 'Đang xử lý…' : 'Xác nhận đã thu'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
