import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/money.dart';
import '../../../../repositories/notification_repository.dart';

class DebtReminderDialog extends ConsumerStatefulWidget {
  final String debtId;
  final String targetUid;
  final String creditorName;
  final String debtorName;
  final int amount;

  const DebtReminderDialog({
    super.key,
    required this.debtId,
    required this.targetUid,
    required this.creditorName,
    required this.debtorName,
    required this.amount,
  });

  static Future<void> show(
    BuildContext context, {
    required String debtId,
    required String targetUid,
    required String creditorName,
    required String debtorName,
    required int amount,
  }) {
    return showDialog(
      context: context,
      builder: (_) => DebtReminderDialog(
        debtId: debtId,
        targetUid: targetUid,
        creditorName: creditorName,
        debtorName: debtorName,
        amount: amount,
      ),
    );
  }

  @override
  ConsumerState<DebtReminderDialog> createState() => _DebtReminderDialogState();
}

class _DebtReminderDialogState extends ConsumerState<DebtReminderDialog> {
  String _selectedStyle = 'funny';
  bool _isSending = false;

  final Map<String, ({String label, String quote, IconData icon})> _styles = {
    'funny': (
      label: 'Hài hước',
      quote: 'Hôm nay trời nhẹ lên cao, mình buồn không hiểu vì sao... bạn chưa chuyển tiền? 🥺',
      icon: Icons.sentiment_very_satisfied,
    ),
    'polite': (
      label: 'Lịch sự',
      quote: 'Gửi lời nhắc thanh toán khoản nợ. Bạn tranh thủ chuyển nhé! 🔔',
      icon: Icons.notifications_active,
    ),
    'gentle': (
      label: 'Nhẹ nhàng',
      quote: 'Ghé SplitPay thanh toán nốt để sổ nợ về 0 nào bạn ơi! ☕',
      icon: Icons.coffee,
    ),
  };

  Future<void> _handleSend() async {
    setState(() => _isSending = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await ref.read(notificationRepositoryProvider).sendDebtReminder(
            debtId: widget.debtId,
            targetUid: widget.targetUid,
            creditorName: widget.creditorName,
            debtorName: widget.debtorName,
            amount: widget.amount,
            style: _selectedStyle,
          );

      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Đã gửi lời nhắc tới ${widget.debtorName}!'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(e is StateError ? e.message : 'Gửi lời nhắc thất bại.'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.forward_to_inbox, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Nhắc trả tiền'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gửi lời nhắc tới ${widget.debtorName} cho khoản nợ ${formatVnd(widget.amount)}:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Chọn phong cách lời nhắc:',
              style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final entry in _styles.entries) ...[
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _selectedStyle = entry.key),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _selectedStyle == entry.key
                        ? theme.colorScheme.primaryContainer.withAlpha(80)
                        : theme.colorScheme.surfaceVariant.withAlpha(40),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _selectedStyle == entry.key
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(entry.value.icon,
                          size: 20,
                          color: _selectedStyle == entry.key
                              ? theme.colorScheme.primary
                              : Colors.grey),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.value.label,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '"${entry.value.quote}"',
                              style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            const Text(
              'ℹ️ Giới hạn: Tối đa 1 lần gửi mỗi ngày để tránh làm phiền bạn bè.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        FilledButton.icon(
          onPressed: _isSending ? null : _handleSend,
          icon: _isSending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.send, size: 16),
          label: const Text('Gửi lời nhắc'),
        ),
      ],
    );
  }
}
