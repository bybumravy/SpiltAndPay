/// Model người dùng đã đăng ký app.
class AppUser {
  final String uid;
  final String name;
  final String email;
  final String? avatarUrl;

  /// URL ảnh QR ngân hàng tĩnh (trên Cloudinary).
  /// null nghĩa là user chưa hoàn thành onboarding.
  final String? qrImageUrl;

  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    this.avatarUrl,
    this.qrImageUrl,
  });

  bool get hasQr => qrImageUrl != null && qrImageUrl!.isNotEmpty;

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      avatarUrl: map['avatarUrl'] as String?,
      qrImageUrl: map['qrImageUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'emailLower': email.toLowerCase(),
      'avatarUrl': avatarUrl,
      'qrImageUrl': qrImageUrl,
    };
  }

  AppUser copyWith({
    String? name,
    String? avatarUrl,
    String? qrImageUrl,
  }) {
    return AppUser(
      uid: uid,
      name: name ?? this.name,
      email: email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      qrImageUrl: qrImageUrl ?? this.qrImageUrl,
    );
  }
}
