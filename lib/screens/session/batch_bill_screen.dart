import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/bill_ocr.dart';
import '../../core/gemini_bill_scanner.dart';
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
  final Future<BillBatchResult> Function(List<File>)? scan;
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
  final int imageIndex;
  final TextEditingController name;
  final TextEditingController amount;
  final String? reviewReason;
  _BillDraft(this.imageIndex, int number, BillScanResult? scan)
    : name = TextEditingController(
        text: scan?.description ?? 'Hoá đơn $number',
      ),
      amount = TextEditingController(
        text: scan?.confident == true && scan?.total != null
            ? formatVndInput(scan!.total!)
            : '',
      ),
      reviewReason = scan == null
          ? 'Nhập từng khoản trong ảnh hoặc bỏ khoản không cần.'
          : scan.confident
          ? null
          : scan.reviewReason ??
                'Chưa đọc chắc tổng tiền. Kiểm tra ảnh và nhập số tiền.';
  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

class _BatchBillScreenState extends State<BatchBillScreen> {
  final _photos = <String>[];
  final _drafts = <_BillDraft>[];
  late String _payer = widget.initialPayerId;
  late final _participants = widget.members.keys.toSet();
  bool _busy = false;
  bool _reading = false;
  bool _review = false;
  int _version = 0;
  int _readVersion = -1;
  int _sequence = 0;
  String? _error;
  bool get _hasResults => _readVersion == _version;
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
    if (_busy || _photos.length >= GeminiBillScanner.maxImages) return;
    setState(() => _busy = true);
    try {
      final path = widget.capture != null
          ? await widget.capture!()
          : (await ImagePicker().pickImage(
              source: ImageSource.camera,
              imageQuality: 85,
              maxWidth: 2000,
              maxHeight: 2000,
            ))?.path;
      if (path == null || !mounted) return;
      if (!_photos.contains(path)) {
        setState(() {
          _photos.add(path);
          _version++;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Không mở được camera. Kiểm tra quyền truy cập rồi thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmReplace() async {
    if (_drafts.isEmpty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Tạo lại khoản nháp?'),
            content: const Text(
              'Các chỉnh sửa trong kết quả hiện tại sẽ bị thay thế.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Huỷ'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Tiếp tục'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _setResults(BillBatchResult result) {
    for (final d in _drafts) {
      d.dispose();
    }
    _drafts.clear();
    _sequence = 0;
    for (var index = 0; index < _photos.length; index++) {
      for (final receipt in result.receipts.where(
        (r) => r.imageIndex == index,
      )) {
        _drafts.add(_BillDraft(index, ++_sequence, receipt.result));
      }
      if (result.unreadableImages.contains(index)) {
        _drafts.add(_BillDraft(index, ++_sequence, null));
      }
    }
    _readVersion = _version;
    _review = true;
    _error = null;
  }

  Future<void> _read() async {
    if (_busy || _photos.isEmpty) return;
    if (_hasResults) {
      setState(() => _review = true);
      return;
    }
    setState(() => _busy = true);
    try {
      if (!await _confirmReplace() || !mounted) return;
      setState(() => _reading = true);
      final result = await (widget.scan ?? scanBillsWithAi)([
        for (final p in _photos) File(p),
      ]);
      if (!mounted) return;
      setState(() => _setResults(result));
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is BillScanFailure
              ? error.message
              : 'Không đọc được đợt ảnh. Thử lại hoặc nhập tay.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _reading = false;
        });
      }
    }
  }

  Future<void> _manualReview() async {
    if (_busy || _photos.isEmpty) return;
    if (!await _confirmReplace() || !mounted) return;
    setState(
      () => _setResults(
        BillBatchResult(
          receipts: const [],
          unreadableImages: Set.of(List.generate(_photos.length, (i) => i)),
        ),
      ),
    );
  }

  Future<void> _addManual() async {
    int? index = 0;
    if (_photos.length > 1) {
      index = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Chọn ảnh nguồn'),
          children: [
            for (var i = 0; i < _photos.length; i++)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, i),
                child: Text('Ảnh ${i + 1}'),
              ),
          ],
        ),
      );
    }
    if (!mounted || index == null) return;
    setState(() => _drafts.add(_BillDraft(index!, ++_sequence, null)));
  }

  Widget _image(int index, {double height = 140}) => GestureDetector(
    onTap: () => showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(
          child: Image.file(
            File(_photos[index]),
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
        File(_photos[index]),
        height: height,
        width: double.infinity,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            SizedBox(height: height, child: const Icon(Icons.receipt_outlined)),
      ),
    ),
  );

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_review ? 'Kiểm tra khoản chi' : 'Chụp hoá đơn'),
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : _review
                  ? () => setState(() => _review = false)
                  : _photos.length < GeminiBillScanner.maxImages
                  ? _capture
                  : null,
              icon: Icon(
                _review
                    ? Icons.photo_library_outlined
                    : Icons.add_a_photo_outlined,
              ),
              label: Text(
                _review
                    ? 'Xem ${_photos.length} ảnh'
                    : _photos.isEmpty
                    ? 'Chụp hoá đơn'
                    : 'Chụp tiếp',
              ),
            ),
            if (_photos.isNotEmpty) ...[
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy
                    ? null
                    : _review
                    ? _valid
                          ? () => Navigator.pop(context, [
                              for (final d in _drafts)
                                ScannedExpense(
                                  d.name.text.trim(),
                                  parseVndInput(d.amount.text)!,
                                  _payer,
                                  _participants.toList(),
                                ),
                            ])
                          : null
                    : _read,
                child: Text(
                  _reading
                      ? 'Đang đọc hoá đơn…'
                      : _review
                      ? 'Thêm ${_drafts.length} khoản chi'
                      : _hasResults
                      ? 'Xem kết quả'
                      : 'Đọc ${_photos.length} ảnh',
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    body: AbsorbPointer(
      absorbing: _busy,
      child: _review ? _reviewBody(context) : _photoBody(context),
    ),
  );

  Widget _photoBody(BuildContext context) => _photos.isEmpty
      ? Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.document_scanner_outlined,
                  size: 56,
                  color: AppTheme.purple,
                ),
                const SizedBox(height: 16),
                Text(
                  'Chụp đủ bill rồi đọc một lượt',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppTheme.red),
                    ),
                  ),
              ],
            ),
          ),
        )
      : ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_photos.length}/${GeminiBillScanner.maxImages} ảnh',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: _manualReview,
                  child: const Text('Nhập tay'),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.red),
                ),
              ),
            if (_reading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(),
              ),
            for (var i = 0; i < _photos.length; i++) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.line),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Ảnh ${i + 1}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Bỏ ảnh',
                          onPressed: () => setState(() {
                            _photos.removeAt(i);
                            _version++;
                            _error = null;
                          }),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    _image(i, height: 180),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );

  Widget _reviewBody(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      DropdownButtonFormField<String>(
        initialValue: _payer,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Người trả chung'),
        items: [
          for (final id in widget.payerIds)
            DropdownMenuItem(value: id, child: Text(widget.members[id] ?? id)),
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
      const SizedBox(height: 20),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _addManual,
          icon: const Icon(Icons.add),
          label: const Text('Thêm khoản thủ công'),
        ),
      ),
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
                      'Ảnh ${d.imageIndex + 1}',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(color: AppTheme.muted),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Bỏ khoản chi',
                    onPressed: () {
                      setState(() => _drafts.remove(d));
                      d.dispose();
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              _image(d.imageIndex),
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
                decoration: const InputDecoration(labelText: 'Số tiền (VND)'),
                onChanged: (_) => setState(() {}),
              ),
              if (d.reviewReason != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    d.reviewReason!,
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    ],
  );
}
