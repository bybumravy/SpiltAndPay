# Graph Report - splitpay  (2026-11-02)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 658 nodes · 866 edges · 31 communities (24 shown, 7 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 31,391 input · 265 output

## Graph Freshness
- Built from commit: `b552a6c6`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Authentication State Management
- App Structure and Navigation
- Debt Data Model
- Dynamic VietQR Generation
- Debt Payment Repository
- Session Creation Flow
- Image Processing Utilities
- Flutter Dependencies
- Friend Management UI
- Core Logic Tests
- Firebase Authentication Repository
- Debt Simplification Algorithm
- User Profile Model
- Session Settlement Logic
- Bill OCR Processing
- Firebase Rules Testing
- Home Screen Navigation
- QR Onboarding Upload
- Money Splitting Utilities
- Cloudinary Upload Service
- VietQR Unit Tests
- Stateful Screen Widgets
- Friend Management Actions
- Dart Lint Configuration
- Image Utilities Tests
- Android App Entry
- Development Mode Flag

## God Nodes (most connected - your core abstractions)
1. `dependencies` - 20 edges
2. `currentUserProvider` - 14 edges
3. `userRepositoryProvider` - 11 edges
4. `authProvider` - 7 edges
5. `authRepositoryProvider` - 6 edges
6. `sessionRepositoryProvider` - 6 edges
7. `_MemberTileState` - 6 edges
8. `staticQrPayloadProvider` - 6 edges
9. `_DebtorActionsState` - 6 edges
10. `_AddFriendScreenState` - 6 edges

## Surprising Connections (you probably didn't know these)
- `_handleEmailSubmit` --references--> `authRepositoryProvider`  [EXTRACTED]
  lib/screens/auth/login_screen.dart → lib/repositories/auth_repository.dart
- `_handleGoogleSignIn` --references--> `authRepositoryProvider`  [EXTRACTED]
  lib/screens/auth/login_screen.dart → lib/repositories/auth_repository.dart
- `_LoginScreenState` --references--> `authRepositoryProvider`  [EXTRACTED]
  lib/screens/auth/login_screen.dart → lib/repositories/auth_repository.dart
- `_confirmClose` --references--> `sessionRepositoryProvider`  [EXTRACTED]
  lib/screens/session/session_detail_screen.dart → lib/repositories/session_repository.dart
- `_editTitle` --references--> `sessionRepositoryProvider`  [EXTRACTED]
  lib/screens/session/session_detail_screen.dart → lib/repositories/session_repository.dart

## Import Cycles
- None detected.

## Communities (31 total, 7 thin omitted)

### Community 0 - "Authentication State Management"
Cohesion: 0.06
Nodes (42): AuthGate, build, authProvider, authStateProvider, Session, authRepositoryProvider, sessionMembersProvider, sessionRepositoryProvider (+34 more)

### Community 1 - "App Structure and Navigation"
Cohesion: 0.05
Nodes (16): android, DefaultFirebaseOptions, initializeApp, main, build, createState, dispose, _emailController (+8 more)

### Community 2 - "Debt Data Model"
Cohesion: 0.05
Nodes (36): amountOwedBy, balance, balanceDelta, creditorFor, Debt, docId, fromMap, toMap (+28 more)

### Community 3 - "Dynamic VietQR Generation"
Cohesion: 0.05
Nodes (39): account, b, beneficiary, bin, body, buildDynamicVietQr, capture, cleaned (+31 more)

### Community 4 - "Debt Payment Repository"
Cohesion: 0.06
Nodes (36): staticQrPayloadProvider, confirmPayment, _db, DebtRepository, debtRepositoryProvider, _debts, markTransferred, paymentsProvider (+28 more)

### Community 5 - "Session Creation Flow"
Cohesion: 0.05
Nodes (33): alreadyAddedUids, createState, creatorUid, _ctrl, currentUid, customAmount, dispose, _editGuestName (+25 more)

### Community 6 - "Image Processing Utilities"
Cohesion: 0.06
Nodes (32): buildPaymentCard, canvas, codec, data, _decode, dir, downloadImageBytes, file (+24 more)

### Community 7 - "Flutter Dependencies"
Cohesion: 0.06
Nodes (33): dependencies, cached_network_image, cloud_firestore, cupertino_icons, firebase_auth, firebase_core, flutter, flutter_riverpod (+25 more)

### Community 8 - "Friend Management UI"
Cohesion: 0.07
Nodes (26): SplitPayApp, contactsProvider, _CreditorSection, AddFriendScreen, _AddFriendScreenState, build, _contactSearch, controller (+18 more)

### Community 9 - "Core Logic Tests"
Cohesion: 0.08
Nodes (16): main, best, _bruteMaxGroups, _debt, _expectSettles, first, left, main (+8 more)

### Community 10 - "Firebase Authentication Repository"
Cohesion: 0.07
Nodes (21): firestoreProvider, watch, _auth, AuthRepository, signInWithEmail, signInWithGoogle, signOut, signUpWithEmail (+13 more)

### Community 11 - "Debt Simplification Algorithm"
Cohesion: 0.07
Nodes (29): amount, _byAmountThenUid, c, creditors, current, debtors, dp, entries (+21 more)

### Community 12 - "User Profile Model"
Cohesion: 0.08
Nodes (22): AppUser, avatarUrl, copyWith, email, fromMap, hasQr, name, qrImageUrl (+14 more)

### Community 13 - "Session Settlement Logic"
Cohesion: 0.08
Nodes (20): guestOwed, legacy, net, paidSum, settleSession, simplifyDebts, totalOwed, closeSession (+12 more)

### Community 14 - "Bill OCR Processing"
Cohesion: 0.09
Nodes (20): all, _amountsIn, _amountToken, BillScanResult, candidates, confident, digits, _excludeKeywords (+12 more)

### Community 15 - "Firebase Rules Testing"
Cohesion: 0.10
Nodes (12): firebase, @firebase/rules-unit-testing, firebase-tools, devDependencies, firebase@^11.0.0, @firebase/rules-unit-testing@^4.0.1, firebase-tools@^14.0.0, name (+4 more)

### Community 16 - "Home Screen Navigation"
Cohesion: 0.16
Nodes (9): _QrScanTab, _QrScanTabState, build, createState, _currentIndex, HomeScreen, _HomeScreenState, _CustomAmountField (+1 more)

### Community 17 - "QR Onboarding Upload"
Cohesion: 0.14
Nodes (8): build, createState, _errorMessage, isChange, _isUploading, _pickedImage, _pickImage, uid

### Community 18 - "Money Splitting Utilities"
Cohesion: 0.15
Nodes (11): base, computeShares, customSum, formatter, formatVnd, generate, next, remainder (+3 more)

### Community 19 - "Cloudinary Upload Service"
Cohesion: 0.17
Nodes (8): body, _cloudName, json, request, response, _uploadPreset, uploadToCloudinary, uri

### Community 20 - "VietQR Unit Tests"
Cohesion: 0.17
Nodes (9): VietQrException, beneficiary, body, _field, i, main, merchant, _staticQr (+1 more)

### Community 21 - "Stateful Screen Widgets"
Cohesion: 0.27
Nodes (8): LoginScreen, _LoginScreenState, QrOnboardingScreen, _QrOnboardingScreenState, _AddMemberSheet, _AddMemberSheetState, CreateSessionScreen, _CreateSessionScreenState

### Community 22 - "Friend Management Actions"
Cohesion: 0.29
Nodes (7): userRepositoryProvider, _upload, _addContact, _handleScannedUid, _searchByEmail, _scanFriendQr, _submit

### Community 23 - "Dart Lint Configuration"
Cohesion: 0.33
Nodes (5): analyzer, exclude, include, linter, rules

## Knowledge Gaps
- **371 isolated node(s):** `_confirmDelete`, `currentUid`, `session`, `_confirmDelete`, `createState` (+366 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 467 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `VietQrException` connect `VietQR Unit Tests` to `Dynamic VietQR Generation`?**
  _High betweenness centrality (0.016) - this node is a cross-community bridge._
- **What connects `_confirmDelete`, `currentUid`, `session` to the rest of the system?**
  _371 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Authentication State Management` be split into smaller, more focused modules?**
  _Cohesion score 0.057329462989840346 - nodes in this community are weakly interconnected._
- **Why does `Debt` connect `Debt Data Model` to `App Structure and Navigation`, `Debt Payment Repository`?**
  _High betweenness centrality (0.012) - this node is a cross-community bridge._
- **Should `App Structure and Navigation` be split into smaller, more focused modules?**
  _Cohesion score 0.05087881591119334 - nodes in this community are weakly interconnected._
- **Why does `Payment` connect `Debt Data Model` to `Debt Payment Repository`?**
  _High betweenness centrality (0.010) - this node is a cross-community bridge._
- **Should `Debt Data Model` be split into smaller, more focused modules?**
  _Cohesion score 0.048625792811839326 - nodes in this community are weakly interconnected._