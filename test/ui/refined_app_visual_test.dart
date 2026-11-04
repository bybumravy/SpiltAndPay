import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:splitpay/core/firebase_providers.dart';
import 'package:splitpay/core/bill_ocr.dart';
import 'package:splitpay/core/gemini_bill_scanner.dart';
import 'package:splitpay/screens/session/batch_bill_screen.dart';
import 'package:splitpay/models/app_user.dart';
import 'package:splitpay/models/friend_request.dart';
import 'package:splitpay/models/debt.dart';
import 'package:splitpay/models/expense.dart';
import 'package:splitpay/models/payment.dart';
import 'package:splitpay/models/session.dart';
import 'package:splitpay/models/session_member.dart';
import 'package:splitpay/repositories/debt_repository.dart';
import 'package:splitpay/repositories/guest_obligation_repository.dart';
import 'package:splitpay/repositories/session_repository.dart';
import 'package:splitpay/repositories/user_repository.dart';
import 'package:splitpay/screens/auth/login_screen.dart';
import 'package:splitpay/screens/auth/qr_onboarding_screen.dart';
import 'package:splitpay/screens/debt/debt_detail_screen.dart';
import 'package:splitpay/screens/friends/add_friend_screen.dart';
import 'package:splitpay/screens/home/home_screen.dart';
import 'package:splitpay/screens/session/create_session_screen.dart';
import 'package:splitpay/screens/session/session_detail_screen.dart';
import 'package:splitpay/ui/app_theme.dart';
import 'package:splitpay/ui/content_rows.dart';

class _User implements User {
  @override
  String get uid => 'hoang';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements FirebaseAuth {
  @override
  User get currentUser => _User();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Users implements UserRepository {
  @override
  Future<AppUser?> findByUid(String uid) async => users[uid];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RequestUsers extends _Users {
  final sent = <String>[];
  @override
  Future<AppUser?> findByEmail(String email) async => users['linh'];
  @override
  Future<void> sendFriendRequest(String senderId, AppUser recipient) async {
    sent.add('$senderId:${recipient.uid}');
  }

  final accepted = <String>[];
  final dismissed = <String>[];
  @override
  Future<void> acceptFriendRequest(FriendRequest request) async {
    accepted.add(request.id);
  }

  @override
  Future<void> dismissFriendRequest(FriendRequest request) async {
    dismissed.add(request.id);
  }
}

const users = {
  'hoang': AppUser(uid: 'hoang', name: 'Hoàng', email: 'hoang@example.com'),
  'linh': AppUser(uid: 'linh', name: 'Linh', email: 'linh@example.com'),
  'nam': AppUser(uid: 'nam', name: 'Nam', email: 'nam@example.com'),
};
final session = Session(
  sessionId: 'dalat',
  creatorId: 'hoang',
  title: 'Đà Lạt',
  totalAmount: 1200000,
  splitMode: SessionSplitMode.equal,
  status: SessionStatus.open,
  memberUserIds: const ['hoang', 'linh', 'nam'],
  createdAt: DateTime(2026, 11, 4),
);
const members = [
  SessionMember(
    memberId: 'hoang',
    userId: 'hoang',
    displayName: 'Hoàng',
    isGuest: false,
    amountOwed: 433334,
    amountPaid: 1200000,
    status: MemberStatus.self,
  ),
  SessionMember(
    memberId: 'linh',
    userId: 'linh',
    displayName: 'Linh',
    isGuest: false,
    amountOwed: 433333,
    status: MemberStatus.ledger,
  ),
  SessionMember(
    memberId: 'nam',
    userId: 'nam',
    displayName: 'Nam',
    isGuest: false,
    amountOwed: 333333,
    status: MemberStatus.ledger,
  ),
];
const expenses = [
  Expense(
    expenseId: 'dinner',
    description: 'Ăn tối',
    amount: 200000,
    payerId: 'hoang',
    participantIds: ['hoang', 'linh'],
    shares: {'hoang': 100000, 'linh': 100000},
  ),
  Expense(
    expenseId: 'stay',
    description: 'Chỗ nghỉ',
    amount: 1000000,
    payerId: 'hoang',
    participantIds: ['hoang', 'linh', 'nam'],
    shares: {'hoang': 333334, 'linh': 333333, 'nam': 333333},
    sequence: 1,
  ),
];
final debts = [
  Debt(
    userA: 'hoang',
    userB: 'linh',
    balance: 150000,
    updatedAt: DateTime(2026, 11, 4),
  ),
  Debt(
    userA: 'hoang',
    userB: 'nam',
    balance: -80000,
    updatedAt: DateTime(2026, 11, 4),
  ),
];

Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(390, 844),
  double textScale = 1,
  UserRepository? previewRepository,
  List<FriendRequest> previewRequests = const [],
  Session? previewSession,
  List<SessionMember>? previewMembers,
  List<Expense>? previewExpenses,
  List<Debt>? previewDebts,
  Map<String, AppUser>? previewUsers,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  tester.view.devicePixelRatio = 1;
  await tester.binding.setSurfaceSize(size);
  final push =
      screen is SessionDetailScreen ||
      screen is CreateSessionScreen ||
      screen is DebtDetailScreen ||
      screen is AddFriendScreen;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWithValue(_Auth()),
        userRepositoryProvider.overrideWithValue(previewRepository ?? _Users()),
        for (final user in {...users, ...?previewUsers}.values)
          currentUserProvider(user.uid)
              .overrideWith((ref) => Stream.value(user)),
        friendRequestsProvider('hoang')
            .overrideWith((ref) => Stream.value(previewRequests)),
        contactsProvider(
          'hoang',
        ).overrideWith((ref) => Stream.value([users['linh']!, users['nam']!])),
        userSessionsProvider('hoang')
            .overrideWith((ref) => Stream.value([previewSession ?? session])),
        sessionMembersProvider('dalat')
            .overrideWith((ref) => Stream.value(previewMembers ?? members)),
        sessionExpensesProvider('dalat')
            .overrideWith((ref) => Stream.value(previewExpenses ?? expenses)),
        sessionGuestObligationsProvider('dalat')
            .overrideWith((ref) => Stream.value([])),
        userDebtsProvider('hoang')
            .overrideWith((ref) => Stream.value(previewDebts ?? debts)),
        paymentsProvider('hoang_linh')
            .overrideWith((ref) => Stream.value(<Payment>[])),
      ],
      child: MaterialApp(
        theme: AppTheme.material,
        localizationsDelegates: FLocalizations.localizationsDelegates,
        supportedLocales: FLocalizations.supportedLocales,
        builder: (context, child) => FTheme(
          data: AppTheme.forui,
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
        home: push ? const Scaffold() : screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (push) {
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    await tester.pumpAndSettle();
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/ui-preview/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final root =
        Platform.environment['FLUTTER_ROOT'] ??
        File(Platform.resolvedExecutable)
            .parent
            .parent
            .parent
            .parent
            .parent
            .path;
    final fonts = '$root/bin/cache/artifacts/material_fonts';
    final loader = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(
        File('$fonts/Roboto-$weight.ttf')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)),
      );
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File('$fonts/MaterialIcons-Regular.otf')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)),
      );
    await icons.load();
  });
  testWidgets('preview primary screens and navigation at phone size', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.binding.setSurfaceSize(null);
    });
    await pumpScreen(tester, const HomeScreen());
    await capture(tester, 'sessions');
    await tester.tap(find.text('Công nợ').last);
    await tester.pumpAndSettle();
    await capture(tester, 'debts');
    await tester.tap(find.text('Hồ sơ').last);
    await tester.pumpAndSettle();
    await capture(tester, 'profile');
    await pumpScreen(
      tester,
      SessionDetailScreen(session: session, currentUid: 'hoang'),
    );
    await capture(tester, 'session-detail');
    expect(find.text('Người trả: Hoàng'), findsNWidgets(2));
    expect(find.textContaining('bạn vẫn có thể'), findsNothing);
    await tester.ensureVisible(find.text('Chỗ nghỉ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chỗ nghỉ'));
    await tester.pumpAndSettle();
    expect(find.text('Chia cho 3 người'), findsOneWidget);
    await pumpScreen(
      tester,
      CreateSessionScreen(
        creatorUid: 'hoang',
        initialSession: session,
        initialMembers: members,
        initialExpenses: expenses,
      ),
    );
    await capture(tester, 'session-editor');
    await pumpScreen(tester, const LoginScreen());
    await capture(tester, 'login');
    await tester.tap(find.text('Chưa có tài khoản? Đăng ký'));
    await tester.pumpAndSettle();
    await capture(tester, 'signup');
    expect(find.text('Họ và tên'), findsOneWidget);
    await pumpScreen(tester, const QrOnboardingScreen(uid: 'hoang'));
    await capture(tester, 'qr-onboarding');
    await pumpScreen(
      tester,
      DebtDetailScreen(debt: debts.first, currentUid: 'hoang'),
    );
    await capture(tester, 'debt-detail');
    await pumpScreen(tester, const AddFriendScreen(currentUid: 'hoang'));
    await capture(tester, 'friends');
    expect(tester.takeException(), isNull);
  });
  testWidgets('phone layouts support narrow screens and large text', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.binding.setSurfaceSize(null);
    });
    await pumpScreen(
      tester,
      SessionDetailScreen(session: session, currentUid: 'hoang'),
      size: const Size(320, 740),
      textScale: 1.3,
    );
    await capture(tester, 'session-detail-narrow');
    expect(tester.takeException(), isNull);
    await pumpScreen(
      tester,
      const HomeScreen(),
      size: const Size(320, 740),
      textScale: 1.3,
    );
    expect(find.byType(ChoiceChip), findsNothing);
    await tester.tap(find.text('Phiên').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(Tab, 'Đã đóng'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Đã đóng'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có phiên nào'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'sessions-tabs-narrow');
    await pumpScreen(
      tester,
      const LoginScreen(),
      size: const Size(320, 740),
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'member spacing follows actual content for zero one two three and many people',
    (tester) async {
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.binding.setSurfaceSize(null);
      });
      for (final narrow in [false, true]) {
        for (final count in [0, 1, 2, 3, 8]) {
          final total = count == 0
              ? 0
              : count == 1
              ? 1200000
              : 9876543210;
          final sample = Session(
            sessionId: session.sessionId,
            creatorId: session.creatorId,
            title: session.title,
            totalAmount: total,
            splitMode: session.splitMode,
            status: session.status,
            memberUserIds: [
              for (var i = 0; i < count; i++) i == 0 ? 'hoang' : 'person-$i',
            ],
            createdAt: session.createdAt,
          );
          final people = List.generate(
            count,
            (i) => SessionMember(
              memberId: i == 0 ? 'hoang' : 'person-$i',
              userId: i == 0 ? 'hoang' : 'person-$i',
              displayName: count == 1
                  ? 'Hoàng'
                  : i == 0
                  ? 'Hoàng'
                  : 'Nguyễn Minh Anh với tên dài $i',
              isGuest: false,
              amountOwed: count == 0 ? 0 : total ~/ count,
              status: MemberStatus.ledger,
            ),
          );
          final items = count == 0
              ? <Expense>[]
              : [
                  Expense(
                    expenseId: 'sizing-$count',
                    description: 'Ăn tối cùng nhóm sau chuyến đi',
                    amount: total,
                    payerId: 'hoang',
                    participantIds: people.map((m) => m.memberId).toList(),
                    shares: {
                      for (final p in people) p.memberId: total ~/ count,
                    },
                  ),
                ];
          await pumpScreen(
            tester,
            SessionDetailScreen(session: sample, currentUid: 'hoang'),
            size: narrow ? const Size(320, 740) : const Size(390, 844),
            textScale: narrow ? 1.3 : 1,
            previewSession: sample,
            previewMembers: people,
            previewExpenses: items,
          );
          final label = tester.getRect(
            find.byKey(const ValueKey('session-member-summary-label')),
          );
          if (count == 0) {
            expect(find.byType(MemberAvatarGroup), findsNothing);
            expect(label.left, 24);
            expect(find.text('Chưa có thành viên'), findsOneWidget);
          } else {
            final avatars = tester.getRect(
              find.byKey(const ValueKey('session-member-avatars')),
            );
            expect(avatars.width, 36 + (count.clamp(1, 3) - 1) * 24);
            expect(
              label.left - avatars.right,
              closeTo(12, 0.5),
              reason: 'Gap must stay 12px for $count members',
            );
            if (count > 3) expect(find.text('+6'), findsOneWidget);
          }
          expect(
            tester.takeException(),
            isNull,
            reason: '$count members, narrow=$narrow',
          );
          await capture(tester, 'members-$count${narrow ? '-narrow' : ''}');
          if (count > 0) {
            await tester.tap(
              find.byKey(const ValueKey('session-member-summary-label')),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: 'Expanded $count members, narrow=$narrow',
            );
            await capture(
              tester,
              'members-$count-expanded${narrow ? '-narrow' : ''}',
            );
          }
        }
      }
    },
  );

  testWidgets(
    'long names and large debt amounts preserve gutters and row alignment',
    (tester) async {
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.binding.setSurfaceSize(null);
      });
      await pumpScreen(
        tester,
        const HomeScreen(),
        size: const Size(320, 740),
        textScale: 1.3,
        previewUsers: {
          'linh': const AppUser(
            uid: 'linh',
            name: 'Nguyễn Thị Linh với tên rất dài',
            email: 'linh@example.com',
          ),
        },
        previewDebts: [
          Debt(
            userA: 'hoang',
            userB: 'linh',
            balance: 9876543210,
            updatedAt: DateTime(2026),
          ),
        ],
      );
      await tester.tap(find.text('Công nợ').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, 'debts-long-content');
      await tester.tap(find.text('Hồ sơ').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, 'profile-narrow');
    },
  );
  testWidgets(
    'incoming invites can be accepted or rejected and outgoing invites cancelled',
    (tester) async {
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.binding.setSurfaceSize(null);
      });
      final repo = _RequestUsers();
      await pumpScreen(
        tester,
        const AddFriendScreen(currentUid: 'hoang'),
        previewRepository: repo,
        previewRequests: const [
          FriendRequest(
            id: 'linh_hoang',
            senderId: 'linh',
            recipientId: 'hoang',
            senderName: 'Linh',
            recipientName: 'Hoàng',
          ),
          FriendRequest(
            id: 'hoang_nam',
            senderId: 'hoang',
            recipientId: 'nam',
            senderName: 'Hoàng',
            recipientName: 'Nam',
          ),
        ],
      );
      await tester.ensureVisible(find.widgetWithText(Tab, 'Lời mời'));
      await tester.tap(find.widgetWithText(Tab, 'Lời mời'));
      await tester.pumpAndSettle();
      expect(find.text('Chấp nhận'), findsOneWidget);
      expect(find.text('Huỷ lời mời'), findsOneWidget);
      await tester.tap(find.text('Chấp nhận'));
      await tester.pumpAndSettle();
      expect(repo.accepted, ['linh_hoang']);
      await tester.tap(find.text('Từ chối'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Huỷ lời mời'));
      await tester.tap(find.text('Huỷ lời mời'));
      await tester.pumpAndSettle();
      expect(repo.dismissed, ['linh_hoang', 'hoang_nam']);
      expect(tester.takeException(), isNull);
      await capture(tester, 'friend-requests');
      expect(find.text('Tìm bạn bè'), findsNothing);
      await pumpScreen(
        tester,
        const AddFriendScreen(currentUid: 'hoang'),
        size: const Size(320, 740),
        textScale: 1.3,
        previewRepository: repo,
        previewRequests: const [
          FriendRequest(
            id: 'long_hoang',
            senderId: 'long',
            recipientId: 'hoang',
            senderName: 'Nguyễn Minh Anh với tên rất dài',
            recipientName: 'Hoàng',
          ),
        ],
      );
      await tester.ensureVisible(find.widgetWithText(Tab, 'Lời mời'));
      await tester.tap(find.widgetWithText(Tab, 'Lời mời'));
      await tester.pumpAndSettle();
      expect(find.text('Nguyễn Minh Anh với tên rất dài'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'friend-requests-narrow');
    },
  );
  testWidgets(
    'email search sends an invitation instead of adding a friend directly',
    (tester) async {
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.binding.setSurfaceSize(null);
      });
      final repo = _RequestUsers();
      await pumpScreen(
        tester,
        const AddFriendScreen(currentUid: 'hoang'),
        previewRepository: repo,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Email bạn bè'),
        'linh@example.com',
      );
      await tester.tap(find.byIcon(Icons.search).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Gửi lời mời'));
      await tester.pumpAndSettle();
      expect(repo.sent, ['hoang:linh']);
      expect(repo.accepted, isEmpty);
      expect(find.text('Đã gửi lời mời đến Linh'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'QR requires sender confirmation and cancel never sends an invitation',
    (tester) async {
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.binding.setSurfaceSize(null);
      });
      final repo = _RequestUsers();
      await pumpScreen(
        tester,
        const AddFriendScreen(currentUid: 'hoang'),
        previewRepository: repo,
      );
      await tester.tap(find.widgetWithText(Tab, 'Quét QR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      void scan() => tester
          .widget<MobileScanner>(find.byType(MobileScanner))
          .onDetect!(BarcodeCapture(barcodes: [Barcode(rawValue: 'linh')]));
      scan();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Gửi lời mời kết bạn?'), findsOneWidget);
      expect(find.text('linh@example.com'), findsWidgets);
      expect(repo.sent, isEmpty);
      await tester.tap(find.text('Huỷ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repo.sent, isEmpty);
      scan();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Gửi lời mời kết bạn?'), findsNothing);
      await tester.tap(find.text('Quét lại'));
      scan();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Gửi lời mời'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repo.sent, ['hoang:linh']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('batch bill review fits phone and narrow large-text layouts', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.binding.setSurfaceSize(null);
    });
    for (final narrow in [false, true]) {
      await pumpScreen(
        tester,
        BatchBillScreen(
          members: const {'hoang': 'Hoàng', 'linh': 'Linh', 'nam': 'Nam'},
          payerIds: const {'hoang', 'linh', 'nam'},
          initialPayerId: 'hoang',
          capture: () async => '/preview-bill.jpg',
          scan: (_) async => const BillBatchResult(
            receipts: [
              BillReceipt(
                0,
                BillScanResult(
                  total: 350000,
                  confident: true,
                  candidates: [350000],
                ),
              ),
            ],
          ),
        ),
        size: narrow ? const Size(320, 740) : const Size(390, 844),
        textScale: narrow ? 1.3 : 1,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Chụp hoá đơn'));
      await tester.pumpAndSettle();
      expect(find.text('350.000'), findsNothing);
      await capture(tester, narrow ? 'batch-photos-narrow' : 'batch-photos');
      await tester.tap(find.text('Đọc 1 ảnh'));
      await tester.pumpAndSettle();
      expect(find.text('350.000'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, narrow ? 'batch-bills-narrow' : 'batch-bills');
    }
  });
}
