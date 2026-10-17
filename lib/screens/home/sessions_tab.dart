import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase_providers.dart';
import '../../core/money.dart';
import '../../models/session.dart';
import '../../repositories/session_repository.dart';
import '../session/create_session_screen.dart';
import '../session/session_detail_screen.dart';

class SessionsTab extends ConsumerWidget {
  const SessionsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).currentUser;
    if (user == null) return const SizedBox.shrink();

    final sessionsAsync = ref.watch(userSessionsProvider(user.uid));

    return Scaffold(
      appBar: AppBar(title: const Text('Phiên')),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text('Lỗi: $e', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref.refresh(userSessionsProvider(user.uid)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ),
        data: (sessions) {
          if (sessions.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async =>
                  ref.refresh(userSessionsProvider(user.uid)),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('Chưa có phiên nào')),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.refresh(userSessionsProvider(user.uid)),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: sessions.length,
              itemBuilder: (_, i) => _SessionTile(
                session: sessions[i],
                currentUid: user.uid,
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreateSessionScreen(creatorUid: user.uid),
          ),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  final Session session;
  final String currentUid;

  const _SessionTile({required this.session, required this.currentUid});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá phiên'),
        content: Text(
          'Bạn có chắc muốn xoá phiên "${session.title}"? Dữ liệu phiên và thành viên sẽ bị xoá vĩnh viễn.',
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
          .deleteSession(session.sessionId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xoá phiên thành công')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Xoá phiên thất bại. Thử lại.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOpen = session.status == SessionStatus.open;
    final isCreator = session.creatorId == currentUid;

    return ListTile(
      title: Text(session.title),
      subtitle: Text(formatVnd(session.totalAmount)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Chip(
            label: Text(isOpen ? 'Đang mở' : 'Đã đóng',
                style: const TextStyle(fontSize: 11)),
            backgroundColor: isOpen ? Colors.green[50] : Colors.grey[200],
            side: BorderSide(color: isOpen ? Colors.green : Colors.grey),
            padding: EdgeInsets.zero,
          ),
          // Phiên đã đóng đã ghi nợ vào sổ nên không được xoá.
          if (isCreator && isOpen)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (val) {
                if (val == 'delete') {
                  _confirmDelete(context, ref);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Xoá phiên', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SessionDetailScreen(
            session: session,
            currentUid: currentUid,
          ),
        ),
      ),
    );
  }
}
