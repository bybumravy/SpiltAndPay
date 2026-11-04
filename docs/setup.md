# Thiết lập và kiểm thử

## Phạm vi nền tảng

Repository hiện có cấu hình Firebase runtime cho Android. `DefaultFirebaseOptions` chưa cấu hình iOS, web, macOS, Windows hoặc Linux; chạy trên các nền tảng đó cần tạo lại cấu hình FlutterFire.

## Yêu cầu cục bộ

- Flutter SDK có Dart thỏa ràng buộc trong `pubspec.yaml`.
- Android SDK và thiết bị/emulator Android.
- JDK 17; Gradle Android đặt Java/Kotlin target 17.
- Node.js 22 cho Functions, npm, Java và Firebase CLI để chạy Firebase Emulator.
- Firebase project đã bật Authentication, Cloud Firestore và Cloud Functions cho môi trường dùng thật.

## Cài dependency và chạy app

```sh
flutter pub get
flutter run
```

Ứng dụng khởi tạo Firebase từ `lib/firebase_options.dart`. Không sao chép Firebase identifiers vào tài liệu khác và không commit credential riêng của developer.

## Firebase Authentication

App hỗ trợ email/mật khẩu và Google Sign-In. Với Android cần bật providers tương ứng, khớp package/application ID và thêm SHA-1 signing certificate khi dùng Google Sign-In. Không đưa private key, service-account JSON hoặc token vào repository.

## Cloudinary và QR nhận tiền

Ảnh QR được upload bằng unsigned Cloudinary upload preset trong `lib/core/cloudinary_service.dart`. Cấu hình cloud name/preset phù hợp môi trường và giới hạn preset đúng mục đích upload ảnh. Onboarding yêu cầu VietQR NAPAS hợp lệ, ảnh tối đa 5 MB. Giữ `kDevMode` là `false` trước khi phát hành.

## Android

- Source/target compatibility và Kotlin JVM target là Java 17.
- Release build hiện dùng debug signing config; cấu hình keystore/signing production trước phát hành.

## Kiểm thử Flutter

```sh
flutter test
```

Có thể chạy một test file hẹp trước, ví dụ:

```sh
flutter test test/core/expense_allocation_test.dart
```

## Cloud Functions unit tests

Cài dependencies và chạy suite Node:

```sh
npm ci --prefix functions
npm test --prefix functions
```

`functions/package.json` định nghĩa `test` là `node --test`. Khi không có `FIRESTORE_EMULATOR_HOST`, các integration tests cần Firestore sẽ được bỏ qua.

## Functions integration với Firestore Emulator

Sau khi cài dependency Functions và Rules tests:

```sh
npm ci --prefix functions
npm ci --prefix rules_test
```

Chạy Functions suite dưới Firestore Emulator để kích hoạt integration tests:

```sh
firebase emulators:exec --only firestore,functions --project demo-splitpay --config firebase.test.json "npm test --prefix functions"
```

`firebase.test.json` trỏ Rules tới `firestore.rules`, Functions source tới `functions`, dùng Firestore port 8080, Functions port 5001 và tắt Emulator UI. Callable integration tests gọi handler trong process Node nhưng dùng Firestore Emulator cho dữ liệu; Functions Emulator đồng thời xác minh các exports có thể được nạp.

## Firestore Rules tests

Script Rules tự khởi động Firestore Emulator:

```sh
npm ci --prefix rules_test
npm test --prefix rules_test
```

Không chạy `npm test --prefix rules_test` bên trong một `firebase emulators:exec` khác; hai lớp sẽ tranh cùng cổng 8080.

## Deploy Firestore Rules và Functions

`firestore.rules` và `functions/` là source trong repository. Xác minh đúng Firebase target trước khi deploy; repository chưa định nghĩa lệnh deploy chuẩn của nhóm, vì vậy không tự suy đoán project đích. Các callable Functions là trusted path cho tạo/sửa khoản, close settlement và guest collection. Không deploy hoặc bật billing chỉ để chạy local tests.

## Xử lý sự cố nhanh

| Hiện tượng | Kiểm tra |
|---|---|
| Google Sign-In thất bại | Provider, package ID và SHA-1 đúng. |
| Không qua onboarding | Ảnh dưới 5 MB, rõ nét và VietQR NAPAS hợp lệ. |
| Upload QR thất bại | Mạng, cloud name và unsigned upload preset. |
| Functions tests thiếu package | Chạy `npm ci --prefix functions`. |
| Rules/Firebase CLI thiếu package | Chạy `npm ci --prefix rules_test`. |
| Port Firestore đang bận | Dừng emulator khác trước khi chạy suite. |
| Nền tảng ngoài Android báo unsupported | Tạo lại cấu hình FlutterFire cho nền tảng đó. |

## Tham chiếu

- [Cấu trúc code](code-standards.md)
- [Kiến trúc và bảo mật dữ liệu](system-architecture.md)
