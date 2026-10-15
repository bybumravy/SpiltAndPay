import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/app_user.dart';
import '../../repositories/user_repository.dart';

class AddFriendScreen extends ConsumerStatefulWidget {
  final String currentUid;
  const AddFriendScreen({super.key, required this.currentUid});

  @override
  ConsumerState<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends ConsumerState<AddFriendScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _emailController = TextEditingController();

  bool _isSearching = false;
  bool _isAdding = false;
  AppUser? _foundUser;
  String? _searchError;
  String _contactSearch = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _searchByEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() {
      _isSearching = true;
      _foundUser = null;
      _searchError = null;
    });
    try {
      final user =
          await ref.read(userRepositoryProvider).findByEmail(email);
      if (!mounted) return;
      if (user == null) {
        setState(() => _searchError = 'Không tìm thấy người dùng với email này.');
      } else if (user.uid == widget.currentUid) {
        setState(() => _searchError = 'Đây là tài khoản của bạn.');
      } else {
        setState(() => _foundUser = user);
      }
    } catch (e) {
      if (mounted) setState(() => _searchError = 'Có lỗi xảy ra. Thử lại.');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _addContact(AppUser user) async {
    setState(() => _isAdding = true);
    try {
      final currentUser =
          await ref.read(userRepositoryProvider).findByUid(widget.currentUid);
      await ref
          .read(userRepositoryProvider)
          .upsertContact(widget.currentUid, user);
      if (currentUser != null) {
        try {
          await ref
              .read(userRepositoryProvider)
              .upsertContact(user.uid, currentUser);
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã thêm ${user.name} vào danh sách bạn bè')),
      );
      setState(() => _foundUser = null);
      _emailController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thêm thất bại. Thử lại.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  /// Gọi sau khi quét được uid từ QR của bạn.
  Future<void> _handleScannedUid(String uid) async {
    if (uid == widget.currentUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đây là mã QR của bạn.')),
      );
      return;
    }
    setState(() => _isAdding = true);
    try {
      final user = await ref.read(userRepositoryProvider).findByUid(uid);
      if (!mounted) return;
      if (user == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Không tìm thấy người dùng.')));
        return;
      }
      final currentUser =
          await ref.read(userRepositoryProvider).findByUid(widget.currentUid);
      await ref
          .read(userRepositoryProvider)
          .upsertContact(widget.currentUid, user);
      if (currentUser != null) {
        try {
          await ref
              .read(userRepositoryProvider)
              .upsertContact(uid, currentUser);
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã kết bạn với ${user.name}')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Có lỗi xảy ra. Thử lại.')));
      }
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<void> _deleteContact(AppUser contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xoá bạn bè'),
        content: Text('Bạn có chắc muốn xoá ${contact.name} khỏi danh sách bạn bè?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(userRepositoryProvider)
          .deleteContact(widget.currentUid, contact.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã xoá ${contact.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Xoá thất bại. Thử lại.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync =
        ref.watch(contactsProvider(widget.currentUid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bạn bè'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Tìm email'),
            Tab(text: 'Quét QR'),
            Tab(text: 'QR của tôi'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _EmailSearchTab(
                  controller: _emailController,
                  isSearching: _isSearching,
                  isAdding: _isAdding,
                  foundUser: _foundUser,
                  searchError: _searchError,
                  onSearch: _searchByEmail,
                  onAdd: _addContact,
                ),
                _QrScanTab(
                  isAdding: _isAdding,
                  onScanned: _handleScannedUid,
                ),
                _MyQrTab(currentUid: widget.currentUid),
              ],
            ),
          ),

          // Danh sách bạn bè hiện tại
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Danh sách bạn bè',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          // Ô tìm kiếm trong danh sách bạn bè
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm trong danh sách bạn bè...',
                prefixIcon: Icon(Icons.search, size: 20),
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) => setState(() => _contactSearch = v.trim().toLowerCase()),
            ),
          ),
          SizedBox(
            height: 180,
            child: contactsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
              data: (list) {
                final filtered = _contactSearch.isEmpty
                    ? list
                    : list
                        .where((u) =>
                            u.name.toLowerCase().contains(_contactSearch) ||
                            u.email.toLowerCase().contains(_contactSearch))
                        .toList();
                if (list.isEmpty) {
                  return const Center(
                      child: Text('Chưa có bạn bè nào',
                          style: TextStyle(color: Colors.grey)));
                }
                if (filtered.isEmpty) {
                  return const Center(
                      child: Text('Không tìm thấy bạn bè nào',
                          style: TextStyle(color: Colors.grey)));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: CircleAvatar(
                      child: Text(filtered[i].name.isNotEmpty
                          ? filtered[i].name[0].toUpperCase()
                          : '?'),
                    ),
                    title: Text(filtered[i].name),
                    subtitle: Text(filtered[i].email,
                        style: const TextStyle(fontSize: 12)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.grey),
                      tooltip: 'Xoá bạn bè',
                      onPressed: () => _deleteContact(filtered[i]),
                    ),
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

// ── Tab tìm theo email ──────────────────────────────────────────────────────

class _EmailSearchTab extends StatelessWidget {
  final TextEditingController controller;
  final bool isSearching;
  final bool isAdding;
  final AppUser? foundUser;
  final String? searchError;
  final VoidCallback onSearch;
  final Future<void> Function(AppUser) onAdd;

  const _EmailSearchTab({
    required this.controller,
    required this.isSearching,
    required this.isAdding,
    required this.foundUser,
    required this.searchError,
    required this.onSearch,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email bạn bè',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => onSearch(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: isSearching ? null : onSearch,
                icon: isSearching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.search),
              ),
            ],
          ),
          if (searchError != null) ...[
            const SizedBox(height: 12),
            Text(searchError!, style: const TextStyle(color: Colors.red)),
          ],
          if (foundUser != null) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(foundUser!.name.isNotEmpty
                      ? foundUser!.name[0].toUpperCase()
                      : '?'),
                ),
                title: Text(foundUser!.name),
                subtitle: Text(foundUser!.email),
                trailing: isAdding
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.person_add),
                        onPressed: () => onAdd(foundUser!),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Tab quét QR ────────────────────────────────────────────────────────────

class _QrScanTab extends StatefulWidget {
  final bool isAdding;
  final Future<void> Function(String uid) onScanned;

  const _QrScanTab({required this.isAdding, required this.onScanned});

  @override
  State<_QrScanTab> createState() => _QrScanTabState();
}

class _QrScanTabState extends State<_QrScanTab> {
  bool _handled = false;
  final _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || widget.isAdding) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value.isEmpty) return;
    setState(() => _handled = true);
    widget.onScanned(value).whenComplete(() {
      if (mounted) setState(() => _handled = false);
    });
  }

  Future<void> _pickFromGallery() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final capture = await _controller.analyzeImage(picked.path);
    if (!mounted) return;
    final value = capture?.barcodes.firstOrNull?.rawValue;
    if (value == null || value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy mã QR trong ảnh.')),
      );
      return;
    }
    await widget.onScanned(value);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        if (widget.isAdding)
          const ColoredBox(
            color: Colors.black54,
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        // khung ngắm giữa màn hình
        Center(
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        Positioned(
          bottom: 64,
          left: 0,
          right: 0,
          child: Center(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('Chọn ảnh từ thư viện'),
              onPressed: widget.isAdding ? null : _pickFromGallery,
            ),
          ),
        ),
        const Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Text(
            'Đặt QR của bạn bè vào khung',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

// ── Tab QR của tôi ──────────────────────────────────────────────────────────

class _MyQrTab extends ConsumerWidget {
  final String currentUid;
  const _MyQrTab({required this.currentUid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider(currentUid));

    return userAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Lỗi: $e')),
      data: (user) {
        final name = user?.name ?? 'Tôi';
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Mã QR kết bạn của bạn',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Đưa bạn bè quét mã này để kết bạn ngay lập tức',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: currentUid,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        );
      },
    );
  }
}
