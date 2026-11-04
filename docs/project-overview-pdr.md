# Tổng quan dự án và yêu cầu sản phẩm

## Sản phẩm

SplitPay là ứng dụng Flutter dành cho Android, hỗ trợ ghi nhận chi phí nhóm, tính phần mỗi thành viên cần chịu, tối ưu lượt chuyển và quản lý việc trả nợ. Backend hiện dùng Firebase Authentication và Cloud Firestore; ảnh QR nhận tiền được lưu qua Cloudinary.

## Phạm vi đã triển khai

### Tài khoản và bạn bè

- Đăng ký/đăng nhập bằng email và mật khẩu hoặc đăng nhập Google.
- Người dùng phải có ảnh VietQR hợp lệ trước khi vào màn hình chính; có thể đổi ảnh trong hồ sơ.
- Tìm người dùng theo email chính xác hoặc quét QR chứa UID.
- Lưu danh bạ gần đây trong `users/{uid}/contacts`; luồng kết bạn cố gắng cập nhật hai chiều.

### Phiên chia tiền

- Tạo phiên từ một tổng bill; tổng tiền có thể nhập tay hoặc lấy từ OCR hóa đơn trên thiết bị.
- Thêm thành viên có tài khoản từ danh bạ hoặc thêm guest bằng tên.
- Chia đều hoặc nhập số tùy chỉnh cho thành viên; phần chưa nhập được chia từ số tiền còn lại.
- Ghi nhận nhiều thành viên có tài khoản cùng ứng tiền. Creator được tính là người ứng phần còn lại của bill.
- Creator có thể đổi tên hoặc xóa phiên khi còn mở. Đóng phiên là thao tác một chiều và ghi công nợ.

### Công nợ và thanh toán

- Khi đóng phiên, hệ thống tính vị thế `amountPaid - amountOwed`, tối ưu lượt chuyển và cộng dồn balance theo cặp UID.
- Mỗi lượt chuyển của phiên được lưu thành entry bất biến; balance không được sửa tự do.
- Con nợ báo đã chuyển toàn bộ số dư đang nợ; chủ nợ xác nhận để cập nhật balance.
- Chưa hỗ trợ thanh toán một phần hoặc từ chối payment trong UI hiện tại.

### QR, chia sẻ và guest

- Ảnh QR onboarding phải là VietQR NAPAS hợp lệ; người dùng có thể đổi ảnh nhận tiền từ hồ sơ.
- App có thể đọc VietQR tĩnh, tạo mã động có sẵn số tiền/nội dung và tính lại CRC ngay trên thiết bị.
- QR hoặc thẻ thanh toán có thể được lưu vào thư viện ảnh và chia sẻ qua ứng dụng khác.
- Guest không có UID nên không xuất hiện trong collection `debts` và không tạo payment.
- **Hành vi hiện tại:** creator nhắc guest và đánh dấu “Đã thu” trong chi tiết phiên, không phải tab Công nợ.

## Ràng buộc hiện tại

| Khu vực | Hành vi hoặc giới hạn |
|---|---|
| Nền tảng | Cấu hình Firebase trong code hiện chỉ hỗ trợ Android. |
| Tiền tệ | Số nguyên VND; mọi phép chia và quyết toán phải bảo toàn tổng. |
| Phiên | Lưu một `totalAmount`; chưa có model hoặc persistence cho từng khoản chi. |
| Chia | Chia đều hoặc tùy chỉnh ở cấp thành viên. |
| Người ứng | Chỉ thành viên có tài khoản được ứng tiền; guest không được chọn làm người trả. |
| Đóng phiên | Tổng `amountOwed` phải khớp bill; với dữ liệu mới, tổng `amountPaid` phải khớp tổng phải chịu. |
| Tương thích | Phiên cũ có tổng `amountPaid == 0` được hiểu là creator đã ứng toàn bộ bill. |
| Nợ | Balance cộng dồn theo cặp tài khoản qua các phiên và được bảo vệ bằng entry/payment liên quan. |
| Thanh toán | Payment chờ xác nhận cho toàn bộ số nợ hiện tại; chưa hỗ trợ trả một phần. |
| Guest | Được tính trong phiên; creator theo dõi, nhắc và xác nhận thu tại chi tiết phiên. |

## Thiết kế khoản chi chi tiết đã duyệt — chưa triển khai

Phần này là yêu cầu cho công việc tiếp theo, không phải hành vi hiện có:

1. Khi tạo phiên, người dùng chọn chỉ nhập tổng bill hoặc nhập danh sách khoản chi chi tiết. Danh sách khoản không bắt buộc cho mọi phiên.
2. Chế độ tổng bill giữ flow hiện tại: nhập tổng và phân bổ `amountPaid`/`amountOwed` ở cấp thành viên.
3. Chế độ chi tiết lưu mỗi khoản gồm mô tả, số tiền, người trả và danh sách người tham gia.
4. Creator là người trả mặc định của từng khoản; có thể chọn thành viên có tài khoản khác làm người trả riêng cho khoản đó.
5. Mỗi khoản chỉ chia đều cho những người được chọn; phần dư đồng phải được phân bổ sao cho tổng phần chia bằng đúng tiền khoản.
6. Guest được chọn tham gia khoản như thành viên khác. Mục tiêu UI tương lai là đưa nghĩa vụ guest vào khu vực cần thu của creator trong giao diện Công nợ; creator tự xác nhận sau khi nhận tiền bên ngoài app. Việc này không tạo balance hoặc payment giữa hai UID.
7. Tổng tiền phiên, `amountPaid` và `amountOwed` được cộng từ các khoản rồi đưa qua logic settlement và balance hiện tại.
8. Phiên cũ và phiên mới chỉ nhập tổng bill phải tiếp tục đọc, hiển thị và chốt được.
9. Firestore Rules và tests phải bảo vệ schema mới cùng các bất biến tiền nợ.

### Tiêu chí nghiệm thu dự kiến

- Tổng phần chia từng khoản bằng chính xác tiền khoản đó.
- Tổng đã ứng và tổng phải chịu bằng tổng chi.
- Nhiều người trả trên các khoản được tổng hợp đúng vào `amountPaid`.
- Thành viên chỉ chịu phần của những khoản họ tham gia.
- Guest không sinh payment hoặc balance cặp UID; creator có luồng cần thu rõ ràng.
- Settlement, balance cộng dồn và xác nhận payment hiện hữu không bị thay đổi sai.
- Phiên chỉ nhập tổng, phiên có khoản chi tiết và dữ liệu cũ đều tương thích.
- Rules, repository và tests bảo vệ schema và các bất biến tiền.

## Ngoài phạm vi đã duyệt

Chưa có quyết định triển khai chia tùy chỉnh từng khoản, thanh toán một phần, nhắc nợ tự động hoặc tính lại phân bổ độc lập bằng Cloud Functions.

## Tham chiếu

- [Kiến trúc hệ thống](system-architecture.md)
- [Roadmap](roadmap.md)
