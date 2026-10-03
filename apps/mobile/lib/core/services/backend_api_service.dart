import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class BackendApiService {
  static const _baseUrl =
      'https://us-central1-<PROJECT_ID>.cloudfunctions.net';

  static Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Belum login');
    final idToken = await user.getIdToken();
    return {
      'Authorization': 'Bearer $idToken',
      'Content-Type': 'application/json',
    };
  }
  static Future<List<dynamic>> getThings() async {
    final headers = await _authHeaders();
    final res = await http.get(Uri.parse('$_baseUrl/getThings'),
        headers: headers);
    _checkStatus(res);
    return jsonDecode(res.body) as List<dynamic>;
  }

  static Future<void> sendItemCommand(String itemName, String command) async {
    final headers = await _authHeaders();
    final res = await http.post(
      Uri.parse('$_baseUrl/sendItemCommand?itemName=$itemName'),
      headers: headers,
      body: jsonEncode({'command': command}),
    );
    _checkStatus(res);
  }

  static Future<void> addThing(Map<String, dynamic> payload) async {
    final headers = await _authHeaders();
    final res = await http.post(
      Uri.parse('$_baseUrl/addThing'),
      headers: headers,
      body: jsonEncode(payload),
    );
    _checkStatus(res); 
  }
  
  static Future<void> updateServerConfig({
    required String openhabUrl,
    String? token,
    String? username,
    String? password,
  }) async {
    final headers = await _authHeaders();
    final res = await http.put(
      Uri.parse('$_baseUrl/updateServerConfig'),
      headers: headers,
      body: jsonEncode({
        'openhabUrl': openhabUrl,
        if (token != null) 'openhabToken': token,
        if (username != null) 'openhabUsername': username,
        if (password != null) 'openhabPassword': password,
      }),
    );
    _checkStatus(res);
  }

  static void _checkStatus(http.Response res) {
    if (res.statusCode == 403) {
      throw Exception('Kamu tidak punya izin untuk aksi ini (admin only)');
    }
    if (res.statusCode == 401) {
      throw Exception('Sesi login habis, silakan login ulang');
    }
    if (res.statusCode >= 400) {
      throw Exception('Request gagal (${res.statusCode})');
    }
  }
}
