# SplitPay

SplitPay là ứng dụng Flutter dành cho Android để ghi nhận chi phí chung, chia tiền và quản lý công nợ nhóm. Ứng dụng dùng Firebase Authentication, Cloud Firestore và Riverpod.

## Tính năng hiện tại

- Đăng nhập bằng Google hoặc email/mật khẩu; người dùng mới hoàn tất onboarding bằng ảnh VietQR nhận tiền.
- Tìm và kết bạn qua email hoặc QR UID; dùng danh bạ khi thêm thành viên vào phiên.
- Tạo phiên từ một tổng bill, nhập tay hoặc quét hóa đơn bằng OCR trên thiết bị.
- Chia đều hoặc chia tùy chỉnh; hỗ trợ guest và nhiều thành viên có tài khoản cùng ứng tiền.
- Đóng phiên để tối ưu số lượt chuyển, cộng dồn công nợ theo từng cặp tài khoản.
- Con nợ báo đã chuyển toàn bộ số dư; chủ nợ xác nhận đã nhận.
- Tạo VietQR động có sẵn số tiền và nội dung, lưu hoặc chia sẻ thẻ thanh toán.
- Người tạo nhắc guest và đánh dấu đã thu tại màn hình chi tiết phiên.

Phiên hiện tại chỉ lưu **một tổng bill** và số phải chịu/đã ứng của từng thành viên. Danh sách khoản chi chi tiết theo từng món đã được thiết kế nhưng **chưa triển khai** trong model, Firestore hoặc UI.

## Tài liệu

- [Tổng quan sản phẩm và yêu cầu](docs/project-overview-pdr.md)
- [Kiến trúc và logic công nợ](docs/system-architecture.md)
- [Cấu trúc code và tiêu chuẩn](docs/code-standards.md)
- [Thiết lập và kiểm thử](docs/setup.md)
- [Roadmap](docs/roadmap.md)

## Chạy ứng dụng

Cần Flutter SDK có Dart phù hợp với `pubspec.yaml` và cấu hình Firebase Android hợp lệ:

```sh
flutter pub get
flutter run
```

Chạy kiểm thử Flutter:

```sh
flutter test
```

Xem [hướng dẫn thiết lập](docs/setup.md) để cấu hình Firebase, Google Sign-In, Cloudinary và Firestore Rules Emulator.
