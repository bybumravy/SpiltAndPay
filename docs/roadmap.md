# Roadmap

## Baseline đã triển khai

### Tài khoản và danh bạ

- Đăng nhập Google hoặc email/mật khẩu.
- Onboarding bằng ảnh VietQR và đổi QR nhận tiền trong hồ sơ.
- Tìm bạn theo email, kết bạn bằng QR UID, lưu danh bạ gần đây.

### Phiên và chia tiền

- Một tổng bill cho mỗi phiên; nhập tay hoặc OCR trên thiết bị.
- Chia đều hoặc chia tùy chỉnh ở cấp thành viên.
- Thành viên có tài khoản, guest và nhiều người cùng ứng tiền.
- Creator đổi tên/xóa phiên đang mở và đóng phiên một lần.

### Công nợ và thanh toán

- Settlement từ `amountPaid - amountOwed`.
- Tối ưu số lượt chuyển chính xác đến 18 số dư khác 0; fallback greedy cho nhóm lớn.
- Balance cộng dồn theo cặp UID với entry bất biến theo phiên.
- Payment toàn bộ số dư, chờ chủ nợ xác nhận.
- VietQR động có số tiền/nội dung, lưu và chia sẻ thẻ thanh toán.
- Creator nhắc guest và đánh dấu đã thu trong chi tiết phiên.

## Đã duyệt, chưa triển khai: khoản chi chi tiết

Code hiện tại chỉ lưu tổng bill và số phải chịu/đã ứng ở cấp thành viên. Chưa có model, UI, repository hoặc Firestore schema cho từng khoản chi.

Mục tiêu đã duyệt:

1. Cho phép chọn giữa phiên chỉ nhập tổng bill và phiên có danh sách khoản chi.
2. Mỗi khoản chi tiết lưu mô tả, số tiền, người trả và người tham gia.
3. Creator là người trả mặc định; có thể chọn thành viên có tài khoản khác cho từng khoản.
4. Chia đều mỗi khoản cho người tham gia được chọn, bảo toàn phần dư đồng.
5. Cộng các khoản thành `totalAmount`, `amountPaid` và `amountOwed`, sau đó dùng lại settlement/balance hiện tại.
6. Guest được tham gia khoản. Mục tiêu UI mới là hiển thị nghĩa vụ guest trong khu vực cần thu của creator; creator tự xác nhận sau khi nhận tiền ngoài app. Không tạo payment hoặc balance giữa UID cho guest.
7. Phiên cũ và phiên mới chỉ nhập tổng bill tiếp tục hoạt động.
8. Firestore Rules và tests bảo vệ schema cùng các bất biến tiền mới.

**Phân biệt hiện trạng:** guest hiện chỉ được nhắc và xác nhận “Đã thu” tại chi tiết phiên. Guest chưa xuất hiện trong tab Công nợ.

Chi tiết yêu cầu và tiêu chí nghiệm thu: [Tổng quan dự án và PDR](project-overview-pdr.md).

## Backlog chưa được duyệt cho đợt này

- Thanh toán một phần.
- Từ chối hoặc hủy payment pending.
- Nhắc nợ tự động.
- Chia tùy chỉnh theo từng khoản.
- Cloud Functions tính lại phân bổ độc lập phía server.
- Hỗ trợ nền tảng ngoài Android.
- OCR đa tiền tệ ngoài VND.

## Điều kiện trước khi phát hành production

- Cấu hình Android release signing bằng keystore production thay cho debug key.
- Chạy `flutter test` và Firestore Rules Emulator tests sau khi cài đủ dependency.
- Xác minh Firebase target, Google Sign-In SHA-1 và Cloudinary upload preset cho môi trường phát hành.

## Tham chiếu

- [Kiến trúc hiện tại](system-architecture.md)
- [Thiết lập và kiểm thử](setup.md)
