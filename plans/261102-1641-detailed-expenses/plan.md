# Detailed Session Expenses Implementation Plan

**Status:** Draft plan for user review; no implementation started.

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a single-item-or-many-item expense flow to SplitPay sessions, with accurate payer/member allocations, guest collection obligations, trusted settlement, and backwards-compatible legacy sessions.

**Architecture:** Keep Flutter as the client and add Firebase Cloud Functions as the trusted authority for validating session expense data and closing sessions. The client writes editable expenses only while a session is open; the close callable computes all per-member totals, guest obligations, account net positions, settlement entries, and balances atomically/idempotently. Legacy sessions without expenses use a server-side branch that matches the current close contract. Guest claims remain outside account-pair debts and are collected by the payer attached to each expense.

**Tech Stack:** Flutter/Dart, Riverpod, Cloud Firestore, Firebase Authentication, Firebase Cloud Functions (runtime to be selected after checking project tooling and Firebase compatibility), Firestore Rules and Emulator Suite, existing Flutter tests.

**Current repository context:** Flutter/Dart + Firebase app; `firebase.json` currently has Firestore config only, no `functions/` directory exists. Existing settlement is in `lib/core/settlement.dart`; session close and pair balance writes are client-side in `lib/repositories/session_repository.dart`; Firestore Rules validate entries/balance delta but do not recalculate cross-document allocations. Existing `docs/roadmap.md`, `docs/system-architecture.md`, and `docs/project-overview-pdr.md` have earlier guest-as-creator statements and must be reconciled after implementation.

**Spec:** `docs/superpowers/specs/2026-11-02-detailed-expenses-design.md`

## Global Constraints

- Use one expense list and one **Thêm khoản chi** action; a single item is the session total, multiple items sum to the session total.
- New expenses are equally split among selected members; newly added items default to all current members, and later-added members do not silently join existing items.
- Creator is the default payer; each payer must be an account member; guests cannot pay.
- Split integer VND exactly, using one stable remainder ordering shared by preview, persistence, and server calculation.
- A guest obligation belongs to the payer of the expense, is created at session close, and never becomes account-pair debt.
- The Cloud Function is trusted authority for totals, allocations, guest obligations, settlement entries, and closing; do not trust client-calculated debt writes or loosen Rules to permit them.
- Keep account-user payment confirmation and debt simplification behavior unchanged.
- Keep legacy sessions without expense documents readable and closable through the existing legacy allocation path; do not fabricate expense records for them.
- Do not deploy Cloud Functions or enable paid Firebase services without explicit user confirmation; report any required billing/runtime setup.
- No partial account debt payments, guest sign-in, automatic reminders, dashboard, or app-wide Forui migration in this feature.

## Review Focus

- Mixed payers and guest shares: aggregate across the complete session and deduct guest claims from each actual payer before simplifying account debts; test mixed-payer net positions.
- Duplicate or concurrent close calls: only one close result/obligation/entry per session; test idempotency under retry/concurrency.
- Client tampering: invalid item totals, participants, payer, shares, status, or debt writes must be rejected by Rules/callable; test forged requests.
- Member list mutation: new members must not be silently added to old items; removed/invalid participants must block close with recoverable error; test both.
- Legacy and pending payment regressions: legacy close and existing pending-payment/confirmation flows preserve their current outputs; regression tests cover each.

---

## Phases, Dependencies, and Acceptance

1. **Phase 1 — Trusted backend/accounting contracts** (`phase-01-accounting-contracts.md`): establish local Functions tooling; pure exact allocation and complete-session aggregation tests.
2. **Phase 2 — Expense persistence/security** (`phase-02-expense-persistence.md`): editable open-session items, canonical validation, and strict Rules/emulator coverage.
3. **Phase 3 — Trusted close/guest collection/legacy** (`phase-03-close-and-guest-collection.md`): atomic/idempotent close, payer-owned guest claims, account debt parity, and legacy compatibility.
4. **Phase 4 — Flutter UI** (`phase-04-flutter-ui.md`): create/detail/list screens and repository integration.
5. **Phase 5 — Verification/docs** (`phase-05-verification-and-docs.md`): full regression/security review and accurate docs.

**Dependencies:** 1 → 2 → 3 → 4 → 5. Phase 4 may begin UI-only work once the client model contract from Phase 2 is stable, but must not expose close/collection actions until Phase 3 callables are integrated. Cloud Functions deployment or any paid Firebase activation is outside this plan’s automatic execution and requires explicit approval.

**Acceptance:** All 12 criteria in the approved design’s “Tiêu chí chấp nhận” section pass, including exact money invariants, payer-specific guest obligations, account balance/payment preservation, legacy close, emulator Rules denial tests, Flutter analysis/tests, Functions tests, and UI acceptance.

## File Structure

- `functions/` — Firebase Cloud Functions package/configuration (create only after confirming supported runtime/tooling); callable validation, allocation, settlement orchestration, and guest collection confirmation.
- `functions/src/expenses/` — shared typed expense validation, exact integer allocation, and aggregation helpers, isolated from Firebase transport.
- `firestore.rules` — restrict client writes to allowed open-session expense editing and payer-only guest-collection confirmation; deny client-authored settlement results.
- `rules_test/` — Firestore Rules emulator tests for expense access, guest collection authorization, and protected debt/entry writes.
- `lib/models/expense.dart` — expense persistence model and serialization.
- `lib/models/guest_obligation.dart` — guest amount due, payer, item/session references, lifecycle and audit timestamps.
- `lib/core/expense_allocation.dart` — Dart preview/allocation and aggregation helpers, contract-tested against server test vectors.
- `lib/repositories/session_repository.dart` — create/edit/delete expenses and invoke trusted close; preserve a legacy close branch only if required by deployed clients/data.
- `lib/repositories/guest_obligation_repository.dart` — read obligations and call trusted mark-collected operation (or extend debt repository only if existing boundaries make that simpler).
- `lib/screens/session/create_session_screen.dart` — one/many item editor, default payer/participants, OCR prefill, derived bill total and previews.
- `lib/screens/session/session_detail_screen.dart` — itemized summary and payer-specific guest collection action.
- `lib/screens/home/sessions_tab.dart` — session card/list presentation consistent with approved mockup.
- `lib/screens/home/debts_tab.dart` and `lib/screens/debt/debt_detail_screen.dart` — include payer-owned guest collection only if the existing debt-ledger UX requires it; do not represent guests as UID debts.
- `test/core/expense_allocation_test.dart`, `test/models/expense_test.dart`, repository/widget tests — money, serialization, workflows, compatibility.
- `docs/project-overview-pdr.md`, `docs/system-architecture.md`, `docs/roadmap.md`, `README.md` — reconcile approved behavior and actual implementation after code is complete.

## Phase 1: Establish backend trust boundary and pure accounting contracts

### Task 1: Confirm Firebase Functions runtime and scaffold local package

**Files:**
- Inspect: `firebase.json`, `firestore.rules`, `pubspec.yaml`, Firebase project configuration and existing CI/deploy scripts.
- Create: `functions/package.json` and runtime/compiler config, only if no existing Functions package exists.
- Test: `functions/test/configuration.test.*` or equivalent package smoke test.

**Interfaces:**
- Produces: deployable local Functions package and documented emulator command; no production deploy.
- Consumes: none.

- [ ] **Step 1: Inspect repository Firebase tooling and confirm candidate supported runtime against installed Firebase CLI/project configuration.** Record the selected runtime and emulator commands in the plan execution notes; do not install or deploy services.
- [ ] **Step 2: Add a package smoke test proving the Functions entry point loads under the selected runtime.**
- [ ] **Step 3: Scaffold the minimal Functions package and local emulator/test scripts without changing Flutter behavior.**
- [ ] **Step 4: Run package install/check and emulator startup smoke test; do not deploy.**

### Task 2: Implement server-side expense allocation and accounting primitives

**Files:**
- Create: `functions/src/expenses/allocation.*`
- Create: `functions/src/expenses/settlement.*`
- Test: `functions/test/expenses/allocation.test.*`
- Test: `functions/test/expenses/settlement.test.*`

**Interfaces:**
- Produces: `allocateExpense(amount, participantIds) -> shares`; `aggregateSession(items, members) -> { totalAmount, paidByMember, owedByMember, guestClaimsByPayer, accountNetPositions }`.
- Consumes: typed plain input DTOs; no Firestore access in pure functions.

- [ ] **Step 1: Write failing allocation tests for 1 participant, uneven remainder (e.g. 10 split 3 ways → 4/3/3 in stable member order), invalid amount, empty participants, duplicate IDs, and share sum equality.**
- [ ] **Step 2: Run the focused server tests and verify failures.**
- [ ] **Step 3: Implement deterministic integer-VND allocation with stable input member order.**
- [ ] **Step 4: Write failing aggregation tests for multiple payers, account-only items, guest shares by payer, exact total paid/owed, and net positions summing to zero after excluding guest claims.**
- [ ] **Step 5: Implement aggregation across the entire session before debt simplification; never settle each item independently.**
- [ ] **Step 6: Run the focused server tests and verify all money invariants.**

## Phase 2: Persist editable expenses and enforce access rules

### Task 3: Add expense and guest-obligation models plus client preview logic

**Files:**
- Create: `lib/models/expense.dart`
- Create: `lib/models/guest_obligation.dart`
- Create: `lib/core/expense_allocation.dart`
- Test: `test/models/expense_test.dart`
- Test: `test/core/expense_allocation_test.dart`

**Interfaces:**
- Produces: `Expense.fromMap/toMap`; `GuestObligation.fromMap/toMap`; `allocateExpenseShares({required int amount, required List<String> participantIds}) -> Map<String,int>` and aggregate preview DTO.
- Consumes: stable participant ordering; mirrors server test vectors.

- [ ] **Step 1: Write failing serialization tests for account/guest participants, payer UID, description, amount, ordered participant IDs, and guest obligation lifecycle/audit fields.**
- [ ] **Step 2: Write failing Dart allocation tests using the server test vectors, including stable remainder allocation and invalid input.**
- [ ] **Step 3: Implement typed serialization with safe parsing for legacy/missing optional fields.**
- [ ] **Step 4: Implement client preview helper and ensure outputs match the shared server fixtures exactly.**
- [ ] **Step 5: Run focused Flutter tests and `dart format --set-exit-if-changed lib/models/expense.dart lib/models/guest_obligation.dart lib/core/expense_allocation.dart test/models/expense_test.dart test/core/expense_allocation_test.dart`.**

### Task 4: Add open-session expense persistence and update Firestore Rules

**Files:**
- Modify: `firebase.json` only if Functions emulator wiring is needed.
- Modify: `functions/src/index.*`
- Create: `functions/src/expenses/mutations.*`
- Modify: `firestore.rules`
- Modify: `rules_test/`
- Test: `functions/test/expenses/mutations.test.*`

**Interfaces:**
- Produces: authenticated callable operations for add/update/remove expense on an open session and a canonical representation with payer/ordered members/amount/description.
- Consumes: allocation/validation primitives from Task 2.

- [ ] **Step 1: Write failing callable tests proving only creator can mutate expenses, only while open, with valid session members, account payer, amount > 0, and nonempty unique participants.**
- [ ] **Step 2: Write emulator rules tests proving client cannot write totals, expense allocations, obligations, entries, or debt balances outside the approved paths.**
- [ ] **Step 3: Implement authenticated callable mutations; serialize mutations per session or use Firestore transactions with version/status checks.**
- [ ] **Step 4: Update Firestore Rules to permit only required client reads and narrowly scoped open-session mutations; settlement writes remain Admin SDK-only.**
- [ ] **Step 5: Test that changing the session member list does not silently rewrite saved expense participant IDs and that close rejects stale/non-member references.**
- [ ] **Step 6: Run Functions and Rules emulator suites; verify forged client writes are denied.**

## Phase 3: Trusted close, guest collection, and legacy compatibility

### Task 5: Implement trusted close-session transaction with guest obligations

**Files:**
- Create: `functions/src/expenses/close-session.*`
- Modify: `functions/src/index.*`
- Modify: `functions/src/expenses/settlement.*`
- Modify: `firestore.rules`
- Test: `functions/test/expenses/close-session.test.*`
- Test: `rules_test/`

**Interfaces:**
- Produces: callable `closeSession({sessionId})`; one immutable per-session account settlement entry per pair; guest obligations keyed stably by session/item/guest; status-closed write and updated balances in the same atomic operation.
- Consumes: validated stored expenses, Task 2 aggregate result, existing debt pair ID/sign semantics.

- [ ] **Step 1: Write failing tests for valid close with account-only items, mixed account/guest participants, two payers, duplicate close retry, invalid items, missing participants, and zero/negative total.**
- [ ] **Step 2: Add a regression test showing legacy no-items sessions use persisted member allocations and current creator fallback exactly.**
- [ ] **Step 3: Implement a transaction/batched close flow that re-reads session/items/members, checks creator/open status, recomputes all shares and totals, and atomically writes obligations, immutable entries, balances, member statuses, and closed status.**
- [ ] **Step 4: Preserve current account debt pair semantics and `simplifyDebts` behavior using aggregate account positions after payer-specific guest claim deductions.**
- [ ] **Step 5: Ensure duplicate/concurrent closes return the committed result without creating extra entries or obligations.**
- [ ] **Step 6: Run emulator integration tests for close, retry, and legacy branches.**

### Task 6: Implement payer-authorized guest collection confirmation

**Files:**
- Create: `functions/src/expenses/guest-collection.*`
- Modify: `functions/src/index.*`
- Modify: `firestore.rules`
- Create/Modify: `lib/repositories/guest_obligation_repository.dart`
- Test: `functions/test/expenses/guest-collection.test.*`
- Test: `rules_test/`

**Interfaces:**
- Produces: callable `markGuestObligationCollected({required String obligationId})`; collection/audit timestamps and actor UID; repository stream/query for obligations visible to payer/session members.
- Consumes: obligations from Task 5.

- [ ] **Step 1: Write failing tests for authorized payer confirmation, unauthorized creator/nonpayer rejection, repeated confirmation idempotency, and unchanged account pair balances.**
- [ ] **Step 2: Implement Admin-SDK transactional confirmation, preserving original amount/payer/session/item identity and recording `collectedAt`/`collectedBy`.**
- [ ] **Step 3: Restrict client writes to obligation status fields only through callable; preserve read access for relevant session members and payer.**
- [ ] **Step 4: Implement repository watch/read APIs following existing Riverpod/repository patterns.**
- [ ] **Step 5: Run Functions/Rules emulator tests and existing debt/payment tests.**

### Task 7: Preserve legacy and account payment flows through repository adapters

**Files:**
- Modify: `lib/repositories/session_repository.dart`
- Modify: `lib/repositories/debt_repository.dart` only if needed for stable existing interfaces.
- Modify: `lib/core/settlement.dart` only if extracting a shared tested contract is necessary; otherwise keep unchanged.
- Test: `test/repositories/session_repository_test.dart` or existing repository test locations.
- Test: existing payment/debt tests.

**Interfaces:**
- Produces: repository methods to mutate expense items and call trusted close; legacy read/close behavior preserved during migration.
- Consumes: deployed callable contracts from Tasks 4–6.

- [ ] **Step 1: Add repository tests proving new close calls the trusted function and maps callable errors to current user-facing failures.**
- [ ] **Step 2: Add a legacy parity test proving no-items data closed by the trusted callable produces the same settlement result as the existing `settleSession` contract, including creator fallback.**
- [ ] **Step 3: Route all new client close requests through the trusted callable; implement the legacy-compatible branch server-side and do not retain a client-authored settlement path. Do not alter payment create/confirm methods.**
- [ ] **Step 4: Run focused repository tests and existing debt/payment tests; compare expected balances and entries.**

## Phase 4: Flutter workflow and approved session UI

### Task 8: Implement one/many expense editor in create-session screen

**Files:**
- Modify: `lib/screens/session/create_session_screen.dart`
- Test: `test/screens/create_session_screen_test.dart` (or existing test convention).

**Interfaces:**
- Consumes: expense preview/allocation types and repository mutation APIs.
- Produces: one or many editable items, each description/amount/payer/participants, derived total, share preview; OCR fills the active item amount.

- [ ] **Step 1: Write failing widget tests for one-item total, multi-item total, add/edit/remove via same action, creator payer default, all-current-member participant default, later member non-mutation, and guest participation.**
- [ ] **Step 2: Add tests for OCR amount prefilling the active item and not creating an alternate total path.**
- [ ] **Step 3: Implement list editor and item controls, using existing Material patterns or selected Forui components only where consistent; avoid app-wide migration.**
- [ ] **Step 4: Keep current title/member validation and create flow; persist itemized inputs and show total/share preview from helper.**
- [ ] **Step 5: Run focused widget tests plus existing create-session tests.**

### Task 9: Render itemized session detail and guest collection state

**Files:**
- Modify: `lib/screens/session/session_detail_screen.dart`
- Modify: `lib/screens/home/debts_tab.dart` and/or `lib/screens/debt/debt_detail_screen.dart` only if needed to satisfy the approved debt-ledger placement.
- Test: `test/screens/session_detail_screen_test.dart`
- Test: relevant debt screen tests.

**Interfaces:**
- Consumes: expense and guest-obligation streams/models; repository guest-collection method.
- Produces: item summary with payer/participants/shares, payer-owned guest collection status/action, existing account debt actions unchanged.

- [ ] **Step 1: Write failing widget tests for open/closed item sections, account/guest participants, payer-specific outstanding/collected obligation, and nonpayer disabled/no action.**
- [ ] **Step 2: Write regression tests proving existing account “Tôi đã chuyển” and creditor-confirmation views are unchanged.**
- [ ] **Step 3: Implement itemized sections and guest obligation action with confirmation/toast/loading/error states.**
- [ ] **Step 4: Keep session close permission and explicit confirmation unchanged; creator remains only actor allowed to close.**
- [ ] **Step 5: Run focused detail and debt widget tests.**

### Task 10: Update session list presentation to approved mockup

**Files:**
- Modify: `lib/screens/home/sessions_tab.dart`
- Test: `test/screens/sessions_tab_test.dart`

**Interfaces:**
- Consumes: existing sessions/member counts and derived totals; no fabricated balance fields.
- Produces: open/closed filters, session cards, total/member/status display, create affordance while retaining current routes.

- [ ] **Step 1: Write failing tests for filters, empty/error/retry states, session totals/member counts, and navigation/create action.**
- [ ] **Step 2: Implement card/filter presentation using existing project visual conventions and the approved mockup; do not add Forui app-wide dependencies/migration.**
- [ ] **Step 3: Run focused list tests and verify all values come from actual model/provider data.**

## Phase 5: Integration verification and documentation

### Task 11: Full cross-contract regression and security verification

**Files:**
- Modify only verified regressions from prior tasks.
- Test: all `test/**`, `functions/test/**`, and `rules_test/**`.

**Interfaces:**
- Consumes: complete tasks 1–10.
- Produces: verified client/server money, access-control, legacy, and payment behavior.

- [ ] **Step 1: Run `dart format --set-exit-if-changed lib test`.**
- [ ] **Step 2: Run `flutter analyze` and `flutter test`; record existing baseline failures separately.**
- [ ] **Step 3: Run Functions unit/integration tests and Firestore Rules emulator suite.**
- [ ] **Step 4: Exercise acceptance matrix: one item, many items/multiple payers, mixed account/guest shares, guest payer collection, account pending/confirmation, repeated close/collection, legacy no-items close.**
- [ ] **Step 5: Inspect Rules for client bypass paths and test forged direct writes against emulator.**
- [ ] **Step 6: Run code review on full diff; fix only verified defects and rerun narrow/full affected tests.**

### Task 12: Sync documentation to implemented behavior

**Files:**
- Modify: `README.md`
- Modify: `docs/project-overview-pdr.md`
- Modify: `docs/system-architecture.md`
- Modify: `docs/roadmap.md`
- Modify: `docs/setup.md` only if emulator/Functions setup steps are added.

**Interfaces:**
- Consumes: verified implementation contracts from Tasks 1–11.
- Produces: docs describing shipped behavior, Functions local testing/setup, Rules/trust boundary, legacy path, and guest collection ownership.

- [ ] **Step 1: Read current docs and replace stale pre-implementation behavior only after implementation is verified.**
- [ ] **Step 2: Add exact emulator setup/test commands and state explicitly that deployment/billing configuration requires project owner authorization.**
- [ ] **Step 3: Check links, dates, claims, and ensure no doc exceeds the 800-line limit.**

## Self-Review

- **Spec coverage:** One/many UI, item/payer/member schema, stable exact splits, multi-payer aggregation, payer-specific guest claim, trusted server close, idempotent confirmation, account payment preservation, legacy support, Rules/emulator tests, list/detail UI, and post-implementation docs have explicit tasks.
- **Step scan:** Each task has tests before implementation and a focused validation step; implementation signatures and data responsibility are defined at each backend/client boundary.
- **Type consistency:** Expense/member IDs and payer UIDs are strings; amount/share fields are integer VND; callable operations use explicit session/obligation IDs; server computes persisted totals and debts.
- **Review Focus:** Mixed payers, concurrency/idempotency, client tampering, mutable member sets, and legacy/payment regressions each have an owning test task.
- **Proportion:** Phase boundaries separate backend trust, persistence/security, accounting, UI, and docs while keeping tests close to each behavior.
