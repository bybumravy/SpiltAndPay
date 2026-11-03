# SplitPay Forui UI Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SplitPay's Material 3 presentation widgets with a consistent Forui mobile interface while preserving all authentication, Firebase, Riverpod, QR, OCR, navigation, validation, and business behaviour.

**Architecture:** Keep Flutter Material imports only where required by Flutter/platform APIs, plugins, `Icons`, routing, and input formatters. Add a reusable presentation layer under `lib/ui/` that owns Forui theme setup, feedback, dialogs, common loading/error/empty states, and reusable tiles. Each existing screen retains its state and repository calls, but uses those UI primitives instead of direct Material visual components.

**Tech Stack:** Flutter 3.47.3, Dart 3.13.3, `forui: ^0.27.7`, Riverpod 2.5.1, Firebase, Material routing/plugins, `mobile_scanner`, `qr_flutter`.

**Spec:** User request in this conversation: migrate the entire existing Flutter mobile UI to Forui; do not change app logic or external integrations.

## Global Constraints

- Add exactly `forui: ^0.27.7` to `pubspec.yaml`; do not add a second UI kit.
- Retain Riverpod providers, Firebase repositories/models, QR scanning/generation, image-picker, OCR, Cloudinary, and all Vietnamese copy and validation rules unless a visual wrapper requires equivalent placement.
- Target Android and iOS first; retain existing Flutter-compatible code paths.
- Use `FTheme.neutral.light.touch` wrapped by `FTheme` and derive the Material `ThemeData` via `toApproximateMaterialTheme()` so required Material/plugin widgets remain readable.
- Add `FToaster` at app root; replace user-facing `SnackBar` feedback with `showFToast` helpers.
- Use Forui components when they exist: `FScaffold`, `FBottomNavigationBar`, `FButton`, `FTextField`/`FTextFormField`, `FCard`, `FTile`, `FDialog`, `FSheet`, `FTabs`, `FSelect`/`FRadio`, `FSwitch`, `FBadge`, and `FCircularProgress`.
- Retain native Material only for non-equivalent framework/plugin surfaces (route transitions, scanner camera overlay, `RefreshIndicator`, image/QR canvas), and keep those uses documented locally by intent.
- Do not alter repository method calls, provider identities, domain models, Firestore schema, validation thresholds, or business-rule conditions.
- Preserve loading, empty, error, disabled, destructive-confirmation, and success/failure feedback states on every existing flow.

## Review Focus

- Authentication and QR-onboarding gates must still route users correctly after theme/root widget changes; add widget coverage for loading, error, unauthenticated, QR-missing, and QR-present branches in Task 2.
- Every async action must restore enabled state and show the current Vietnamese error/success copy after a failed/successful repository call; cover helpers in Task 3 and critical submit flows in Tasks 4–7.
- Destructive actions (delete session/contact, close session, sign out) must stay cancellable and must execute only after explicit confirmation; cover dialog callback wiring in Task 3 and each owning screen task.
- Numeric session constraints must remain unchanged: positive total, custom-sum not above total, and multi-payer sum not above total; cover create-session validation in Task 6.
- QR scanner/image-picker interactions must remain usable above Forui layouts and all scanner controllers must still dispose; exercise QR entry flows manually on Android in Tasks 5–6.

---

## File Structure

- `pubspec.yaml` — declares Forui.
- `lib/app.dart` — provides Material compatibility theme, `FTheme`, and `FToaster` for all app routes.
- `lib/ui/app-theme.dart` — exposes central Forui theme constants and semantic visual styles (success, warning, destructive) without scattering colors through feature screens.
- `lib/ui/app-feedback.dart` — exposes toast/dialog helpers with existing Vietnamese copy passed in by callers.
- `lib/ui/async-state.dart` — consistent Forui loading/error/empty widgets used by Riverpod `.when` branches.
- `lib/ui/app-tile.dart` — reusable Forui list-row/card treatment for sessions, debts, contacts, members, and payments.
- `lib/ui/amount-badge.dart` — semantic amount/status representation for debt/session status without business logic.
- Existing `lib/screens/**` files — retain business state and callbacks; migrate only visual widget composition.
- `test/ui/*_test.dart` — widget tests for app root and shared visual primitives; feature-screen widget coverage uses provider overrides/fakes only where existing code makes it practical.

### Task 1: Add Forui and establish the application design system

**Files:**
- Modify: `pubspec.yaml:9-57`
- Modify: `lib/app.dart:1-75`
- Create: `lib/ui/app-theme.dart`
- Create: `lib/ui/app-feedback.dart`
- Test: `test/ui/app_theme_test.dart`

**Interfaces:**
- Produces: `splitPayForuiTheme` (`FThemeData`), `SplitPayTheme` semantic colors, `showAppToast(BuildContext context, {required String title, String? description, AppToastKind kind = AppToastKind.info})`, and `showConfirmationDialog<T>(...)`.
- Consumed by: Tasks 2–7.

- [ ] **Step 1: Add a failing widget test proving the app root exposes `FTheme` and `FToaster` to a descendant.**

```dart
testWidgets('SplitPayApp provides Forui theme and toaster', (tester) async {
  await tester.pumpWidget(const ProviderScope(child: SplitPayApp()));
  expect(find.byType(FTheme), findsOneWidget);
  expect(find.byType(FToaster), findsOneWidget);
});
```

- [ ] **Step 2: Run the test to verify it fails before Forui is configured.**

Run: `flutter test test/ui/app_theme_test.dart`
Expected: FAIL because `forui`/`FTheme`/`FToaster` are unavailable.

- [ ] **Step 3: Add `forui: ^0.27.7`, run dependency resolution, and create `lib/ui/app-theme.dart`.**

Expose the single light touch theme based on `FTheme.neutral.light.touch`; derive the root Material compatibility theme with `toApproximateMaterialTheme()`. Define semantic success/warning/destructive colors for the current green/orange/red business states rather than hard-coding colors in migrated screens.

- [ ] **Step 4: Update `SplitPayApp` in `lib/app.dart` to install the Forui root layer.**

Keep `MaterialApp`, its `home: const AuthGate()`, and all auth-gate logic. Use its `builder` to wrap the descendant with `FTheme(data: splitPayForuiTheme, child: FToaster(child: child!))`.

- [ ] **Step 5: Implement `lib/ui/app-feedback.dart` with toast and confirmation-dialog adapters.**

`showAppToast` maps `AppToastKind` to Forui icon/title/description presentation via `showFToast`; `showConfirmationDialog<T>` invokes `showFDialog` and returns a `Future<T?>`. Keep action callbacks supplied by the screen so this layer owns no feature/business state.

- [ ] **Step 6: Run focused verification.**

Run: `flutter test test/ui/app_theme_test.dart && flutter analyze`
Expected: PASS with no analyzer errors.

- [ ] **Step 7: Commit.**

```bash
git add pubspec.yaml pubspec.lock lib/app.dart lib/ui/app-theme.dart lib/ui/app-feedback.dart test/ui/app_theme_test.dart
git commit -m "feat: add Forui application theme"
```

### Task 2: Build reusable Forui state and row primitives

**Files:**
- Create: `lib/ui/async-state.dart`
- Create: `lib/ui/app-tile.dart`
- Create: `lib/ui/amount-badge.dart`
- Test: `test/ui/async_state_test.dart`
- Test: `test/ui/app_tile_test.dart`

**Interfaces:**
- Consumes: `SplitPayTheme` from Task 1.
- Produces: `AppLoadingState`, `AppErrorState`, `AppEmptyState`, `AppTile`, `AmountBadge`, and `StatusBadge` widgets.
- Consumed by: Tasks 3–7.

- [ ] **Step 1: Write failing widget tests for loading, empty/error retry, semantic amount badge, and tappable tile behavior.**

```dart
testWidgets('AppErrorState invokes retry', (tester) async {
  var retried = false;
  await tester.pumpWidget(testHost(AppErrorState(message: 'Lỗi tải', onRetry: () => retried = true)));
  await tester.tap(find.text('Thử lại'));
  expect(retried, isTrue);
});

testWidgets('AmountBadge distinguishes money owed and receivable', (tester) async {
  await tester.pumpWidget(testHost(const AmountBadge(amount: 25000, direction: AmountDirection.owed)));
  expect(find.text('25.000 ₫'), findsOneWidget);
});
```

- [ ] **Step 2: Run the focused tests and verify failure.**

Run: `flutter test test/ui/async_state_test.dart test/ui/app_tile_test.dart`
Expected: FAIL because primitives do not exist.

- [ ] **Step 3: Implement the reusable visual primitives using Forui feedback, card, tile, button, badge, and progress widgets.**

`AppTile` takes explicit `title`, optional `subtitle`, `leading`, `trailing`, and `onTap`; it must not access providers or domain models. `AmountBadge` receives already-calculated values and formatting text from callers, preserving calculation ownership in feature screens.

- [ ] **Step 4: Run focused verification.**

Run: `flutter test test/ui/async_state_test.dart test/ui/app_tile_test.dart && flutter analyze`
Expected: PASS with no analyzer errors.

- [ ] **Step 5: Commit.**

```bash
git add lib/ui/async-state.dart lib/ui/app-tile.dart lib/ui/amount-badge.dart test/ui/async_state_test.dart test/ui/app_tile_test.dart
git commit -m "feat: add shared Forui UI primitives"
```

### Task 3: Migrate app shell and authentication/QR onboarding UI

**Files:**
- Modify: `lib/screens/home/home_screen.dart:1-48`
- Modify: `lib/screens/auth/login_screen.dart:1-210`
- Modify: `lib/screens/auth/qr_onboarding_screen.dart:1-203`
- Test: `test/ui/auth_screens_test.dart`

**Interfaces:**
- Consumes: root theme/feedback from Task 1 and async primitives from Task 2.
- Produces: Forui-styled app shell, sign-in/sign-up form, and QR onboarding UI with unchanged callbacks.
- Consumed by: all authenticated screen tasks.

- [ ] **Step 1: Write failing widget tests for app-shell tab changes, sign-in/sign-up toggle, disabled sign-in controls while loading, and QR onboarding validation state.**

```dart
testWidgets('home bottom navigation changes the visible tab', (tester) async {
  await tester.pumpWidget(testHost(const HomeScreen()));
  await tester.tap(find.text('Công nợ'));
  expect(find.byType(DebtsTab), findsOneWidget);
});

testWidgets('QR onboarding displays upload validation when no image is selected', (tester) async {
  await tester.pumpWidget(testHost(const QrOnboardingScreen(uid: 'u1')));
  await tester.tap(find.text('Xác nhận và tiếp tục'));
  expect(find.text('Vui lòng chọn ảnh QR trước.'), findsOneWidget);
});
```

- [ ] **Step 2: Run the auth/app-shell tests and verify failure.**

Run: `flutter test test/ui/auth_screens_test.dart`
Expected: FAIL until tests and Forui widget labels/semantics are implemented.

- [ ] **Step 3: Replace `BottomNavigationBar` with `FBottomNavigationBar`.**

Keep the `IndexedStack`, tab order, icons, labels, and `_currentIndex` lifecycle intact. Use the Forui `index`/`onChange` API and place it in the `FScaffold` footer or an equivalent composition that preserves safe-area behavior.

- [ ] **Step 4: Migrate `LoginScreen` forms and action controls to Forui.**

Use `FTextFormField`/`FTextField` and `FButton` equivalents for name/email/password, submit, mode toggle, and Google sign-in. Preserve the current `Form` validators, `TextEditingController`s, `_isSignUp`, `_isLoading`, Google/email repository calls, and Vietnamese error mapping.

- [ ] **Step 5: Migrate `QrOnboardingScreen` visual composition to Forui.**

Use `FScaffold`/header, `FCard` or an equivalent Forui surface for the QR preview, Forui buttons/progress/error presentation, and keep the `ImagePicker`, `verifyBankQrImage`, dev mode, upload, and navigation behavior unchanged.

- [ ] **Step 6: Replace only presentation-level auth/QR status feedback with the shared Forui feedback helpers.**

Do not remove inline form/field validation messages. Keep existing error text and ensure all loading controls are disabled during their current operations.

- [ ] **Step 7: Run focused verification and manual Android smoke test.**

Run: `flutter test test/ui/auth_screens_test.dart && flutter analyze`
Expected: PASS with no analyzer errors.

Manual Android checks: login/sign-up toggle; invalid fields; Google button; QR image picker cancellation; invalid QR; valid QR upload/dev-mode continuation; back navigation only when changing QR.

- [ ] **Step 8: Commit.**

```bash
git add lib/screens/home/home_screen.dart lib/screens/auth/login_screen.dart lib/screens/auth/qr_onboarding_screen.dart test/ui/auth_screens_test.dart
git commit -m "feat: migrate authentication UI to Forui"
```

### Task 4: Migrate session/debt overview and profile UI

**Files:**
- Modify: `lib/screens/home/sessions_tab.dart:1-186`
- Modify: `lib/screens/home/debts_tab.dart:1-91`
- Modify: `lib/screens/home/profile_tab.dart:1-153`
- Test: `test/ui/home_tabs_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3 primitives and app shell.
- Produces: Forui visual treatment for overviews; keeps navigation and repository calls intact.
- Consumed by: Tasks 5–7 detail screens.

- [ ] **Step 1: Write failing widget tests for the session empty/error/retry views, debt owed/receivable rows, profile QR-change route action, and sign-out cancellation.**

```dart
testWidgets('session delete confirmation does not delete on cancel', (tester) async {
  // Override session repository provider with a recording fake.
  // Tap Xoá phiên then Huỷ.
  expect(fake.deleteCalls, isZero);
});

testWidgets('debt tile shows the existing formatted amount and direction', (tester) async {
  // Pump with a provider override containing a debt where current user owes money.
  expect(find.text('Bạn nợ'), findsOneWidget);
});
```

- [ ] **Step 2: Run the overview tests and verify they fail.**

Run: `flutter test test/ui/home_tabs_test.dart`
Expected: FAIL before the migrated components/confirmation adapter are wired.

- [ ] **Step 3: Migrate `SessionsTab` to Forui scaffold, async states, cards/tiles, badge, action menu, confirmation dialog, feedback toast, and primary add action.**

Retain pull-to-refresh, route pushes, creator/open delete availability, destructive wording, and `deleteSession` call exactly as today. Keep `RefreshIndicator` if no Forui equivalent meets the behavior.

- [ ] **Step 4: Migrate `DebtsTab` and `_DebtTile` to Forui scaffold, async states, tiles/cards, avatar surface, and semantic amount badges.**

Retain `amountOwedBy`, counterpart lookup, `formatVnd`, and route parameters unchanged.

- [ ] **Step 5: Migrate `ProfileTab` to Forui scaffold/header, profile/QR cards, action tile, confirmation dialog, and toast.**

Keep cached image behavior, QR change route result handling, contacts route, and `signOut()` behavior unchanged.

- [ ] **Step 6: Run focused verification and manual Android smoke test.**

Run: `flutter test test/ui/home_tabs_test.dart && flutter analyze`
Expected: PASS with no analyzer errors.

Manual Android checks: pull refresh sessions; delete-cancel and delete-confirm; debt navigation; sign-out cancel/confirm; update QR and return; open friends.

- [ ] **Step 7: Commit.**

```bash
git add lib/screens/home/sessions_tab.dart lib/screens/home/debts_tab.dart lib/screens/home/profile_tab.dart test/ui/home_tabs_test.dart
git commit -m "feat: migrate overview screens to Forui"
```

### Task 5: Migrate contacts and friend QR interactions

**Files:**
- Modify: `lib/screens/friends/add_friend_screen.dart:1-551`
- Test: `test/ui/add_friend_screen_test.dart`

**Interfaces:**
- Consumes: Forui theme, feedback, dialog, async-state, and tile primitives from Tasks 1–2.
- Produces: Forui forms/tabs/sheets/cards/tile actions for contacts without changing scanner or repository flow.
- Consumed by: Task 6 through the contacts/add-member list expectation.

- [ ] **Step 1: Write failing widget tests for email search validation/result, add-contact feedback, deletion cancellation, and contacts search filtering.**

```dart
testWidgets('deleting a contact calls repository only after confirmation', (tester) async {
  // Override contacts and user repositories with fakes.
  // Tap delete, cancel, then confirm in separate assertions.
  expect(fake.deletedUids, isEmpty);
});
```

- [ ] **Step 2: Run the contact tests and verify failure.**

Run: `flutter test test/ui/add_friend_screen_test.dart`
Expected: FAIL before migrated components preserve accessible labels/actions.

- [ ] **Step 3: Replace page scaffold, app header, tab surface, email/search controls, result card, contacts filter field, and contact rows with Forui equivalents.**

Preserve the three tabs, `TabController`, search query/filter behavior, `findByEmail`, bidirectional contact insertion, and all existing messages.

- [ ] **Step 4: Replace dialog/sheet/toast presentation with Forui without replacing camera/scanner or QR painter.**

Use `FDialog` for contact deletion and `FSheet` for any current modal UI where appropriate. Keep `MobileScanner`, its overlay/controls, `ImagePicker`, `QrImageView`/`QrPainter`, disposal, and scanner duplicate guard (`_handled`) unchanged.

- [ ] **Step 5: Run focused verification and manual Android camera/QR test.**

Run: `flutter test test/ui/add_friend_screen_test.dart && flutter analyze`
Expected: PASS with no analyzer errors.

Manual Android checks: find missing/self/found email; add friend; scan own/friend QR; choose a QR image; filter contacts; cancel/delete contact; show personal QR.

- [ ] **Step 6: Commit.**

```bash
git add lib/screens/friends/add_friend_screen.dart test/ui/add_friend_screen_test.dart
git commit -m "feat: migrate friends UI to Forui"
```

### Task 6: Migrate create-session and add-member surfaces

**Files:**
- Modify: `lib/screens/session/create_session_screen.dart:1-884`
- Test: `test/ui/create_session_screen_test.dart`

**Interfaces:**
- Consumes: shared Forui primitives/feedback from Tasks 1–2 and contacts data behavior from Task 5.
- Produces: Forui create-session form, split choice, multi-payer switch, member tiles, add-member sheet, and QR dialog while retaining all calculations/validation.
- Consumed by: Task 7 through the existing session model/UI state.

- [ ] **Step 1: Write failing widget tests for validation and business-critical UI states.**

```dart
testWidgets('create session rejects a non-positive total', (tester) async {
  await tester.enterText(find.bySemanticsLabel('Tên phiên'), 'Ăn trưa');
  await tester.enterText(find.bySemanticsLabel('Tổng tiền (VND)'), '0');
  await tester.tap(find.text('Tạo phiên'));
  expect(find.text('Nhập tổng tiền hợp lệ.'), findsOneWidget);
});

testWidgets('create session prevents custom allocation above total', (tester) async {
  // Populate custom member values exceeding total and assert existing copy.
  expect(find.textContaining('vượt quá tổng bill'), findsOneWidget);
});
```

- [ ] **Step 2: Run the create-session tests and verify failure.**

Run: `flutter test test/ui/create_session_screen_test.dart`
Expected: FAIL before the Forui control migration maintains field labels and callbacks.

- [ ] **Step 3: Migrate title/total/custom amount inputs, OCR action, submit action, and loading states to Forui form controls/buttons.**

Preserve controllers, digit-only formatters, OCR result assignment, validation copy, `computeShares`, and create-repository payload construction exactly.

- [ ] **Step 4: Migrate split choice, multi-payer switch, member rows, empty hints, and remove/edit actions to Forui selection/switch/tile components.**

Keep values, state changes, guest edit condition, share previews, and amount calculations unchanged.

- [ ] **Step 5: Migrate `_AddMemberSheet`, its personal QR dialog, and friend QR scanner sheet to `FSheet`/`FDialog` with Forui controls.**

Retain `MobileScanner`, Firestore contact updates, member callbacks, all QR drawing code, and the current rule that the sheet remains open while selecting multiple contacts/guests.

- [ ] **Step 6: Run focused verification and manual Android workflow.**

Run: `flutter test test/ui/create_session_screen_test.dart && flutter analyze`
Expected: PASS with no analyzer errors.

Manual Android checks: OCR success/no-total/failure; equal/custom split; multi-payer values; add/remove/edit guest; add existing/new QR contact; invalid totals; create a valid session.

- [ ] **Step 7: Commit.**

```bash
git add lib/screens/session/create_session_screen.dart test/ui/create_session_screen_test.dart
git commit -m "feat: migrate session creation UI to Forui"
```

### Task 7: Migrate session detail and debt payment UI

**Files:**
- Modify: `lib/screens/session/session_detail_screen.dart:1-455`
- Modify: `lib/screens/debt/debt_detail_screen.dart:1-450`
- Test: `test/ui/detail_screens_test.dart`

**Interfaces:**
- Consumes: all shared UI primitives and migrated create/session/debt state from Tasks 1–6.
- Produces: Forui presentation for session closing/editing/deletion, member actions, debt amounts/QR/payment history, and toast/dialog feedback.

- [ ] **Step 1: Write failing widget tests for guarded actions and status presentation.**

```dart
testWidgets('closing a session requires confirmation before repository call', (tester) async {
  // Override repository with recording fake; verify cancel then confirm behavior.
});

testWidgets('pending payment disables transfer confirmation action', (tester) async {
  // Pump debt detail with a pending payment and assert “Đang chờ xác nhận...”.
  expect(find.text('Đang chờ xác nhận...'), findsOneWidget);
});
```

- [ ] **Step 2: Run detail-screen tests and verify failure.**

Run: `flutter test test/ui/detail_screens_test.dart`
Expected: FAIL before Forui component migration preserves current labels/disabled states.

- [ ] **Step 3: Migrate `SessionDetailScreen` header/actions, summary/status, member list, close/edit/delete confirmations, and feedback to Forui.**

Keep session status guards, member-provider behavior, repository calls, navigation after close/delete, guest share action, and guest paid marking unchanged.

- [ ] **Step 4: Migrate `DebtDetailScreen`, `_DebtorActions`, `_CreditorSection`, and `_PaymentTile` to Forui cards/tiles/buttons/badges/progress/toasts.**

Retain QR generation/download/rendering, gallery save/open action, dynamic VietQR fallback, pending-payment locking, `markTransferred`, `confirmPayment`, formatted amount logic, and payment history behavior.

- [ ] **Step 5: Run focused verification and manual Android payment/session smoke test.**

Run: `flutter test test/ui/detail_screens_test.dart && flutter analyze`
Expected: PASS with no analyzer errors.

Manual Android checks: close/edit/delete session cancel+confirm; mark a guest paid; share guest payment request; debt QR save/error; pending transfer lock; mark transfer; creditor payment confirmation; settled debt view.

- [ ] **Step 6: Commit.**

```bash
git add lib/screens/session/session_detail_screen.dart lib/screens/debt/debt_detail_screen.dart test/ui/detail_screens_test.dart
git commit -m "feat: migrate detail screens to Forui"
```

### Task 8: Full regression verification and visual acceptance

**Files:**
- Modify: only files required to correct verified regressions from prior tasks.
- Test: existing `test/**` and newly created `test/ui/**`.

**Interfaces:**
- Consumes: complete migration from Tasks 1–7.
- Produces: verified Forui migration ready for review.

- [ ] **Step 1: Run formatting and the complete automated suite.**

Run: `dart format --set-exit-if-changed lib test && flutter analyze && flutter test`
Expected: all commands pass; no ignored analyzer/test failure.

- [ ] **Step 2: Run the app on an Android device and perform the end-to-end acceptance workflow.**

Verify: email login; Google entry visibility; first-time QR onboarding; home tab navigation; friend email and QR additions; session creation with OCR and manual values; session close; debt transfer/confirmation; QR update; sign out.

- [ ] **Step 3: Inspect the visual system for migration completeness.**

Search all `lib/**/*.dart` sources for direct `Scaffold`, Material buttons, Material text fields, `AlertDialog`, `showDialog`, `showModalBottomSheet`, `SnackBar`, `ListTile`, `Card`, `Chip`, and `BottomNavigationBar`. Retain only documented framework/plugin exceptions; migrate remaining presentation usages to Forui.

- [ ] **Step 4: Fix only verified UI regressions and repeat narrow tests, then the full suite.**

Run: `flutter analyze && flutter test`
Expected: PASS.

- [ ] **Step 5: Request a final code review before shipping.**

Use `/code-review` or the project review workflow on the completed diff. Address confirmed regressions without weakening tests.

- [ ] **Step 6: Commit any verified final fixes.**

```bash
git add lib test pubspec.yaml pubspec.lock
git commit -m "fix: polish Forui migration"
```

## Self-Review

- **Spec coverage:** Tasks 1–2 establish a coherent Forui root and reusable layer; Tasks 3–7 cover every current presentation screen under `lib/screens`; Task 8 searches for remaining Material presentation widgets and runs full regression validation. No repository/model/Firebase files change.
- **Step scan:** Every task has a bounded UI area, a failing behavior test, implementation steps with component choices, focused verification, and a commit.
- **Type consistency:** `splitPayForuiTheme`, `showAppToast`, `showConfirmationDialog`, `AppLoadingState`, `AppErrorState`, `AppEmptyState`, `AppTile`, `AmountBadge`, and `StatusBadge` are introduced once and consumed consistently.
- **Review focus:** Root gates, async feedback, destructive confirmations, money validation, and QR/plugin flows are assigned explicit automated/manual checks in owning tasks.
- **Proportion:** The migration is extensive (10 screens, 184 Material UI usages); the plan gives contracts and test outcomes, not replacement code bodies.
