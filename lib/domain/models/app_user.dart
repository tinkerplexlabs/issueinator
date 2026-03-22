class AppUser {
  final String id;
  final String? email;
  final String? displayName;

  const AppUser({
    required this.id,
    this.email,
    this.displayName,
  });

  factory AppUser.fromSupabaseUser(dynamic user) {
    return AppUser(
      id: user.id as String,
      email: user.email as String?,
      displayName: user.userMetadata?['full_name'] as String?,
    );
  }
}
