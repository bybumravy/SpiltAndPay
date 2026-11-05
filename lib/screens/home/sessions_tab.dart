import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase_providers.dart';
import '../../core/money.dart';
import '../../models/session.dart';
import '../../repositories/session_repository.dart';
import '../../ui/app_tabs.dart';
import '../../ui/app_theme.dart';
import '../../ui/content_rows.dart';
import '../session/create_session_screen.dart';
import '../session/session_detail_screen.dart';

enum _SessionFilter { all, open, closed }

class SessionsTab extends ConsumerStatefulWidget {
  const SessionsTab({super.key});

  @override
  ConsumerState<SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends ConsumerState<SessionsTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _SessionFilter.values.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).currentUser;
    if (user == null) return const SizedBox.shrink();

    final sessionsAsync = ref.watch(userSessionsProvider(user.uid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Phiên'),
        bottom: AppTabs(
          controller: _tabs,
          labels: const ['Tất cả', 'Đang mở', 'Đã đóng'],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          for (final filter in _SessionFilter.values)
            sessionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        e.toString().toLowerCase().contains('permission-denied')
                            ? 'Chưa thể tải danh sách phiên do đang đồng bộ kết nối. Vui lòng thử lại.'
                            : 'Lỗi: $e',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () =>
                            ref.invalidate(userSessionsProvider(user.uid)),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (sessions) {
                final filtered = switch (filter) {
                  _SessionFilter.all => sessions,
                  _SessionFilter.open =>
                    sessions
                        .where((s) => s.status == SessionStatus.open)
                        .toList(),
                  _SessionFilter.closed =>
                    sessions
                        .where((s) => s.status == SessionStatus.closed)
                        .toList(),
                };
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(userSessionsProvider(user.uid)),
                  child: ListView(
                    key: PageStorageKey('sessions-${filter.name}'),
                    padding: const EdgeInsets.only(top: 8, bottom: 100),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      if (filtered.isEmpty)
                        const AppEmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'Chưa có phiên nào',
                        )
                      else
                        for (final session in filtered)
                          _SessionTile(session: session, currentUid: user.uid),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreateSessionScreen(creatorUid: user.uid),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Tạo phiên'),
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
    } catch (_) {
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
    final membersAsync = ref.watch(sessionMembersProvider(session.sessionId));

    final count = membersAsync.when(
      data: (m) => '${m.length} thành viên',
      loading: () => 'Đang tải…',
      error: (_, _) => 'Không tải được thành viên',
    );
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              SessionDetailScreen(session: session, currentUid: currentUid),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          session.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SessionStatusBadge(isOpen: isOpen),
                      if (isCreator && isOpen)
                        SizedBox(
                          width: 44,
                          child: PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            onSelected: (value) {
                              if (value == 'delete') {
                                _confirmDelete(context, ref);
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
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LabelValueRow(
                    label: Text(
                      formatVnd(session.totalAmount),
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(color: AppTheme.purple),
                    ),
                    value: Text(
                      count,
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
          ],
        ),
      ),
    );
  }
}
