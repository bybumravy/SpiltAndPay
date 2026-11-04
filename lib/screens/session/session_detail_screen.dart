import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/image_tools.dart';
import 'create_session_screen.dart';
import '../../core/money.dart';
import '../../core/vietqr.dart';
import '../../core/vietqr_provider.dart';
import '../../models/expense.dart';
import '../../models/session.dart';
import '../../repositories/guest_obligation_repository.dart';
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
                if (val == 'all') {
                  final members = membersAsync.valueOrNull;
                  final expenses = expensesAsync.valueOrNull;
                  if (members == null || expenses == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Chờ tải thành viên và khoản chi trước khi sửa.',
                        ),
                      ),
                    );
                    return;
                  }
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
                if (val == 'edit') _editTitle(context, ref, currentSession);
                if (val == 'delete') {
                  _confirmDelete(context, ref, currentSession);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'all',
                  child: Text('Chỉnh sửa toàn bộ phiên'),
                ),
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
                      Text(
                        'Tổng bill',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        formatVnd(currentSession.totalAmount),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
                _StatusChip(currentSession.status),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: membersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Không tải được thành viên: $e',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () {
                          ref.invalidate(
                            sessionMembersProvider(currentSession.sessionId),
                          );
                          ref.invalidate(
                            sessionExpensesProvider(currentSession.sessionId),
                          );
                          ref.invalidate(
                            sessionGuestObligationsProvider(
                              currentSession.sessionId,
                            ),
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
                children: [
                  _ExpenseSection(
                    session: currentSession,
                    expensesAsync: expensesAsync,
                    members: members,
                    sessionId: currentSession.sessionId,
                    creatorId: currentSession.creatorId,
                    isEditable:
                        currentSession.status == SessionStatus.open &&
                        currentSession.creatorId == currentUid,
                  ),
                  _GuestObligationSection(
                    obligationsAsync: guestObligationsAsync,
                    members: members,
                    currentUid: currentUid,
                    sessionId: currentSession.sessionId,
                  ),
                  const ListTile(title: Text('Thành viên')),
                  if (members.isEmpty)
                    const Center(child: Text('Không có thành viên'))
                  else
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

  Future<void> _editTitle(
    BuildContext context,
    WidgetRef ref,
    Session targetSession,
  ) async {
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
      await ref
          .read(sessionRepositoryProvider)
          .updateSessionTitle(
            sessionId: targetSession.sessionId,
            newTitle: newTitle,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã cập nhật tên phiên')));
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

class _AddExpenseDialog extends StatefulWidget {
  final List<SessionMember> members;
  final String initialPayerId;

  const _AddExpenseDialog({
    required this.members,
    required this.initialPayerId,
  });

  @override
  State<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<_AddExpenseDialog> {
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  late String _payerId = widget.initialPayerId;
  late final List<String> _participantIds = widget.members
      .map((m) => m.memberId)
      .toList();

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Thêm khoản chi'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _descriptionController,
          decoration: const InputDecoration(labelText: 'Mô tả'),
        ),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          inputFormatters: [VndInputFormatter()],
          decoration: const InputDecoration(labelText: 'Số tiền (VND)'),
        ),
        DropdownButtonFormField<String>(
          initialValue: _payerId,
          decoration: const InputDecoration(labelText: 'Người trả'),
          items: [
            for (final member in widget.members.where((m) => m.userId != null))
              DropdownMenuItem(
                value: member.memberId,
                child: Text(member.displayName),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _payerId = value);
          },
        ),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Người tham gia'),
        ),
        for (final member in widget.members)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(member.displayName),
            value: _participantIds.contains(member.memberId),
            onChanged: (selected) => setState(() {
              if (selected == true) {
                _participantIds.add(member.memberId);
              } else {
                _participantIds.remove(member.memberId);
              }
            }),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Huỷ'),
      ),
      FilledButton(
        onPressed: () {
          final description = _descriptionController.text.trim();
          final parsedAmount = parseVndInput(_amountController.text);
          if (description.isNotEmpty &&
              parsedAmount != null &&
              parsedAmount > 0 &&
              _participantIds.isNotEmpty &&
              widget.members.any(
                (member) =>
                    member.memberId == _payerId && member.userId != null,
              )) {
            Navigator.pop(context, (
              description: description,
              amount: parsedAmount,
              payerId: _payerId,
              participantIds: List<String>.unmodifiable(_participantIds),
            ));
          }
        },
        child: const Text('Thêm'),
      ),
    ],
  );
}

class _EditExpenseDialog extends StatefulWidget {
  final Expense expense;
  final List<SessionMember> members;

  const _EditExpenseDialog({required this.expense, required this.members});

  @override
  State<_EditExpenseDialog> createState() => _EditExpenseDialogState();
}

class _EditExpenseDialogState extends State<_EditExpenseDialog> {
  late final _descriptionController = TextEditingController(
    text: widget.expense.description,
  );
  late final _amountController = TextEditingController(
    text: formatVndInput(widget.expense.amount),
  );
  late String _payerId = widget.expense.payerId;
  late final List<String> _participantIds = [...widget.expense.participantIds];

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sửa khoản chi'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _descriptionController,
          decoration: const InputDecoration(labelText: 'Mô tả'),
        ),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          inputFormatters: [VndInputFormatter()],
          decoration: const InputDecoration(labelText: 'Số tiền (VND)'),
        ),
        DropdownButtonFormField<String>(
          initialValue: _payerId,
          decoration: const InputDecoration(labelText: 'Người trả'),
          items: [
            for (final member in widget.members.where((m) => m.userId != null))
              DropdownMenuItem(
                value: member.memberId,
                child: Text(member.displayName),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _payerId = value);
          },
        ),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Người tham gia'),
        ),
        for (final member in widget.members)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(member.displayName),
            value: _participantIds.contains(member.memberId),
            onChanged: (selected) => setState(() {
              if (selected == true) {
                _participantIds.add(member.memberId);
              } else {
                _participantIds.remove(member.memberId);
              }
            }),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Huỷ'),
      ),
      FilledButton(
        onPressed: () {
          final description = _descriptionController.text.trim();
          final parsedAmount = parseVndInput(_amountController.text);
          if (description.isNotEmpty &&
              parsedAmount != null &&
              parsedAmount > 0 &&
              _participantIds.isNotEmpty &&
              widget.members.any(
                (member) =>
                    member.memberId == _payerId && member.userId != null,
              )) {
            Navigator.pop(
              context,
              ExpenseInput(
                expenseId: widget.expense.expenseId,
                description: description,
                amount: parsedAmount,
                payerId: _payerId,
                participantIds: List.unmodifiable(_participantIds),
              ),
            );
          }
        },
        child: const Text('Lưu'),
      ),
    ],
  );
}

class _ExpenseSection extends ConsumerWidget {
  final Session session;
  final AsyncValue<List<Expense>> expensesAsync;
  final List<SessionMember> members;
  final String sessionId;
  final String creatorId;
  final bool isEditable;

  const _ExpenseSection({
    required this.session,
    required this.expensesAsync,
    required this.members,
    required this.sessionId,
    required this.creatorId,
    required this.isEditable,
  });

  Future<void> _editExpense(
    BuildContext context,
    WidgetRef ref,
    Expense expense,
  ) async {
    final result = await showDialog<ExpenseInput>(
      context: context,
      builder: (context) =>
          _EditExpenseDialog(expense: expense, members: members),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref
          .read(sessionRepositoryProvider)
          .updateExpense(
            sessionId: sessionId,
            expenseId: expense.expenseId,
            expense: result,
          );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể sửa khoản chi. Thử lại.')),
        );
      }
    }
  }

  Future<void> _addExpense(
    BuildContext context,
    WidgetRef ref,
    List<SessionMember> members,
  ) async {
    if (expensesAsync.valueOrNull?.isEmpty ?? false) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CreateSessionScreen(
            creatorUid: creatorId,
            initialSession: session,
            initialMembers: List.unmodifiable(members),
          ),
        ),
      );
      return;
    }
    final accountMembers = members
        .where((member) => member.userId != null)
        .toList();
    if (!accountMembers.any((member) => member.userId == creatorId)) return;
    final creator = accountMembers.firstWhere(
      (member) => member.userId == creatorId,
    );
    final result =
        await showDialog<
          ({
            String description,
            int amount,
            String payerId,
            List<String> participantIds,
          })
        >(
          context: context,
          builder: (context) => _AddExpenseDialog(
            members: members,
            initialPayerId: creator.memberId,
          ),
        );
    if (result == null || !context.mounted) return;
    try {
      await ref
          .read(sessionRepositoryProvider)
          .addExpense(
            sessionId: sessionId,
            expense: ExpenseInput(
              expenseId: newUuid(),
              description: result.description,
              amount: result.amount,
              payerId: result.payerId,
              participantIds: result.participantIds,
            ),
          );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể thêm khoản chi. Thử lại.')),
        );
      }
    }
  }

  Future<void> _deleteExpense(
    BuildContext context,
    WidgetRef ref,
    Expense expense,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá khoản chi'),
        content: Text('Xoá “${expense.description}”?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(sessionRepositoryProvider)
          .deleteExpense(sessionId: sessionId, expenseId: expense.expenseId);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể xoá khoản chi. Thử lại.')),
        );
      }
    }
  }

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
      if (expenses.isEmpty && !isEditable) return const SizedBox.shrink();
      final names = {
        for (final member in members) member.memberId: member.displayName,
      };
      return ExpansionTile(
        title: const Text('Các khoản chi'),
        subtitle: Text('${expenses.length} khoản'),
        children: [
          if (expenses.isEmpty)
            const ListTile(title: Text('Chưa có khoản chi')),
          for (final expense in expenses)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Card.outlined(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              expense.description,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              formatVnd(expense.amount),
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Người trả: ${names[expense.payerId] ?? expense.payerId}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Text(
                        'Chia cho ${expense.participantIds.length} người',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 4),
                      for (final share in expense.effectiveShares.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(names[share.key] ?? share.key),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  formatVnd(share.value),
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (isEditable) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: 'Sửa khoản chi',
                              onPressed: () =>
                                  _editExpense(context, ref, expense),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Xoá khoản chi',
                              onPressed: expenses.length <= 1
                                  ? null
                                  : () => _deleteExpense(context, ref, expense),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          if (isEditable)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _addExpense(context, ref, members),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm khoản chi'),
                ),
              ),
            ),
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

  const _GuestObligationSection({
    required this.obligationsAsync,
    required this.members,
    required this.currentUid,
    required this.sessionId,
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

class _StatusChip extends StatelessWidget {
  final SessionStatus status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final isOpen = status == SessionStatus.open;
    return Chip(
      label: Text(
        isOpen ? 'Đang mở' : 'Đã đóng',
        style: const TextStyle(fontSize: 12),
      ),
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
        'Hi ${m.displayName}, tiền "${widget.sessionTitle}" của bạn là '
        '${formatVnd(m.amountOwed)} nhé. Quét mã này gửi mình nha!';

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
      subtitle = 'Phần chia tạm tính · chưa chốt';
      if (m.amountPaid > 0) subtitle += ' · đã ứng ${formatVnd(m.amountPaid)}';
    } else if (m.isGuest) {
      subtitle = widget.isItemizedSession
          ? 'Khách — xem nghĩa vụ theo khoản chi'
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

    // Trailing: số tiền + nút hành động cho guest
    Widget trailing;
    if (m.isGuest &&
        !isCreator &&
        widget.isCreatorView &&
        !widget.isItemizedSession) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(formatVnd(m.amountOwed)),
          const SizedBox(width: 4),
          if (m.status != MemberStatus.paid)
            IconButton(
              icon: const Icon(Icons.share, size: 18),
              tooltip: 'Nhắc nhở',
              onPressed: _shareGuest,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            )
          else
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
