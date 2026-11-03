# Thiết kế: Khoản chi chi tiết trong phiên

## Ý định

Làm màn tạo phiên và chi tiết phiên dễ hiểu hơn theo mockup đã duyệt, đồng thời hỗ trợ ghi một hoặc nhiều khoản chi mà không làm hỏng cách tính/cộng dồn nợ hiện tại. Người dùng thao tác cùng một danh sách khoản và cùng nút **Thêm khoản chi**: chỉ thêm một khoản nếu chỉ có một bill đơn giản; thêm nhiều khoản nếu nhóm có nhiều lần ứng tiền hoặc nhiều nội dung chi. Nếu chỉ có một khoản, tổng khoản đó chính là tổng phiên.

## Trạng thái

Thiết kế nghiệp vụ đang chờ người dùng duyệt toàn văn trước khi lập kế hoạch và viết code. Người dùng đã chọn Cloud Function làm nơi tin cậy tính/kiểm tra hạch toán, và mặc định chọn tất cả thành viên hiện tại tham gia mỗi khoản. Code hiện tại chưa lưu khoản chi riêng.

## Quyết định đã chốt

- Tất cả phiên mới có thể nhập một hoặc nhiều khoản chi qua cùng UI, không có lựa chọn chế độ “tổng” đối lập với “chi tiết”. Một khoản đơn lẻ chính là tổng bill; nhiều khoản thì tổng phiên là tổng khoản.
- Mỗi khoản gồm mô tả, số tiền, người trả, và danh sách người tham gia chia.
- Mỗi khoản chia đều cho các thành viên được chọn; chưa yêu cầu chia tuỳ chỉnh theo tỷ lệ/số tiền.
- Người tạo phiên là người trả mặc định cho mỗi khoản; người tạo có thể đổi người trả riêng theo từng khoản.
- Có thể thêm tài khoản và guest vào phiên, và chọn guest tham gia từng khoản.
- Nếu người trả là tài khoản, ứng dụng ghi toàn bộ khoản vào số đã ứng thực tế của họ. Phần chia của tài khoản được cộng vào tổng phải chịu của người đó.
- Phần guest phải trả gắn với **người trả cụ thể của khoản**, không mặc định gắn với creator. Ví dụ nếu B trả khoản mà guest A cùng chia, guest A nợ B phần của họ; B tự xác nhận đã nhận trong sổ nợ/thu guest khi nhận tiền mặt hay chuyển khoản ngoài app.
- Khi tính nghĩa vụ giữa các tài khoản, trừ phần guest phải thu của từng payer khỏi số đã ứng ròng của payer; phần guest vẫn là một khoản phải thu riêng, không được chuyển thành nợ của creator nếu creator không phải payer. Như vậy sổ chuyển giữa account users chỉ cân bằng sau khi tách guest claims.
- Guest không có tài khoản/nút “Tôi đã chuyển”. Nghĩa vụ guest không được biến thành khoản creator hoặc tài khoản khác phải ứng/thanh toán thay.
- Các phần nợ giữa tài khoản được tổng hợp và đưa qua settlement hiện có; xác nhận thanh toán giữa tài khoản tiếp tục theo pending payment → chủ nợ xác nhận.
- Phiên cũ không có items tiếp tục đọc và chốt theo schema/logic cũ.
- Màn danh sách phiên và màn chi tiết được cải thiện theo mockup HTML đã duyệt.

## Mục tiêu

1. Tạo nhanh phiên với một khoản duy nhất nhưng không cần workflow/form riêng.
2. Hỗ trợ nhiều khoản, từng khoản có người trả riêng và tập người chia riêng.
3. Giữ chính xác mọi đồng VND khi chia đều và cộng tổng.
4. Phân biệt nghĩa vụ tài khoản với khoản phải thu guest, gắn guest phải thu đúng với người trả khoản.
5. Không thay đổi hành vi nợ cộng dồn và xác nhận trả nợ của các tài khoản.
6. Duy trì khả năng đọc/đóng phiên cũ.
7. Làm rõ tổng chi, khoản chi, người trả, người tham gia và tình trạng đã thu trong UI.

## Ngoài phạm vi

- Chia một khoản theo tỷ lệ hoặc nhập số tiền tuỳ chỉnh cho từng người.
- Thanh toán một phần giữa hai tài khoản.
- Guest đăng nhập hoặc tự xác nhận thanh toán trong ứng dụng.
- Nhắc nợ tự động, push notification.
- Thay thuật toán simplify/settlement nợ giữa các tài khoản.
- Dashboard chi tiêu tuần/tháng trong cùng phạm vi, trừ khi được yêu cầu bổ sung riêng.
- Chuyển toàn bộ UI app sang ForUI. ForUI hiện là dependency nhưng chưa dùng; builder đánh giá dùng component phù hợp ở vùng sửa đổi hay duy trì Material để không tạo inconsistency.

## Quy tắc nghiệp vụ

### Khoản chi và phân bổ

- `sessionTotal = sum(expense.amount)` cho phiên mới.
- Mỗi khoản phải có amount > 0, payer là member của phiên và có ít nhất một người tham gia.
- Tập người tham gia có thể gồm tài khoản hoặc guest. Khi thêm khoản mới, mặc định chọn tất cả thành viên hiện tại trong phiên; người dùng có thể bỏ chọn người không tham gia khoản đó. Nếu thay danh sách thành viên sau đó, không âm thầm thay đổi participants của các khoản đã tạo.
- Chia nguyên VND đều: `base = amount ~/ participantCount`; phần dư `remainder = amount % participantCount`. Phân bổ `base + 1` cho `remainder` thành viên theo thứ tự ổn định, còn lại `base`. Quy tắc thứ tự ổn định do builder chọn (ví dụ thứ tự thành viên phiên) và phải dùng chung cho preview, lưu và tính lại.
- Tổng các phần trên khoản phải bằng đúng amount. Tổng amount của items, tổng phần chia và tổng số tiền trả phải khớp ở toàn phiên.
- `amountPaid` theo thành viên = tổng amount khoản mà họ là payer tài khoản. Guest không được chọn làm payer trong phạm vi hiện tại.
- `amountOwed` theo thành viên = tổng share trên các khoản họ tham gia.

### Chốt nợ cho tài khoản và guest

- Nghĩa vụ mỗi tài khoản: tổng `amountPaid - amountOwed` có tính riêng các khoản guest phải trả cho tài khoản đó như khoản phải thu của payer.
- Phần guest share là khoản phải thu ngoài sổ debt giữa UID. Gắn nghĩa vụ guest với payer của item; payer là người có quyền/hiển thị action xác nhận đã thu.
- Không trừ phần guest khỏi creator nếu creator không phải payer của item; không đưa guest vào `settleSession` dưới dạng phải trả của creator.
- Với các khoản item chỉ có tài khoản tham gia, dùng đúng `settleSession` → `simplifyDebts`, ghi entries và cộng dồn balance cặp như hiện tại.
- Trước khi gọi `simplifyDebts`, tổng hợp net position theo từng UID account qua tất cả items; khấu trừ guest claims ở đúng payer của từng item. Không settle riêng từng khoản một cách có thể làm sai netting qua nhiều payer/items.
- Cần biểu diễn các khoản guest phải thu sao cho xác nhận đã thu là idempotent/auditable; không thay đổi balance cặp tài khoản khi guest xác nhận.
- Không đóng phiên nếu totals/participants/payers hoặc tổng tiền không hợp lệ.

### Trả nợ

- Tài khoản: giữ flow hiện tại — người nợ bấm đã chuyển cho số dư đầy đủ; chủ nợ xác nhận; transaction cập nhật payment và balance.
- Guest: không có payment action phía guest. Người payer/thu khoản guest đánh dấu đã nhận sau khi thực thu ngoài app. Dữ liệu xác nhận cần gắn đúng obligation, phiên/item và payer.
- Xử lý giao dịch tài khoản đang chờ xác nhận không thay đổi trong phạm vi này; điểm tồn tại của flow pending/balance đổi ở phiên khác cần được giữ nguyên hoặc nêu rõ cho người dùng nếu reviewer phát hiện regressions, không tự ý đổi public contract.

## Giao diện dự kiến

### Danh sách phiên

Theo mockup: chào người dùng/hồ sơ; bộ lọc tất cả/đang mở/đã đóng; card mỗi phiên với tên, trạng thái, số thành viên và tổng chi/số dư; nút tạo phiên; điều hướng hiện có được giữ phù hợp cấu trúc app. Chỉ xây các dữ liệu UI có thể lấy từ schema hiện tại/new schema; không giả dữ liệu thành viên/số dư.

### Tạo phiên

- Tên phiên và danh sách thành viên như flow hiện tại.
- Một danh sách khoản chi, ban đầu thuận tiện nhập một khoản.
- Mỗi item cho nhập mô tả/số tiền, chọn người trả (creator mặc định) và chọn người chia (mặc định tất cả thành viên hiện có; người tạo có thể bỏ chọn người không tham gia khoản đó). Người tạo thành viên mới về sau không tự động được thêm vào items đã tồn tại.
- Cùng nút **Thêm khoản chi** để thêm item; nút xoá/sửa từng item.
- Hiển thị tổng bill tự tính từ danh sách khoản và tổng tạm tính mỗi thành viên.
- OCR bill hiện tại điền số tiền vào khoản đang tạo/đang sửa, không tạo một luồng lưu tổng song song.
- Cách chia cũ `custom` không tự động áp cho items; nếu muốn tương thích workflow tổng hiện tại cho phiên mới, thiết kế một khoản sẽ chia đều như đã duyệt. Các phiên cũ giữ allocation đã lưu.

### Chi tiết phiên

- Header: tên, trạng thái, creator/ngày nếu sẵn có.
- Tổng chi và số thành viên.
- Danh sách khoản: mô tả, tổng tiền, payer, participants và phần share/thu guest cần thiết.
- Tab/sections “Khoản chi”, “Thành viên”, “Cân bằng” chỉ khi dữ liệu thật có thể hỗ trợ và không làm thay đổi semantics.
- Action thêm khoản chi và mời/thêm thành viên chỉ khi phiên còn mở, theo quyền hiện tại.
- Guest obligation hiển thị người payer nhận cần thu, số tiền và trạng thái chờ/đã thu; action xác nhận theo payer, trong sổ nợ/thu guest, không phải chỉ creator nếu payer khác. Obligations được tạo khi phiên đóng từ items cuối cùng.
- Đóng phiên vẫn chỉ creator như hiện tại, trước đó có bước xác nhận rõ rằng đóng sẽ tạo/cập nhật nợ.

## Kiến trúc / persistence

- Cloud Function là trusted authority để tính/kiểm tra tổng tiền, allocations, payer totals, guest obligations, settlement entries và ghi nhận đóng phiên. Client không tự quyết định debt entries/balance; không nới Firestore Rules để tin payload hạch toán từ client.
- Cần kiểm tra cấu hình Firebase Functions hiện hữu và lựa chọn triển khai tương thích dự án; nếu chưa có Functions, đây là phần mở rộng kiến trúc cần đưa vào plan và yêu cầu xác nhận chi phí/vận hành trước khi deploy.
- Có thể lưu items trong session doc/subcollection nhưng mọi operation phải bảo toàn quy tắc đóng phiên và idempotency.
- Cần lưu đủ snapshot/identity để xem guest và payer khi session mở/đóng.
- Guest collection obligation phải có identity ổn định, payer UID, guest member ID, item/session reference, amount, status/timestamps.
- Firestore Rules hiện giới hạn fields trên session/member và loại các collection chưa khai báo; cập nhật rules và emulator tests là bắt buộc nếu thêm collection/field. Rules chỉ cho phép quyền truy cập/thao tác phù hợp; Cloud Function chịu trách nhiệm tính toán cross-document và hạch toán.
- Guest obligations được tạo nguyên tử khi đóng phiên từ items cuối cùng đã lưu. Trước khi phiên đóng, item có thể thêm/sửa/xoá nhưng chưa phát sinh khoản thu guest chính thức. Sau khi đóng, items và obligations liên quan bất biến; chỉ action xác nhận đã thu theo đúng payer được cập nhật trạng thái, idempotent và audit được.
- Phiên legacy không có items phải phân nhánh đọc/chốt rõ ràng, tránh tự coi tổng cũ là item đã persist nếu không có migration.

## Các touchpoint dự kiến

- UI: `lib/screens/session/create_session_screen.dart`, `lib/screens/session/session_detail_screen.dart`, `lib/screens/home/sessions_tab.dart`, có thể `lib/screens/home/debts_tab.dart`/`lib/screens/debt/debt_detail_screen.dart` cho guest obligation.
- Model: `lib/models/session.dart`, `lib/models/session_member.dart`, thêm expense/guest-obligation model theo boundary phù hợp.
- Persistence: `lib/repositories/session_repository.dart`, có thể `lib/repositories/debt_repository.dart` hoặc repository obligation riêng.
- Pure logic: `lib/core/money.dart`, `lib/core/settlement.dart`, có thể helper mới cho item allocation/aggregate.
- Security: `firestore.rules` và `rules_test/`.
- Tests: unit tests cho rounding/aggregation/guest debt/settlement/legacy, repository/rules tests, UI tests theo patterns có sẵn.
- Docs: cập nhật các tài liệu dự án sau khi code thật được triển khai; tài liệu này là approved design.

## Tiêu chí chấp nhận

1. Tạo phiên bằng một item cho tổng bill; tổng phiên bằng khoản duy nhất.
2. Thêm nhiều items bằng cùng nút; tổng = tổng các item.
3. Mỗi item có payer riêng; payer mặc định creator; chọn member khác cập nhật amountPaid đúng.
4. Có thể chọn nhiều account/guest làm participants; chia đều và làm tròn chính xác.
5. `amountOwed` cho từng người khớp đúng items họ được chọn; tổng chia = tổng phiên.
6. Guest share tạo obligation phải thu gắn với payer item; nếu payer là B thì guest nợ B, không tự chuyển sang creator.
7. Payer xác nhận guest đã trả sau khi thực nhận; không tạo hoặc đổi account-pair balance; thao tác lặp không ghi nhận hai lần.
8. Account-user transfers từ settlement giữ nguyên đúng số tiền, idempotency, transaction/rules; balance nợ cộng dồn qua nhiều phiên không sai.
9. Phiên cũ không có items vẫn mở, đọc, đóng và settle như trước.
10. App cập nhật hiển thị đúng list/detail mockup, loading/error/empty state và quyền mở/đóng.
11. Firestore Rules và tests không cho client tuỳ ý thay amount/balance/paid status trái quy tắc.
12. Flutter analyze/test và rules tests liên quan pass; các baseline failures hiện có phải được tách biệt và báo chính xác.

## Còn để người dùng duyệt

- Toàn bộ đặc tả, đặc biệt trusted Cloud Function cho hạch toán, nghĩa vụ guest nợ payer của từng khoản (không tham gia balance cặp tài khoản), mặc định tất cả thành viên tham gia, và thời điểm tạo obligations khi đóng phiên.
- Việc triển khai/deploy Cloud Functions có thể phát sinh chi phí Firebase và yêu cầu cấu hình dự án; cần xác nhận trước khi deploy hoặc bật dịch vụ có tính phí.
