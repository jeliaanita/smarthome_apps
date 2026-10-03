import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String email;
  final String role; // 'admin' | 'user'
  final String? installationId;

  const AppUser({
    required this.uid,
    required this.email,
    required this.role,
    this.installationId,
  });

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AppUser(
      uid: doc.id,
      email: data['email'] as String? ?? '(email tidak tersimpan)',
      role: data['role'] as String? ?? 'user',
      installationId: data['installationId'] as String?,
    );
  }

  bool get isAdmin => role == 'admin';
}

class UserManagementService {
  static final _db = FirebaseFirestore.instance;

  /// ADMIN ONLY (dijaga Firestore Rules) — ambil semua user
  static Stream<List<AppUser>> watchAllUsers() {
    return _db.collection('users').snapshots().map(
          (snap) => snap.docs.map((d) => AppUser.fromDoc(d)).toList(),
        );
  }

  /// ADMIN ONLY — assign role & installationId ke user tertentu
  static Future<void> updateUser({
    required String uid,
    String? role,
    String? installationId,
  }) async {
    await _db.collection('users').doc(uid).set(
      {
        if (role != null) 'role': role,
        if (installationId != null) 'installationId': installationId,
      },
      SetOptions(merge: true),
    );
  }

  /// ADMIN ONLY — ambil daftar installationId yang sudah ada,
  /// buat dropdown pilihan (bukan bikin baru)
  static Future<List<String>> listInstallationIds() async {
    final snap = await _db.collection('installations').get();
    return snap.docs.map((d) => d.id).toList();
  }
}
