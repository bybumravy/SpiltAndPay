# Tổng quan dự án và yêu cầu sản phẩm

## Sản phẩm

SplitPay là ứng dụng Flutter hỗ trợ ghi nhận chi phí nhóm, tính phần mỗi thành viên cần chịu và quản lý việc trả nợ. Backend hiện dùng Firebase Authentication và Cloud Firestore.

## Khả năng hiện tại trong code

- Tạo phiên với một tổng bill, thêm thành viên có tài khoản hoặc khách, chia đều hoặc chia tuỳ chỉnh.
- Ghi nhận một hay nhiều thành viên có tài khoản đã ứng tiền cho bill phiên.
- Đóng phiên để tính lượt chuyển giữa thành viên, ghi nợ cộng dồn theo cặp UID.
- Thành viên có tài khoản báo đã chuyển toàn bộ nợ; chủ nợ xác nhận đã nhận.
- Người tạo quản lý việc thu tiền khách ngoài sổ nợ tài khoản.
- Hỗ trợ tính năng QR VietQR, chia sẻ thông tin thanh toán và OCR bill trên thiết bị.

Xem [kiến trúc và logic công nợ](system-architecture.md) để biết chi tiết và giới hạn hiện tại.

## Ràng buộc hiện tại

| Khu vực | Hành vi/giới hạn hiện tại |
|---|---|
| Tiền tệ | Số nguyên VND; phép chia cần bảo toàn tổng tiền. |
| Phiên | Schema hiện lưu một tổng tiền và số phải chịu/đã ứng ở cấp thành viên. |
| Chia | Tạo phiên hiện hỗ trợ chia đều và tuỳ chỉnh. |
| Đóng phiên | Kiểm tra tổng phần phải chịu khớp bill; ghi entry và balance trong transaction. |
| Nợ | Balance cộng dồn theo cặp tài khoản qua các phiên. |
| Thanh toán tài khoản | Payment chờ xác nhận cho toàn bộ số nợ hiện tại; chưa hỗ trợ trả một phần. |
| Khách | Được tính trong phiên; người tạo tự theo dõi và xác nhận đã thu, không ghi nợ tài khoản cho khách. |

## Thiết kế khoản chi đã duyệt — chưa triển khai

Các yêu cầu sau được duyệt cho công việc tiếp theo, nhưng model/UI/Firestore hiện tại chưa triển khai:

1. Khi tạo phiên, người dùng chọn một trong hai cách ghi nhận: nhập duy nhất tổng bill (không cần khai báo từng khoản), hoặc nhập nhiều khoản chi tiết. Không bắt buộc mọi phiên phải có danh sách khoản chi.
2. Ở chế độ tổng bill, không hiện form nhập từng khoản; phân bổ số phải chịu theo thành viên vẫn phải đủ để kiểm tra/chốt phiên như hiện tại.
3. Ở chế độ chi tiết, mỗi khoản có mô tả, số tiền, người trả và danh sách người tham gia.
2. Người tạo là người trả mặc định trên mỗi khoản; có thể chọn thành viên khác làm người trả cho riêng khoản đó.
3. Mỗi khoản chia đều cho những người được chọn; không thêm chế độ chia tuỳ chỉnh từng khoản trong phạm vi đã thống nhất. Xử lý phần dư đồng phải giữ tổng chính xác.
5. Guest được chọn tham gia chia như thành viên khác trong chế độ chi tiết. Nghĩa vụ guest hiển thị như khoản cần thu trong sổ nợ người tạo phiên; guest không có thao tác báo đã chuyển. Khi người tạo thực nhận tiền mặt hoặc chuyển khoản riêng ngoài app, người tạo tự xác nhận đã nhận ngay trong sổ nợ. Thành viên có tài khoản tiếp tục báo chuyển và chờ chủ nợ xác nhận theo luồng hiện tại.
6. Ở chế độ chi tiết, tổng tiền phiên, số đã ứng và số phải chịu được cộng từ các khoản; khi đóng phiên, tổng hợp được đưa qua logic settle/simplify và cộng dồn balance hiện tại. Ở chế độ chỉ nhập tổng bill, dùng tổng cùng phân bổ thành viên được nhập như flow hiện hành.
7. Phiên cũ chỉ có tổng và số chia thành viên vẫn đọc/chốt nợ bình thường.

### Tiêu chí nghiệm thu dự kiến

- Tổng phần chia từng khoản bằng chính xác tiền khoản đó sau xử lý phần dư.
- Tổng số đã ứng và tổng số phải chịu khớp tổng chi.
- Nhiều người trả khác nhau trên các khoản được phản ánh chính xác vào tổng `amountPaid`.
- Thành viên chỉ chịu phần từ những khoản họ được chọn tham gia.
- Guest tham gia chia; nghĩa vụ thu hiển thị trong sổ nợ creator, người tạo tự xác nhận đã nhận tiền bên ngoài app; không sinh payment hoặc balance cặp UID tài khoản cho guest.
- Không thay đổi sai logic settlement, balance cộng dồn và xác nhận payment hiện hữu.
- Cả phiên mới ở chế độ chỉ nhập tổng bill, phiên mới có khoản chi chi tiết và phiên cũ không có items đều mở/hiển thị/chốt được đúng dữ liệu.
- Firestore Rules, repository và tests bảo vệ schema mới và các bất biến tiền nợ.

## Ngoài phạm vi đã duyệt

Chưa có quyết định thêm chia tuỳ chỉnh từng khoản, thanh toán một phần, nhắc nợ tự động hoặc xác minh phân bổ độc lập bằng Cloud Functions. Không coi các hạng mục này là yêu cầu được duyệt.
