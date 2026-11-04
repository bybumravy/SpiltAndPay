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

## Kiểm thử chỉnh sửa toàn bộ phiên mở trên Android

Mở phiên → menu → **Chỉnh sửa toàn bộ phiên**. Chỉ creator của phiên mở được lưu. Thay đổi thành viên, tên, khoản chi, payer và participants được ghi cùng một transaction; phần đã trả/phải chịu tính lại từ các khoản. Guest không được làm payer. Phiên đóng không sửa; bản sửa cũ bị từ chối nếu dữ liệu đã thay đổi ở nơi khác. Phiên legacy hiển thị cảnh báo chuyển sang chia đều theo từng khoản trước khi lưu.

Integration test chạy repository Flutter thật qua Auth/Firestore Emulator, dùng named Firebase app `demo-splitpay-edit`, không ghi vào project thật:

```sh
flutter pub get
rules_test/node_modules/.bin/firebase emulators:exec --project demo-splitpay-edit --config firebase.edit-test.json --only auth,firestore 'flutter test --no-pub integration_test/open_session_edit_test.dart -d emulator-5554'
```

Cần emulator Android đang chạy. Debug manifest chỉ cho HTTP tới `10.0.2.2` để truy cập emulator Firebase trên máy host. Không chạy đồng thời với Rules tests vì dùng cùng port Firestore. Test bao phủ sửa toàn bộ, đồng bộ member accounting khi sửa khoản riêng, chống stale edit, thu hồi quyền thành viên bị xoá, đóng phiên, payment và guest collection; gồm cả creator chốt nợ giữa hai tài khoản khác mà không đọc số dư riêng của họ.


## Gemini bill scanning experiment

- Branch: `codex/gemini-bill-scanning`. Bill scanning uses Firebase AI Logic with the Gemini Developer API (`FirebaseAI.googleAI`), not a Gemini key in the APK.
- Enable Firebase AI Logic for project `splitandpay-2a413` using the Gemini Developer API. Keep Spark/no Cloud Billing for eligible free-tier models; quotas still apply. Linking Cloud Billing changes Gemini usage to paid pricing.
- Debug builds activate App Check debug providers. Register each device's debug secret under App Check > app > Manage debug tokens. `.local/` holds local setup secrets and is gitignored; do not commit or share debug tokens publicly. Release builds select Play Integrity/App Attest and require production provider registration.
- Default model: `gemini-3.1-flash-lite`; override with `--dart-define=BILL_AI_MODEL=...` when testing another supported model. SDK versions stay compatible with the existing Firebase Core 3.x stack.
- Capturing/removing photos is local. The explicit Read N images action sends one multi-image request (1-6 images, 8 MiB per image, 12 MiB combined before base64, 120-second timeout). A photo may contain several bills; the result contains up to 24 separate receipts with source-image indices and an explicit unreadable-images list. Receipt images leave the device only on that read action; free-tier data terms apply. Batching reduces request count, not the image/token input volume. Returning to unchanged results uses the cached draft and makes no request.
- JSON extraction returns description, VND total, literal amount text and review flag. Only a positive integer VND amount matching the quoted digits is prefilled; other results require manual review. Matching fields do not prove the AI read the image correctly. Draft confirmation and the existing atomic session save still control persistence.
- Tests inject the AI transport and cover invalid types, mismatched evidence, currency, unknown image signatures, oversized files, timeouts and quota/attestation errors. Run `flutter test --no-pub`. Live AI validation additionally requires registered App Check tokens and an enabled model/project quota.
