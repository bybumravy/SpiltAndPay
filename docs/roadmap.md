# Roadmap

## Đã duyệt, chưa triển khai: khoản chi chi tiết

Code hiện tại lưu tổng bill và phần chia ở cấp thành viên; chưa có model, UI hay Firestore persistence cho từng khoản chi. Mục tiêu được duyệt:

- Khi tạo phiên, hỗ trợ chọn chỉ nhập tổng bill hoặc nhập chi tiết nhiều khoản; không bắt buộc lúc nào cũng khai báo từng khoản.
- Ở chế độ chi tiết, lưu mỗi khoản gồm mô tả, tiền, người trả và thành viên được chọn chia.
- Mặc định creator là người trả cho mỗi khoản; cho phép chọn người trả khác riêng trên từng khoản.
- Chia đều cho những người tham gia được chọn; xử lý phần dư đồng chính xác.
- Bao gồm guest như người tham gia chia; nghĩa vụ guest hiển thị như khoản cần thu trong sổ nợ creator. Guest không báo đã chuyển; creator tự xác nhận đã nhận tại sổ nợ sau khi thực nhận tiền mặt hoặc chuyển khoản riêng ngoài app. Không tạo payment/balance giữa UID tài khoản cho guest.
- Chế độ chỉ nhập tổng bill không bắt buộc khai báo khoản chi; dùng phân bổ thành viên theo luồng nhập tổng hiện tại.
- Với chế độ chi tiết, cộng các khoản thành tổng paid/owed mỗi thành viên, rồi gọi settlement và cộng dồn balance hiện tại.
- Giữ luồng payment chờ xác nhận cho tài khoản và tiếp tục hỗ trợ phiên cũ không có danh sách khoản chi.
- Cập nhật Firestore Rules và test để bảo vệ tính toàn vẹn dữ liệu/money invariants.

Chi tiết và tiêu chí nghiệm thu trong [PDR](project-overview-pdr.md); trạng thái code hiện tại ở [kiến trúc](system-architecture.md).

## Khoảng trống khác đã ghi nhận

`NOTES.md` nêu trả nợ một phần, nhắc nợ, hỗ trợ iOS và OCR ngoài VND là khoảng trống/hướng phát triển. Chưa coi các mục đó là yêu cầu được duyệt cho đợt khoản chi chi tiết.
