# Thiết lập và kiểm thử

## Yêu cầu cục bộ

- Flutter SDK có Dart thỏa mãn ràng buộc trong `pubspec.yaml` (`^3.13.3`).
- Cấu hình Firebase cục bộ hợp lệ: app khởi tạo `DefaultFirebaseOptions.currentPlatform` từ `lib/firebase_options.dart`.
- Android tooling và thiết bị/emulator khi chạy trên Android. Phiên bản SDK/JDK bắt buộc chưa được xác định trong các tệp dự án đã đọc.

## Chạy

Từ thư mục gốc:

```sh
flutter pub get
flutter run
```

Không chia sẻ hoặc commit cấu hình Firebase riêng của nhà phát triển. Không ghi Firebase identifiers hay credentials vào tài liệu.

## Kiểm thử

```sh
flutter test
```

Firestore Rules có bộ test tách trong `rules_test/`; kiểm tra `rules_test/package.json` và hướng dẫn tại chỗ để biết script/prerequisite thực tế. Dự án chứa `firebase.test.json`, nhưng môi trường và lệnh chạy emulator cần xác nhận tại máy.

## Firestore Rules

`firestore.rules` là nguồn rules trong repository. Khi thay đổi rules, cần publish rules tương ứng tới đúng Firebase project theo quy trình nhóm; repository được kiểm tra ở đây không xác lập lệnh deploy hay CI deploy cụ thể. Xác minh target project trước mọi thao tác publish.

## Lưu ý cấu hình

`NOTES.md` ghi chú cấu hình Firebase riêng theo developer và yêu cầu bổ sung SHA-1 cho Google Sign-In trên Android. Đây là hướng dẫn dự án, nhưng không bao gồm giá trị cấu hình nhạy cảm. Nếu thay đổi schema khoản chi đã duyệt, cần cập nhật rules, emulator tests và app cùng nhau trước khi phát hành.
