## Dev note — Công nợ khách vãng lai và chia sẻ QR (2026-11-05)

Trạng thái: đã triển khai phần Công nợ khách vãng lai và chia sẻ QR.

- Khoản cần thu của khách vãng lai phải xuất hiện trong màn Công nợ của người thực tế được nhận tiền, không chỉ trong chi tiết phiên. Hiển thị tên khách, phiên liên quan, số tiền và trạng thái chưa thu/đã thu.
- Dùng guest obligation hiện có làm nguồn dữ liệu; không tạo tài khoản giả hoặc cộng khoản khách vào debt theo cặp UID. Không gộp hai khách chỉ vì trùng tên và không cộng trùng khoản đã ghi từ phiên.
- Mỗi khoản có QR nhận tiền của đúng người được thu, điền sẵn số tiền còn phải thu và nội dung nhận diện khoản/phiên. Nếu chưa có QR nhận tiền, cho người nhận bổ sung; không dùng QR của người tạo phiên khi họ không phải người được thu.
- Thêm nút chia sẻ ảnh QR kèm số tiền và nội dung qua bảng chia sẻ hệ thống để người dùng chọn Zalo, Messenger hoặc app nhắn tin đã cài. Không tự gửi tin hay tự chọn người nhận; hủy chia sẻ không đổi trạng thái khoản thu.
- Chia sẻ hoặc lưu QR không có nghĩa đã thu tiền. Chỉ người có quyền thu xác nhận đã nhận tiền qua luồng guest obligation hiện có; trạng thái và số tổng cập nhật đồng nhất ở Công nợ và chi tiết phiên. Xác nhận lại không được ghi nhận tiền lần hai.
- Kiểm tra các trường hợp: nhiều người ứng tiền, khách trùng tên ở các phiên khác nhau, chưa có QR, không lưu/chia sẻ được ảnh, hủy chia sẻ, xác nhận thu và tải lại app. Không hiển thị khoản từ phiên mở thành khoản công nợ đã chốt.

# Ghi chú tiến độ Split & Pay

Cập nhật: 2026-10-18

## Đã làm

### Chia tiền và nợ (logic cốt lõi)
- **Nhiều người ứng tiền trong một phiên**: công tắc "Có người khác cũng ứng tiền" ở màn tạo phiên.
  Mỗi thành viên có `amountOwed` (phải trả) và `amountPaid` (đã ứng). Khách (guest) không ứng tiền;
  người tạo phiên gánh phần của khách và tự thu tiền mặt.
- **Chốt nợ tối ưu số lần chuyển** (`lib/core/debt_simplify.dart`, `lib/core/settlement.dart`):
  số lần chuyển nhỏ nhất = n − k, với k là số nhóm lớn nhất có tổng số dư bằng 0
  (quy hoạch động theo tập con, n ≤ 18; lớn hơn dùng tham lam).
  Nợ có thể ghi trực tiếp giữa hai thành viên bất kỳ, không phải đi vòng qua người tạo phiên.
- **Gom công thức chia** về một hàm `computeShares` (`lib/core/money.dart`), dùng chung cho phần
  xem trước và lúc lưu, tránh lệch số.
- **Sửa lỗi nghiệp vụ**:
  - Đóng phiên 2 lần làm nợ bị cộng trùng → chặn trong transaction.
  - Guest bị đánh dấu "đã trả" khi đóng phiên → giữ nguyên trạng thái chờ.
  - Xác nhận thanh toán 2 lần → chỉ xác nhận được payment đang chờ.
  - Màn Chi tiết nợ không cập nhật sau khi trả xong, vẫn cho bấm "Tôi đã chuyển" → đọc nợ mới nhất,
    "Tôi đã chuyển" chạy trong transaction, từ chối khi hết nợ hoặc đang chờ xác nhận.
  - Đóng phiên kiểm tra tổng phần chia khớp tổng bill.
  - Màn chi tiết phiên hiện "(bạn)" sai (đánh dấu người tạo thay vì người đang xem), tên người tạo trống.
  - Phiên đã đóng không còn nút sửa/xoá (đã ghi nợ vào sổ).

### Chống gian lận (rules Firestore)
- `balance` của khoản nợ chỉ đổi được theo đúng 2 cách, mỗi cách gắn với một bản ghi bất biến:
  1. Đóng phiên → `debts/{id}/entries/{sessionId}`, `balance` đổi đúng bằng số tiền của entry.
  2. Xác nhận trả → `payments`, `balance` đổi đúng bằng số tiền của payment.
- Số tiền phiên/thành viên không âm, không vượt tổng bill; không sửa tiền sau khi tạo; không xoá nợ,
  không xoá phiên đã đóng; payment phải bằng đúng số đang nợ.
- Rules được kiểm thử bằng Firebase Emulator: **34 test** (`rules_test/`).

### QR và thanh toán
- **Xác thực ảnh QR nhận tiền**: phải có mã QR, đúng VietQR/NAPAS, CRC hợp lệ, ảnh ≤ 5MB
  (`lib/core/vietqr.dart`).
- **Mã VietQR động có sẵn số tiền và nội dung chuyển khoản**: dựng trên máy từ QR tĩnh của chủ nợ,
  không gọi API nào (sửa tag 01, thêm tag 54 và 62.08, tính lại CRC).
- **Lưu ảnh QR vào máy** (album "SplitPay"), khung nội dung chuyển khoản gợi ý
  ("[Tên bạn] tra tien [Tên chủ nợ]", không dấu, tối đa 25 ký tự).
- **Chia sẻ cho khách**: ảnh ghép QR (có sẵn số tiền) với câu nhắc, gửi qua Zalo/Messenger.
- **OCR hoá đơn** (ML Kit, trên máy): tìm số cạnh "Tổng cộng", loại tạm tính/tiền khách đưa/số điện thoại.
  Hiện chưa dùng nhiều, chỉ là tiện ích phụ.

### Khác
- Thêm quyền INTERNET vào manifest chính (trước đó chỉ bản debug có mạng).
- Sửa QR kết bạn không hiện (QrImageView trong AlertDialog → dùng QrPainter).

## Kiểm thử
- App: **48 test** (`flutter test test/core test/models`), gồm mô phỏng 5000 phiên ngẫu nhiên
  (số người 1–9, đều/tuỳ chỉnh, một/nhiều người ứng, có khách) và 200 nhóm × 100 phiên cộng dồn.
  Mỗi phiên kiểm tra: tổng chia = tổng bill, bảo toàn tiền, sổ nợ khớp vị thế từng người, trả xong về 0.
- Rules: `cd rules_test && npm install && npm test` (cần Java và Node).
- `test/widget_test.dart` lỗi khi nạp từ trước (chưa sửa).

## Thiết lập khi chạy máy mới
- `android/app/google-services.json` và `lib/firebase_options.dart` trỏ tới project Firebase riêng
  của từng người; **không commit bản riêng**. Local đã dùng
  `git update-index --assume-unchanged` cho hai file này.
- Thêm SHA-1 của máy vào Firebase (Project settings → app Android) để Google Sign-In chạy.
- **Publish `firestore.rules` lên Firebase** mỗi khi file đổi, app và rules phải đi đôi với nhau.
- Chạy flutter: thêm `<thư mục flutter>/bin` vào PATH.

## Còn thiếu so với tài liệu
- Ô nhập tên ngân hàng và số tài khoản trong hồ sơ (tuỳ chọn).
- OCR đa tiền tệ (hiện chỉ VND).
- Nhắc nợ: popup khi mở app, ảnh thiệp nhắc nợ vui kèm QR.
- iOS (chưa có thư mục `ios/`).
- Tài liệu ghi Firebase Storage nhưng code đang dùng Cloudinary.

## Hạn chế đã biết
- Không có Cloud Functions, nên người tạo phiên vẫn có thể ghi phần chia sai (tối đa bằng tổng bill)
  cho một thành viên trong phiên của mình; thành viên chỉ có thể tự xem lại, chưa có luồng phản đối.
- Trả nợ một phần chưa hỗ trợ (chỉ trả đủ số đang nợ).
