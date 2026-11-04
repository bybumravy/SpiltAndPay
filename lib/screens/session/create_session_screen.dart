import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/bill_ocr.dart';
import '../../core/expense_allocation.dart';
import '../../core/money.dart';
import '../../models/app_user.dart';
import '../../models/expense.dart';
import '../../models/session.dart';
import '../../models/session_member.dart';
import '../../repositories/session_repository.dart';
import '../../repositories/user_repository.dart';

class CreateSessionScreen extends ConsumerStatefulWidget {
  final String creatorUid;
  final Session? initialSession;
  final List<SessionMember> initialMembers;
  final List<Expense> initialExpenses;
  const CreateSessionScreen({
    super.key,
    required this.creatorUid,
    this.initialSession,
    this.initialMembers = const [],
    this.initialExpenses = const [],
  });

  @override
  ConsumerState<CreateSessionScreen> createState() =>
      _CreateSessionScreenState();
}

class _CreateSessionScreenState extends ConsumerState<CreateSessionScreen> {
  final _titleController = TextEditingController();
  static const SessionSplitMode _splitMode = SessionSplitMode.equal;
  bool _isSaving = false;
  String? _creatorName;
  int? _activeExpenseIndex;
  final List<_MemberEntry> _members = [];
  final List<_ExpenseEntry> _expenses = [];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSession;
    if (initial != null) {
      _creatorName = widget.initialMembers
          .where((m) => m.memberId == widget.creatorUid)
          .firstOrNull
          ?.displayName;
      _titleController.text = initial.title;
      for (final member in widget.initialMembers.where(
        (m) => m.memberId != widget.creatorUid,
      )) {
        _members.add(
          _MemberEntry(
            name: member.displayName,
            userId: member.userId,
            memberId: member.memberId,
            isGuest: member.isGuest,
          ),
        );
      }
      for (final expense in widget.initialExpenses) {
        final entry = _ExpenseEntry(
          payerId: expense.payerId,
          expenseId: expense.expenseId,
        );
        entry.descriptionController.text = expense.description;
        entry.amountController.text = formatVndInput(expense.amount);
        entry.participantIds.addAll(expense.participantIds);
        _expenses.add(entry);
      }
      if (_expenses.isEmpty) {
        // Preserve known advances while explicitly migrating legacy equal shares.
        final payers = widget.initialMembers
            .where((m) => !m.isGuest && m.userId != null && m.amountPaid > 0)
            .toList();
        final paidTotal = payers.fold<int>(
          0,
          (total, m) => total + m.amountPaid,
        );
        if (paidTotal == initial.totalAmount && payers.isNotEmpty) {
          for (final payer in payers) {
            final entry = _ExpenseEntry(payerId: payer.memberId);
            entry.descriptionController.text =
                '${initial.title} · ${payer.displayName}';
            entry.amountController.text = formatVndInput(payer.amountPaid);
            entry.participantIds.addAll(_memberIds);
            _expenses.add(entry);
          }
        } else {
          final entry = _ExpenseEntry(payerId: widget.creatorUid);
          entry.descriptionController.text = initial.title;
          entry.amountController.text = formatVndInput(initial.totalAmount);
          entry.participantIds.addAll(_memberIds);
          _expenses.add(entry);
        }
      }
    } else {
      final firstExpense = _ExpenseEntry(payerId: widget.creatorUid);
      firstExpense.participantIds.add(widget.creatorUid);
      _expenses.add(firstExpense);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final expense in _expenses) {
      expense.dispose();
    }
    super.dispose();
  }

  List<String> get _memberIds => [
    widget.creatorUid,
    ..._members.map((m) => m.memberId),
  ];

  Set<String> get _guestIds =>
      _members.where((m) => m.isGuest).map((m) => m.memberId).toSet();

  List<_ExpenseEntry> get _validExpenses => _expenses
      .where(
        (expense) => expense.amount > 0 && expense.participantIds.isNotEmpty,
      )
      .toList();

  SessionExpensePreview get _preview => previewSessionExpenses([
    for (final expense in _validExpenses)
      ExpenseDraft(
        amount: expense.amount,
        payerId: expense.payerId,
        participantIds: expense.participantIds,
      ),
  ], guestMemberIds: _guestIds);

  Future<void> _pickAndOcr(int index) async {
    final target = _expenses[index];
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null || !mounted || !_expenses.contains(target)) return;
    setState(() => _activeExpenseIndex = index);
    try {
      final scan = await scanBill(File(picked.path));
      if (!mounted || !_expenses.contains(target)) return;
      if (scan.total == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không nhận ra số tiền nào từ ảnh.')),
        );
        return;
      }
      setState(
        () => _expenses[index].amountController.text = formatVndInput(
          scan.total!,
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            scan.confident
                ? 'Đã đọc tổng tiền: ${formatVnd(scan.total!)}. Kiểm tra lại nhé.'
                : 'Không thấy dòng "Tổng cộng", tạm lấy số lớn nhất: ${formatVnd(scan.total!)}. Hãy kiểm tra lại.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OCR thất bại. Nhập tay số tiền.')),
        );
      }
    }
  }

  Future<void> _showAddMemberDialog() async {
    final alreadyAdded = _members
        .where((m) => m.userId != null)
        .map((m) => m.userId!)
        .toSet();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddMemberSheet(
        currentUid: widget.creatorUid,
        alreadyAddedUids: alreadyAdded,
        onAddUser: (user) {
          if (_members.any((m) => m.userId == user.uid)) return;
          setState(() {
            _members.add(_MemberEntry.fromUser(user));
          });
        },
        onAddGuest: (name) {
          final guest = _MemberEntry.guest(name);
          setState(() {
            _members.add(guest);
          });
        },
      ),
    );
  }

  Future<void> _editMember(_MemberEntry member) async {
    var editedName = member.name;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tên trong phiên'),
        content: TextFormField(
          initialValue: member.name,
          autofocus: true,
          onChanged: (value) => editedName = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () {
              if (editedName.trim().isNotEmpty) {
                Navigator.pop(ctx, editedName.trim());
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (mounted && name != null) {
      setState(() {
        if (member.memberId == widget.creatorUid) {
          _creatorName = name;
        } else {
          member.name = name;
        }
      });
    }
  }

  Future<void> _removeMember(_MemberEntry member) async {
    if (_expenses.any(
      (e) =>
          e.participantIds.length == 1 &&
          e.participantIds.contains(member.memberId),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hãy chọn người tham gia thay thế cho khoản chi chỉ có thành viên này trước khi xoá.',
          ),
        ),
      );
      return;
    }
    final wasPayer = _expenses.any((e) => e.payerId == member.memberId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Xoá ${member.name} khỏi phiên?'),
        content: Text(
          'Phần tiền các khoản có người này sẽ được chia lại cho những người còn lại.${wasPayer ? ' Các khoản người này trả sẽ chuyển người trả sang bạn; bạn có thể chọn lại trước khi lưu.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _members.remove(member);
      for (final expense in _expenses) {
        expense.participantIds.remove(member.memberId);
        if (expense.payerId == member.memberId) {
          expense.payerId = widget.creatorUid;
        }
      }
    });
  }

  void _addExpense() => setState(() {
    final expense = _ExpenseEntry(payerId: widget.creatorUid);
    expense.participantIds.addAll(_memberIds);
    _expenses.add(expense);
    _activeExpenseIndex = _expenses.length - 1;
  });

  void _removeExpense(int index) {
    if (_expenses.length <= 1) return;
    final removed = _expenses.removeAt(index);
    removed.dispose();
    setState(() {
      if (_activeExpenseIndex == index) {
        _activeExpenseIndex = null;
      } else if (_activeExpenseIndex != null && _activeExpenseIndex! > index) {
        _activeExpenseIndex = _activeExpenseIndex! - 1;
      }
    });
  }

  Future<void> _editParticipants(int index) async {
    final expense = _expenses[index];
    setState(() => _activeExpenseIndex = index);
    final selected = Set<String>.from(expense.participantIds);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Ai tham gia khoản này?',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    FSelectTileGroup<String>(
                      control: FMultiValueControl.lifted(
                        value: Set.unmodifiable(selected),
                        onChange: (value) => setSheetState(() {
                          selected
                            ..clear()
                            ..addAll(value);
                        }),
                      ),
                      children: [
                        FSelectTile<String>(
                          title: const Text('Bạn (người tạo)'),
                          value: widget.creatorUid,
                        ),
                        for (final member in _members)
                          FSelectTile<String>(
                            title: Text(member.name),
                            value: member.memberId,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FButton(
                      onPress: () {
                        setState(() {
                          expense.participantIds
                            ..clear()
                            ..addAll(_memberIds.where(selected.contains));
                        });
                        Navigator.pop(context);
                      },
                      child: const Text('Lưu người tham gia'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _choosePayer(int index) async {
    final expense = _expenses[index];
    setState(() => _activeExpenseIndex = index);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text('Người trả khoản ${index + 1}')),
              for (final memberId in _memberIds.where(
                (id) => !_guestIds.contains(id),
              ))
                ListTile(
                  leading: Icon(
                    expense.payerId == memberId
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text(
                    memberId == widget.creatorUid
                        ? 'Bạn (người tạo)'
                        : _members
                              .firstWhere((m) => m.memberId == memberId)
                              .name,
                  ),
                  onTap: () {
                    setState(() => expense.payerId = memberId);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Nhập tên phiên.')));
      return;
    }
    if (_expenses.any((expense) => expense.amount <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nhập số tiền hợp lệ cho từng khoản chi.'),
        ),
      );
      return;
    }
    if (_expenses.any((expense) => expense.participantIds.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mỗi khoản chi cần ít nhất một người tham gia.'),
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final sessionId = widget.initialSession?.sessionId ?? newUuid();
      final now = DateTime.now();
      final total = _preview.totalAmount;
      final preview = _preview;
      final me = await ref
          .read(userRepositoryProvider)
          .findByUid(widget.creatorUid);
      final members = <SessionMember>[
        SessionMember(
          memberId: widget.creatorUid,
          userId: widget.creatorUid,
          displayName: (_creatorName?.trim().isNotEmpty ?? false)
              ? _creatorName!.trim()
              : me?.name ?? 'Bạn',
          isGuest: false,
          amountOwed: preview.owedByMember[widget.creatorUid] ?? 0,
          amountPaid: preview.paidByMember[widget.creatorUid] ?? 0,
          status: MemberStatus.self,
        ),
        for (var i = 0; i < _members.length; i++)
          SessionMember(
            memberId: _members[i].memberId,
            userId: _members[i].userId,
            displayName: _members[i].name,
            isGuest: _members[i].isGuest,
            amountOwed: preview.owedByMember[_members[i].memberId] ?? 0,
            amountPaid: preview.paidByMember[_members[i].memberId] ?? 0,
            status: _members[i].isGuest
                ? MemberStatus.pending
                : MemberStatus.ledger,
          ),
      ];
      final session = Session(
        sessionId: sessionId,
        creatorId: widget.creatorUid,
        title: title,
        totalAmount: total,
        splitMode: _splitMode,
        status: SessionStatus.open,
        memberUserIds: members
            .where((m) => m.userId != null)
            .map((m) => m.userId!)
            .toList(),
        createdAt: now,
      );
      final repository = ref.read(sessionRepositoryProvider);
      final inputs = [
        for (var i = 0; i < _expenses.length; i++)
          ExpenseInput(
            expenseId: _expenses[i].expenseId,
            description: _expenses[i].descriptionController.text.trim().isEmpty
                ? 'Khoản chi ${i + 1}'
                : _expenses[i].descriptionController.text.trim(),
            amount: _expenses[i].amount,
            payerId: _expenses[i].payerId,
            participantIds: List.unmodifiable(
              _memberIds.where(_expenses[i].participantIds.contains),
            ),
          ),
      ];
      if (widget.initialSession case final original?) {
        await repository.saveOpenSession(
          originalSession: original,
          originalMembers: widget.initialMembers,
          originalExpenses: widget.initialExpenses,
          title: title,
          members: members,
          expenses: inputs,
        );
      } else {
        await repository.createSessionWithExpenses(
          session: session,
          members: members,
          expenses: inputs,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError
                  ? e.message
                  : e is ArgumentError
                  ? e.message.toString()
                  : 'Không lưu được phiên. Kiểm tra kết nối rồi thử lại.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _preview.totalAmount;
    final theme = FTheme.neutral.light.touch;
    return FTheme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.initialSession == null ? 'Tạo phiên mới' : 'Chỉnh sửa phiên',
          ),
        ),
        body: AbsorbPointer(
          absorbing: _isSaving,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.initialSession != null &&
                  widget.initialExpenses.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Phiên cũ sẽ chuyển sang chia đều theo từng khoản chi khi lưu. Kiểm tra lại người trả, số tiền đã ứng và phần chia bên dưới.',
                  ),
                ),
              FCard(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      FTextField(
                        control: FTextFieldControl.managed(
                          controller: _titleController,
                        ),
                        label: const Text('Tên phiên'),
                        hint: 'Ví dụ: Đi Đà Lạt',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Khoản chi',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _expenses.length; i++) ...[
                        _ExpenseEditorCard(
                          key: ValueKey(_expenses[i].key),
                          index: i,
                          expense: _expenses[i],
                          memberIds: _memberIds,
                          members: _members,
                          creatorName: 'Bạn',
                          isActive: _activeExpenseIndex == i,
                          onActive: () =>
                              setState(() => _activeExpenseIndex = i),
                          onAmountChanged: (_) =>
                              setState(() => _activeExpenseIndex = i),
                          onRemove: _expenses.length > 1
                              ? () => _removeExpense(i)
                              : null,
                          onChoosePayer: () => _choosePayer(i),
                          onChooseParticipants: () => _editParticipants(i),
                          onOcr: () => _pickAndOcr(i),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FButton(
                          variant: .outline,
                          mainAxisSize: .min,
                          onPress: _addExpense,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add),
                              SizedBox(width: 6),
                              Text('Thêm khoản chi'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FCard(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tổng phiên',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatVnd(total),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const Divider(),
                      for (final memberId in _memberIds)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  memberId == widget.creatorUid
                                      ? 'Bạn'
                                      : _members
                                            .firstWhere(
                                              (m) => m.memberId == memberId,
                                            )
                                            .name,
                                ),
                              ),
                              Text(
                                formatVnd(_preview.owedByMember[memberId] ?? 0),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Thành viên (${_members.length + 1})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.person_add_outlined),
                    label: const Text('Thêm'),
                    onPressed: _showAddMemberDialog,
                  ),
                ],
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: const Text('Bạn (người tạo)'),
                onTap: () => _editMember(
                  _MemberEntry(
                    name: _creatorName ?? 'Bạn',
                    userId: widget.creatorUid,
                    memberId: widget.creatorUid,
                    isGuest: false,
                  ),
                ),
                subtitle: Text(
                  '${_creatorName ?? 'Bạn'} · Chạm để đổi tên trong phiên',
                ),
                trailing: Text(
                  formatVnd(_preview.owedByMember[widget.creatorUid] ?? 0),
                ),
              ),
              for (final member in _members)
                ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      member.name.isEmpty ? '?' : member.name[0].toUpperCase(),
                    ),
                  ),
                  title: Text(member.name),
                  subtitle: member.isGuest ? const Text('Khách') : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatVnd(_preview.owedByMember[member.memberId] ?? 0),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Sửa thành viên',
                        onSelected: (value) {
                          if (value == 'name') {
                            _editMember(member);
                          } else {
                            _removeMember(member);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'name',
                            child: Text('Đổi tên trong phiên'),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text('Xoá khỏi phiên'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              FButton(
                onPress: _isSaving ? null : _submit,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        widget.initialSession == null
                            ? 'Tạo phiên'
                            : 'Lưu thay đổi',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpenseEditorCard extends StatelessWidget {
  final int index;
  final _ExpenseEntry expense;
  final List<String> memberIds;
  final List<_MemberEntry> members;
  final String creatorName;
  final bool isActive;
  final VoidCallback onActive;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback? onRemove;
  final VoidCallback onChoosePayer;
  final VoidCallback onChooseParticipants;
  final VoidCallback onOcr;

  const _ExpenseEditorCard({
    super.key,
    required this.index,
    required this.expense,
    required this.memberIds,
    required this.members,
    required this.creatorName,
    required this.isActive,
    required this.onActive,
    required this.onAmountChanged,
    required this.onRemove,
    required this.onChoosePayer,
    required this.onChooseParticipants,
    required this.onOcr,
  });

  @override
  Widget build(BuildContext context) {
    final payer = expense.payerId == memberIds.first
        ? creatorName
        : members.firstWhere((m) => m.memberId == expense.payerId).name;
    final selectedNames = [
      if (expense.participantIds.contains(memberIds.first)) creatorName,
      for (final member in members)
        if (expense.participantIds.contains(member.memberId)) member.name,
    ];
    return FCard(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Khoản chi ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    onPressed: onRemove,
                    tooltip: 'Xoá khoản chi',
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            FTextField(
              control: FTextFieldControl.managed(
                controller: expense.descriptionController,
              ),
              label: const Text('Mô tả'),
              hint: 'Ví dụ: Ăn tối, vé xem phim',
              onTap: onActive,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FTextField(
                    control: FTextFieldControl.managed(
                      controller: expense.amountController,
                      onChange: (_) => onAmountChanged(''),
                    ),
                    label: const Text('Số tiền (VND)'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [VndInputFormatter()],
                    onTap: onActive,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onOcr,
                  tooltip: 'Quét bill bằng OCR',
                  icon: const Icon(Icons.document_scanner_outlined),
                ),
              ],
            ),
            Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Người trả'),
                subtitle: Text(payer),
                trailing: const Icon(Icons.chevron_right),
                onTap: onChoosePayer,
              ),
            ),
            Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Người tham gia'),
                subtitle: Text(
                  selectedNames.isEmpty
                      ? 'Chưa chọn'
                      : selectedNames.join(', '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: onChooseParticipants,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseEntry {
  final String key = UniqueKey().toString();
  final String expenseId;
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final List<String> participantIds = [];
  String payerId;

  _ExpenseEntry({required this.payerId, String? expenseId})
    : expenseId = expenseId ?? newUuid();

  int get amount => parseVndInput(amountController.text) ?? 0;

  void dispose() {
    descriptionController.dispose();
    amountController.dispose();
  }
}

class _MemberEntry {
  String name;
  final String? userId;
  final String memberId;
  final bool isGuest;
  int? customAmount;

  _MemberEntry({
    required this.name,
    required this.userId,
    required this.memberId,
    required this.isGuest,
  });

  factory _MemberEntry.fromUser(AppUser user) => _MemberEntry(
    name: user.name,
    userId: user.uid,
    memberId: user.uid,
    isGuest: false,
  );

  factory _MemberEntry.guest(String name) => _MemberEntry(
    name: name,
    userId: null,
    memberId: newUuid(),
    isGuest: true,
  );
}

class _AddMemberSheet extends ConsumerStatefulWidget {
  final String currentUid;
  final Set<String> alreadyAddedUids;
  final ValueChanged<AppUser> onAddUser;
  final ValueChanged<String> onAddGuest;

  const _AddMemberSheet({
    required this.currentUid,
    required this.alreadyAddedUids,
    required this.onAddUser,
    required this.onAddGuest,
  });

  @override
  ConsumerState<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<_AddMemberSheet> {
  final _guestController = TextEditingController();

  @override
  void dispose() {
    _guestController.dispose();
    super.dispose();
  }

  void _showMyQrCode(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QR kết bạn của bạn'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Đưa bạn bè quét mã này để kết bạn.'),
            const SizedBox(height: 16),
            CustomPaint(
              size: const Size(200, 200),
              painter: QrPainter(
                data: widget.currentUid,
                version: QrVersions.auto,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _scanFriendQr(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: 420,
        child: Column(
          children: [
            AppBar(
              title: const Text('Quét QR bạn bè'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            Expanded(
              child: MobileScanner(
                onDetect: (capture) async {
                  final uid = capture.barcodes.firstOrNull?.rawValue;
                  if (uid == null || uid.isEmpty || uid == widget.currentUid) {
                    return;
                  }
                  Navigator.pop(ctx);
                  try {
                    final userRepo = ref.read(userRepositoryProvider);
                    final otherUser = await userRepo.findByUid(uid);
                    final currentUser = await userRepo.findByUid(
                      widget.currentUid,
                    );
                    if (otherUser != null) {
                      await userRepo.upsertContact(
                        widget.currentUid,
                        otherUser,
                      );
                      if (currentUser != null) {
                        try {
                          await userRepo.upsertContact(
                            otherUser.uid,
                            currentUser,
                          );
                        } catch (_) {}
                      }
                      widget.onAddUser(otherUser);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Đã kết bạn và thêm ${otherUser.name} vào phiên!',
                            ),
                          ),
                        );
                        Navigator.pop(context);
                      }
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Có lỗi khi kết bạn. Thử lại.'),
                        ),
                      );
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsProvider(widget.currentUid));
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Thêm thành viên',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _showMyQrCode(context),
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Hiện QR của tôi'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _scanFriendQr(context),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Quét QR bạn'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FTextField(
                  control: FTextFieldControl.managed(
                    controller: _guestController,
                  ),
                  label: const Text('Tên khách (nếu không có app)'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final name = _guestController.text.trim();
                  if (name.isEmpty) return;
                  widget.onAddGuest(name);
                  _guestController.clear();
                },
                child: const Text('Thêm'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Chọn từ danh sách bạn bè:'),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: contactsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
              data: (list) {
                final filtered = list
                    .where(
                      (u) =>
                          u.uid != widget.currentUid &&
                          !widget.alreadyAddedUids.contains(u.uid),
                    )
                    .toList();
                if (filtered.isEmpty) {
                  return const Center(
                    child: Text('Chưa có bạn bè nào có thể thêm.'),
                  );
                }
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        filtered[i].name.isEmpty
                            ? '?'
                            : filtered[i].name[0].toUpperCase(),
                      ),
                    ),
                    title: Text(filtered[i].name),
                    subtitle: Text(filtered[i].email),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () => widget.onAddUser(filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
