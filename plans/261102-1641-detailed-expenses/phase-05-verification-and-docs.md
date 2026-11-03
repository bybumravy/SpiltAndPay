# Phase 5 — Regression Verification and Documentation

## Context

Verify the complete feature across client, callable backend, Firestore Rules and legacy data before describing it as shipped.

## Requirements

- No tests, lint, analyzer, or emulator failures hidden.
- Preserve existing debt simplification, pair accumulation, pending-payment confirmation, and legacy close.
- Update docs only to reflect behavior proven in the implementation.
- Cloud Functions deployment/billing setup remains user-authorized separately.

## Files

- Test all changed Flutter, Functions, and Rules modules.
- Update `README.md`, `docs/project-overview-pdr.md`, `docs/system-architecture.md`, `docs/roadmap.md`; update `docs/setup.md` only if local Functions/emulator setup changes.

## Steps

1. Run `dart format --set-exit-if-changed lib test`.
2. Run `flutter analyze` and `flutter test`; report baseline failures separately.
3. Run Functions unit/integration tests and Firestore Rules emulator suite.
4. Verify acceptance matrix: single item, multiple items/payers, guest shares, payer collection, account pending/confirm, duplicate close/collection, legacy no-item close.
5. Test forged direct writes against emulator; verify clients cannot modify settlement results, obligation amounts, or paid flags.
6. Perform device smoke test where available for add/edit/remove, OCR, session close, guest collection, and account payment. If no authorized device is available, report this unverified step.
7. Request full-diff code review; address confirmed defects and rerun affected tests.
8. Update docs from verified behavior; reconcile stale guest-as-creator wording and clearly explain local emulator setup/trust boundary/legacy branch.
9. Check internal links, dates, commands, and the 800-line documentation limit.

## Validation

- Flutter analysis/tests, Functions tests and Rules emulator tests pass, or baseline/environment blockers are named precisely.
- Acceptance matrix has recorded results; no claim of deployment without explicit approval.
- Documentation matches tested behavior and does not promise unimplemented behavior.

## Risks / Rollback

- Emulator/device credentials or unavailable project config may block integration validation; report rather than weakening security or marking unverified behavior as passed.
- Keep implementation feature-gated until callable deployment is intentionally authorized and available.
