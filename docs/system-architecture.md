# Kiến trúc và logic công nợ

## Thành phần runtime

`lib/main.dart` khởi tạo Firebase rồi chạy ứng dụng Flutter trong Riverpod `ProviderScope`. Firebase Auth và Firestore được cung cấp qua `lib/core/firebase_providers.dart`. Màn hình gọi repository để đọc/ghi dữ liệu; model chuyển đổi dữ liệu Firestore qua `fromMap`/`toMap`.

## Dữ liệu phiên hiện tại

`Session` lưu creator, tên phiên, một `totalAmount`, chế độ chia, trạng thái, danh sách UID thành viên có tài khoản và thời gian. Thành viên lưu `amountOwed`, `amountPaid`, guest/account identity và trạng thái. Code hiện tại chưa có model hay persistence cho từng khoản chi.

Màn tạo phiên hiện hỗ trợ chia đều hoặc chia tuỳ chỉnh; nhiều thành viên có tài khoản có thể được ghi nhận là đã ứng tiền. Có thể thêm guest, nhưng UI hiện tại không cho guest làm người ứng tiền. Chia đều dùng `computeShares`; phần dư đồng được cộng vào phần người tạo.

## Đóng phiên và cộng dồn nợ

`SessionRepository.closeSession` dùng Firestore transaction để ngăn đóng phiên lặp lại và kiểm tra tổng `amountOwed` đúng bằng bill. Sau đó gọi `settleSession`, ghi từng lượt chuyển thành entry bất biến theo phiên, cộng/trừ vào balance của cặp UID, đóng phiên và cập nhật trạng thái thành viên.

`settleSession` tính vị thế ròng: `amountPaid - amountOwed`. Giá trị dương nghĩa là được nhận; âm nghĩa là phải trả. Phiên cũ không có `amountPaid` (tổng bằng 0) được coi là creator đã ứng toàn bộ. Guest không vào sổ nợ tài khoản; phần guest phải trả được trừ khỏi vị thế ròng của creator, người này tự thu guest ở ngoài.

`simplifyDebts` tìm số lượt chuyển tối thiểu bằng subset dynamic programming cho tối đa 18 người có số dư khác 0. Với nhóm lớn hơn, dùng greedy; tiền vẫn cân bằng nhưng số lượt không đảm bảo tối thiểu.

Balance của mỗi cặp được lưu cộng dồn trong `debts/{id}` với ID từ hai UID đã sắp xếp. Số dư dương nghĩa userA nợ userB; âm là userB nợ userA. Mỗi phiên đóng thêm một entry trong `entries/{sessionId}`; khoản trả được xác nhận sẽ cập nhật balance theo payment. Đây là bù trừ nợ ròng theo từng cặp qua nhiều phiên.

## Trả nợ hiện tại

Thành viên có tài khoản bấm “Tôi đã chuyển”; repository kiểm tra trong transaction rằng họ còn nợ và chưa có payment chờ, rồi tạo payment `pending` cho toàn bộ số nợ hiện tại. Chủ nợ xác nhận payment đang chờ; transaction đánh dấu payment `confirmed` và giảm balance đúng số payment. Trả một phần chưa được hỗ trợ qua luồng này.

Guest được người tạo theo dõi trong phiên. Hiện người tạo có thể nhắc guest qua QR/chia sẻ và tự đánh dấu “Đã thu” trong chi tiết phiên; guest không tạo payment hoặc nợ tài khoản.

## Firestore và giới hạn tin cậy

`firestore.rules` kiểm soát quyền truy cập và các thay đổi balance: cộng nợ phải khớp entry mới của phiên; xác nhận trả phải khớp payment đang chờ. Rules yêu cầu payment bằng đúng số đang nợ và các entry/payment bất biến về số tiền. Theo `NOTES.md`, dự án chưa có Cloud Functions tự tính lại phần chia phía server; không nên xem phân bổ do client gửi là phép tính đã được máy chủ xác minh độc lập.

## Logic đã duyệt cho tương lai: khoản chi chi tiết (chưa triển khai)

Đây là mục tiêu sản phẩm đã được người dùng duyệt, không phải hành vi code hiện tại:

- Khi tạo phiên, người dùng chọn một trong hai cách: chỉ nhập tổng bill (không cần nhập từng khoản), hoặc lưu nhiều khoản chi tiết. Với phiên chi tiết, mỗi khoản có mô tả, số tiền, người trả và người tham gia.
- Người tạo phiên là người trả mặc định cho từng khoản; có thể chọn người trả khác riêng cho mỗi khoản.
- Chỉ có chia đều cho những người tham gia được chọn. Phần dư đồng phải được phân bổ chính xác sao cho tổng phần chia bằng đúng số tiền khoản.
- Guest có thể tham gia chia khoản chi như thành viên khác. Phần guest phải trả được hiển thị như một khoản cần thu trong sổ nợ của người tạo phiên. Guest không có tài khoản/nút “Tôi đã chuyển”; khi người tạo thực nhận tiền mặt hoặc khoản chuyển riêng bên ngoài ứng dụng, người tạo tự xác nhận đã nhận ngay trong sổ nợ. Việc xác nhận này đánh dấu nghĩa vụ guest đã thu, không tạo payment hoặc balance cộng dồn giữa hai UID tài khoản.
- Chế độ chỉ nhập tổng bill: cho phép nhập tổng mà không khai báo từng khoản; vẫn dùng phân bổ thành viên để xác định `amountPaid`/`amountOwed` và chốt phiên theo flow tương thích hiện tại.
- Chế độ chi tiết: cộng dồn từ các khoản thành tổng `amountPaid` và `amountOwed` theo thành viên; tổng tiền và tổng phần chia phải khớp. Sau đó dùng lại `settleSession`, `simplifyDebts` và cơ chế cộng dồn balance cặp hiện tại.
- Tài khoản có app tiếp tục dùng luồng “Tôi đã chuyển” → chủ nợ xác nhận.
- Phiên cũ chỉ có tổng tiền/phần chia tiếp tục đọc và chốt được như trước.

Trước khi triển khai persistence mới, cần cập nhật Firestore Rules và kiểm thử đồng bộ với schema mới; không được nới quyền cho client ghi tuỳ ý vào khoản nợ.
