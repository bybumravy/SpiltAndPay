# Cấu trúc code và tiêu chuẩn hiện tại

## Cấu trúc chính

| Đường dẫn | Trách nhiệm |
|---|---|
| `lib/main.dart`, `lib/app.dart` | Khởi tạo Firebase, Riverpod và điều phối auth/onboarding. |
| `lib/screens/` | Màn hình xác thực, phiên, công nợ, bạn bè và hồ sơ. |
| `lib/models/` | Model Firestore và `fromMap`/`toMap`. |
| `lib/repositories/` | Query, stream, batch và transaction Firestore. |
| `lib/core/money.dart` | Format VND và phân bổ phần chia. |
| `lib/core/settlement.dart` | Chuyển `amountPaid`/`amountOwed` thành vị thế ròng. |
| `lib/core/debt_simplify.dart` | Tối ưu lượt chuyển và fallback cho nhóm lớn. |
| `lib/core/bill_ocr.dart` | OCR hóa đơn và chọn tổng tiền. |
| `lib/core/vietqr.dart`, `vietqr_provider.dart` | Kiểm tra và tạo VietQR động. |
| `lib/core/image_tools.dart` | Tải, render, lưu và chia sẻ ảnh QR/thẻ thanh toán. |
| `lib/core/cloudinary_service.dart` | Upload ảnh QR lên Cloudinary. |
| `test/` | Unit/widget tests Flutter. |
| `rules_test/` | Firestore Rules tests bằng Node test runner. |

## Quy ước kiến trúc

- Dùng Riverpod để cấp dependency và stream dữ liệu.
- Widget điều phối tương tác; repository sở hữu truy cập Firestore; logic tiền thuần đặt trong `lib/core/`.
- Model dùng số nguyên VND và chuyển đổi rõ ràng giữa object với Firestore map.
- Ghi nhiều document liên quan dùng batch hoặc transaction; không cập nhật balance bằng các write rời rạc.
- Giữ tương thích dữ liệu cũ khi thêm field: ví dụ `amountPaid` vắng mặt được đọc là 0.
- Không đưa credential hoặc cấu hình riêng của developer vào code hay tài liệu.

## Bất biến tiền và công nợ

- Tổng phần chia phải bằng tổng bill; không dùng số thực cho tiền.
- Dữ liệu multi-payer mới phải có tổng `amountPaid == amountOwed`.
- `Debt.docId` luôn tạo từ hai UID đã sắp xếp.
- Chiều cập nhật balance phải dùng `Debt.balanceDelta` thay vì tự suy luận dấu ở UI.
- Mỗi lần đóng phiên tạo entry bất biến; mỗi lần giảm nợ phải đi qua payment được xác nhận.
- Không cho sửa trực tiếp amount của session member, entry, payment hoặc balance sau khi tạo.
- Guest không được tạo debt/payment cặp UID.

## UI và dịch vụ thiết bị

- OCR là gợi ý: luôn cho người dùng kiểm tra lại số tiền.
- VietQR phải được parse và kiểm tra CRC trước khi dùng để tạo mã động.
- Có fallback về ảnh QR tĩnh nếu không đọc được payload.
- `kDevMode` chỉ dành cho phát triển và phải là `false` trước khi phát hành.
- Xử lý bất đồng bộ phải kiểm tra `mounted` trước khi cập nhật UI sau `await`.

## Kiểm thử

Chạy test Flutter:

```sh
flutter test
```

Test hiện bao phủ phân bổ tiền, settlement, tối ưu nợ, luồng tiền ngẫu nhiên, OCR parsing, VietQR, image helpers và model session.

Chạy Firestore Rules tests sau khi cài dependency Node:

```sh
npm ci --prefix rules_test
npm test --prefix rules_test
```

Rules tests dùng Firebase Emulator để kiểm tra tạo/đóng/xóa session, quyền đọc, entry/balance, full-balance payment và xác nhận guest.

## Khi mở rộng

- Viết test thuần cho logic tiền trước khi nối vào widget/repository.
- Thay đổi schema phải cập nhật model, repository, Firestore Rules và rules tests cùng nhau.
- Không mô tả schema khoản chi chi tiết như đã tồn tại cho đến khi có model, persistence và UI thực tế.
- Chạy test hẹp trước, sau đó `flutter test` và rules tests khi thay đổi hợp đồng dữ liệu hoặc bảo mật.

## Tham chiếu

- [Kiến trúc hệ thống](system-architecture.md)
- [Thiết lập](setup.md)
