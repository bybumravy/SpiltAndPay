# Phase 1 — Trusted Backend and Accounting Contracts

## Context

Implement the server accounting foundation from [approved design](../../docs/superpowers/specs/2026-11-02-detailed-expenses-design.md). No production deploy or paid service activation without explicit user confirmation.

## Requirements

- Confirm Firebase Functions runtime/tooling; no existing `functions/` package was found, and `firebase.json` currently configures Firestore only.
- Cloud Function is authoritative for validating expense totals/allocations, guest obligations, account settlement and close.
- Use exact integer-VND allocation with stable member order; aggregate all items and payers before debt simplification.
- Deduct each guest share from the actual payer’s account net. Guest claims remain outside UID pair balances.

## Files

- Create minimal `functions/` package, runtime/compiler config and emulator scripts.
- Create `functions/src/expenses/allocation.*` and `settlement.*` pure helpers.
- Add corresponding `functions/test/expenses/*` tests.

## Steps

1. Inspect Firebase tooling, CLI, and project configuration; choose a compatible Functions runtime and record local test/emulator commands.
2. Add package entrypoint smoke test, scaffold package, and verify local tests/emulator startup. Do not deploy.
3. Test and implement deterministic `allocateExpense(amount, participantIds) -> shares`; cover remainder 10/3 => 4/3/3, single participant, duplicate/empty IDs, invalid amount, sum conservation.
4. Test and implement `aggregateSession(items, members) -> { totalAmount, paidByMember, owedByMember, guestClaimsByPayer, accountNetPositions }`; cover account-only, guest shares, mixed payers, totals and zero-sum account positions after guest claims.
5. Run Functions tests and verify money invariants.

## Validation

- Functions package smoke test and focused unit tests pass.
- No production deployment or billing configuration changes.

## Risks / Rollback

- Functions runtime or billing requirements may not fit the current Firebase project; stop and report required owner decision rather than enabling services.
- New package can be removed independently before any client integration.
