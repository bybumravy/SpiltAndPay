# Cấu trúc code và tiêu chuẩn hiện tại

## Cấu trúc chính

| Đường dẫn | Trách nhiệm |
|---|---|
| `lib/main.dart`, `lib/app.dart` | Khởi tạo Firebase, Riverpod và auth/onboarding. |
| `lib/screens/` | UI xác thực, phiên, công nợ, bạn bè và hồ sơ. |
| `lib/models/` | Model Firestore; `expense.dart` định nghĩa `Expense` và `GuestObligation`. |
| `lib/repositories/` | Query/stream Firestore và callable Functions. |
| `lib/core/money.dart` | Format VND và logic chia hiện có. |
| `lib/core/expense_allocation.dart` | Chia đều từng khoản, remainder theo participant order và preview tổng hợp phiên. |
| `lib/core/settlement.dart` | Chuyển paid/owed thành vị thế ròng cho logic client/legacy. |
| `lib/core/debt_simplify.dart` | Bộ tối ưu nợ phía client và fallback cho nhóm lớn. |
| `functions/index.js` | Export `health`, `createSessionWithExpenses`, `mutateExpense`, `closeSession`, `markGuestObligationCollected`. |
| `functions/src/expenses/` | Validation, allocation/aggregation, close settlement, guest collection và tests. |
| `firestore.rules` | Quyền client và các bất biến Firestore. |
| `test/` | Unit/widget tests Flutter. |
| `rules_test/` | Firestore Rules tests bằng Node test runner. |

## Quy ước kiến trúc

- Dùng Riverpod để cấp dependency và stream dữ liệu.
- Widget điều phối tương tác; repository sở hữu Firestore/callable access; logic tiền thuần đặt trong `lib/core/` và `functions/src/expenses/`.
- Dùng số nguyên VND; validate safe integer và amount dương ở expense input.
- Client tính preview/UI shares, nhưng trusted Functions phải xác thực và tính lại accounting authoritative khi create/mutate/close.
- Ghi nhiều document liên quan bằng batch/transaction; không ghi rời rạc các output kế toán liên quan.
- Giữ tương thích schema legacy; thiếu `amountPaid` được xử lý như 0 và session không có expenses dùng nhánh close legacy.
- Không đưa credential hoặc cấu hình riêng của developer vào code hay tài liệu.

## Bất biến khoản chi và công nợ

- Mỗi expense có payer là account member; guest không thể là payer. Participant IDs phải duy nhất, không rỗng và thuộc session.
- `participantIds` có thứ tự: chia base đều, rồi cộng từng đồng remainder cho các participant đầu danh sách; tổng shares phải bằng amount.
- Không coi persisted `shares` từ client là nguồn authoritative; server tính lại từ amount và participant order.
- Tổng expense amounts phải khớp session `totalAmount`; paid/owed và net positions được tính từ items khi close.
- Account debts/entries/payments không bao gồm guest UID; guest claim được lưu thành obligation riêng theo payer thực tế.
- Chỉ payer của guest obligation mới xác nhận `collected`; client không trực tiếp ghi collection state.
- Debt ID luôn tạo từ hai UID đã sắp xếp; chiều balance phải theo quy ước `userA`/`userB`.
- Close tạo entry theo session; giảm nợ phải đi qua payment được xác nhận.

## UI và dịch vụ thiết bị

- OCR là gợi ý: người dùng luôn kiểm tra số tiền.
- VietQR phải parse và kiểm tra CRC trước khi tạo mã động; có fallback ảnh QR tĩnh.
- `kDevMode` chỉ dành cho phát triển và phải là `false` trước khi phát hành.
- Xử lý bất đồng bộ phải kiểm tra `mounted` trước khi cập nhật UI sau `await`.

## Kiểm thử

Flutter:

```sh
flutter test
```

Functions unit tests:

```sh
npm ci --prefix functions
npm test --prefix functions
```

Functions integration tests dưới Firebase Emulator:

```sh
firebase emulators:exec --only firestore,functions --project demo-splitpay --config firebase.test.json "npm test --prefix functions"
```

Rules tests riêng; script tự khởi động Firestore Emulator:

```sh
npm ci --prefix rules_test
npm test --prefix rules_test
```

`functions/package.json` dùng `node --test`; các integration tests chỉ chạy khi `FIRESTORE_EMULATOR_HOST` có sẵn. `rules_test/package.json` tự bọc `node --test` bằng Firebase CLI. Không lồng `npm test --prefix rules_test` bên trong một `emulators:exec` khác vì script này tự mở emulator.

## Khi mở rộng

- Viết test thuần cho allocation/settlement trước khi nối UI hoặc repository; kiểm tra amount nhỏ có remainder, participant order, payer/guest validation và tổng bảo toàn.
- Thay đổi schema phải cập nhật model, repository, callable validation, Firestore Rules và tests tương ứng.
- Thay đổi accounting cần Functions unit tests; thay đổi giao tiếp Firestore/Rules cần emulator integration và rules tests.
- Không dùng client input làm nguồn authoritative cho close settlement.

## Tham chiếu

- [Kiến trúc hệ thống](system-architecture.md)
- [Thiết lập](setup.md)
