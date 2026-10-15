import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase_providers.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/user_repository.dart';
import '../friends/add_friend_screen.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseUser = ref.watch(authProvider).currentUser;
    if (firebaseUser == null) return const SizedBox.shrink();

    final userAsync = ref.watch(currentUserProvider(firebaseUser.uid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hồ sơ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Đăng xuất',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Đăng xuất'),
                  content: const Text('Bạn có chắc muốn đăng xuất?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Huỷ'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Đăng xuất'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await ref.read(authRepositoryProvider).signOut();
              }
            },
          ),
        ],
      ),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (user) {
          if (user == null) return const Center(child: Text('Không tải được hồ sơ'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Avatar + tên + email
              Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundImage: user.avatarUrl != null
                        ? CachedNetworkImageProvider(user.avatarUrl!)
                        : null,
                    child: user.avatarUrl == null
                        ? Text(
                            user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 24),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(user.email,
                            style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // QR nhận tiền
              Text('QR nhận tiền',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              if (user.qrImageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: user.qrImageUrl!,
                    height: 200,
                    fit: BoxFit.contain,
                    placeholder: (ctx, url) =>
                        const Center(child: CircularProgressIndicator()),
                    errorWidget: (ctx, url, err) =>
                        const Icon(Icons.broken_image, size: 64),
                  ),
                ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),

              // Bạn bè
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('Bạn bè'),
                trailing: const Icon(Icons.chevron_right),
                contentPadding: EdgeInsets.zero,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddFriendScreen(currentUid: user.uid),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
