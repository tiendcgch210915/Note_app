/// Người dùng — mirror UserPublic shape của backend.
class User {
  final String id;
  final String email;
  final String? displayName;
  final String? avatarUrl;
  final String timezone;

  const User({
    required this.id,
    required this.email,
    this.displayName,
    this.avatarUrl,
    this.timezone = 'Asia/Ho_Chi_Minh',
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      timezone: (json['timezone'] as String?) ?? 'Asia/Ho_Chi_Minh',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'timezone': timezone,
      };
}
