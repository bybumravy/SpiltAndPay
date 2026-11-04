import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/bill_ocr.dart';
import '../../core/money.dart';
import '../../ui/app_theme.dart';

class ScannedExpense {
  final String description;
  final int amount;
  final String payerId;
  final List<String> participantIds;
  const ScannedExpense(
    this.description,
    this.amount,
    this.payerId,
    this.participantIds,
  );
}

class BatchBillScreen extends StatefulWidget {
  final Map<String, String> members;
  final Set<String> payerIds;
  final String initialPayerId;
  final Future<String?> Function()? capture;
  final Future<BillScanResult> Function(File)? scan;
  const BatchBillScreen({
    super.key,
    required this.members,
    required this.payerIds,
    required this.initialPayerId,
    this.capture,
    this.scan,
  });
  @override
  State<BatchBillScreen> createState() => _BatchBillScreenState();
}

class _BillDraft {
  final String path;
  final TextEditingController name;
  final TextEditingController amount;
  final bool needsReview;
  final String? reviewReason;
  _BillDraft(this.path, int index, BillScanResult? scan)
    : name = TextEditingController(text: 'Hoá đơn $index'),
      amount = TextEditingController(
        text: scan?.confident == true && scan?.total != null
            ? formatVndInput(scan!.total!)
            : '',
      ),
      needsReview = scan?.confident != true || scan?.total == null,
      reviewReason = scan == null
          ? 'Không đọc được ảnh hoá đơn. Chụp lại hoặc nhập số tiền.'
          : 'Chưa tìm được dòng tổng tiền. Nhập số tiền từ ảnh.';
  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

class _BatchBillScreenState extends State<BatchBillScreen> {
  final _drafts = <_BillDraft>[];
  late String _payer = widget.initialPayerId;
  late final _participants = widget.members.keys.toSet();
  bool _busy = false;
  int _sequence = 0;
  bool get _valid =>
      !_busy &&
      _drafts.isNotEmpty &&
      _participants.isNotEmpty &&
      _drafts.every(
        (d) =>
            d.name.text.trim().isNotEmpty &&
            (parseVndInput(d.amount.text) ?? 0) > 0,
      );

  Future<void> _capture() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final path = widget.capture != null
          ? await widget.capture!()
          : (await ImagePicker().pickImage(
              source: ImageSource.camera,
              imageQuality: 95,
            ))?.path;
      if (path == null || !mounted) return;
      BillScanResult? result;
      try {
        result = await (widget.scan ?? scanBill)(File(path));
      } catch (error) {
        debugPrint('Bill OCR failed: ${error.runtimeType}');
      }
      if (!mounted) return;
      setState(() => _drafts.add(_BillDraft(path, ++_sequence, result)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Không mở được camera. Kiểm tra quyền truy cập rồi thử lại.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quét nhiều hoá đơn')),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _capture,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(
                _busy
                    ? 'Đang đọc hoá đơn…'
                    : _drafts.isEmpty
                    ? 'Chụp hoá đơn'
                    : 'Chụp tiếp',
              ),
            ),
            if (_drafts.isNotEmpty) ...[
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _valid
                    ? () => Navigator.pop(context, [
                        for (final d in _drafts)
                          ScannedExpense(
                            d.name.text.trim(),
                            parseVndInput(d.amount.text)!,
                            _payer,
                            _participants.toList(),
                          ),
                      ])
                    : null,
                child: Text('Thêm ${_drafts.length} khoản chi'),
              ),
            ],
          ],
        ),
      ),
    ),
    body: _drafts.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: 56,
                    color: AppTheme.purple,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Mỗi ảnh một hoá đơn',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                ],
              ),
            ),
          )
        : AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _payer,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Người trả chung',
                  ),
                  items: [
                    for (final id in widget.payerIds)
                      DropdownMenuItem(
                        value: id,
                        child: Text(widget.members[id] ?? id),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _payer = value);
                  },
                ),
                const SizedBox(height: 20),
                Text('Chia cho', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in widget.members.entries)
                      FilterChip(
                        label: Text(m.value),
                        selected: _participants.contains(m.key),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _participants.add(m.key);
                          } else {
                            _participants.remove(m.key);
                          }
                        }),
                      ),
                  ],
                ),
                if (_participants.isEmpty)
                  const Text(
                    'Chọn ít nhất một người tham gia.',
                    style: TextStyle(color: AppTheme.red),
                  ),
                const SizedBox(height: 24),
                for (final d in _drafts) ...[
                  Container(
                    key: ObjectKey(d),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.line),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                d.name.text,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Bỏ hoá đơn',
                              onPressed: () {
                                setState(() => _drafts.remove(d));
                                d.dispose();
                              },
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: () => showDialog<void>(
                            context: context,
                            builder: (ctx) => Dialog(
                              child: InteractiveViewer(
                                child: Image.file(
                                  File(d.path),
                                  errorBuilder: (_, _, _) => const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text('Không mở được ảnh.'),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(d.path),
                              height: 140,
                              width: double.infinity,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const SizedBox(
                                height: 80,
                                child: Icon(Icons.receipt_outlined),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: d.name,
                          decoration: const InputDecoration(labelText: 'Mô tả'),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: d.amount,
                          keyboardType: TextInputType.number,
                          inputFormatters: [VndInputFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Số tiền (VND)',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        if (d.needsReview)
                          Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              d.reviewReason!,
                              style: TextStyle(color: AppTheme.muted),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
  );
}
