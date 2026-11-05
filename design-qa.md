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

## Friend invitation consent

- Email and friend QR actions now send invitations. The “Lời mời” tab shows incoming requests with accept/reject controls and outgoing requests with cancellation. A transaction checks existing invitations/contacts, and acceptance atomically writes both contact documents with the accepted request.
- Firestore rules enforce recipient-only acceptance, restrict invitation reads to participants, and block direct contact creation without acceptance. Removing a friend deletes both contact entries and associated invitation records. Existing contacts are retained.
- Scanning a user QR inside the session editor only adds a session participant; it no longer creates a friendship implicitly.
- Flutter suite: 89 passed, including email invitation dispatch and accept/reject/cancel UI interactions. Firestore emulator rules suite: 49 passed, including consent, crossed invitations, forgery, self-invites and participant access. Changed source analyzer passed. Rules deployed to splitandpay-2a413.
- Friend request UI capture inspected at 390×844. Camera scanning and two real signed-in accounts were not exercised in these fixture tests.

## Invitation layout refinement

- Invitation tab now fills the content area; the contact-search/list region is hidden in this tab, removing the split-height layout.
- Incoming and outgoing invitations are grouped separately with counts. Consistent 24px page gutters, 16px bordered surfaces, initial avatars and wrapped 44px minimum actions replace loose labels/buttons. Redundant status copy removed.
- Six visual/interaction tests passed, including invitation accept/reject/cancel and 320px/1.3 text-scale with a long Vietnamese name. Both normal and narrow invitation captures inspected. Screen analyzer found no issues.

## Sender confirmation after QR scanning

- Both camera and gallery QR results resolve the user's profile and show name/email with Send invitation/Cancel. No invitation is sent until the sender confirms.
- Repeated camera detections of the same code are ignored until the user chooses Scan again. Gallery selection and camera handling share an in-flight guard.
- Seven visual/interaction tests passed, including simulated camera detection, cancelling without a repository send, repeated-code suppression, explicit rescan and sending once after confirmation. Screen analyzer passed; APK built. Physical camera/gallery input was not exercised by the widget test.

## Sequential bill capture

- Session editor has a single batch scan entry. Each native-camera capture is processed into a local draft with image review/zoom, editable description/amount and removal. Capture cancellation leaves drafts untouched; failed/uncertain OCR requires manual amount entry rather than applying the largest guessed number.
- Shared payer excludes guests; shared participants default to current members and may be deselected. Confirming appends new expense entries; an untouched empty starter entry is replaced. Each expense can still be edited individually in the session editor. Existing atomic session save remains the persistence boundary; scanned photos are local review material, not uploaded attachments.
- Full Flutter suite: 93 passed. Expanded batch test subsequently passed with a shared payer change and participant deselection across both drafts. Changed files analyzer passed; debug APK built and installed on emulator. Meizu was not connected during this update.
- Normal/narrow review captures inspected. Tests inject capture/OCR results and use image placeholders; physical camera capture and actual receipt recognition accuracy were not validated in this run.

## OCR failure on real captured receipt

- Meizu recognition produced text, but column-ordered OCR blocks separated the total label from its amount; space-grouped VND such as 606 549 was also unsupported. The photographed electricity receipt exposed both failures.
- OCR lines now reconstruct visual rows from bounding boxes before parsing. Amounts support regular/nonbreaking/narrow spaces; labels normalize Vietnamese accents. Column table headers and company-name totals no longer qualify as final-total labels. OCR exceptions and missing-total results now have distinct review messages.
- Full suite: 96 passed, including spatial column grouping, whitespace amounts and accented/noisy labels. Analyzer passed. Native Android OCR against the actual photographed receipt passed on emulator with expected total 606549; raw text recognition was also exercised on Meizu. This validates that receipt, not arbitrary receipt accuracy.
- Temporary device diagnostics and image fixture were removed from the repository after verification. Normal application APK rebuilt for installation.

## Gemini AI Logic experiment

- Branch `codex/gemini-bill-scanning` uses Firebase AI Logic's Gemini Developer API with model `gemini-3.1-flash-lite`. No Gemini API key is embedded in Dart/APK. Firebase Core 3.x-compatible AI Logic/App Check SDKs were selected to avoid an unrelated Firebase major-version migration.
- App Check uses debug attestation in debug builds and production providers in release. Emulator debug token was registered by the user; native token retrieval succeeded. Local debug secrets are under gitignored `.local/` with restricted file permissions.
- Gemini extracts description, VND total, literal amount text and a review flag. Only a positive integer amount consistent with the quoted digits and VND is prefilled; other results remain editable drafts. Currency validation, response type validation, size/mime checks, bounded waiting, quota and attestation failure messages are included. These checks do not prove AI accuracy; users still review before session save.
- Camera images are capped at 1600×1600, JPEG quality 85, to reduce upload size. Live requests initially exceeded 20/40-second test limits; an actual receipt request completed under a 90-second limit and returned the expected total 606549 on Android emulator. Do not claim uniformly low latency from this single sample. Default timeout for the experiment is 90 seconds.
- Full Flutter suite: 104 passed. Changed-source analyzer passed before the final timeout/camera-size adjustment; automated tests were rerun afterward. Normal application APK rebuilt after removing the temporary smoke-test entry and embedded receipt fixture. The live test used registered App Check plus a real Gemini request, not an injected response. No live Gemini test on Meizu yet.
- Normal Gemini-enabled application was installed and opened on both emulator and Meizu. Emulator App Check was verified and a live Gemini receipt request returned 606549. Meizu's separate debug secret was saved privately for user registration; phone-side AI validation is pending that registration. Final changed-source analyzer reported no issues; 104 tests passed after the timeout/camera adjustment.
- After the user registered Meizu's debug secret, the normal app was restarted. Its native App Check cache contained an unexpired token bound to this Android app; Firebase AI Logic accepted that device token with HTTP 200 on countTokens. This verifies Meizu attestation/access, not a physical-camera bill inference on the phone.

## Explicit multi-image AI request

- Capture/remove actions now only edit a local photo batch. The explicit Read N images button makes one generateContent request for all selected images. Viewing cached results makes no request; changing photos requires a new explicit read, with a replacement confirmation if old drafts exist. Failed reads retain photos and require an explicit retry or manual entry; busy reads disable repeat submission.
- Each photo can return multiple separate receipts, all carrying a validated source-image index. Every photo must either have receipt results or be explicitly unreadable; missing, out-of-range or conflicting references reject the response. Suspected duplicate bills require manual review rather than automatic deletion or addition. Users can remove results and add manual rows for missed bills.
- Experiment limits: 6 photos, 8 MiB per photo/12 MiB combined (before base64, below the documented 20 MB request cap), 24 extracted receipts, 120-second timeout. Camera images use quality 85 with max 2000×2000. Batching reduces request counts; it does not eliminate image/token usage.
- Full Flutter suite: 111 passed, including zero API calls during capture, one transport call for multiple photos, multiple receipts from one image, cached-result reuse, invalid source mapping, manual fallback, explicit retries, busy protection and changed-photo confirmation. Normal/narrow capture and review fixtures rendered; normal capture was visually inspected. Changed-source analyzer was rerun after the final style fix.
- Live Android Gemini test: one generateContent request with two images returned three correct receipts in 5 seconds: real captured electricity bill 606549 on source 1; two synthetic test bills 120000 and 80000 on source 2. This demonstrates multi-image and multi-bill extraction for those samples, not guaranteed recall/accuracy for arbitrary bill layouts. Temporary smoke entry/image fixtures were removed before rebuilding the normal APK.

## Dashboard and notifications — 2026-11-05

Branch: `codex/refine-dashboard-notifications`, based on `feat/financial-dashboard-truong`.

1. Dashboard: refined. Baseline renderer capture `build/ui-before/dashboard.png` showed mixed blue/orange/purple actions, independent bordered cards, small metadata, and an emoji greeting. Replaced with shared white/violet tokens, 24px gutters, initial avatars, flat separated rows, and the existing session status component. The net figure is labelled “Công nợ ròng”; the full amount stays on one line. Large debt values stack below long names. Current captures: `build/ui-preview/dashboard.png`, `dashboard-narrow.png`, `dashboard-large-amount.png`, `dashboard-pending-narrow.png`, `dashboard-empty.png`.
2. Notifications: refined. Baseline `build/ui-before/notifications.png` incorrectly labelled pending confirmation as “CHƯA TRẢ” and used several unrelated icon colors. Current design uses shared AppTabs (“Hiện tại” / “Tất cả”), lavender icons, explicit payment/confirmation labels, and concise copy. Empty and load-error states are distinct; errors offer retry without raw Firebase instructions. Current captures: `build/ui-preview/notifications.png`, `notifications-narrow.png`, `notifications-empty.png`, `notifications-error.png`.

Compared the baseline and current captures at 390 × 844, and checked against the existing friends screen captured in the same run (`build/ui-preview/friends.png`). Narrow captures use 320 × 740 with text scale 1.3. A clipped quick-action label color and a wrapped large net amount found in the first pass were corrected and recaptured.

Validation: full Flutter suite 118 tests passed; focused dashboard/inbox render and interaction check passed again after final amount/label adjustments; final analyzer reports no issues; Android debug APK built successfully. Fixtures exercise current/all filtering, mark-all-read dispatch, persistent debt IDs excluded from locally read IDs, pending-creditor status, and dashboard destinations for debts/sessions. Existing debt/session navigation handlers and accounting calculations were retained.

Limits: deterministic Flutter renderer fixtures, not a live Firestore notification-delivery test. Native Meizu layout, screen-reader traversal, and live bank app handoff were not exercised in this pass. No claim of full accessibility compliance.

Greeting follow-up: replaced the isolated greeting line with a muted salutation above a larger display name and a 52px profile avatar. Profile images fall back to the shared initial avatar while loading or on error; blank names fall back to “Bạn”. Recaptured dashboard at both tested viewports; focused visual/interaction fixture and analyzer passed.
