# Tổng quan dự án và yêu cầu sản phẩm

## Sản phẩm

SplitPay là ứng dụng Flutter Android hỗ trợ ghi nhận chi phí nhóm, tính phần mỗi thành viên chịu và quản lý trả nợ. Runtime dùng Firebase Authentication, Cloud Firestore, Cloud Functions và Riverpod; ảnh QR nhận tiền được lưu qua Cloudinary.

## Phạm vi hiện tại

### Tài khoản và bạn bè

- Đăng ký/đăng nhập bằng email/mật khẩu hoặc Google.
- Người dùng cần ảnh VietQR hợp lệ trước khi vào màn hình chính; có thể đổi ảnh trong hồ sơ.
- Tìm người dùng theo email chính xác hoặc quét QR chứa UID.
- Lưu danh bạ gần đây trong `users/{uid}/contacts`; luồng kết bạn cố gắng cập nhật hai chiều.

### Phiên và khoản chi

- Tạo phiên gồm một hoặc nhiều khoản chi. Mỗi khoản có mô tả, số nguyên VND, payer là thành viên tài khoản và danh sách participant có thứ tự.
- Mỗi khoản được chia đều. Phần dư đồng được cộng lần lượt cho participant đầu danh sách; tổng phần chia luôn bằng số tiền khoản.
- UI cho phép thêm, sửa, xóa khoản khi phiên mở; chọn payer/participants, xem shares và đóng phiên qua xác nhận.
- Có thể có nhiều account payer trong một phiên. Tổng phiên và `amountPaid`/`amountOwed` được tổng hợp từ các khoản.
- Creator có thể đổi tiêu đề hoặc xóa phiên khi còn mở. Đóng phiên là thao tác một chiều.
- Phiên legacy không có documents trong `expenses` tiếp tục được đọc và đóng theo logic legacy dựa trên các trường member hiện có.

### Công nợ, thanh toán và guest

- Khi đóng phiên, Cloud Function đọc lại members/expenses, tính lại phân bổ và account net positions, rồi tạo entries và cộng dồn balance theo cặp UID.
- Lượt chuyển được ghép xác định giữa debtor và creditor; implementation server hiện không cam kết số lượt chuyển là tối thiểu tuyệt đối.
- Mỗi lượt chuyển của phiên có entry bất biến; balance không được sửa tự do mà phải khớp close entry hoặc payment liên quan.
- Con nợ báo đã chuyển toàn bộ số dư hiện nợ; chủ nợ xác nhận để cập nhật balance. Chưa hỗ trợ thanh toán một phần hoặc từ chối payment trong UI.
- Guest không có UID nên không xuất hiện trong collection `debts` và không tạo payment. Nghĩa vụ guest được ghi riêng tại `sessions/{sessionId}/guestObligations/{obligationId}`; chỉ payer thực tế được xác nhận đã thu qua callable tin cậy.

### QR và chia sẻ

- Ảnh QR onboarding phải là VietQR NAPAS hợp lệ; người dùng có thể đổi ảnh nhận tiền trong hồ sơ.
- App đọc VietQR tĩnh, tạo mã động có số tiền/nội dung và tính lại CRC trên thiết bị.
- QR/thẻ thanh toán có thể lưu vào thư viện ảnh và chia sẻ qua ứng dụng khác.

## Yêu cầu và ràng buộc hiện hành

| Khu vực | Yêu cầu/hạn chế |
|---|---|
| Nền tảng | Cấu hình Firebase hiện chỉ hỗ trợ Android. |
| Tiền | Số nguyên VND; phép chia và quyết toán phải bảo toàn tổng. |
| Khoản chi | `sessions/{sessionId}/expenses/{expenseId}` lưu mô tả, amount, payer, ordered participants và metadata. Payer phải là account member; participant phải là member phiên. |
| Chia | Chia đều từng khoản; chưa có chia tùy chỉnh theo từng khoản. Shares có thể được tính lại từ amount và participant order thay vì tin dữ liệu client. |
| Kế toán | Tổng khoản phải khớp `sessions.totalAmount`; server xác thực và tính lại aggregates/settlement khi đóng. |
| Guest | Nghĩa vụ guest là khoản phải thu riêng gắn payer và guest member, không chuyển thành debt/payment giữa UID. |
| Legacy | Nếu không có expense documents, close callable dùng `amountOwed`/`amountPaid` hiện có; `amountPaid` vắng mặt được đọc như 0 và legacy `paidSum == 0` coi creator đã ứng tổng owed. |
| Nợ | Balance cộng dồn theo cặp account UID, gắn với entry/payment; Rules hoặc trusted Functions bảo vệ các chuyển đổi kế toán. |
| Thanh toán | Payment hiện bao phủ toàn bộ số dư đang nợ; chủ nợ xác nhận. |

## Tiêu chí sản phẩm đã hiện thực

- Chia đều mỗi khoản bảo toàn chính xác amount, gồm phần dư theo thứ tự participant.
- Payer, participants và tổng khoản được xác thực ở trusted Functions boundary; payer guest hoặc participant ngoài phiên bị từ chối.
- Tổng paid/owed, vị thế account, guest claims và transfer settlement được tính lại từ expense items khi đóng.
- Tạo session cùng members/expenses trong atomic batch; sửa/xóa expense chỉ khi creator và session còn mở; không xóa khoản cuối cùng.
- Guest obligation chỉ được đánh dấu `collected` bởi payer thực tế; thao tác lặp của chính payer là idempotent.
- Dữ liệu legacy không có expense items vẫn được đọc/đóng bằng nhánh tương thích.
- Rules chặn client ghi expenses, guest collection state và sửa member accounting sau khi tạo; balance/entry/payment chỉ đổi theo các flow được kiểm tra.

## Backlog sản phẩm

- Thanh toán một phần.
- Từ chối/hủy payment pending.
- Nhắc nợ tự động.
- Chia tùy chỉnh theo từng khoản.
- Nếu sản phẩm yêu cầu, thay matcher server hiện tại bằng thuật toán tối ưu số lượt chuyển có bằng chứng tương ứng.
- Hỗ trợ nền tảng ngoài Android và OCR đa tiền tệ ngoài VND.

## Tham chiếu

- [Kiến trúc hệ thống](system-architecture.md)
- [Roadmap](roadmap.md)
