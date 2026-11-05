import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/expense.dart';
import '../models/session.dart';
import 'guest_obligation_repository.dart';
import 'session_repository.dart';

class GuestReceivable {
  final GuestObligation obligation;
  final String guestName;
  final String sessionTitle;
  const GuestReceivable({
    required this.obligation,
    required this.guestName,
    required this.sessionTitle,
  });
}

/// Reuse session-authorized streams; no second ledger or collection-group index.
final guestReceivablesProvider = Provider.autoDispose
    .family<AsyncValue<List<GuestReceivable>>, String>((ref, uid) {
      final sessions = ref.watch(userSessionsProvider(uid));
      if (sessions.hasError) {
        return AsyncError(sessions.error!, sessions.stackTrace!);
      }
      if (!sessions.hasValue) return const AsyncLoading();
      final result = <GuestReceivable>[];
      Object? error;
      StackTrace? stack;
      var loading = false;
      for (final session in sessions.requireValue.where(
        (s) => s.status == SessionStatus.closed,
      )) {
        final obligations = ref.watch(
          sessionGuestObligationsProvider(session.sessionId),
        );
        final members = ref.watch(sessionMembersProvider(session.sessionId));
        for (final value in <AsyncValue<dynamic>>[obligations, members]) {
          if (value.hasError) {
            error = value.error;
            stack = value.stackTrace;
          }
          if (!value.hasValue) loading = true;
        }
        final names = {
          for (final m in members.valueOrNull ?? []) m.memberId: m.displayName,
        };
        for (final obligation
            in obligations.valueOrNull ?? <GuestObligation>[]) {
          if (obligation.payerId != uid || obligation.amount <= 0) continue;
          result.add(
            GuestReceivable(
              obligation: obligation,
              guestName: names[obligation.guestMemberId] ?? 'Khách',
              sessionTitle: session.title,
            ),
          );
        }
      }
      if (error != null) return AsyncError(error, stack ?? StackTrace.current);
      if (loading) return const AsyncLoading();
      return AsyncData(result);
    });

int pendingGuestTotal(List<GuestReceivable> items) => items
    .where((item) => item.obligation.status == GuestObligationStatus.pending)
    .fold(0, (sum, item) => sum + item.obligation.amount);
