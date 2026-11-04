# SplitPay

SplitPay là ứng dụng Flutter dành cho Android để ghi nhận chi phí chung, chia tiền và quản lý công nợ nhóm. Ứng dụng dùng Firebase Authentication, Cloud Firestore, Cloud Functions và Riverpod.

## Tính năng hiện tại

- Đăng nhập bằng Google hoặc email/mật khẩu; người dùng mới hoàn tất onboarding bằng ảnh VietQR nhận tiền.
- Tìm và kết bạn qua email hoặc QR UID; dùng danh bạ khi thêm thành viên vào phiên.
- Tạo phiên với một hoặc nhiều khoản chi; nhập mô tả, số tiền VND nguyên, người trả là tài khoản và danh sách người tham gia.
- Chia đều từng khoản theo danh sách tham gia; phần dư đồng được phân bổ theo thứ tự participant đã lưu, bảo đảm tổng phần chia bằng tiền khoản.
- Thêm, sửa, xóa khoản khi phiên đang mở; chọn người trả/người tham gia và xem phần chia. Đóng phiên có xác nhận.
- Tính tổng phiên, `amountPaid`/`amountOwed`, vị thế tài khoản và nghĩa vụ guest từ các khoản; Cloud Functions xác thực và tính lại kế toán khi đóng.
- Ghi công nợ theo cặp tài khoản. Con nợ báo đã chuyển toàn bộ số dư; chủ nợ xác nhận đã nhận.
- Tạo VietQR động có sẵn số tiền và nội dung, lưu hoặc chia sẻ thẻ thanh toán.
- Guest không tạo debt/payment theo cặp UID. Người trả thực tế có thể xác nhận đã thu nghĩa vụ guest.
- Phiên legacy không có expense documents tiếp tục được đọc và đóng theo logic tương thích cũ.

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

Xem [hướng dẫn thiết lập](docs/setup.md) để cấu hình Firebase, Google Sign-In, Cloudinary, Cloud Functions và các emulator tests.
