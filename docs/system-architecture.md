# Kiến trúc và logic công nợ

## Tổng quan runtime

`lib/main.dart` khởi tạo Firebase rồi chạy ứng dụng trong Riverpod `ProviderScope`. `AuthGate` theo dõi Firebase Auth và hồ sơ Firestore để điều phối:

1. Chưa đăng nhập → màn hình đăng nhập email/mật khẩu hoặc Google.
2. Đã đăng nhập nhưng chưa có QR nhận tiền → onboarding VietQR.
3. Hồ sơ đã có QR → màn hình chính gồm Phiên, Công nợ và Hồ sơ.

Cấu hình Firebase sinh bởi FlutterFire hiện chỉ trả về options cho Android; các nền tảng khác ném `UnsupportedError`.

## Các tầng chính

| Tầng | Trách nhiệm |
|---|---|
| `lib/screens/` | UI và điều phối tương tác người dùng. |
| `lib/models/` | Model ứng dụng và chuyển đổi dữ liệu Firestore. |
| `lib/repositories/` | Query, stream, batch và transaction Firestore. |
| `lib/core/` | Chia tiền, settlement, tối ưu nợ, OCR, VietQR, ảnh và dịch vụ hạ tầng. |

Riverpod cung cấp Firebase Auth, Firestore, repository và stream theo UID/session/debt.

## Mô hình dữ liệu Firestore

### `users/{uid}`

Lưu tên, email, `emailLower`, avatar và URL ảnh QR nhận tiền. Người dùng đã đăng nhập có thể đọc hồ sơ để tìm bạn; chỉ chính chủ được ghi document hồ sơ.

`users/{uid}/contacts/{contactId}` lưu snapshot tên/avatar và thời điểm tương tác. Chủ danh bạ có thể đọc/xóa; rules còn cho phép chính contact ghi thông tin của họ để hỗ trợ kết bạn hai chiều.

### `sessions/{sessionId}`

`Session` lưu creator, tiêu đề, một `totalAmount`, `splitMode`, trạng thái, danh sách UID thành viên và timestamp. `sessions/{sessionId}/members/{memberId}` lưu identity snapshot, `amountOwed`, `amountPaid`, trạng thái và thời điểm trả.

Creator tạo session và members trong batch. Khi phiên còn mở, creator có thể đổi tiêu đề hoặc xóa session cùng members. Đóng phiên cập nhật session, entries và balances trong một transaction.

Code hiện **không có** model, subcollection hoặc field cho danh sách khoản chi chi tiết.

### `debts/{userA_userB}`

Document ID được tạo từ hai UID đã sắp xếp; `userA < userB`. `balance > 0` nghĩa userA nợ userB, `balance < 0` nghĩa userB nợ userA.

- `entries/{sessionId}`: lượt chuyển bất biến sinh khi đóng phiên.
- `payments/{paymentId}`: lần báo chuyển tiền, từ `pending` sang `confirmed`.
- `pendingPaymentId`: khóa một payment đang chờ cho cặp nợ.

Guest không có UID và không được lưu vào `debts` hoặc `payments`.

## Tạo và chia phiên

Màn tạo phiên nhận tổng bill bằng nhập tay hoặc OCR. OCR dùng Google ML Kit trên thiết bị, ưu tiên số cạnh từ khóa tổng tiền; nếu không có từ khóa thì gợi ý số hợp lệ lớn nhất và yêu cầu người dùng kiểm tra.

`computeShares` hỗ trợ:

- Chia đều: phần dư đồng được cộng vào creator.
- Chia tùy chỉnh: số nhập tay được giữ nguyên; phần còn lại chia đều cho các thành viên chưa nhập và creator.

Khi bật nhiều người ứng tiền, thành viên có tài khoản nhập `amountPaid`; creator nhận `totalAmount - othersPaid`. Guest không được ứng tiền.

## Đóng phiên và settlement

`SessionRepository.closeSession` thực hiện trong transaction:

1. Từ chối nếu phiên đã đóng.
2. Kiểm tra tổng `amountOwed` bằng `totalAmount`.
3. Gọi `settleSession` để tính vị thế ròng.
4. Ghi session thành `closed`, tạo entry theo phiên và cộng dồn balance từng cặp.
5. Chuyển thành viên tài khoản sang trạng thái ledger/paid; guest giữ trạng thái cần thu.

Với dữ liệu mới, `settleSession` yêu cầu tổng `amountPaid` bằng tổng `amountOwed`. Với phiên cũ có tổng `amountPaid == 0`, creator được coi là đã ứng toàn bộ bill.

Mỗi tài khoản có vị thế `amountPaid - amountOwed`. Phần guest phải chịu được trừ khỏi vị thế creator vì creator tự thu guest ngoài sổ nợ tài khoản.

`simplifyDebts` tìm số lượt chuyển tối thiểu bằng subset dynamic programming khi có tối đa 18 số dư khác 0. Nhóm lớn hơn dùng greedy: vẫn bảo toàn tiền nhưng không bảo đảm số lượt tối thiểu.

## Thanh toán công nợ

Con nợ bấm “Tôi đã chuyển” để tạo payment `pending` đúng bằng toàn bộ số dư đang nợ. Transaction từ chối khi balance đã hết hoặc đã có payment chờ. Chủ nợ bấm “Đã nhận”; payment chuyển sang `confirmed` và balance giảm đúng amount đã lưu.

Luồng hiện tại không hỗ trợ trả một phần hoặc từ chối payment trong UI.

Guest được nhắc và đánh dấu “Đã thu” tại màn hình chi tiết phiên. Mục tiêu đưa nghĩa vụ guest vào giao diện Công nợ thuộc thiết kế khoản chi chi tiết tương lai, chưa tồn tại trong code hiện tại.

## VietQR, ảnh và chia sẻ

- Onboarding kiểm tra ảnh tối đa 5 MB, đọc QR trên thiết bị, xác minh payload EMVCo/NAPAS và CRC trước khi upload lên Cloudinary.
- `staticQrPayloadProvider` tải ảnh QR của chủ nợ và đọc payload trên thiết bị.
- `buildDynamicVietQr` chuyển mã tĩnh thành mã động, thêm số tiền và nội dung không dấu tối đa 25 ký tự, rồi tính lại CRC16-CCITT.
- Nếu không đọc được payload tĩnh, UI dùng ảnh QR gốc làm fallback.
- QR có thể được render thành PNG, lưu vào album SplitPay hoặc ghép thành thẻ thanh toán để chia sẻ.

Không có Cloud Function trong repository; tính chia và settlement chạy ở client.

## Biên bảo mật Firestore

`firestore.rules` giới hạn các mutation quan trọng:

- Chỉ creator tạo session hợp lệ; chỉ thành viên tài khoản đọc session.
- Tiền trong session/member không được sửa sau khi tạo; creator chỉ đổi tiêu đề, đóng hoặc xóa phiên đang mở.
- Debt ID và thứ tự participants phải đúng quy ước.
- Balance chỉ thay đổi khi khớp entry mới của phiên đang được đóng hoặc payment đang được xác nhận.
- Entry phải thuộc thành viên phiên, có số tiền dương không vượt bill và bất biến sau khi tạo.
- Payment pending phải đúng toàn bộ số đang nợ; chỉ chủ nợ xác nhận và không được sửa amount.
- Debt, entry và payment không được xóa qua client.

Rules bảo vệ liên kết giữa balance và chứng từ, nhưng không tính lại độc lập toàn bộ phân bổ `amountOwed`/`amountPaid` do client gửi. Khi thêm khoản chi chi tiết phải cập nhật model, repository, rules và tests đồng bộ.

## Tham chiếu

- [Tổng quan và PDR](project-overview-pdr.md)
- [Cấu trúc code và tiêu chuẩn](code-standards.md)
- [Thiết lập và kiểm thử](setup.md)
