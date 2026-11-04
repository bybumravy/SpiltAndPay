# Split & Pay — UI refinement QA

final result: passed

## Target and scope

Selected visual: option 3, refined to remove advisory copy and use “Người trả: …”. Reference: `docs/design/refined-session-reference.png`. Existing Flutter Android application, not a replacement web prototype. Repository/auth/accounting APIs remain unchanged in this UI pass.

## Evidence

- Flutter renderer captures: `build/ui-preview/` — sessions, session-detail, session-editor, login, signup, debts, debt-detail, profile, friends, qr-onboarding, session-detail-narrow.
- Source and implementation were opened together at a normalized 390 × 844 viewport: `reference-normalized.png` and `session-normalized.png` in that directory. Source image 852 × 1846; implementation 780 × 1688 (390 × 844 logical at 2×). Source was downsampled and cropped by one vertical pixel; no device frame included.
- Narrow layout: 320 × 740 logical, text scale 1.3. Typography uses real Roboto and Material icon fonts in the visual tests, not Flutter's Ahem test font.

## Findings and resolutions

- [Resolved P1] Expense description, shares and actions competed horizontally. Each expense now expands independently; shares have a lavender inset and right-aligned amounts. Edit/delete actions wrap when needed.
- [Resolved P2] Excess whitespace pushed the friends list to the bottom. Search/QR panel height is bounded, email results scroll, contacts use remaining space.
- [Resolved P2] Mixed neutral Forui and Material controls. A shared white/violet palette and Roboto typography now cover both systems.
- [Resolved P2] Long dialogs and onboarding could exceed short viewports. Expense dialogs and onboarding scroll; primary session actions remain reachable.
- [Resolved P2] Redundant guidance and inconsistent payer copy. Static helper sentences were removed; payer labels consistently use “Người trả: …”. Destructive confirmations, validation errors, camera aiming guidance and legacy allocation warnings remain functional information.

## Fidelity surfaces

- Typography: Roboto, 15–16px body, 17px row titles, 28px page title and 40px session total. Vietnamese glyphs render correctly. Native navigation/header sizes intentionally differ from the illustration.
- Spacing: 24px page gutters, simple separators, independent expense disclosure, no nested card stacks in the editor. Both expenses and the pinned actions fit the normal phone viewport; longer content scrolls.
- Colors: solid violet #6135E8, ink #171321, muted #716B7E, lavender #F5F1FF, separator #E9E5F0. Status also uses text, not color alone.
- Assets: existing Material icons, initial avatars and runtime QR/photo widgets. No raster mock is used as interactive UI. No new decorative raster assets needed.
- Copy: concise Vietnamese labels and actual amounts/status. No advisory footer or “Hoàng trả” phrasing.

## Validation and limits

- `flutter test --no-pub`: 86 tests passed, including screen interaction and visual render checks.
- Analyzer on changed UI files and visual test: no issues.
- Android debug APK built successfully.
- Captures use deterministic provider fixtures. Real Google sign-in, image picking, camera permissions and live bank QR downloads were not exercised in the visual fixture; their service implementations were retained. Profile/payment captures include the missing-QR state. No claim of full accessibility compliance.

## Follow-up

The initial fixture review did not cover varying member counts. The follow-up below adds that coverage; visual fixtures still do not exercise every live-data or device state.

## Consistency follow-up

final result: passed

- Sessions and Friends now use the same `AppTabs` component: 52px height, 15px labels, violet underline, identical padding and selected states. Both support tapping and horizontal swiping. Narrow/large-text layouts scroll the tab strip rather than clipping labels.
- Session list filters remain visible during loading/errors; page scroll positions are separate. Regression test checks All/Open/Closed filtering and swipe navigation.
- Empty session/debt views share an icon/title treatment. Debt rows use the same separators as session rows. Profile QR content has a defined surface and explicit empty/loading/error states.
- Shared section headings and action icon shapes are consistent across outer screens. No advisory copy added.
- Current-run sessions/friends captures were inspected together; the 320px/1.3 text-scale filter state was inspected separately.
- All 86 Flutter tests passed; analyzer on changed components and tests found no issues; Android APK built.


## Content-dependent spacing follow-up

- Avatar groups now occupy 36/60/84 logical pixels for 1/2/3 visible avatars, with a consistent 12px gap before the name. Empty membership removes the avatar slot; larger groups use two avatars and a count. Geometry assertions cover 0/1/2/3/8 members.
- Amount/name rows use intrinsic value width. Amounts that exceed the available column move below the label; this applies to expenses, shares, member balances, debt rows and session summaries.
- Removed duplicate member-list heading/indentation. Long member/debt rows align avatars at the top. Friend email search uses the same 24px page gutter. Session header reserves a gap before the status badge.
- Captured collapsed and expanded member states at 390×844 and 320×740 with 1.3 text scale, including long names and large amounts. Inspected single-member, expanded and narrow multi-member captures, long debt content, sessions, friends and profile.
- Full Flutter suite: 88 passed. The updated visual fixtures were rerun afterward: 4 passed. Changed UI analyzer: no issues. Android debug APK built successfully.
- These checks validate rendering and existing interaction tests; external Google/camera/bank flows retain the limitations above.


## One session editing flow

- Detail is now a reading/settlement view. Its single “Chỉnh sửa phiên” button opens the full editor; duplicate menu entries for full editing and renaming, plus direct add/edit/delete expense dialogs, were removed. The menu retains session deletion.
- Title, members, expenses, payer and participant changes use the existing editor and atomic save. Returning without saving discards the draft. Closed sessions and non-creators do not receive an editing entry.
- Regression coverage now navigates from detail into the editor with the original snapshot, cancels a draft, reopens it, and saves changed title/description/amount through saveOpenSession. Existing editor tests continue covering member removal, payer/participant choices, multiple items and legacy migration. Tests for the removed quick-edit dialogs were replaced by the consolidated-flow checks.
- Full suite: 86 tests passed; changed screen/test analyzer: no issues. Updated normal/narrow detail renders were generated; normal detail was visually inspected after removing duplicate controls.
