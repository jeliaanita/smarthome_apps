import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

class _CredentialCipher {
  static const _appSecret =
      'b2cf53ab0ffe7179fafdf58b394853d463cefab41ae9a8256aba644e7b14a146';

  static enc.Key get _key => enc.Key(
      Uint8List.fromList(sha256.convert(utf8.encode(_appSecret)).bytes));

  static String encryptText(String plain) {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plain, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  /// Dekripsi. Kalau formatnya tidak sesuai (mis. data lama sebelum fitur
  /// enkripsi ini ada) atau gagal decrypt, kembalikan nilai aslinya apa
  /// adanya — supaya tidak crash & tidak diam-diam menghilangkan data lama.
  static String? decryptText(String? stored) {
    if (stored == null || stored.isEmpty) return stored;
    final parts = stored.split(':');
    if (parts.length != 2) return stored;
    try {
      final iv = enc.IV.fromBase64(parts[0]);
      final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc));
      return encrypter.decrypt64(parts[1], iv: iv);
    } catch (_) {
      return stored;
    }
  }
}

class InstallationConfig {
  final String openhabUrl;
  final String? apiToken;
  final String? username;
  final String? password;

  const InstallationConfig({
    required this.openhabUrl,
    this.apiToken,
    this.username,
    this.password,
  });

  factory InstallationConfig.fromMap(Map<String, dynamic> map) {
    return InstallationConfig(
      openhabUrl: map['openhabUrl'] as String? ?? '',
      apiToken: _CredentialCipher.decryptText(map['openhabToken'] as String?),
      username: _CredentialCipher.decryptText(map['openhabUsername'] as String?),
      password: _CredentialCipher.decryptText(map['openhabPassword'] as String?),
    );
  }

  Map<String, dynamic> toMap() => {
        'openhabUrl': openhabUrl,
        if (apiToken != null) 'openhabToken': _CredentialCipher.encryptText(apiToken!),
        if (username != null) 'openhabUsername': _CredentialCipher.encryptText(username!),
        if (password != null) 'openhabPassword': _CredentialCipher.encryptText(password!),
      };
}

class InstallationService {
  static final _db = FirebaseFirestore.instance;

  static Future<String?> getMyInstallationId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final doc = await _db.collection('users').doc(user.uid).get();
    return doc.data()?['installationId'] as String?;
  }

  static Future<InstallationConfig?> getConfig(String installationId) async {
    final doc =
        await _db.collection('installations').doc(installationId).get();
    if (!doc.exists) return null;
    return InstallationConfig.fromMap(doc.data()!);
  }

  static Future<InstallationConfig?> getMyConfig() async {
    final installationId = await getMyInstallationId();
    if (installationId == null) return null;
    return getConfig(installationId);
  }

  static Future<void> updateConfig({
    required String installationId,
    required String openhabUrl,
    String? apiToken,
    String? username,
    String? password,
  }) async {
    await _db.collection('installations').doc(installationId).set(
      {
        'openhabUrl': openhabUrl,
        if (apiToken != null && apiToken.isNotEmpty)
          'openhabToken': _CredentialCipher.encryptText(apiToken),
        if (username != null && username.isNotEmpty)
          'openhabUsername': _CredentialCipher.encryptText(username),
        if (password != null && password.isNotEmpty)
          'openhabPassword': _CredentialCipher.encryptText(password),
      },
      SetOptions(merge: true),
    );
  }
}