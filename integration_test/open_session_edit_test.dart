import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:splitpay/models/debt.dart';
import 'package:splitpay/models/session.dart';
import 'package:splitpay/models/session_member.dart';
import 'package:splitpay/repositories/debt_repository.dart';
import 'package:splitpay/repositories/guest_obligation_repository.dart';
import 'package:splitpay/repositories/session_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'edit all fields then close settle collect; stale and closed edits fail',
    (tester) async {
      // Named demo app + emulator endpoints: never connect this test to live data.
      final app = await Firebase.initializeApp(
        name: 'session-edit-test',
        options: const FirebaseOptions(
          apiKey: 'fake-api-key',
          appId: '1:123:android:abc',
          messagingSenderId: '123',
          projectId: 'demo-splitpay-edit',
        ),
      );
      final auth = FirebaseAuth.instanceFor(app: app);
      final db = FirebaseFirestore.instanceFor(app: app);
      db.settings = const Settings(persistenceEnabled: false);
      db.useFirestoreEmulator('10.0.2.2', 8080);
      await auth.useAuthEmulator('10.0.2.2', 9099);
      final suffix = DateTime.now().microsecondsSinceEpoch;
      Future<String> register(String name) async =>
          (await auth.createUserWithEmailAndPassword(
            email: '$name-$suffix@example.com',
            password: 'test-password',
          )).user!.uid;
      final a = await register('a');
      final b = await register('b');
      final c = await register('c');
      await auth.signInWithEmailAndPassword(
        email: 'a-$suffix@example.com',
        password: 'test-password',
      );
      final repo = SessionRepository(db, auth);
      final id = 'edit-$suffix';
      SessionMember member(String uid, {bool guest = false}) => SessionMember(
        memberId: uid,
        userId: guest ? null : uid,
        displayName: uid,
        isGuest: guest,
        amountOwed: 0,
        status: guest ? MemberStatus.pending : MemberStatus.ledger,
      );
      final original = Session(
        sessionId: id,
        creatorId: a,
        title: 'Original',
        totalAmount: 120000,
        splitMode: SessionSplitMode.equal,
        status: SessionStatus.open,
        memberUserIds: [a, b],
        createdAt: DateTime.now(),
      );
      ExpenseInput expense(
        String itemId,
        int amount,
        String payer,
        List<String> people,
      ) => ExpenseInput(
        expenseId: itemId,
        description: itemId,
        amount: amount,
        payerId: payer,
        participantIds: people,
      );
      await repo.createSessionWithExpenses(
        session: original,
        members: [member(a), member(b)],
        expenses: [
          expense('meal', 120000, a, [a, b]),
        ],
      );
      await repo.updateExpense(
        sessionId: id,
        expenseId: 'meal',
        expense: expense('meal', 240000, b, [a, b]),
      );
      var members = await repo.watchSessionMembers(id).first;
      expect(members.firstWhere((m) => m.memberId == b).amountPaid, 240000);
      expect(members.firstWhere((m) => m.memberId == a).amountOwed, 120000);
      await repo.addExpense(
        sessionId: id,
        expense: expense('taxi', 60000, a, [a, b]),
      );
      await repo.deleteExpense(sessionId: id, expenseId: 'taxi');
      final before = Session.fromMap(
        id,
        (await db.doc('sessions/$id').get()).data()!,
      );
      members = await repo.watchSessionMembers(id).first;
      final items = await repo.watchSessionExpenses(id).first;
      final editedItems = [
        expense('meal', 100001, c, [a, c, 'guest']),
      ];
      await repo.saveOpenSession(
        originalSession: before,
        originalMembers: members,
        originalExpenses: items,
        title: 'Edited',
        members: [member(a), member(c), member('guest', guest: true)],
        expenses: editedItems,
      );
      expect(
        (await db.doc('sessions/$id').get()).data()!['totalAmount'],
        100001,
      );
      expect((await db.doc('sessions/$id/members/$b').get()).exists, false);
      final current = Session.fromMap(
        id,
        (await db.doc('sessions/$id').get()).data()!,
      );
      final currentMembers = await repo.watchSessionMembers(id).first;
      final currentItems = await repo.watchSessionExpenses(id).first;
      expect(current.memberUserIds.toSet(), {a, c});
      expect(
        currentMembers.firstWhere((m) => m.memberId == c).amountPaid,
        100001,
      );
      await expectLater(
        repo.saveOpenSession(
          originalSession: before,
          originalMembers: members,
          originalExpenses: items,
          title: 'Stale',
          members: [member(a), member(c), member('guest', guest: true)],
          expenses: editedItems,
        ),
        throwsStateError,
      );
      await auth.signInWithEmailAndPassword(
        email: 'b-$suffix@example.com',
        password: 'test-password',
      );
      await expectLater(
        db.doc('sessions/$id').get(const GetOptions(source: Source.server)),
        throwsA(isA<FirebaseException>()),
      );
      await auth.signInWithEmailAndPassword(
        email: 'a-$suffix@example.com',
        password: 'test-password',
      );
      await repo.closeSession(
        sessionId: id,
        creatorId: a,
        members: currentMembers,
      );
      await expectLater(
        repo.saveOpenSession(
          originalSession: current,
          originalMembers: currentMembers,
          originalExpenses: currentItems,
          title: 'Closed edit',
          members: currentMembers,
          expenses: editedItems,
        ),
        throwsStateError,
      );
      final debtId = Debt.docId(a, c);
      final debt = (await db.doc('debts/$debtId').get()).data()!;
      expect((debt['balance'] as num).abs(), 33334);
      final payments = DebtRepository(db);
      await payments.markTransferred(
        debtId: debtId,
        fromUid: a,
        toUid: c,
        paymentId: 'P1',
      );
      final pendingSession = 'pending-$suffix';
      await repo.createSessionWithExpenses(
        session: Session(
          sessionId: pendingSession,
          creatorId: a,
          title: 'Pending pair',
          totalAmount: 100,
          splitMode: SessionSplitMode.equal,
          status: SessionStatus.open,
          memberUserIds: [a, c],
          createdAt: DateTime.now(),
        ),
        members: [member(a), member(c)],
        expenses: [
          expense('new-item', 100, c, [a]),
        ],
      );
      await expectLater(
        repo.closeSession(
          sessionId: pendingSession,
          creatorId: a,
          members: await repo.watchSessionMembers(pendingSession).first,
        ),
        throwsA(isA<FirebaseException>()),
      );
      expect(
        (await db.doc('sessions/$pendingSession').get()).data()!['status'],
        'open',
      );
      expect(
        (await db.doc('debts/$debtId/entries/$pendingSession').get()).exists,
        false,
      );
      await auth.signInWithEmailAndPassword(
        email: 'c-$suffix@example.com',
        password: 'test-password',
      );
      await payments.confirmPayment(
        debtId: debtId,
        paymentId: 'P1',
        debtorIsUserA: debt['userA'] == a,
      );
      expect((await db.doc('debts/$debtId').get()).data()!['balance'], 0);
      await GuestObligationRepository(
        db,
        auth,
      ).markCollected(sessionId: id, obligationId: 'meal_guest');
      expect(
        (await db.doc('sessions/$id/guestObligations/meal_guest').get())
            .data()!['status'],
        'collected',
      );
      // Creator is not a debtor/creditor: close both new and existing pair debts.
      final otherDebt = Debt.docId(b, c);
      for (var round = 0; round < 2; round++) {
        await auth.signInWithEmailAndPassword(
          email: 'a-$suffix@example.com',
          password: 'test-password',
        );
        final otherId = 'third-party-$suffix-$round';
        await repo.createSessionWithExpenses(
          session: Session(
            sessionId: otherId,
            creatorId: a,
            title: 'Other pair',
            totalAmount: 100,
            splitMode: SessionSplitMode.equal,
            status: SessionStatus.open,
            memberUserIds: [a, b, c],
            createdAt: DateTime.now(),
          ),
          members: [member(a), member(b), member(c)],
          expenses: [
            expense('paid-by-c', 100, c, [b]),
          ],
        );
        await repo.closeSession(
          sessionId: otherId,
          creatorId: a,
          members: await repo.watchSessionMembers(otherId).first,
        );
        await expectLater(
          db
              .doc('debts/$otherDebt')
              .get(const GetOptions(source: Source.server)),
          throwsA(isA<FirebaseException>()),
        );
      }
      await auth.signInWithEmailAndPassword(
        email: 'c-$suffix@example.com',
        password: 'test-password',
      );
      expect(
        ((await db.doc('debts/$otherDebt').get()).data()!['balance'] as num)
            .abs(),
        200,
      );
      await auth.signOut();
      await app.delete();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
