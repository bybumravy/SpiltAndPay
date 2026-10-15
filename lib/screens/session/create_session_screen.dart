import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/money.dart';
import '../../models/app_user.dart';
import '../../models/session.dart';
import '../../models/session_member.dart';
import '../../repositories/session_repository.dart';
import '../../repositories/user_repository.dart';

class CreateSessionScreen extends ConsumerStatefulWidget {
  final String creatorUid;
  const CreateSessionScreen({super.key, required this.creatorUid});

  @override
  ConsumerState<CreateSessionScreen> createState() =>
      _CreateSessionScreenState();
}

class _CreateSessionScreenState extends ConsumerState<CreateSessionScreen> {
  final _titleController = TextEditingController();
  final _totalController = TextEditingController();

  SessionSplitMode _splitMode = SessionSplitMode.equal;
  bool _isSaving = false;
  bool _isOcring = false;

  // Danh sách thành viên thêm vào (ngoài creator).
  final List<_MemberEntry> _members = [];

  @override
  void dispose() {
    _titleController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  // ── OCR ────────────────────────────────────────────────────────────────────

  Future<void> _pickAndOcr() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null) return;

    setState(() => _isOcring = true);
    try {
      final inputImage = InputImage.fromFilePath(picked.path);
      final recognizer = TextRecognizer();
      final result = await recognizer.processImage(inputImage);
      await recognizer.close();

      // Tìm số tiền lớn nhất trong văn bản (giả định đó là tổng bill).
      final amounts = <int>[];
      final numPattern = RegExp(r'[\d.,]+');
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final text = line.text.replaceAll('.', '').replaceAll(',', '');
          final match = numPattern.firstMatch(text);
          if (match != null) {
            final val = int.tryParse(match.group(0)!);
            if (val != null && val >= 1000) amounts.add(val);
          }
        }
      }

      if (amounts.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không nhận ra số tiền nào từ ảnh.')),
          );
        }
        return;
      }

      amounts.sort((a, b) => b.compareTo(a));
      if (mounted) _totalController.text = amounts.first.toString();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OCR thất bại. Nhập tay số tiền.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isOcring = false);
    }
  }

  // ── Thêm thành viên ────────────────────────────────────────────────────────

  Future<void> _showAddMemberDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddMemberSheet(
        currentUid: widget.creatorUid,
        onAddUser: (user) {
          if (_members.any((m) => m.userId == user.uid)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${user.name} đã có trong danh sách.')),
            );
            return;
          }
          setState(() => _members.add(_MemberEntry.fromUser(user)));
        },
        onAddGuest: (name) {
          setState(() => _members.add(_MemberEntry.guest(name)));
        },
      ),
    );
    _recalcCustomAmounts();
  }

  void _removeMember(int index) {
    setState(() => _members.removeAt(index));
    _recalcCustomAmounts();
  }

  Future<void> _editGuestName(int index) async {
    final member = _members[index];
    if (!member.isGuest) return;
    final ctrl = TextEditingController(text: member.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sửa tên khách'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tên mới'),
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
    if (newName != null && newName.isNotEmpty) {
      setState(() {
        _members[index] = _MemberEntry(
          name: newName,
          userId: member.userId,
          isGuest: member.isGuest,
        )..customAmount = member.customAmount;
      });
    }
  }

  void _recalcCustomAmounts() {
    if (_splitMode == SessionSplitMode.custom) return;
    // Với equal split, giữ nguyên — tính lại khi tạo phiên.
  }

  // ── Tạo phiên ───────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final totalStr = _totalController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập tên phiên.')),
      );
      return;
    }
    final total = int.tryParse(totalStr);
    if (total == null || total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập tổng tiền hợp lệ.')),
      );
      return;
    }

    // Validate custom amounts.
    if (_splitMode == SessionSplitMode.custom) {
      final sum = _members.fold<int>(0, (s, m) => s + (m.customAmount ?? 0));
      if (sum != total) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Tổng chia (${formatVnd(sum)}) ≠ tổng bill (${formatVnd(total)}).'),
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final sessionId = newUuid();
      final now = DateTime.now();

      // Tính amounts.
      final count = _members.length + 1; // +1 cho creator
      final shares = _splitMode == SessionSplitMode.equal
          ? splitEqual(total, count)
          : null;

      // Creator member (status: self).
      final allMembers = <SessionMember>[
        SessionMember(
          memberId: widget.creatorUid,
          userId: widget.creatorUid,
          displayName: '',
          isGuest: false,
          amountOwed: shares != null ? shares[0] : 0,
          status: MemberStatus.self,
        ),
      ];

      // Các thành viên khác.
      for (int i = 0; i < _members.length; i++) {
        final m = _members[i];
        allMembers.add(SessionMember(
          memberId: m.userId ?? newUuid(),
          userId: m.userId,
          displayName: m.name,
          isGuest: m.isGuest,
          amountOwed: shares != null ? shares[i + 1] : (m.customAmount ?? 0),
          status: m.isGuest ? MemberStatus.pending : MemberStatus.ledger,
        ));
      }

      final memberUserIds = allMembers
          .where((m) => m.userId != null)
          .map((m) => m.userId!)
          .toList();

      final session = Session(
        sessionId: sessionId,
        creatorId: widget.creatorUid,
        title: title,
        totalAmount: total,
        splitMode: _splitMode,
        status: SessionStatus.open,
        memberUserIds: memberUserIds,
        createdAt: now,
      );

      await ref
          .read(sessionRepositoryProvider)
          .createSession(session, allMembers);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tạo phiên thất bại. Thử lại.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final total = int.tryParse(_totalController.text) ?? 0;
    final count = _members.length + 1;
    final shares =
        total > 0 && _splitMode == SessionSplitMode.equal
            ? splitEqual(total, count)
            : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Tạo phiên mới')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Tên phiên
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Tên phiên',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Tổng tiền + OCR
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _totalController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Tổng tiền (VND)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Quét bill bằng OCR',
                onPressed: _isOcring ? null : _pickAndOcr,
                icon: _isOcring
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.document_scanner_outlined),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Chế độ chia
          Row(
            children: [
              const Text('Cách chia:'),
              const SizedBox(width: 12),
              ChoiceChip(
                label: const Text('Đều'),
                selected: _splitMode == SessionSplitMode.equal,
                onSelected: (_) =>
                    setState(() => _splitMode = SessionSplitMode.equal),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Tuỳ chỉnh'),
                selected: _splitMode == SessionSplitMode.custom,
                onSelected: (_) =>
                    setState(() => _splitMode = SessionSplitMode.custom),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Danh sách thành viên
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Thành viên (${_members.length + 1})',
                  style: Theme.of(context).textTheme.titleSmall),
              TextButton.icon(
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: const Text('Thêm'),
                onPressed: _showAddMemberDialog,
              ),
            ],
          ),

          // Creator row
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: const Text('Bạn (người tạo)'),
            trailing: shares != null
                ? Text(formatVnd(shares[0]))
                : const Text('—'),
          ),

          // Other members
          for (int i = 0; i < _members.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Text(_members[i].name.isNotEmpty
                    ? _members[i].name[0].toUpperCase()
                    : '?'),
              ),
              title: Text(_members[i].name),
              subtitle: _members[i].isGuest
                  ? const Text('Khách (chạm để sửa tên)',
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey))
                  : null,
              onTap: _members[i].isGuest ? () => _editGuestName(i) : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_splitMode == SessionSplitMode.equal)
                    (shares != null
                        ? Text(formatVnd(shares[i + 1]),
                            style: const TextStyle(fontWeight: FontWeight.w500))
                        : const SizedBox.shrink())
                  else
                    _CustomAmountField(
                      value: _members[i].customAmount,
                      onChanged: (v) =>
                          setState(() => _members[i].customAmount = v),
                    ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: Colors.red, size: 20),
                    tooltip: 'Xoá thành viên',
                    onPressed: () => _removeMember(i),
                  ),
                ],
              ),
            ),

          if (_members.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Chưa có thành viên nào khác. Bấm "Thêm" để thêm bạn bè.',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('Mẹo: Nhấn vào tên khách để đổi tên, bấm biểu tượng đỏ để xoá.',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),

          const SizedBox(height: 24),

          FilledButton(
            onPressed: _isSaving ? null : _submit,
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child:
                        CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Tạo phiên'),
          ),
        ],
      ),
    );
  }
}

// ── Helper model ────────────────────────────────────────────────────────────

class _MemberEntry {
  final String name;
  final String? userId;
  final bool isGuest;
  int? customAmount;

  _MemberEntry({
    required this.name,
    required this.userId,
    required this.isGuest,
  });

  factory _MemberEntry.fromUser(AppUser user) => _MemberEntry(
        name: user.name,
        userId: user.uid,
        isGuest: false,
      );

  factory _MemberEntry.guest(String name) => _MemberEntry(
        name: name,
        userId: null,
        isGuest: true,
      );
}

// ── Widget nhập số tiền tuỳ chỉnh ──────────────────────────────────────────

class _CustomAmountField extends StatefulWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  const _CustomAmountField({required this.value, required this.onChanged});

  @override
  State<_CustomAmountField> createState() => _CustomAmountFieldState();
}

class _CustomAmountFieldState extends State<_CustomAmountField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.value != null ? widget.value.toString() : '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: TextField(
        controller: _ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          suffixText: 'đ',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        onChanged: (v) => widget.onChanged(int.tryParse(v)),
      ),
    );
  }
}

// ── Bottom sheet thêm thành viên ────────────────────────────────────────────

class _AddMemberSheet extends ConsumerStatefulWidget {
  final String currentUid;
  final ValueChanged<AppUser> onAddUser;
  final ValueChanged<String> onAddGuest;

  const _AddMemberSheet({
    required this.currentUid,
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.qr_code_2, color: Colors.blue),
            SizedBox(width: 8),
            Text('QR kết bạn của bạn'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Đưa bạn bè quét mã này. Họ sẽ tự động xuất hiện trong danh sách bạn bè bên dưới!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: QrImageView(
                data: widget.currentUid,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚡ Bạn bè quét xong sẽ tự hiện ngay lập tức!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.green,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _scanFriendQr(BuildContext context) {
    showModalBottomSheet(
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
                  if (uid == null || uid.isEmpty) return;
                  if (uid == widget.currentUid) return;

                  Navigator.pop(ctx); // Đóng scanner

                  try {
                    final userRepo = ref.read(userRepositoryProvider);
                    final otherUser = await userRepo.findByUid(uid);
                    final currentUser =
                        await userRepo.findByUid(widget.currentUid);

                    if (otherUser != null) {
                      // Kết bạn 2 chiều
                      await userRepo.upsertContact(
                          widget.currentUid, otherUser);
                      if (currentUser != null) {
                        try {
                          await userRepo.upsertContact(
                              otherUser.uid, currentUser);
                        } catch (_) {}
                      }
                      // Thêm luôn vào phiên
                      widget.onAddUser(otherUser);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'Đã kết bạn và thêm ${otherUser.name} vào phiên!')),
                        );
                        Navigator.pop(context); // Đóng sheet
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Có lỗi khi kết bạn. Thử lại.')),
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
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Thêm thành viên',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),

          // Hai nút QR tiện lợi: Hiện QR của tôi & Quét QR bạn bè
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.qr_code_2, size: 20),
                  label: const Text('Hiện QR của tôi',
                      style: TextStyle(fontSize: 13)),
                  onPressed: () => _showMyQrCode(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Quét QR bạn',
                      style: TextStyle(fontSize: 13)),
                  onPressed: () => _scanFriendQr(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Thêm Guest
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _guestController,
                  decoration: const InputDecoration(
                    labelText: 'Tên khách (nếu không có app)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final name = _guestController.text.trim();
                  if (name.isEmpty) return;
                  widget.onAddGuest(name);
                  Navigator.pop(context);
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
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
              data: (list) {
                if (list.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Chưa có bạn bè.\nBấm "Hiện QR của tôi" ở trên để bạn bè quét kết bạn!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, height: 1.4),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: CircleAvatar(
                      child: Text(list[i].name.isNotEmpty
                          ? list[i].name[0].toUpperCase()
                          : '?'),
                    ),
                    title: Text(list[i].name),
                    subtitle: Text(list[i].email,
                        style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.add_circle_outline,
                        color: Colors.blue),
                    onTap: () {
                      widget.onAddUser(list[i]);
                      Navigator.pop(context);
                    },
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
