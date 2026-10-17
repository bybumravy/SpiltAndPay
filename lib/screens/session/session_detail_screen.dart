import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/image_tools.dart';
import '../../core/money.dart';
import '../../core/vietqr.dart';
import '../../core/vietqr_provider.dart';
import '../../models/session.dart';
import '../../models/session_member.dart';
import '../../repositories/session_repository.dart';
import '../../repositories/user_repository.dart';

class SessionDetailScreen extends ConsumerWidget {
  final Session session;
  final String currentUid;

  const SessionDetailScreen({
    super.key,
    required this.session,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(userSessionsProvider(currentUid)).valueOrNull;
    final currentSession = sessions?.firstWhere(
          (s) => s.sessionId == session.sessionId,
          orElse: () => session,
        ) ??
        session;
    final membersAsync =
        ref.watch(sessionMembersProvider(currentSession.sessionId));

    return Scaffold(
      appBar: AppBar(
        title: Text(currentSession.title),
        actions: [
          if (currentSession.status == SessionStatus.open &&
              currentSession.creatorId == currentUid)
            membersAsync.maybeWhen(
              data: (members) => TextButton(
                onPressed: () =>
                    _confirmClose(context, ref, members, currentSession),
                child: const Text('Đóng phiên'),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          // Phiên đã đóng đã ghi nợ vào sổ → chỉ phiên đang mở mới sửa/xoá được.
          if (currentSession.creatorId == currentUid &&
              currentSession.status == SessionStatus.open)
            PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'edit') _editTitle(context, ref, currentSession);
                if (val == 'delete') _confirmDelete(context, ref, currentSession);
              },
              itemBuilder: (_) => [
                if (currentSession.status == SessionStatus.open)
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('Sửa tên phiên'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Xoá phiên', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // Tổng quan phiên
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tổng bill',
                          style: Theme.of(context).textTheme.bodySmall),
                      Text(formatVnd(currentSession.totalAmount),
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                ),
                _StatusChip(currentSession.status),
              ],
            ),
          ),
          const Divider(height: 1),

          // Danh sách thành viên
          Expanded(
            child: membersAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
              data: (members) {
                if (members.isEmpty) {
                  return const Center(child: Text('Không có thành viên'));
                }
                return ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (_, i) => _MemberTile(
                    member: members[i],
                    creatorId: currentSession.creatorId,
                    sessionId: currentSession.sessionId,
                    sessionTitle: currentSession.title,
                    isCreatorView: currentSession.creatorId == currentUid,
                    currentUid: currentUid,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClose(
    BuildContext context,
    WidgetRef ref,
    List<SessionMember> members,
    Session targetSession,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Đóng phiên'),
        content: const Text(
          'Đóng phiên sẽ ghi nợ vào sổ của các thành viên. Không thể hoàn tác.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(sessionRepositoryProvider).closeSession(
            sessionId: targetSession.sessionId,
            creatorId: targetSession.creatorId,
            members: members,
          );
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đóng phiên thất bại. Thử lại.')),
        );
      }
    }
  }

  Future<void> _editTitle(
      BuildContext context, WidgetRef ref, Session targetSession) async {
    final ctrl = TextEditingController(text: targetSession.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sửa tên phiên'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tên phiên mới'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    if (newTitle == null || newTitle.isEmpty || !context.mounted) return;

    try {
      await ref.read(sessionRepositoryProvider).updateSessionTitle(
            sessionId: targetSession.sessionId,
            newTitle: newTitle,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật tên phiên')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật thất bại. Thử lại.')),
        );
      }
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Session targetSession) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá phiên'),
        content: const Text(
          'Bạn có chắc muốn xoá phiên này? Dữ liệu phiên và thành viên sẽ bị xoá vĩnh viễn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xoá vĩnh viễn'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(sessionRepositoryProvider)
          .deleteSession(targetSession.sessionId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xoá phiên thành công')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Xoá phiên thất bại. Thử lại.')),
        );
      }
    }
  }
}

class _StatusChip extends StatelessWidget {
  final SessionStatus status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final isOpen = status == SessionStatus.open;
    return Chip(
      label: Text(isOpen ? 'Đang mở' : 'Đã đóng',
          style: const TextStyle(fontSize: 12)),
      backgroundColor: isOpen ? Colors.green[50] : Colors.grey[200],
      side: BorderSide(color: isOpen ? Colors.green : Colors.grey),
      padding: EdgeInsets.zero,
    );
  }
}

class _MemberTile extends ConsumerStatefulWidget {
  final SessionMember member;
  final String creatorId;
  final String sessionId;
  final String sessionTitle;
  final bool isCreatorView; // creator có thể đánh dấu "Đã thu" cho guest
  final String currentUid;

  const _MemberTile({
    required this.member,
    required this.creatorId,
    required this.sessionId,
    required this.sessionTitle,
    required this.isCreatorView,
    required this.currentUid,
  });

  @override
  ConsumerState<_MemberTile> createState() => _MemberTileState();
}

class _MemberTileState extends ConsumerState<_MemberTile> {
  bool _isUpdating = false;

  Future<void> _markGuestPaid() async {
    setState(() => _isUpdating = true);
    try {
      await ref.read(sessionRepositoryProvider).markGuestPaid(
            sessionId: widget.sessionId,
            memberId: widget.member.memberId,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật thất bại. Thử lại.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  /// Chia sẻ cho khách: ảnh QR của chủ nợ ghép với câu nhắc, gửi qua Zalo/Messenger.
  Future<void> _shareGuest() async {
    final m = widget.member;
    final message = 'Hi ${m.displayName}, tiền "${widget.sessionTitle}" của bạn là '
        '${formatVnd(m.amountOwed)} nhé. Quét mã này gửi mình nha!';

    final qrUrl =
        ref.read(currentUserProvider(widget.creatorId)).valueOrNull?.qrImageUrl;
    if (qrUrl == null) {
      // Chưa có QR → vẫn gửi được câu nhắc dạng chữ.
      await Share.share(message);
      return;
    }

    setState(() => _isUpdating = true);
    try {
      // Ưu tiên mã VietQR có sẵn số tiền + nội dung; không đọc được thì dùng ảnh QR gốc.
      Uint8List qr;
      final staticPayload = await ref.read(staticQrPayloadProvider(qrUrl).future);
      final creatorName =
          ref.read(currentUserProvider(widget.creatorId)).valueOrNull?.name ?? '';
      if (staticPayload != null && m.amountOwed > 0) {
        final dyn = buildDynamicVietQr(
          staticPayload,
          amount: m.amountOwed,
          note: transferNote(debtorName: m.displayName, creditorName: creatorName),
        );
        qr = await renderQrPng(dyn, size: 700, margin: 40);
      } else {
        qr = await downloadImageBytes(qrUrl);
      }
      final card = await buildPaymentCard(qrPng: qr, message: message);
      final path = await writeTempImage(card, 'thanh_toan_${m.memberId}.png');
      await Share.shareXFiles([XFile(path, mimeType: 'image/png')], text: message);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không tạo được ảnh. Kiểm tra mạng và thử lại.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final isCreator = m.memberId == widget.creatorId;
    final isMe = m.userId != null && m.userId == widget.currentUid;

    // Phiên cũ lưu tên rỗng cho người tạo → lấy tên từ hồ sơ người dùng.
    var name = m.displayName;
    if (name.isEmpty && m.userId != null) {
      name = ref.watch(currentUserProvider(m.userId!)).valueOrNull?.name ?? '';
    }

    String subtitle;
    if (isCreator) {
      subtitle = 'Người tạo';
      if (m.amountPaid > 0) subtitle += ' · đã ứng ${formatVnd(m.amountPaid)}';
    } else if (m.isGuest) {
      subtitle = m.status == MemberStatus.paid ? 'Khách — đã trả' : 'Khách — chưa trả';
    } else {
      switch (m.status) {
        case MemberStatus.ledger:
          subtitle = 'Đã ghi nợ';
        case MemberStatus.paid:
          subtitle = 'Đã trả';
        default:
          subtitle = 'Chờ xử lý';
      }
      if (m.amountPaid > 0) subtitle += ' · đã ứng ${formatVnd(m.amountPaid)}';
    }

    // Trailing: số tiền + nút hành động cho guest
    Widget trailing;
    if (m.isGuest && !isCreator && widget.isCreatorView) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(formatVnd(m.amountOwed)),
          const SizedBox(width: 4),
          if (m.status != MemberStatus.paid) ...[
            IconButton(
              icon: const Icon(Icons.share, size: 18),
              tooltip: 'Nhắc nhở',
              onPressed: _shareGuest,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
            _isUpdating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    tooltip: 'Đã thu',
                    onPressed: _markGuestPaid,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
          ] else
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
        ],
      );
    } else {
      trailing = Text(formatVnd(m.amountOwed));
    }

    return ListTile(
      leading: CircleAvatar(
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
      ),
      title: Text(isMe ? '${name.isEmpty ? 'Bạn' : name} (bạn)' : name),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: trailing,
    );
  }
}
