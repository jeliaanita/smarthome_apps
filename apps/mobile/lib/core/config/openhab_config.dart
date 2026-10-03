import 'package:shared_preferences/shared_preferences.dart';

// ignore: avoid_classes_with_only_static_members
class OpenHABConfig {
  static const _keyBaseUrl  = 'openhab_base_url';

  static const defaultUrl = 'http://202.6.231.102:82';

  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBaseUrl) ?? defaultUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    await prefs.setString(_keyBaseUrl, clean);
  }

  // ⚠️ CATATAN KEAMANAN: method untuk kredensial (token/username/password)
  // SENGAJA DIHAPUS dari class ini. Kredensial sekarang disimpan lewat
  // InstallationProvider (Firestore-backed) — lihat _ServerConfigSheetMinState
  // di hub_connectivity_page.dart untuk alur simpannya. SharedPreferences
  // (yang dipakai class ini) TIDAK terenkripsi — bisa dibaca langsung di
  // device yang di-root/jailbreak. Jangan tambahkan lagi method kredensial
  // di sini; kalau butuh cache lokal untuk kredensial, pakai secure storage
  // (mis. package flutter_secure_storage yang berbasis Keychain/Keystore),
  // bukan SharedPreferences.

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyBaseUrl);
  }

  static bool isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && uri.host.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}