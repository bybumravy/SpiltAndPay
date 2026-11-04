# Thiết lập và kiểm thử

## Phạm vi nền tảng

Repository hiện có cấu hình Firebase runtime cho Android. `DefaultFirebaseOptions` chưa cấu hình iOS, web, macOS, Windows hoặc Linux; chạy trên các nền tảng đó cần tạo lại cấu hình FlutterFire.

## Yêu cầu cục bộ

- Flutter SDK có Dart thỏa ràng buộc `^3.13.3` trong `pubspec.yaml`.
- Android SDK và thiết bị/emulator Android.
- JDK 17; Gradle Android đặt Java/Kotlin target 17.
- Node.js, npm và Java để chạy Firebase Firestore Emulator tests.
- Firebase project đã bật Authentication và Cloud Firestore.

## Cài dependency và chạy app

```sh
flutter pub get
flutter run
```

Ứng dụng khởi tạo Firebase từ `lib/firebase_options.dart`. Không sao chép Firebase identifiers vào tài liệu khác và không commit credential riêng của developer.

## Firebase Authentication

App hỗ trợ email/mật khẩu và Google Sign-In. Với Android, cần:

1. Bật Email/Password và Google provider trong Firebase Authentication.
2. Đảm bảo package/application ID khớp cấu hình Android.
3. Thêm SHA-1 của debug/release signing certificate vào Firebase khi dùng Google Sign-In.
4. Cập nhật file cấu hình Android bằng FlutterFire/Firebase tooling theo quy trình của nhóm.

Không đưa private key, service-account JSON hoặc token vào repository.

## Cloudinary và QR nhận tiền

Ảnh QR được upload trực tiếp bằng unsigned Cloudinary upload preset trong `lib/core/cloudinary_service.dart`. Khi dùng môi trường khác, cấu hình cloud name và preset phù hợp; preset phải giới hạn đúng mục đích upload ảnh.

Onboarding chỉ chấp nhận ảnh có payload VietQR NAPAS hợp lệ và dung lượng tối đa 5 MB. `lib/core/dev_mode.dart` có cờ `kDevMode`; giữ `false` trước khi build phát hành vì chế độ dev có thể bỏ qua bước chọn/kiểm tra QR thật.

## Android

- `compileSdk`, `minSdk` và `targetSdk` lấy từ Flutter toolchain.
- Source/target compatibility và Kotlin JVM target là Java 17.
- Manifest app khai báo Internet và quyền ghi bộ nhớ chỉ cho Android 9 trở xuống; các plugin camera/thư viện ảnh có thể bổ sung manifest khi build.
- Release build hiện dùng debug signing config. Phải cấu hình keystore/signing production trước khi phát hành lên store.

## Kiểm thử Flutter

```sh
flutter test
```

Có thể chạy một file hẹp trước, ví dụ:

```sh
flutter test test/core/settlement_test.dart
```

Các test chính bao phủ chia tiền, settlement, tối ưu nợ, bảo toàn tiền qua dữ liệu ngẫu nhiên, OCR, VietQR, image helpers và parsing session.

## Firestore Rules Emulator

Cài dependency trong `rules_test/`:

```sh
npm ci --prefix rules_test
```

Chạy bộ rules tests:

```sh
npm test --prefix rules_test
```

Script dùng Firebase CLI để khởi động Firestore Emulator với:

- Project demo cục bộ `demo-splitpay`.
- Rules từ `firestore.rules`.
- Cấu hình `firebase.test.json`.
- Cổng Firestore Emulator `8080`; Emulator UI tắt.

Nếu gặp lỗi không tìm thấy `@firebase/rules-unit-testing`, dependency trong `rules_test/` chưa được cài; chạy lại `npm ci --prefix rules_test`.

## Deploy Firestore Rules

`firestore.rules` là nguồn rules trong repository. Xác minh đúng Firebase target trước khi deploy. Repository không định nghĩa CI/CD hoặc lệnh deploy chuẩn của nhóm, vì vậy không tự suy đoán project đích.

Mọi thay đổi schema tiền/nợ phải được kiểm tra đồng thời bằng Flutter tests và Rules Emulator tests trước khi publish rules.

## Xử lý sự cố nhanh

| Hiện tượng | Kiểm tra |
|---|---|
| Google Sign-In thất bại trên Android | Provider đã bật, package ID và SHA-1 đúng. |
| Không qua onboarding | Ảnh dưới 5 MB, rõ nét và là VietQR NAPAS hợp lệ. |
| Upload QR thất bại | Mạng, cloud name và unsigned upload preset Cloudinary. |
| OCR không nhận tổng | Nhập tay; OCR là gợi ý và cần hóa đơn rõ nét. |
| Rules tests thiếu package | Chạy `npm ci --prefix rules_test`. |
| Nền tảng ngoài Android báo unsupported | Tạo lại cấu hình bằng FlutterFire cho nền tảng đó. |

## Tham chiếu

- [Cấu trúc code](code-standards.md)
- [Kiến trúc và bảo mật dữ liệu](system-architecture.md)
