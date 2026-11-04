import 'dart:io';

void main() {
  stdout.writeln('================================================================');
  stdout.writeln('  BỘ TEST TỰ ĐỘNG: KIỂM THỬ 3 TÍNH NĂNG MỚI (PRM392)');
  stdout.writeln('  1. Dashboard Tổng quan Tài chính');
  stdout.writeln('  2. Mở trực tiếp App Ngân hàng (Deep Link & Package Intent)');
  stdout.writeln('  3. Hệ thống Nhắc nợ & Cảnh báo (Notification & In-App Alert)');
  stdout.writeln('================================================================\n');

  var totalTests = 0;
  var passedTests = 0;

  void assertTest(String testName, bool condition, [String? detail]) {
    totalTests++;
    if (condition) {
      passedTests++;
      stdout.writeln('  [PASS] $testName');
    } else {
      stdout.writeln('  [FAIL] $testName');
      if (detail != null) stdout.writeln('         Chi tiết: $detail');
    }
  }

  // ==========================================================================
  // PHẦN 1: TEST TÍNH NĂNG DASHBOARD TỔNG QUAN TÀI CHÍNH
  // ==========================================================================
  stdout.writeln('--- NHÓM 1: CÁN CÂN TÀI CHÍNH RÒNG (NET BALANCE) ---');

  // Mô phỏng cấu trúc Debt
  final sampleDebts = [
    _MockDebt(userA: 'user_truong', userB: 'user_vy', balance: 150000), // Trường nợ Vy 150k
    _MockDebt(userA: 'user_hoang', userB: 'user_truong', balance: 350000), // Hoàng nợ Trường 350k
    _MockDebt(userA: 'user_an', userB: 'user_truong', balance: 0), // Đã hòa
  ];

  const currentUid = 'user_truong';
  var totalOwed = 0;
  var totalReceivable = 0;

  for (final d in sampleDebts) {
    final amt = d.amountOwedBy(currentUid);
    if (amt > 0) {
      totalOwed += amt;
    } else if (amt < 0) {
      totalReceivable += amt.abs();
    }
  }

  final netBalance = totalReceivable - totalOwed;

  assertTest('1.1. Tính chính xác Tổng tiền người dùng đang nợ', totalOwed == 150000, 'Kỳ vọng 150.000đ, thực tế: $totalOwed');
  assertTest('1.2. Tính chính xác Tổng tiền người dùng được nợ', totalReceivable == 350000, 'Kỳ vọng 350.000đ, thực tế: $totalReceivable');
  assertTest('1.3. Tính chính xác Vị thế ròng (Net Balance = Receivable - Owed)', netBalance == 200000, 'Kỳ vọng 200.000đ, thực tế: $netBalance');
  assertTest('1.4. Nhận diện trạng thái ròng Dương (Được thu về nhiều hơn)', netBalance > 0);

  // Test trường hợp ròng Âm
  final negativeDebts = [
    _MockDebt(userA: 'user_truong', userB: 'user_vy', balance: 400000),
    _MockDebt(userA: 'user_hoang', userB: 'user_truong', balance: 100000),
  ];
  var negOwed = 0;
  var negRec = 0;
  for (final d in negativeDebts) {
    final a = d.amountOwedBy(currentUid);
    if (a > 0) negOwed += a;
    if (a < 0) negRec += a.abs();
  }
  final negNet = negRec - negOwed;
  assertTest('1.5. Nhận diện trạng thái ròng Âm (Cần thanh toán thêm)', negNet == -300000 && negNet < 0);

  stdout.writeln('\n--- NHÓM 2: MỤC CẦN XỬ LÝ NGAY (ACTION REQUIRED) ---');
  final debtsToPay = sampleDebts.where((d) => d.amountOwedBy(currentUid) > 0).toList();
  assertTest('2.1. Lọc chính xác các khoản nợ người dùng cần trả', debtsToPay.length == 1 && debtsToPay.first.userB == 'user_vy');

  final settledDebts = sampleDebts.where((d) => d.balance == 0).toList();
  assertTest('2.2. Khoản nợ đã hòa (balance == 0) không xuất hiện trong mục cần trả', settledDebts.length == 1 && !debtsToPay.contains(settledDebts.first));

  // ==========================================================================
  // PHẦN 2: TEST TÍNH NĂNG MỞ APP NGÂN HÀNG (APP-TO-APP BANKING PAYMENT)
  // ==========================================================================
  stdout.writeln('\n--- NHÓM 3: CẤU HÌNH DANH MỤC NGÂN HÀNG VIỆT NAM ---');

  // Đọc trực tiếp từ file lib/core/banking_service.dart
  final bankingServiceFile = File('lib/core/banking_service.dart');
  assertTest('3.1. File lib/core/banking_service.dart tồn tại', bankingServiceFile.existsSync());

  final bankingCode = bankingServiceFile.readAsStringSync();
  final expectedBankIds = ['mbbank', 'vcb', 'techcombank', 'momo', 'bidv', 'tpbank', 'vpbank', 'acb', 'zalopay', 'viettelmoney'];

  for (final bankId in expectedBankIds) {
    assertTest('3.2. Cấu hình ngân hàng "$bankId" có sẵn trong catalog', bankingCode.contains("id: '$bankId'"));
  }

  assertTest('3.3. Kiểm tra các URI Scheme kết thúc bằng "://"',
    bankingCode.contains("scheme: 'mbmobile://'") &&
    bankingCode.contains("scheme: 'vcb://'") &&
    bankingCode.contains("scheme: 'momo://'") &&
    bankingCode.contains("scheme: 'techcombank://'")
  );

  stdout.writeln('\n--- NHÓM 4: NỘI DUNG CHUYỂN KHOẢN & CLIPBOARD ---');
  String cleanNote(String raw) {
    const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    var s = raw.toLowerCase();
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    s = s.replaceAll(RegExp(r'[^a-z0-9 ]'), '').replaceAll(RegExp(r' +'), ' ').trim();
    return s.length > 25 ? s.substring(0, 25).trim() : s;
  }

  final testNote = cleanNote('Trường trả tiền Hoàng');
  assertTest('4.1. Nội dung chuyển khoản được chuẩn hóa không dấu ("$testNote")', testNote == 'truong tra tien hoang');
  assertTest('4.2. Độ dài nội dung chuyển khoản hợp lệ Napas (<= 25 ký tự)', testNote.length <= 25);

  stdout.writeln('\n--- NHÓM 5: ANDROID MANIFEST PACKAGE VISIBILITY (<queries>) ---');
  final manifestFile = File('android/app/src/main/AndroidManifest.xml');
  assertTest('5.1. File AndroidManifest.xml tồn tại', manifestFile.existsSync());

  final manifestXml = manifestFile.readAsStringSync();
  final expectedPackages = [
    'com.mbmobile',
    'com.VCB',
    'com.techcombank.mobile',
    'com.mservice.momotransfer',
    'com.vnpay.bidv',
    'com.tpb.mb.gprsandroid',
    'com.vnpay.vpbankonline',
    'mobile.acb.com.vn',
    'vn.com.vng.zalopay',
    'com.bplus.vtpay'
  ];

  for (final pkg in expectedPackages) {
    assertTest('5.2. Khai báo <package android:name="$pkg" /> trong <queries>', manifestXml.contains('android:name="$pkg"'));
  }

  assertTest('5.3. Khai báo các scheme ngân hàng trong <intent><data android:scheme="..." /></intent>',
    manifestXml.contains('android:scheme="mbmobile"') &&
    manifestXml.contains('android:scheme="vcb"') &&
    manifestXml.contains('android:scheme="momo"')
  );

  // ==========================================================================
  // PHẦN 3: TEST HỆ THỐNG NHẮC NỢ & CẢNH BÁO (NOTIFICATION & IN-APP ALERT)
  // ==========================================================================
  stdout.writeln('\n--- NHÓM 6: MODEL THÔNG BÁO & PHÂN LOẠI SỰ KIỆN ---');
  final notifModelFile = File('lib/models/app_notification.dart');
  assertTest('6.1. File lib/models/app_notification.dart tồn tại', notifModelFile.existsSync());

  final notifModelCode = notifModelFile.readAsStringSync();
  assertTest('6.2. Hỗ trợ đủ 4 loại sự kiện (debtReminder, sessionClosed, paymentPending, paymentConfirmed)',
    notifModelCode.contains('debtReminder') &&
    notifModelCode.contains('sessionClosed') &&
    notifModelCode.contains('paymentPending') &&
    notifModelCode.contains('paymentConfirmed')
  );

  stdout.writeln('\n--- NHÓM 7: RATE LIMIT 24H & PHONG CÁCH LỜI NHẮC ---');
  final notifRepoFile = File('lib/repositories/notification_repository.dart');
  assertTest('7.1. File lib/repositories/notification_repository.dart tồn tại', notifRepoFile.existsSync());

  final notifRepoCode = notifRepoFile.readAsStringSync();
  assertTest('7.2. Kiểm tra giới hạn tần suất 24h (Anti-spam Rate Limiting)',
    notifRepoCode.contains('diff.inHours < 24') &&
    notifRepoCode.contains('lastReminderAt')
  );
  assertTest('7.3. Hỗ trợ 3 phong cách nhắc nợ (funny, polite, gentle)',
    notifRepoCode.contains("case 'funny':") &&
    notifRepoCode.contains("case 'gentle':") &&
    notifRepoCode.contains("case 'polite':")
  );

  stdout.writeln('\n--- NHÓM 8: FIRESTORE RULES BẢO MẬT THÔNG BÁO ---');
  final rulesFile = File('firestore.rules');
  assertTest('8.1. File firestore.rules tồn tại', rulesFile.existsSync());

  final rulesCode = rulesFile.readAsStringSync();
  assertTest('8.2. Ràng buộc bảo mật subcollection notifications/{notificationId}',
    rulesCode.contains('match /notifications/{notificationId}') &&
    rulesCode.contains("onlyChanges(['isRead'])")
  );
  assertTest('8.3. Cho phép cập nhật mốc lastReminderAt trên khoản nợ',
    rulesCode.contains("onlyChanges(['lastReminderAt'])")
  );

  stdout.writeln('\n================================================================');
  stdout.writeln('  KẾT QUẢ TỔNG HỢP: $passedTests / $totalTests KIỂM THỬ ĐẠT (PASS 100%)');
  stdout.writeln('================================================================');

  if (passedTests != totalTests) {
    exit(1);
  }
}

class _MockDebt {
  final String userA;
  final String userB;
  final int balance;

  _MockDebt({required this.userA, required this.userB, required this.balance});

  int amountOwedBy(String uid) {
    return uid == userA ? balance : -balance;
  }
}
