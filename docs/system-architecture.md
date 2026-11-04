# Kiến trúc và logic công nợ

## Tổng quan runtime

`lib/main.dart` khởi tạo Firebase rồi chạy ứng dụng trong Riverpod `ProviderScope`. `AuthGate` điều phối đăng nhập, onboarding VietQR và màn hình chính. Flutter client dùng Firebase Auth, Firestore và callable Cloud Functions; Functions dùng Admin SDK làm trusted writer cho các chuyển đổi kế toán của khoản chi.

Cấu hình Firebase Flutter hiện chỉ trả options cho Android; nền tảng khác ném `UnsupportedError`.

## Các tầng chính

| Tầng | Trách nhiệm |
|---|---|
| `lib/screens/` | UI và điều phối tương tác người dùng. |
| `lib/models/` | Model ứng dụng và chuyển đổi Firestore. |
| `lib/repositories/` | Query/stream Firestore và gọi callable Functions. |
| `lib/core/` | Preview allocation, settlement cũ, OCR, VietQR và dịch vụ thiết bị. |
| `functions/index.js` | Export callable trusted handlers và health endpoint. |
| `functions/src/expenses/` | Validation, aggregation, mutation và close-session settlement phía server. |
| `firestore.rules` | Giới hạn các thao tác trực tiếp từ client. |

Riverpod cấp dependencies và streams theo UID/session/debt.

## Mô hình dữ liệu Firestore

### `users/{uid}` và contacts

Lưu hồ sơ gồm tên, email, avatar và QR nhận tiền. `users/{uid}/contacts/{contactId}` giữ snapshot contact.

### `sessions/{sessionId}`

Session lưu creator, tiêu đề, `totalAmount`, trạng thái, `memberUserIds`, timestamps và `closeResult` sau khi đóng. `sessions/{sessionId}/members/{memberId}` giữ identity snapshot cùng `amountOwed`, `amountPaid`, trạng thái và thời điểm trả.

### `sessions/{sessionId}/expenses/{expenseId}`

Expense lưu `description`, số nguyên dương `amount`, `payerId`, ordered `participantIds`, metadata thứ tự/thời gian khi có. Model client vẫn đọc được `shares` nếu document có field này, nhưng dữ liệu mới không dựa vào persisted shares: client có thể tính `effectiveShares`, còn Functions luôn phân bổ lại từ amount và participant order.

Payer phải là account member; participants phải thuộc phiên. Clients chỉ đọc collection này. `createSessionWithExpenses` ghi session, members và expenses trong một atomic batch, đồng thời kiểm tra tổng session bằng tổng expense. `mutateExpense` cho creator add/update/delete khi phiên mở, giữ ít nhất một khoản và cập nhật `totalAmount` trong transaction.

### `sessions/{sessionId}/guestObligations/{obligationId}`

Khi đóng phiên itemized, mỗi guest share phát sinh obligation gồm `sessionId`, `expenseId`, `payerId` là UID người trả thực tế, `guestMemberId`, `amount`, `status`, timestamps và thông tin người xác nhận. ID hiện ghép expense ID với guest member ID. Thành viên phiên được đọc; client không được ghi. Chỉ payer thực tế có thể xác nhận đã thu qua callable.

### `debts/{userA_userB}`

Document ID ghép hai UID đã sắp xếp (`userA < userB`). `balance > 0` nghĩa userA nợ userB; `balance < 0` nghĩa userB nợ userA. `entries/{sessionId}` là transfer bất biến theo phiên; `payments/{paymentId}` ghi báo chuyển từ `pending` sang `confirmed`. Guest obligations không nằm trong debts/payments.

## Allocation, tổng hợp và close

Client preview dùng `lib/core/expense_allocation.dart`; allocation chia số nguyên đều và cấp remainder theo ordered participant IDs. Trusted itemized close đọc lại expenses/members, kiểm tra tổng, tự phân bổ lại và tổng hợp:

- `totalAmount` từ expense amounts;
- `paidByMember` theo payer;
- `owedByMember` theo shares;
- account net positions sau khi tách phần guest khỏi debt UID-pair;
- guest obligations theo từng expense/guest participant.

`closeSession` chỉ cho creator đóng session đang mở. Trong transaction, Function ghép debtor với creditor theo thứ tự xác định, tạo guest obligations, entries, cập nhật balances/member amounts và chuyển session sang `closed` cùng `closeResult`. Matcher server hiện là greedy, bảo toàn tiền nhưng không cam kết số transfer tối thiểu tuyệt đối. Client không gửi settlement result làm authoritative input.

### Legacy compatibility

Nếu không có expense documents, close logic dùng member `amountOwed`/`amountPaid`. Tổng owed phải khớp session total; `amountPaid` thiếu được đọc là 0. Khi `paidSum == 0`, creator được coi là đã ứng toàn bộ total. Phiên legacy vẫn đóng được nhưng nhánh này không tạo itemized guest obligations.

## Account settlement và payment

Mỗi account net position phản ánh phần đã trả trừ phần phải chịu sau khi loại guest claims. Transfers được gom theo cặp UID và cộng vào balance hiện có, đồng thời lưu entry cho session.

Debt/payment semantics hiện tại không đổi: debtor tạo payment `pending` cho toàn bộ số đang nợ, creditor xác nhận để giảm balance. Các thao tác payment được Firestore Rules kiểm tra; chưa có partial payment. Guest không tạo UID-pair debt/payment và chỉ được theo dõi qua obligation riêng.

## Cloud Functions

`functions/index.js` export:

| Function | Vai trò |
|---|---|
| `health` | HTTP health check trả `ok`. |
| `createSessionWithExpenses` | Tạo session, members và expenses sau validation. |
| `mutateExpense` | Add/update/delete expense khi phiên mở, cập nhật tổng phiên. |
| `closeSession` | Tính lại settlement authoritative, ghi debts/entries/guest obligations. |
| `markGuestObligationCollected` | Payer thực tế xác nhận guest obligation đã thu. |

## Biên bảo mật Firestore

Rules cho phép thành viên đọc sessions, members, expenses và guest obligations. Client không được ghi expenses/guest obligations, đóng session hoặc cập nhật member accounting. Debt, entry và payment client writes chỉ được phép khi khớp chứng từ và chuyển đổi trạng thái mà Rules kiểm tra; Functions dùng Admin SDK để ghi trusted close outputs sau khi tự xác thực caller, session state, membership và số liệu.

## VietQR, ảnh và chia sẻ

Onboarding kiểm tra ảnh tối đa 5 MB, đọc payload VietQR NAPAS và CRC trước khi upload Cloudinary. App có thể tạo QR động từ payload tĩnh, render PNG, lưu hoặc chia sẻ thẻ; nếu không parse được payload thì dùng ảnh QR gốc.

## Tham chiếu

- [Tổng quan và PDR](project-overview-pdr.md)
- [Cấu trúc code và tiêu chuẩn](code-standards.md)
- [Thiết lập và kiểm thử](setup.md)
