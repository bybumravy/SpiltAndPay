import 'package:flutter/material.dart';

import '../../../../core/banking_service.dart';
import '../../../../core/money.dart';

class BankChooserBottomSheet extends StatefulWidget {
  final String transferNote;
  final int amount;
  final Future<void> Function() onSaveQr;

  const BankChooserBottomSheet({
    super.key,
    required this.transferNote,
    required this.amount,
    required this.onSaveQr,
  });

  static Future<void> show(
    BuildContext context, {
    required String transferNote,
    required int amount,
    required Future<void> Function() onSaveQr,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => BankChooserBottomSheet(
        transferNote: transferNote,
        amount: amount,
        onSaveQr: onSaveQr,
      ),
    );
  }

  @override
  State<BankChooserBottomSheet> createState() => _BankChooserBottomSheetState();
}

class _BankChooserBottomSheetState extends State<BankChooserBottomSheet> {
  late Future<List<BankAppInfo>> _banksFuture;
  bool _isSavingQr = false;

  @override
  void initState() {
    super.initState();
    _banksFuture = BankingAppService.getPrioritizedBanks();
  }

  Future<void> _handleBankSelect(BankAppInfo bank) async {
    final messenger = ScaffoldMessenger.of(context);
    final note = widget.transferNote;

    Navigator.pop(context);

    // Tự động lưu ảnh QR vào thư viện ngầm
    try {
      await widget.onSaveQr();
    } catch (_) {}

    final success = await BankingAppService.openBankApp(
      bank: bank,
      transferNote: note,
    );

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Đã mở ${bank.shortName}! QR đã tự động lưu vào máy & sao chép nội dung.'
              : 'Không mở được ứng dụng. Vui lòng kiểm tra lại.',
        ),
        backgroundColor: success ? Colors.teal.shade800 : Colors.red.shade700,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              // Thanh gạt modal
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Tiêu đề
              Text(
                'Mở App Ngân hàng thanh toán',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Số tiền: ${formatVnd(widget.amount)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Banner tự động hóa 1-chạm
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 18, color: Colors.teal.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tự động 1-chạm khi chọn ngân hàng:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal.shade900,
                            ),
                          ),
                          Text(
                            'Lưu ảnh QR vào máy + Copy: "${widget.transferNote}"',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.teal.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Nút lưu nhanh QR vào thư viện
              OutlinedButton.icon(
                onPressed: _isSavingQr
                    ? null
                    : () async {
                        setState(() => _isSavingQr = true);
                        try {
                          await widget.onSaveQr();
                        } finally {
                          if (mounted) setState(() => _isSavingQr = false);
                        }
                      },
                icon: _isSavingQr
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download, size: 18),
                label: const Text('Bấm để lưu ảnh QR vào máy'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                ),
              ),
              const SizedBox(height: 12),

              // Danh sách ngân hàng
              Expanded(
                child: FutureBuilder<List<BankAppInfo>>(
                  future: _banksFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final banks = snapshot.data ?? kSupportedBanks;

                    return ListView.separated(
                      controller: scrollController,
                      itemCount: banks.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final bank = banks[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: bank.brandColor.withAlpha(30),
                            child: Icon(bank.icon, color: bank.brandColor),
                          ),
                          title: Text(
                            bank.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            'Chạm để mở ${bank.shortName}',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          trailing: const Icon(Icons.open_in_new, size: 18),
                          onTap: () => _handleBankSelect(bank),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
