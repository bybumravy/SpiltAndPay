# SplitPay

SplitPay là ứng dụng Flutter ghi nhận chi phí chung, quản lý công nợ nhóm và hỗ trợ các thành viên phối hợp thanh toán. Phiên bản hiện tại dùng Firebase Authentication và Cloud Firestore; chi tiết khoản chi cho từng phiên đang là thiết kế đã duyệt, chưa triển khai.

## Tài liệu

- [Tổng quan và yêu cầu sản phẩm](docs/project-overview-pdr.md)
- [Cấu trúc code và tiêu chuẩn hiện tại](docs/code-standards.md)
- [Kiến trúc và logic công nợ](docs/system-architecture.md)
- [Roadmap](docs/roadmap.md)
- [Thiết lập và triển khai](docs/setup.md)

## Chạy ứng dụng

Cần Flutter SDK phù hợp với ràng buộc Dart trong `pubspec.yaml` và cấu hình Firebase hợp lệ cho môi trường của bạn. Từ thư mục dự án:

```sh
flutter pub get
flutter run
```

Xem [hướng dẫn thiết lập](docs/setup.md) để biết thêm về cấu hình Firebase, kiểm thử và những giả định chưa được xác nhận.
