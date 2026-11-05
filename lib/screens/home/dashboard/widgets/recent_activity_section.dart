import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/money.dart';
import '../../../../ui/app_theme.dart';
import '../../../../ui/content_rows.dart';
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
        SectionHeading(
          'Phiên gần đây',
          action: TextButton(
            onPressed: onViewAllSessions,
            child: const Text('Tất cả'),
          ),
        ),
        if (recent.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Chưa có phiên nào',
              style: TextStyle(color: AppTheme.muted),
            ),
          )
        else
          for (final session in recent)
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => onSelectSession(session),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppTheme.line)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LabelValueRow(
                        label: Text(
                          session.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        value: Text(
                          formatVnd(session.totalAmount),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              DateFormat('dd/MM/yyyy')
                                  .format(session.createdAt),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppTheme.muted),
                            ),
                          ),
                          SessionStatusBadge(
                            isOpen: session.status == SessionStatus.open,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
