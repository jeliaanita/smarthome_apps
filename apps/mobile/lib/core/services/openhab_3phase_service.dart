import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'mqtt_service_3phase.dart' show PowerMeter3PhaseData;

/// Sumber data 3-phase = openHAB REST API, BUKAN koneksi MQTT langsung dari
/// app. Alasannya: openHAB sudah tahu persis topic, struktur payload, dan
/// status koneksi device yang benar (Thing-nya sudah dikonfigurasi & terbukti
/// ONLINE) — jadi app tinggal "nanya ke openHAB", tidak perlu duplikat logic
/// MQTT + nebak-nebak field lagi. Status ONLINE/OFFLINE di app ini akan
/// selalu sama persis dengan yang ditampilkan openHAB.
///
/// Cara kerja:
/// 1. Baca status Thing dari `/rest/things/{thingUID}` → `statusInfo.status`.
/// 2. Temukan nama Item yang ter-link ke tiap channel secara OTOMATIS lewat
///    `/rest/links` — tidak perlu hardcode nama Item lagi.
/// 3. Polling `/rest/items` tiap beberapa detik untuk ambil nilainya.
class OpenHab3PhaseService {
  static final OpenHab3PhaseService instance = OpenHab3PhaseService._();
  OpenHab3PhaseService._();

  /// ⚠️ Sesuaikan kalau UID Thing-nya beda di instalasi openHAB lain.
  /// Ini sesuai screenshot: mqtt:topic:38d561eeba76:pow_office_sby
  static const String thingUID = 'mqtt:topic:38d561eeba76:pow_office_sby';

  final _controller = StreamController<PowerMeter3PhaseData>.broadcast();
  PowerMeter3PhaseData _lastData = const PowerMeter3PhaseData();
  bool _isConnected = false; // = status Thing openHAB ONLINE
  bool _configured = false;
  Timer? _pollTimer;

  // channelId (mis. "voltage_phase_a") -> nama Item openHAB, hasil temuan
  // otomatis dari /rest/links, bukan tebakan manual.
  Map<String, String> _channelToItem = {};

  String _baseUrl = '';
  Map<String, String> _headers = {'Accept': 'application/json'};

  Stream<PowerMeter3PhaseData> get stream => _controller.stream;
  PowerMeter3PhaseData get lastData => _lastData;
  bool get isConnected => _isConnected;

  /// Panggil sekali sebelum start(), isi dari config instalasi (openHAB URL
  /// & kredensial) yang sudah ada di app kamu.
  void configure({
    required String baseUrl,
    String? apiToken,
    String? username,
    String? password,
  }) {
    _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final headers = <String, String>{'Accept': 'application/json'};
    if (apiToken != null && apiToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiToken';
    } else if (username != null && username.isNotEmpty && password != null) {
      final enc = base64Encode(utf8.encode('$username:$password'));
      headers['Authorization'] = 'Basic $enc';
    }
    _headers = headers;
    _configured = true;
  }

  Future<void> start({Duration interval = const Duration(seconds: 3)}) async {
    if (!_configured || _baseUrl.isEmpty) {
      debugPrint('OpenHab3PhaseService: belum di-configure() — panggil configure() dulu dengan URL openHAB');
      return;
    }
    _pollTimer?.cancel();
    await _discoverItemMapping();
    await _pollOnce();
    _pollTimer = Timer.periodic(interval, (_) => _pollOnce());
  }

  void stop() {
    _pollTimer?.cancel();
  }

  /// Cari otomatis nama Item yang ter-link ke tiap channel Thing ini, lewat
  /// endpoint /rest/links openHAB. Ini menggantikan cara lama (hardcode nama
  /// Item, gampang salah kalau beda instalasi).
  Future<void> _discoverItemMapping() async {
    try {
      final uri = Uri.parse('$_baseUrl/rest/links');
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        debugPrint('OpenHab3PhaseService: /rest/links gagal (${res.statusCode})');
        return;
      }
      final list = jsonDecode(res.body) as List;
      final map = <String, String>{};
      for (final link in list) {
        final channelUid = (link['channelUID'] as String?) ?? '';
        final itemName = (link['itemName'] as String?) ?? '';
        if (channelUid.startsWith('$thingUID:') && itemName.isNotEmpty) {
          final channelId = channelUid.substring(thingUID.length + 1);
          map[channelId] = itemName;
        }
      }
      _channelToItem = map;
      debugPrint('OpenHab3PhaseService: ditemukan ${map.length} channel ter-link ke Item');
    } catch (e) {
      debugPrint('OpenHab3PhaseService: gagal discover item mapping — $e');
    }
  }

  String? itemNameFor(String channelId) => _channelToItem[channelId];

  /// Ambil data histori mentah dari openHAB Persistence API untuk 1 channel
  /// (nama Item-nya di-resolve otomatis lewat mapping /rest/links).
  /// Balikin null kalau channel belum ketemu Item-nya, atau request gagal.
  Future<List<Map<String, dynamic>>?> fetchPersistence(
    String channelId, {
    required DateTime start,
    required DateTime end,
  }) async {
    if (_channelToItem.isEmpty) await _discoverItemMapping();
    final itemName = _channelToItem[channelId];
    if (itemName == null) {
      debugPrint('OpenHab3PhaseService: channel "$channelId" belum ter-link ke Item apapun');
      return null;
    }
    final uri = Uri.parse('$_baseUrl/rest/persistence/items/$itemName').replace(
      queryParameters: {
        'starttime': start.toUtc().toIso8601String(),
        'endtime': end.toUtc().toIso8601String(),
      },
    );
    final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      debugPrint('OpenHab3PhaseService: /rest/persistence gagal (${res.statusCode}) untuk $itemName');
      return null;
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return (json['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }

  Future<void> _pollOnce() async {
    try {
      // 1) Status Thing — persis yang ditampilkan openHAB.
      final thingUri = Uri.parse('$_baseUrl/rest/things/$thingUID');
      final thingRes = await http.get(thingUri, headers: _headers).timeout(const Duration(seconds: 8));
      bool online = false;
      if (thingRes.statusCode == 200) {
        final thingJson = jsonDecode(thingRes.body) as Map<String, dynamic>;
        final status = ((thingJson['statusInfo'] as Map<String, dynamic>?)?['status'] ?? '')
            .toString().toUpperCase();
        online = status == 'ONLINE';
      } else {
        debugPrint('OpenHab3PhaseService: /rest/things gagal (${thingRes.statusCode})');
      }
      _isConnected = online;

      if (_channelToItem.isEmpty) await _discoverItemMapping();
      if (_channelToItem.isEmpty) {
        _controller.add(_lastData.copyWith(deviceOnline: online));
        return;
      }

      // 2) Ambil semua nilai Item sekaligus dalam 1 request.
      final itemsUri = Uri.parse('$_baseUrl/rest/items?fields=name,state');
      final itemsRes = await http.get(itemsUri, headers: _headers).timeout(const Duration(seconds: 8));
      if (itemsRes.statusCode != 200) {
        debugPrint('OpenHab3PhaseService: /rest/items gagal (${itemsRes.statusCode})');
        _controller.add(_lastData.copyWith(deviceOnline: online));
        return;
      }
      final itemsList = jsonDecode(itemsRes.body) as List;
      final stateByName = <String, String>{};
      for (final it in itemsList) {
        final name = (it['name'] as String?) ?? '';
        final state = (it['state'] as String?) ?? '';
        if (name.isNotEmpty) stateByName[name] = state;
      }

      double val(String channelId) {
        final itemName = _channelToItem[channelId];
        if (itemName == null) return 0;
        final raw = stateByName[itemName];
        if (raw == null) return 0;
        return double.tryParse(raw) ?? 0;
      }

      _lastData = PowerMeter3PhaseData(
        voltA: val('voltage_phase_a'), voltB: val('voltage_phase_b'), voltC: val('voltage_phase_c'),
        currentA: val('current_phase_a'), currentB: val('current_phase_b'), currentC: val('current_phase_c'),
        freqA: val('frequency_phase_a'), freqB: val('frequency_phase_b'), freqC: val('frequency_phase_c'),
        angleVoltBtoA: val('phase_angle_voltage_b_to_a'),
        angleVoltCtoA: val('phase_angle_voltage_c_to_a'),
        angleCurrAtoVoltA: val('phase_angle_current_a_to_voltage_a'),
        angleCurrBtoVoltA: val('phase_angle_current_b_to_voltage_a'),
        angleCurrCtoVoltA: val('phase_angle_current_c_to_voltage_a'),
        activePowerA: val('active_power_phase_a'), activePowerB: val('active_power_phase_b'),
        activePowerC: val('active_power_phase_c'), activePowerTotal: val('active_power_total'),
        reactivePowerA: val('reactive_power_phase_a'), reactivePowerB: val('reactive_power_phase_b'),
        reactivePowerC: val('reactive_power_phase_c'), reactivePowerTotal: val('reactive_power_total'),
        apparentPowerA: val('apparent_power_phase_a'), apparentPowerB: val('apparent_power_phase_b'),
        apparentPowerC: val('apparent_power_phase_c'), apparentPowerTotal: val('apparent_power_total'),
        pfA: val('power_factor_phase_a'), pfB: val('power_factor_phase_b'),
        pfC: val('power_factor_phase_c'), pfTotal: val('power_factor_total'),
        activeEnergyA: val('active_energy_phase_a'), activeEnergyB: val('active_energy_phase_b'),
        activeEnergyC: val('active_energy_phase_c'), activeEnergyTotal: val('active_energy_total'),
        reactiveEnergyA: val('reactive_energy_phase_a'), reactiveEnergyB: val('reactive_energy_phase_b'),
        reactiveEnergyC: val('reactive_energy_phase_c'), reactiveEnergyTotal: val('reactive_energy_total'),
        apparentEnergyA: val('apparent_energy_phase_a'), apparentEnergyB: val('apparent_energy_phase_b'),
        apparentEnergyC: val('apparent_energy_phase_c'), apparentEnergyTotal: val('apparent_energy_total'),
        status: stateByName[_channelToItem['status']] ?? 'OFF',
        deviceOnline: online,
      );
      _controller.add(_lastData);
    } catch (e) {
      debugPrint('OpenHab3PhaseService: poll error — $e');
      _isConnected = false;
      _controller.add(_lastData.copyWith(deviceOnline: false));
    }
  }
}