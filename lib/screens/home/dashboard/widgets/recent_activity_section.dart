import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/money.dart';
import '../../../../models/session.dart';

class RecentActivitySection extends StatelessWidget {
  final List<Session> sessions;
  final String currentUid;
  final void Function(Session session) onSelectSession;
  final VoidCallback onViewAllSessions;

  const RecentActivitySection({
    super.key,
    required this.sessions,
    required this.currentUid,
    required this.onSelectSession,
    required this.onViewAllSessions,
  });

  @override
  Widget build(BuildContext context) {
    final recent = sessions.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.history, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Hoạt động gần đây',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            TextButton(
              onPressed: onViewAllSessions,
              child: const Text('Xem tất cả'),
            ),
          ],
        ),
        if (recent.isEmpty)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'Chưa có phiên chi tiêu nào. Bấm "Tạo phiên" để bắt đầu chia tiền!',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recent.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final session = recent[i];
              return _SessionTile(
                session: session,
                onTap: () => onSelectSession(session),
              );
            },
          ),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  final Session session;
  final VoidCallback onTap;

  const _SessionTile({
    required this.session,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOpen = session.status == SessionStatus.open;
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(session.createdAt);

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isOpen ? Colors.orange.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.receipt_long,
                  color: isOpen ? Colors.orange.shade800 : Colors.blue.shade700,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateStr,
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatVnd(session.totalAmount),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isOpen ? Colors.orange.shade100 : Colors.green.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isOpen ? 'Đang mở' : 'Đã chốt',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isOpen ? Colors.orange.shade900 : Colors.green.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
