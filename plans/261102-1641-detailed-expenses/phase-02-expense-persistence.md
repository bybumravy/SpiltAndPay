# Phase 2 — Expense Persistence and Access Rules

## Context

Save editable expense items only for open sessions. Rules and callable validation must prevent client-authored accounting results. See [design](../../docs/superpowers/specs/2026-11-02-detailed-expenses-design.md) and [Phase 1](phase-01-accounting-contracts.md).

## Requirements

- Each item stores description, integer amount, account payer UID, and an ordered participant snapshot including account/guest identities.
- Members added later do not mutate existing item participants.
- Creator may add/edit/remove items while session is open; all items and membership references are revalidated at close.

## Files

- Create `lib/models/expense.dart`, `lib/models/guest_obligation.dart`, `lib/core/expense_allocation.dart`.
- Create `functions/src/expenses/mutations.*`; wire `functions/src/index.*` and `firebase.json` emulator config only as needed.
- Modify `firestore.rules` and `rules_test/`.
- Add Flutter model/allocation tests and Functions/Rules emulator tests.

## Steps

1. Test and implement typed serialization for expenses and guest obligations, including identity, payer, item/session references, amount, collection state, and audit fields.
2. Test Dart allocation against server test vectors and implement preview helper with identical stable remainder ordering.
3. Test callable item mutations: authenticated creator only, open session only, positive amount, payer is account member, participants are unique current members and nonempty.
4. Implement mutation calls using Firestore transactions/version checks and persist only canonical editable item data; do not accept client computed shares/totals as trusted accounting.
5. Write Rules emulator tests for read access and rejected client writes to totals, obligations, debt entries and balances.
6. Update Rules and `firebase.json` emulator wiring narrowly; verify later-added member does not join saved participant snapshots.
7. Run focused Flutter, Functions and Rules emulator tests.

## Validation

- Serialization and client preview tests pass and match server vectors.
- Unauthorized/closed-session/invalid-member writes fail; legitimate creator mutations pass.
- Client cannot write settlement outputs.

## Risks / Rollback

- Firestore Rules may not safely express intended create/update boundaries for nested items; prefer callable mutations over permissive direct writes.
- If backend deployment is unavailable, keep the feature unexposed and report the blocker; do not ship a client-only settlement fallback.
