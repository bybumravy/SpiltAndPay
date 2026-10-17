import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/core/money.dart';
import 'package:splitpay/core/settlement.dart';
import 'package:splitpay/models/debt.dart';
import 'package:splitpay/models/session_member.dart';

void main() {
  group('computeShares', () {
    test('chia đều: tổng đúng, dư về người tạo', () {
      expect(computeShares(total: 100000, customAmounts: [null, null], custom: false),
          [33334, 33333, 33333]);
    });

    test('tuỳ chỉnh: ai nhập giữ nguyên, còn lại chia đều phần dư', () {
      // bill 500k, Nam nhập 200k, 2 người còn lại + người tạo chia 300k.
      expect(
        computeShares(total: 500000, customAmounts: [200000, null, null], custom: true),
        [100000, 200000, 100000, 100000],
      );
    });

    test('tuỳ chỉnh dùng hết bill: người chưa nhập = 0', () {
      expect(computeShares(total: 300000, customAmounts: [300000, null], custom: true),
          [0, 300000, 0]);
    });

    test('nhập vượt bill → lỗi', () {
      expect(() => computeShares(total: 100, customAmounts: [200], custom: true),
          throwsArgumentError);
    });
  });

  // Mô phỏng toàn bộ đường đi của tiền: chia → ứng → chốt nợ → sổ nợ → trả hết.
  // uid được sinh ngẫu nhiên nên người tạo có thể có uid nhỏ HOẶC lớn hơn người khác
  // (ảnh hưởng chiều userA/userB trong sổ nợ).
  test('ngẫu nhiên 5000 phiên: tiền luôn bảo toàn, sổ nợ khớp, trả xong về 0', () {
    final rnd = Random(2026);
    final stats = <String, int>{};
    void count(String k) => stats[k] = (stats[k] ?? 0) + 1;

    for (var trial = 0; trial < 5000; trial++) {
      final nApp = rnd.nextInt(6); // thành viên có app NGOÀI người tạo: 0..5
      final nGuest = rnd.nextInt(4); // khách: 0..3
      final total = switch (rnd.nextInt(4)) {
        0 => 1000, // bill nhỏ nhất
        1 => (1 + rnd.nextInt(50)) * 1000,
        2 => (1 + rnd.nextInt(2000)) * 1000 + rnd.nextInt(3) * 111, // số lẻ
        _ => 1 + rnd.nextInt(5000000), // số bất kỳ
      };
      final custom = rnd.nextBool();
      final multiPayer = rnd.nextBool();

      // uid ngẫu nhiên, không trùng; ids[0] là người tạo.
      final used = <String>{};
      String uid() {
        while (true) {
          final v = String.fromCharCodes(List.generate(3, (_) => 97 + rnd.nextInt(26)));
          if (used.add(v)) return v;
        }
      }

      final creator = uid();
      final apps = [for (var i = 0; i < nApp; i++) uid()];
      final appIds = [creator, ...apps];
      count('người: ${1 + nApp + nGuest}');
      count(custom ? 'chia tuỳ chỉnh' : 'chia đều');
      count(multiPayer ? 'nhiều người ứng' : 'một người ứng (người tạo)');
      if (nGuest > 0) count('có khách');
      if (nApp == 0) count('chỉ người tạo + khách');
      if (apps.any((a) => a.compareTo(creator) < 0)) count('có uid nhỏ hơn người tạo');
      if (apps.any((a) => a.compareTo(creator) > 0)) count('có uid lớn hơn người tạo');

      // Số nhập tay (chỉ khi tuỳ chỉnh), không vượt bill.
      final customAmounts = List<int?>.filled(nApp + nGuest, null);
      if (custom) {
        var left = total;
        for (var i = 0; i < customAmounts.length; i++) {
          if (rnd.nextBool()) {
            final v = switch (rnd.nextInt(3)) {
              0 => 0,
              1 => left, // dùng hết phần còn lại
              _ => rnd.nextInt(left + 1),
            };
            customAmounts[i] = v;
            left -= v;
          }
        }
        if (left == 0 && customAmounts.contains(null)) count('tuỳ chỉnh dùng hết bill, còn người chưa nhập');
        if (customAmounts.every((v) => v != null)) count('tuỳ chỉnh: ai cũng nhập (người tạo nhận phần dư)');
        if (customAmounts.contains(0)) count('có người nhập 0đ');
      }

      final shares =
          computeShares(total: total, customAmounts: customAmounts, custom: custom);
      expect(shares.fold<int>(0, (s, v) => s + v), total, reason: 'tổng chia');
      expect(shares.every((v) => v >= 0), isTrue);
      if (custom) {
        for (var i = 0; i < customAmounts.length; i++) {
          if (customAmounts[i] != null) expect(shares[i + 1], customAmounts[i]);
        }
      }

      // Ai ứng bao nhiêu (chỉ người có app).
      final paid = <String, int>{};
      var othersPaid = 0;
      if (multiPayer) {
        for (final a in apps) {
          final v = switch (rnd.nextInt(4)) {
            0 => 0,
            1 => total - othersPaid, // ứng hết phần còn lại
            _ => rnd.nextInt(total - othersPaid + 1),
          };
          paid[a] = v;
          othersPaid += v;
        }
      }
      paid[creator] = total - othersPaid;
      if (multiPayer && apps.isNotEmpty) {
        if (paid[creator] == 0) count('người tạo ứng 0đ');
        if (apps.where((a) => (paid[a] ?? 0) > 0).length >= 2) count('từ 2 người khác cùng ứng');
        if (apps.every((a) => (paid[a] ?? 0) > 0)) count('mọi thành viên đều ứng');
      }

      final members = <SessionMember>[
        SessionMember(
          memberId: creator, userId: creator, displayName: 'c', isGuest: false,
          amountOwed: shares[0], amountPaid: paid[creator]!, status: MemberStatus.self,
        ),
        for (var i = 0; i < nApp + nGuest; i++)
          if (i < nApp)
            SessionMember(
              memberId: apps[i], userId: apps[i], displayName: 'm',
              isGuest: false, amountOwed: shares[i + 1],
              amountPaid: paid[apps[i]] ?? 0, status: MemberStatus.ledger,
            )
          else
            SessionMember(
              memberId: 'G${i - nApp + 1}', userId: null, displayName: 'G',
              isGuest: true, amountOwed: shares[i + 1], status: MemberStatus.pending,
            ),
      ];

      final transfers = settleSession(creatorId: creator, members: members);
      count('số lần chuyển: ${transfers.length}');

      // Vị thế kỳ vọng của từng người có app (dương = được nhận).
      final guestOwed = members.where((m) => m.isGuest).fold<int>(0, (s, m) => s + m.amountOwed);
      final expected = <String, int>{
        for (final id in appIds)
          id: (paid[id] ?? 0) - members.firstWhere((m) => m.userId == id).amountOwed,
      };
      expected[creator] = expected[creator]! - guestOwed; // người tạo gánh phần khách

      // Ghi vào sổ nợ như closeSession: mỗi cặp một document balance.
      final balances = <String, int>{}; // docId → balance
      for (final t in transfers) {
        expect(t.amount, greaterThan(0));
        expect(t.from, isNot(t.to));
        final id = Debt.docId(t.from, t.to);
        balances[id] = (balances[id] ?? 0) +
            Debt.balanceDelta(debtorUid: t.from, creditorUid: t.to, amount: t.amount);
        if (t.from == creator) count('người tạo phải trả lại cho thành viên');
      }
      Debt debtOf(String id) {
        final parts = id.split('_');
        return Debt(userA: parts[0], userB: parts[1], balance: balances[id]!, updatedAt: DateTime(2026));
      }

      // Vị thế của mỗi người suy ra từ sổ nợ phải khớp kỳ vọng.
      for (final id in appIds) {
        var position = 0;
        for (final e in balances.entries) {
          final d = debtOf(e.key);
          if (d.userA == id || d.userB == id) position -= d.amountOwedBy(id);
        }
        expect(position, expected[id], reason: 'vị thế $id, trial $trial');
      }
      expect(expected.values.fold<int>(0, (s, v) => s + v), 0, reason: 'bảo toàn tiền');

      // Số lần chuyển không vượt (số người còn dư - 1).
      final nonZero = expected.values.where((v) => v != 0).length;
      expect(transfers.length, lessThanOrEqualTo(max(0, nonZero - 1)));

      // Trả hết: mỗi bên trả đúng số nợ → mọi sổ về 0.
      for (final e in balances.entries.toList()) {
        final d = debtOf(e.key);
        final debtor = d.balance > 0 ? d.userA : d.userB;
        final amount = d.balance.abs();
        final debtorIsA = debtor == d.userA;
        balances[e.key] = e.value + (debtorIsA ? -amount : amount);
      }
      expect(balances.values.every((v) => v == 0), isTrue, reason: 'trả hết về 0');
    }

    final keys = stats.keys.toList()..sort();
    // ignore: avoid_print
    print('\n=== Thống kê 5000 phiên ===\n${keys.map((k) => '${stats[k].toString().padLeft(5)}  $k').join('\n')}');
  });

  // Cộng dồn nhiều phiên giữa cùng một nhóm: sổ nợ từng cặp phải luôn khớp
  // tổng vị thế của mỗi người qua tất cả các phiên.
  test('cộng dồn 100 phiên liên tiếp trong cùng nhóm (người tạo thay đổi)', () {
    final rnd = Random(77);
    for (var round = 0; round < 200; round++) {
      final used = <String>{};
      String uid() {
        while (true) {
          final v = String.fromCharCodes(List.generate(3, (_) => 97 + rnd.nextInt(26)));
          if (used.add(v)) return v;
        }
      }

      final group = [for (var i = 0; i < 2 + rnd.nextInt(5); i++) uid()];
      final balances = <String, int>{};
      final position = {for (final g in group) g: 0}; // vị thế cộng dồn kỳ vọng

      for (var session = 0; session < 100; session++) {
        final creator = group[rnd.nextInt(group.length)];
        final others = group.where((g) => g != creator).toList();
        final total = (1 + rnd.nextInt(3000)) * 1000 + rnd.nextInt(2) * 357;
        final custom = rnd.nextBool();

        final customAmounts = List<int?>.filled(others.length, null);
        if (custom) {
          var left = total;
          for (var i = 0; i < others.length; i++) {
            if (rnd.nextBool()) {
              final v = rnd.nextInt(left + 1);
              customAmounts[i] = v;
              left -= v;
            }
          }
        }
        final shares = computeShares(total: total, customAmounts: customAmounts, custom: custom);

        final paid = <String, int>{};
        var othersPaid = 0;
        if (rnd.nextBool()) {
          for (final o in others) {
            final v = rnd.nextBool() ? rnd.nextInt(total - othersPaid + 1) : 0;
            paid[o] = v;
            othersPaid += v;
          }
        }
        paid[creator] = total - othersPaid;

        final members = [
          SessionMember(
            memberId: creator, userId: creator, displayName: 'c', isGuest: false,
            amountOwed: shares[0], amountPaid: paid[creator]!, status: MemberStatus.self,
          ),
          for (var i = 0; i < others.length; i++)
            SessionMember(
              memberId: others[i], userId: others[i], displayName: 'm', isGuest: false,
              amountOwed: shares[i + 1], amountPaid: paid[others[i]] ?? 0,
              status: MemberStatus.ledger,
            ),
        ];
        position[creator] = position[creator]! + paid[creator]! - shares[0];
        for (var i = 0; i < others.length; i++) {
          position[others[i]] = position[others[i]]! + (paid[others[i]] ?? 0) - shares[i + 1];
        }

        for (final t in settleSession(creatorId: creator, members: members)) {
          final id = Debt.docId(t.from, t.to);
          balances[id] = (balances[id] ?? 0) +
              Debt.balanceDelta(debtorUid: t.from, creditorUid: t.to, amount: t.amount);
        }
      }

      // Vị thế mỗi người đọc từ sổ nợ phải bằng vị thế cộng dồn.
      for (final g in group) {
        var fromLedger = 0;
        balances.forEach((id, bal) {
          final parts = id.split('_');
          final d = Debt(userA: parts[0], userB: parts[1], balance: bal, updatedAt: DateTime(2026));
          if (d.userA == g || d.userB == g) fromLedger -= d.amountOwedBy(g);
        });
        expect(fromLedger, position[g], reason: 'round $round, người $g');
      }
      expect(position.values.fold<int>(0, (s, v) => s + v), 0);
    }
  });
}
