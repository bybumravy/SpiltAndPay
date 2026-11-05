import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/image_tools.dart';
import '../../ui/app_theme.dart';
import '../../ui/content_rows.dart';
import 'create_session_screen.dart';
import '../../core/money.dart';
import '../../core/vietqr.dart';
import '../../core/vietqr_provider.dart';
import '../../models/expense.dart';
import '../../models/session.dart';
import '../../repositories/guest_obligation_repository.dart';
import '../../repositories/guest_receivables_provider.dart';
import '../debt/widgets/guest_receivable_tile.dart';
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
    if (sessions != null &&
        currentUid != session.creatorId &&
        !sessions.any((s) => s.sessionId == session.sessionId)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Phiên')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Phiên đã bị xoá hoặc bạn không còn là thành viên.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final currentSession =
        sessions?.firstWhere(
          (s) => s.sessionId == session.sessionId,
          orElse: () => session,
        ) ??
        session;
    final membersAsync = ref.watch(
      sessionMembersProvider(currentSession.sessionId),
    );
    final expensesAsync = ref.watch(
      sessionExpensesProvider(currentSession.sessionId),
    );
    final guestObligationsAsync = ref.watch(
      sessionGuestObligationsProvider(currentSession.sessionId),
    );

    final editable =
        currentSession.status == SessionStatus.open &&
        currentSession.creatorId == currentUid;
    void editSession() {
      final members = membersAsync.valueOrNull;
      final expenses = expensesAsync.valueOrNull;
      if (members == null || expenses == null) return;
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CreateSessionScreen(
            creatorUid: currentUid,
            initialSession: currentSession,
            initialMembers: List.unmodifiable(members),
            initialExpenses: List.unmodifiable(expenses),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.only(right: 12),
          child: Text(
            'PHIÊN CHIA TIỀN',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: AppTheme.purple,
            ),
          ),
        ),
        titleSpacing: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: SessionStatusBadge(
              isOpen: currentSession.status == SessionStatus.open,
            ),
          ),
          if (editable)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') {
                  _confirmDelete(context, ref, currentSession);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Xoá phiên',
                    style: TextStyle(color: AppTheme.red),
                  ),
                ),
              ],
            )
          else
            const SizedBox(width: 24),
        ],
      ),
      bottomNavigationBar: editable
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton(
                      onPressed: membersAsync.hasValue && expensesAsync.hasValue
                          ? editSession
                          : null,
                      child: const Text('Chỉnh sửa phiên'),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: membersAsync.valueOrNull == null
                          ? null
                          : () => _confirmClose(
                              context,
                              ref,
                              membersAsync.valueOrNull!,
                              currentSession,
                            ),
                      child: const Text('Đóng phiên'),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  e.toString().toLowerCase().contains('permission-denied')
                      ? 'Không tải được thành viên: Kết nối hoặc phiên xác thực đang đồng bộ. Vui lòng thử lại.'
                      : 'Không tải được thành viên: $e',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    ref.invalidate(
                      sessionMembersProvider(currentSession.sessionId),
                    );
                    ref.invalidate(
                      sessionExpensesProvider(currentSession.sessionId),
                    );
                    ref.invalidate(
                      sessionGuestObligationsProvider(currentSession.sessionId),
                    );
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ),
        data: (members) => ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(
              currentSession.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text(
              'Tổng chi phí',
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: AppTheme.muted),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatVnd(currentSession.totalAmount),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              key: PageStorageKey('members-${currentSession.sessionId}'),
              dense: true,
              minTileHeight: 48,
              enabled: members.isNotEmpty,
              leading: members.isEmpty
                  ? null
                  : MemberAvatarGroup(
                      key: const ValueKey('session-member-avatars'),
                      names: members
                          .map(
                            (m) => m.displayName.trim().isEmpty
                                ? (m.userId == currentUid
                                      ? 'Bạn'
                                      : m.isGuest
                                      ? 'Khách'
                                      : 'Thành viên')
                                : m.displayName.trim(),
                          )
                          .toList(),
                    ),
              title: Text(
                key: const ValueKey('session-member-summary-label'),
                members.isEmpty
                    ? 'Chưa có thành viên'
                    : [
                        ...members
                            .take(members.length > 3 ? 2 : 3)
                            .map(
                              (m) => m.displayName.trim().isEmpty
                                  ? (m.userId == currentUid
                                        ? 'Bạn'
                                        : m.isGuest
                                        ? 'Khách'
                                        : 'Thành viên')
                                  : m.displayName.trim(),
                            ),
                        if (members.length > 3) '+${members.length - 2}',
                      ].join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              children: [
                for (final member in members)
                  _MemberTile(
                    member: member,
                    isOpen: currentSession.status == SessionStatus.open,
                    creatorId: currentSession.creatorId,
                    sessionId: currentSession.sessionId,
                    sessionTitle: currentSession.title,
                    isCreatorView: currentSession.creatorId == currentUid,
                    isItemizedSession:
                        expensesAsync.valueOrNull?.isNotEmpty ?? true,
                    currentUid: currentUid,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 4),
            _ExpenseSection(expensesAsync: expensesAsync, members: members),
            _GuestObligationSection(
              obligationsAsync: guestObligationsAsync,
              members: members,
              currentUid: currentUid,
              sessionId: currentSession.sessionId,
              sessionTitle: currentSession.title,
            ),
          ],
        ),
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
      await ref
          .read(sessionRepositoryProvider)
          .closeSession(
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

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Session targetSession,
  ) async {
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

class _ExpenseSection extends ConsumerWidget {
  final AsyncValue<List<Expense>> expensesAsync;
  final List<SessionMember> members;

  const _ExpenseSection({required this.expensesAsync, required this.members});

  @override
  Widget build(BuildContext context, WidgetRef ref) => expensesAsync.when(
    loading: () => const ListTile(
      title: Text('Khoản chi'),
      subtitle: LinearProgressIndicator(),
    ),
    error: (error, _) => ListTile(
      title: const Text('Khoản chi'),
      subtitle: Text('Không tải được danh sách: $error'),
    ),
    data: (expenses) {
      final names = {
        for (final member in members) member.memberId: member.displayName,
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            '${expenses.length} khoản chi',
            key: const ValueKey('expense-section-heading'),
          ),
          if (expenses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Chưa có khoản chi',
                style: TextStyle(color: AppTheme.muted),
              ),
            ),
          for (var index = 0; index < expenses.length; index++) ...[
            ExpansionTile(
              key: PageStorageKey('expense-${expenses[index].expenseId}'),
              initiallyExpanded: index == 0,
              dense: true,
              minTileHeight: 64,
              tilePadding: const EdgeInsets.symmetric(vertical: 4),
              title: LabelValueRow(
                label: Text(
                  expenses[index].description,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                value: Text(
                  formatVnd(expenses[index].amount),
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.purple,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  'Người trả: ${names[expenses[index].payerId] ?? expenses[index].payerId}',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: AppTheme.muted),
                ),
              ),
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.soft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Chia cho ${expenses[index].participantIds.length} người',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      for (final share
                          in expenses[index].effectiveShares.entries) ...[
                        const Divider(),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: LabelValueRow(
                            label: Text(names[share.key] ?? share.key),
                            value: Text(
                              formatVnd(share.value),
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const Divider(),
          ],
        ],
      );
    },
  );
}

class _GuestObligationSection extends ConsumerStatefulWidget {
  final AsyncValue<List<GuestObligation>> obligationsAsync;
  final List<SessionMember> members;
  final String currentUid;
  final String sessionId;
  final String sessionTitle;

  const _GuestObligationSection({
    required this.obligationsAsync,
    required this.members,
    required this.currentUid,
    required this.sessionId,
    required this.sessionTitle,
  });

  @override
  ConsumerState<_GuestObligationSection> createState() =>
      _GuestObligationSectionState();
}

class _GuestObligationSectionState
    extends ConsumerState<_GuestObligationSection> {
  final Set<String> _pending = {};

  Future<void> _collect(GuestObligation obligation) async {
    setState(() => _pending.add(obligation.obligationId));
    try {
      await ref
          .read(guestObligationRepositoryProvider)
          .markCollected(
            sessionId: widget.sessionId,
            obligationId: obligation.obligationId,
          );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể xác nhận đã thu. Thử lại.')),
        );
      }
    } finally {
      if (mounted) setState(() => _pending.remove(obligation.obligationId));
    }
  }

  @override
  Widget build(BuildContext context) => widget.obligationsAsync.when(
    loading: () => const ListTile(
      title: Text('Khoản khách nợ'),
      subtitle: LinearProgressIndicator(),
    ),
    error: (error, _) => ListTile(
      title: const Text('Khoản khách nợ'),
      subtitle: Text('Không tải được trạng thái: $error'),
    ),
    data: (obligations) {
      if (obligations.isEmpty) return const SizedBox.shrink();
      final guests = {
        for (final member in widget.members)
          member.memberId: member.displayName,
      };
      final payerNames = {
        for (final member in widget.members)
          if (member.userId != null) member.userId!: member.displayName,
      };
      return ExpansionTile(
        title: const Text('Khoản khách nợ'),
        subtitle: Text('${obligations.length} nghĩa vụ'),
        children: [
          for (final obligation in obligations)
            ListTile(
              title: Text(guests[obligation.guestMemberId] ?? 'Khách'),
              onTap: obligation.payerId == widget.currentUid
                  ? () => GuestReceivableTile.show(
                      context,
                      GuestReceivable(
                        obligation: obligation,
                        guestName: guests[obligation.guestMemberId] ?? 'Khách',
                        sessionTitle: widget.sessionTitle,
                      ),
                    )
                  : null,
              subtitle: Text(
                'Người thu: ${payerNames[obligation.payerId] ?? obligation.payerId} · '
                '${formatVnd(obligation.amount)} · '
                '${obligation.status == GuestObligationStatus.collected ? 'Đã thu' : 'Chưa thu'}',
              ),
              trailing: obligation.status == GuestObligationStatus.collected
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : obligation.payerId == widget.currentUid
                  ? _pending.contains(obligation.obligationId)
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: () => _collect(obligation),
                            child: const Text('Đã thu'),
                          )
                  : Text(formatVnd(obligation.amount)),
            ),
        ],
      );
    },
  );
}

class _MemberTile extends ConsumerStatefulWidget {
  final SessionMember member;
  final String creatorId;
  final String sessionId;
  final String sessionTitle;
  final bool
  isCreatorView; // creator can use legacy guest controls in legacy sessions
  final bool isItemizedSession;
  final bool isOpen;
  final String currentUid;

  const _MemberTile({
    required this.member,
    required this.creatorId,
    required this.sessionId,
    required this.sessionTitle,
    required this.isCreatorView,
    required this.isItemizedSession,
    required this.isOpen,
    required this.currentUid,
  });

  @override
  ConsumerState<_MemberTile> createState() => _MemberTileState();
}

class _MemberTileState extends ConsumerState<_MemberTile> {
  /// Chia sẻ cho khách của phiên legacy không có nghĩa vụ theo từng khoản.
  Future<void> _shareGuest() async {
    final m = widget.member;
    final message =
        '${widget.sessionTitle} — ${m.displayName}: ${formatVnd(m.amountOwed)}';

    final qrUrl = ref
        .read(currentUserProvider(widget.creatorId))
        .valueOrNull
        ?.qrImageUrl;
    if (qrUrl == null) {
      // Chưa có QR → vẫn gửi được câu nhắc dạng chữ.
      await Share.share(message);
      return;
    }

    try {
      // Ưu tiên mã VietQR có sẵn số tiền + nội dung; không đọc được thì dùng ảnh QR gốc.
      Uint8List qr;
      final staticPayload = await ref.read(
        staticQrPayloadProvider(qrUrl).future,
      );
      final creatorName =
          ref.read(currentUserProvider(widget.creatorId)).valueOrNull?.name ??
          '';
      if (staticPayload != null && m.amountOwed > 0) {
        final dyn = buildDynamicVietQr(
          staticPayload,
          amount: m.amountOwed,
          note: transferNote(
            debtorName: m.displayName,
            creditorName: creatorName,
          ),
        );
        qr = await renderQrPng(dyn, size: 700, margin: 40);
      } else {
        qr = await downloadImageBytes(qrUrl);
      }
      final card = await buildPaymentCard(qrPng: qr, message: message);
      final path = await writeTempImage(card, 'thanh_toan_${m.memberId}.png');
      await Share.shareXFiles([
        XFile(path, mimeType: 'image/png'),
      ], text: message);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không tạo được ảnh. Kiểm tra mạng và thử lại.'),
          ),
        );
      }
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
    } else if (widget.isOpen) {
      subtitle = 'Chưa chốt';
      if (m.amountPaid > 0) subtitle += ' · đã ứng ${formatVnd(m.amountPaid)}';
    } else if (m.isGuest) {
      subtitle = widget.isItemizedSession
          ? 'Khách'
          : m.status == MemberStatus.paid
          ? 'Khách — đã trả'
          : 'Khách — chưa trả';
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

    final legacyGuest =
        m.isGuest &&
        !isCreator &&
        widget.isCreatorView &&
        !widget.isItemizedSession;
    return ListTile(
      titleAlignment: ListTileTitleAlignment.top,
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      leading: InitialAvatar(name, radius: 18),
      title: LabelValueRow(
        label: Text(isMe ? '${name.isEmpty ? 'Bạn' : name} (bạn)' : name),
        value: Text(formatVnd(m.amountOwed), textAlign: TextAlign.end),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: legacyGuest
          ? (m.status != MemberStatus.paid
                ? IconButton(
                    icon: const Icon(Icons.share_outlined, size: 20),
                    tooltip: 'Nhắc nhở',
                    onPressed: _shareGuest,
                  )
                : const Icon(
                    Icons.check_circle,
                    color: AppTheme.green,
                    size: 20,
                  ))
          : null,
    );
  }
}
