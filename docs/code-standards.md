# Cấu trúc code và tiêu chuẩn hiện tại

## Cấu trúc chính

| Đường dẫn | Trách nhiệm |
|---|---|
| `lib/main.dart`, `lib/app.dart` | Khởi tạo Firebase và app Flutter. |
| `lib/screens/` | Màn hình xác thực, trang chính, phiên, nợ, bạn bè. |
| `lib/models/` | Model dữ liệu Firestore và chuyển đổi map. |
| `lib/repositories/` | Đọc/ghi Firestore và khai báo provider repository. |
| `lib/core/` | Chia tiền, tính nợ, QR, OCR, tiền tệ, hình ảnh, Firebase providers. |
| `test/` | Unit/widget tests Flutter. |
| `rules_test/` | Test Firestore Security Rules. |

## Quy ước hiện dùng

- Flutter/Dart với Riverpod (`flutter_riverpod`) để cấp dependency và stream dữ liệu.
- Màn hình gọi repository; repository quản lý truy cập Firestore; model có `fromMap`/`toMap`.
- Tiền lưu bằng số nguyên VND, tránh sai số số thực.
- Logic chia tiền và quyết toán thuần nằm trong `lib/core/`, tách khỏi widget.
- Ghi nhiều document liên quan dùng Firestore batch/transaction; đóng phiên và xác nhận trả tiền là transaction.
- Quyền đọc/ghi Firestore nằm trong `firestore.rules`, có test riêng trong `rules_test/`.

## Lệnh kiểm tra

```sh
flutter pub get
flutter test
```

Test rules chạy riêng theo cấu hình Node/Firebase Emulator của `rules_test/`; xem package scripts và tài liệu trong thư mục đó trước khi chạy. Môi trường Android/Firebase cần được cấu hình cục bộ.

## Hướng dẫn khi mở rộng

- Bảo toàn tổng VND chính xác khi phân bổ phần dư.
- Giữ nguyên các hợp đồng model/Firestore hiện hữu hoặc có đường đọc tương thích cho dữ liệu cũ.
- Thay đổi ghi nợ phải đồng bộ repository, rules và test; balance chỉ được thay đổi theo entry đóng phiên hoặc payment đã xác nhận.
- Với thiết kế khoản chi chi tiết đã duyệt, cộng số tiền từng khoản thành tổng thành viên trước khi gọi logic settlement; không mô tả schema đó như đã tồn tại cho đến khi triển khai.
