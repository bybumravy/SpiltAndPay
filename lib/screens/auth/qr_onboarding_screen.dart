import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/dev_mode.dart';
import '../../core/cloudinary_service.dart';
import '../../repositories/user_repository.dart';

/// Màn hình bắt buộc sau lần đăng nhập đầu tiên.
/// Yêu cầu user tải lên ảnh QR nhận tiền từ ngân hàng.
/// Sau khi upload thành công → AuthGate tự chuyển sang HomeScreen.
class QrOnboardingScreen extends ConsumerStatefulWidget {
  final String uid;
  const QrOnboardingScreen({super.key, required this.uid});

  @override
  ConsumerState<QrOnboardingScreen> createState() => _QrOnboardingScreenState();
}

class _QrOnboardingScreenState extends ConsumerState<QrOnboardingScreen> {
  File? _pickedImage;
  bool _isUploading = false;
  String? _errorMessage;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85, // nén nhẹ để giảm dung lượng upload
    );
    if (picked == null) return;
    setState(() {
      _pickedImage = File(picked.path);
      _errorMessage = null;
    });
  }

  Future<void> _upload() async {
    if (_pickedImage == null && !kDevMode) {
      setState(() => _errorMessage = 'Vui lòng chọn ảnh QR trước.');
      return;
    }

    setState(() { _isUploading = true; _errorMessage = null; });

    try {
      String url;
      if (kDevMode) {
        // Dev mode: URL fake cho test trên emulator
        url = 'https://res.cloudinary.com/dev-mode/image/upload/v1/mock_qr_${DateTime.now().millisecondsSinceEpoch}.png';
      } else {
        // Production: upload thật lên Cloudinary
        url = await uploadToCloudinary(_pickedImage!);
      }

      // Lưu URL vào Firestore profile.
      await ref.read(userRepositoryProvider).updateQrImageUrl(widget.uid, url);

      // AuthGate đang watch currentUserProvider — tự rebuild khi qrImageUrl không null.
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Upload thất bại. Kiểm tra kết nối và thử lại.');
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thiết lập QR nhận tiền'),
        automaticallyImplyLeading: false, // không cho back, bắt buộc hoàn thành
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hướng dẫn
              const Text(
                'Để nhận tiền từ bạn bè, bạn cần tải lên ảnh mã QR ngân hàng của mình.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ảnh này sẽ được hiển thị khi bạn bè cần chuyển tiền cho bạn.',
                style: TextStyle(color: Colors.grey),
              ),
              if (kDevMode) ...[
                const SizedBox(height: 8),
                const Text(
                  '[Dev mode] Skip QR upload trên emulator',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ],
              const SizedBox(height: 32),

              // Preview ảnh hoặc placeholder
              GestureDetector(
                onTap: (_isUploading || kDevMode) ? null : _pickImage,
                child: Container(
                  height: 240,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: _pickedImage != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(_pickedImage!, fit: BoxFit.contain),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              kDevMode ? Icons.check_circle : Icons.qr_code_2,
                              size: 80,
                              color: kDevMode ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              kDevMode ? 'Dev mode: Ready to continue' : 'Bấm để chọn ảnh QR',
                              style: TextStyle(
                                color: kDevMode ? Colors.green : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // Nút chọn ảnh (hidden ở dev mode)
              if (!kDevMode)
                TextButton.icon(
                  onPressed: _isUploading ? null : _pickImage,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(_pickedImage == null ? 'Chọn ảnh từ thư viện' : 'Đổi ảnh khác'),
                ),

              // Thông báo lỗi
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],

              const Spacer(),

              // Nút xác nhận
              FilledButton(
                onPressed: _isUploading ? null : _upload,
                child: _isUploading
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(kDevMode ? 'Tiếp tục (Dev mode)' : 'Xác nhận và tiếp tục'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
