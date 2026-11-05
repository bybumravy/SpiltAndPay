import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/models/expense.dart';
import 'package:splitpay/models/session.dart';
import 'package:splitpay/models/session_member.dart';
import 'package:splitpay/repositories/guest_obligation_repository.dart';
import 'package:splitpay/repositories/guest_receivables_provider.dart';
import 'package:splitpay/repositories/session_repository.dart';

void main() {
  test(
    'only closed sessions and actual payer contribute guest receivables',
    () async {
      final container = ProviderContainer(
        overrides: [
          userSessionsProvider('payer').overrideWith(
            (ref) => Stream.value([
              for (final status in SessionStatus.values)
                Session(
                  sessionId: status.name,
                  creatorId: 'creator',
                  title: status.name,
                  totalAmount: 600,
                  splitMode: SessionSplitMode.equal,
                  status: status,
                  memberUserIds: ['payer', 'creator'],
                  createdAt: DateTime(2026),
                ),
            ]),
          ),
          sessionMembersProvider('closed').overrideWith(
            (ref) => Stream.value([
              const SessionMember(
                memberId: 'guest',
                userId: null,
                displayName: 'Khách An',
                isGuest: true,
                amountOwed: 600,
                status: MemberStatus.pending,
              ),
            ]),
          ),
          sessionGuestObligationsProvider('closed').overrideWith(
            (ref) => Stream.value([
              const GuestObligation(
                obligationId: 'mine',
                sessionId: 'closed',
                payerId: 'payer',
                guestMemberId: 'guest',
                amount: 100,
              ),
              const GuestObligation(
                obligationId: 'other',
                sessionId: 'closed',
                payerId: 'creator',
                guestMemberId: 'guest',
                amount: 200,
              ),
              const GuestObligation(
                obligationId: 'collected',
                sessionId: 'closed',
                payerId: 'payer',
                guestMemberId: 'guest',
                amount: 300,
                status: GuestObligationStatus.collected,
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        guestReceivablesProvider('payer'),
        (_, _) {},
      );
      addTearDown(sub.close);
      await container.read(userSessionsProvider('payer').future);
      await container.read(sessionGuestObligationsProvider('closed').future);
      await container.read(sessionMembersProvider('closed').future);
      final items = container
          .read(guestReceivablesProvider('payer'))
          .requireValue;
      expect(items.map((i) => i.obligation.obligationId), [
        'mine',
        'collected',
      ]);
      expect(items.first.guestName, 'Khách An');
      expect(pendingGuestTotal(items), 100);
    },
  );
}
