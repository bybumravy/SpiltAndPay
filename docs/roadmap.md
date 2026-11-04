# Roadmap

## Baseline đã triển khai

### Tài khoản và danh bạ

- Đăng nhập Google/email-mật khẩu, onboarding VietQR và đổi QR trong hồ sơ.
- Tìm bạn theo email, kết bạn bằng QR UID, lưu danh bạ gần đây.

### Phiên và khoản chi

- Phiên có một hoặc nhiều khoản chi; mỗi khoản gồm mô tả, amount VND nguyên, account payer và ordered participants.
- Equal shares được tính từ amount/participant order; remainder được phân bổ theo thứ tự và bảo toàn tổng khoản.
- UI thêm/sửa/xóa item khi phiên mở, chọn payer/participants, xem shares và đóng phiên có xác nhận.
- Tổng phiên, member paid/owed, account net positions và guest obligations được tổng hợp từ item.
- Cloud Functions tin cậy xác thực create/mutate/close và tính lại settlement; client không ghi expenses, sửa member accounting hoặc cập nhật guest collection state trực tiếp.
- Expenses nằm tại `sessions/{sessionId}/expenses/{expenseId}`; guest claims tại `sessions/{sessionId}/guestObligations/{obligationId}`.
- Phiên legacy không có expense documents vẫn đọc/đóng qua nhánh tương thích.

### Công nợ và thanh toán

- Trusted close ghép debtor với creditor, tạo entry theo session và cộng dồn balance theo cặp UID.
- Matcher server hiện bảo toàn tiền và xác định, nhưng không cam kết số lượt chuyển tối thiểu tuyệt đối.
- Payment bao phủ toàn bộ số dư và chờ chủ nợ xác nhận.
- Guest không tạo debt/payment UID pair; payer thực tế xác nhận `collected` trên obligation riêng.
- VietQR động có số tiền/nội dung, lưu và chia sẻ thẻ thanh toán.

## Backlog

- Thanh toán một phần.
- Từ chối/hủy payment pending.
- Nhắc nợ tự động.
- Chia tùy chỉnh theo từng khoản.
- Tối ưu số lượt chuyển ở trusted server nếu đây là yêu cầu phát hành.
- Hỗ trợ nền tảng ngoài Android.
- OCR đa tiền tệ ngoài VND.

## Điều kiện trước khi phát hành production

- Cấu hình Android release signing bằng keystore production thay cho debug key.
- Chạy Flutter, Functions unit/integration và Rules tests theo [hướng dẫn setup](setup.md).
- Xác minh Firebase target, Google Sign-In SHA-1, Cloud Functions runtime và Cloudinary upload preset cho môi trường phát hành.

## Tham chiếu

- [Tổng quan và PDR](project-overview-pdr.md)
- [Kiến trúc hiện tại](system-architecture.md)
- [Thiết lập và kiểm thử](setup.md)
