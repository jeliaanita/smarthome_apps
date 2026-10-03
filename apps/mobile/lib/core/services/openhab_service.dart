import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/openhab_item.dart';

class OpenHABService {
  static final OpenHABService _instance = OpenHABService._internal();
  factory OpenHABService() => _instance;
  OpenHABService._internal();
  String _baseUrl = 'http://202.6.231.102:82';
  String? _apiToken;
  final Duration _timeout = const Duration(seconds: 10);

  // ⚠️ FIX: sebelumnya semua request pakai fungsi top-level http.get()/
  // http.post(), yang MEMBUAT KONEKSI TCP+TLS BARU dari nol setiap kali
  // dipanggil lalu langsung menutupnya lagi — tidak ada keep-alive/reuse
  // koneksi sama sekali. Di jaringan mobile dengan latency lumayan, biaya
  // handshake ini bisa ratusan ms sampai >1 detik PER REQUEST, dan kalau
  // ada beberapa request berurutan di satu halaman, semuanya numpuk jadi
  // "loading lama banget tapi akhirnya jalan" — persis gejala yang
  // dilaporkan, muncul random di semua halaman karena memang semua halaman
  // pakai pola yang sama.
  //
  // Fix: satu instance http.Client() dipakai ulang terus untuk semua
  // request di service ini, supaya koneksi TCP+TLS ke server yang sama
  // bisa dipakai berkali-kali (HTTP keep-alive) alih-alih connect ulang
  // tiap kali.
  final http.Client _client = http.Client();

  String get baseUrl => _baseUrl;

  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  void setApiToken(String token) {
    _apiToken = token;
  }

  String? _basicAuth;

  void setBasicAuth(String username, String password) {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    _basicAuth = 'Basic $credentials';
  }

  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_apiToken != null && _apiToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_apiToken';
    } else if (_basicAuth != null) {
      headers['Authorization'] = _basicAuth!;
    }
    return headers;
  }

  /// Header Authorization saja (tanpa Content-Type/Accept JSON yang gak
  /// relevan) — dipakai untuk request non-REST-API, contohnya video
  /// player yang minta stream HLS/MJPEG langsung ke file server openHAB.
  /// Tanpa ini, request video tidak membawa kredensial sama sekali dan
  /// akan selalu kena 401 kalau server openHAB butuh autentikasi.
  Map<String, String> get authHeaders {
    if (_apiToken != null && _apiToken!.isNotEmpty) {
      return {'Authorization': 'Bearer $_apiToken'};
    } else if (_basicAuth != null) {
      return {'Authorization': _basicAuth!};
    }
    return {};
  }

  Map<String, String> get _textHeaders {
    final headers = {
      'Content-Type': 'text/plain',
      'Accept': 'application/json',
    };
    if (_apiToken != null && _apiToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_apiToken';
    } else if (_basicAuth != null) {
      headers['Authorization'] = _basicAuth!;
    }
    return headers;
  }
  Future<List<OpenHABItem>> getItems({String? tags, String? type}) async {
    try {
      String url = '$_baseUrl/rest/items?recursive=false';
      if (tags != null) url += '&tags=$tags';
      if (type != null) url += '&type=$type';

      final response = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => OpenHABItem.fromJson(json)).toList();
      } else {
        throw OpenHABException('Gagal ambil items: ${response.statusCode}');
      }
    } on TimeoutException {
      throw OpenHABException('Koneksi timeout. Cek server openHAB.');
    } catch (e) {
      if (e is OpenHABException) rethrow;
      throw OpenHABException('Error: $e');
    }
  }
  Future<OpenHABItem> getItem(String itemName) async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/rest/items/$itemName'), headers: _headers)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return OpenHABItem.fromJson(jsonDecode(response.body));
      } else if (response.statusCode == 404) {
        throw OpenHABException('Item "$itemName" tidak ditemukan.');
      } else {
        throw OpenHABException('Error: ${response.statusCode}');
      }
    } on TimeoutException {
      throw OpenHABException('Koneksi timeout.');
    } catch (e) {
      if (e is OpenHABException) rethrow;
      throw OpenHABException('Error: $e');
    }
  }
  Future<bool> sendCommand(String itemName, String command) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/rest/items/$itemName'),
            headers: _textHeaders,
            body: command,
          )
          .timeout(_timeout);

      return response.statusCode == 200 || response.statusCode == 204;
    } on TimeoutException {
      throw OpenHABException('Koneksi timeout.');
    } catch (e) {
      throw OpenHABException('Gagal kirim perintah: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getLocations() async {
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/rest/items?type=Group&fields=name,label,type,tags,groupNames,category,members'),
            headers: _headers,
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw OpenHABException('Gagal ambil locations: ${response.statusCode}');
      }
    } on TimeoutException {
      throw OpenHABException('Koneksi timeout.');
    } catch (e) {
      if (e is OpenHABException) rethrow;
      throw OpenHABException('Error getLocations: $e');
    }
  }
  Future<List<OpenHABItem>> getItemsInLocation(String groupName) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/rest/items?memberOf=$groupName&recursive=true'),
            headers: _headers,
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => OpenHABItem.fromJson(json)).toList();
      } else {
        throw OpenHABException('Gagal ambil items in location: ${response.statusCode}');
      }
    } on TimeoutException {
      throw OpenHABException('Koneksi timeout.');
    } catch (e) {
      if (e is OpenHABException) rethrow;
      throw OpenHABException('Error getItemsInLocation: $e');
    }
  }

  Future<bool> turnOn(String itemName) => sendCommand(itemName, 'ON');
  Future<bool> turnOff(String itemName) => sendCommand(itemName, 'OFF');
  Future<bool> toggle(String itemName, bool currentState) =>
      sendCommand(itemName, currentState ? 'OFF' : 'ON');

  Future<bool> setBrightness(String itemName, int value) {
    final clamped = value.clamp(0, 100);
    return sendCommand(itemName, clamped.toString());
  }

  Future<bool> setColor(String itemName, String hsbValue) =>
      sendCommand(itemName, hsbValue);

  Future<List<Map<String, dynamic>>> getThings() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/rest/things'), headers: _headers)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw OpenHABException('Gagal ambil things: ${response.statusCode}');
      }
    } on TimeoutException {
      throw OpenHABException('Koneksi timeout.');
    } catch (e) {
      if (e is OpenHABException) rethrow;
      throw OpenHABException('Error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getRules() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/rest/rules'), headers: _headers)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw OpenHABException('Gagal ambil rules: ${response.statusCode}');
      }
    } on TimeoutException {
      throw OpenHABException('Koneksi timeout.');
    } catch (e) {
      if (e is OpenHABException) rethrow;
      throw OpenHABException('Error: $e');
    }
  }

  Future<bool> runRule(String ruleUid) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/rest/rules/$ruleUid/runnow'),
            headers: _headers,
          )
          .timeout(_timeout);

      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      throw OpenHABException('Gagal jalankan rule: $e');
    }
  }

  /// ⚠️ FIX: sebelumnya stream ini tidak punya heartbeat/idle-timeout sama
  /// sekali. Kalau koneksi diam-diam putus (mis. NAT timeout di jaringan
  /// seluler memotong koneksi tanpa kirim sinyal close resmi — sangat umum
  /// terjadi), stream ini akan hang selamanya menunggu data yang tidak akan
  /// pernah datang: tidak error, tidak close, jadi reconnect logic di
  /// OpenHABController._startRealTimeUpdates() (yang cuma listen ke
  /// `onError`) tidak pernah ke-trigger. Real-time update berhenti diam-diam
  /// dan satu-satunya cara "sembuh" adalah restart manual app (force close).
  ///
  /// Sekarang: kalau tidak ada data SAMA SEKALI (bahkan bukan event valid,
  /// cukup ada byte apapun masuk) selama 60 detik, dianggap koneksi macet →
  /// paksa error supaya pemanggil melakukan reconnect otomatis.
  Stream<Map<String, dynamic>> streamEvents({String? itemFilter}) {
    late StreamController<Map<String, dynamic>> controller;
    http.Client? client;
    Timer? idleTimer;
    StreamSubscription? sub;
    var closed = false;

    void cleanup() {
      if (closed) return;
      closed = true;
      idleTimer?.cancel();
      sub?.cancel();
      client?.close();
    }

    void resetIdleTimer() {
      idleTimer?.cancel();
      idleTimer = Timer(const Duration(seconds: 60), () {
        if (!controller.isClosed) {
          controller.addError(OpenHABException(
              'Tidak ada data dari server selama 60 detik — koneksi real-time kemungkinan macet, mencoba sambung ulang.'));
        }
        cleanup();
      });
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: () async {
        final url = '$_baseUrl/rest/events'
            '?topics=openhab/items${itemFilter != null ? '/$itemFilter' : ''}/statechanged';
        client = http.Client();
        try {
          final request = http.Request('GET', Uri.parse(url));
          request.headers.addAll(_headers);
          request.headers['Accept'] = 'text/event-stream';

          final response = await client!.send(request).timeout(_timeout);

          if (response.statusCode != 200) {
            if (!controller.isClosed) {
              controller.addError(OpenHABException('SSE error: ${response.statusCode}'));
            }
            cleanup();
            return;
          }

          resetIdleTimer();

          sub = response.stream.transform(utf8.decoder).listen(
            (chunk) {
              resetIdleTimer(); // ada data masuk = koneksi masih hidup
              for (final line in chunk.split('\n')) {
                if (line.startsWith('data:')) {
                  final raw = line.substring(5).trim();
                  if (raw.isNotEmpty) {
                    try {
                      if (!controller.isClosed) {
                        controller.add(jsonDecode(raw) as Map<String, dynamic>);
                      }
                    } catch (_) {}
                  }
                }
              }
            },
            onError: (e) {
              if (!controller.isClosed) controller.addError(e);
              cleanup();
            },
            onDone: () {
              if (!controller.isClosed) {
                controller.addError(OpenHABException('Koneksi SSE ditutup server.'));
              }
              cleanup();
            },
          );
        } catch (e) {
          if (!controller.isClosed) controller.addError(e);
          cleanup();
        }
      },
      onCancel: cleanup,
    );

    return controller.stream;
  }

  Future<bool> isServerReachable() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/rest/'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
class OpenHABException implements Exception {
  final String message;
  OpenHABException(this.message);

  @override
  String toString() => 'OpenHABException: $message';
}