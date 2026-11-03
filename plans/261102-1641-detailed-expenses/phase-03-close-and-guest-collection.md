# Phase 3 — Trusted Close, Guest Collections, and Legacy Compatibility

## Context

Close must atomically compute debt for the complete session, create guest claims per payer/item, write existing account-pair entries/balances, and preserve legacy no-item settlement. Guest confirmation never changes pair balances.

## Requirements

- Cloud Function re-reads all source documents, validates and calculates; client does not submit authoritative entries/balances.
- Aggregate across items/payers before existing simplification; subtract guest claims from each actual payer.
- Stable obligations are created on close and immutable except collected state/audit metadata.
- Duplicate/concurrent close and collection calls are idempotent.
- No-item legacy sessions preserve stored allocation and current creator fallback behavior.

## Files

- Create `functions/src/expenses/close-session.*`, `guest-collection.*`.
- Modify `functions/src/index.*`, settlement helper and `firestore.rules`.
- Modify `lib/repositories/session_repository.dart`; create `lib/repositories/guest_obligation_repository.dart` (or use existing debt repository if it is the better established boundary).
- Add Functions and Rules emulator tests plus repository tests.

## Steps

1. Test close callable for account-only, mixed account/guest, multiple payers, invalid totals/participants/payers, and legacy no-item inputs.
2. Implement close transaction: assert creator/open; load session/items/members; recompute shares and all totals; create deterministic obligations and immutable debt entries; update pair balances/member statuses and close status atomically.
3. Test concurrent/repeated close; verify no duplicate entries/obligations and return already-closed outcome consistently.
4. Test legacy outputs against existing `settleSession` behavior, including sessions with missing/zero `amountPaid` creator fallback; implement legacy branch without fabricating items.
5. Test guest collection: payer allowed, nonpayer rejected (even if creator), repeated collection idempotent, original amount/identity unchanged, pair balances unchanged.
6. Implement callable confirmation with transaction and actor/time audit fields; add payer/member-scoped read rules and deny client status forgery.
7. Adapt Flutter repositories to invoke callables for new itemized flow; leave account payment APIs untouched.
8. Run Functions/Rules emulator and focused repository/payment regression suites.

## Validation

- New close and guest collection behavior passes emulator integration tests, including duplicate/concurrency scenarios.
- Existing account debt/payment tests have unchanged balances and pending/confirmed transitions.
- Legacy sessions close with same settlement result as baseline.

## Risks / Rollback

- Firestore atomic write limits or settlement fan-out may exceed transaction/batch constraints; stop and design chunking/idempotency before implementation if measured.
- Existing client versions may continue direct-closing sessions. Confirm deployed-client compatibility and preserve/retire old writes only through a deliberate versioned migration; never allow dual trusted close paths to race.
- No production deploy without explicit user confirmation.
