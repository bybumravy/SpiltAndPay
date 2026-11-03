# Phase 4 — Flutter Expense and Session UI

## Context

Build on the approved mockup while preserving existing navigation, providers, validation and account debt flow. Use one expense list/action for a single bill or multiple detailed items.

## Requirements

- Initially show one convenient item; same **Thêm khoản chi** action adds more items.
- Each item supports description, positive VND amount, creator-default account payer, selectable account payer, and equal-split participants defaulting to all current session members (user can deselect).
- Display derived session total and member share previews; OCR fills active item amount.
- New member additions never silently modify existing item participant snapshots.
- Closed session details show expenses, payer, participants/shares, and payer-specific guest collection status/action.
- Sessions list follows approved mockup and only shows real available data.

## Files

- Modify `lib/screens/session/create_session_screen.dart` and `session_detail_screen.dart`.
- Modify `lib/screens/home/sessions_tab.dart`.
- Modify `lib/screens/home/debts_tab.dart` and/or `lib/screens/debt/debt_detail_screen.dart` only if required for guest collection ledger placement.
- Add focused widget tests under existing `test/` conventions.

## Steps

1. Add widget tests for one item total, multiple item sum, add/edit/remove using one action, payer default/change, all-member participant default/deselect, later member exclusion from old item, and account/guest sharing.
2. Add OCR test proving recognized amount is assigned to the currently active item only.
3. Implement create-session item editor with existing UI conventions and selective Forui use only where consistent; preserve title/member workflow and current validation where still applicable.
4. Connect editor persistence and preview to repository/model helpers; show errors/loading without bypassing server validation.
5. Add detail tests for item rendering, payer and participant snapshots, outstanding/collected guest claims, payer-only action, and nonpayer behavior.
6. Implement detail guest collection confirmation and status, preserving creator-only close session and all existing account payment actions.
7. Add list tests for all/open/closed filters, card values, empty/error/retry, and navigation; implement mockup styling with real session data only.
8. Run focused widget tests and existing session/debt tests.

## Validation

- UI previews match persisted/server calculations for remainder splits.
- OCR, edit/remove, participant membership changes, loading/error, permissions, and account payment flows work.
- No dashboard or broad Forui migration is introduced.

## Risks / Rollback

- Existing custom split creation is not applied to new expense items; preserve legacy stored allocations and clearly retain required current user-facing behavior where the design excludes a new custom mode.
- If guest ledger placement conflicts with current semantics, keep obligations in session detail and avoid depicting them as account-pair debts.
