import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;
import 'package:http/http.dart' as http;
import 'package:mobile/core/models/power_meter_3phase_data.dart';
import 'package:mobile/core/models/power_meter_data.dart';

/// URL + kredensial openHAB untuk semua service power meter. Diisi SEKALI
/// (dari InstallationProvider) oleh halaman Energy.
class OpenHabEndpoint {
  static final OpenHabEndpoint instance = OpenHabEndpoint._();
  OpenHabEndpoint._();

  String baseUrl = '';
  Map<String, String> headers = {'Accept': 'application/json'};
  bool get isConfigured => baseUrl.isNotEmpty;

  void configure({
    required String baseUrl,
    String? apiToken,
    String? username,
    String? password,
  }) {
    if (baseUrl.isEmpty) return;
    this.baseUrl =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final h = <String, String>{'Accept': 'application/json'};
    if (apiToken != null && apiToken.isNotEmpty) {
      h['Authorization'] = 'Bearer $apiToken';
    } else if (username != null && username.isNotEmpty && password != null) {
      h['Authorization'] =
          'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    }
    headers = h;
  }
}

/// Satu meter 3 fasa hasil discovery otomatis dari openHAB.
class PowerMeterDevice {
  final String thingUid;
  final String label;
  final Map<String, String> channelToItem; // channelId -> nama Item
  const PowerMeterDevice(this.thingUid, this.label, this.channelToItem);
}

class PowerMeterSnapshot {
  final PowerMeterDevice device;
  final PowerMeter3PhaseData data;

  /// Terakhir kali ADA nilai yang berubah. Dipakai untuk deteksi stale —
  /// bukan waktu polling (polling jalan terus walau datanya macet).
  final DateTime lastChange;
  const PowerMeterSnapshot(
      {required this.device, required this.data, required this.lastChange});
}

/// Satu meter 1 fasa hasil discovery. [keyToItem] memakai kunci logis:
/// power, voltage, current, frequency, pf, energyTotal, energyToday,
/// energyYesterday, status.
class SinglePhaseDevice {
  final String thingUid;
  final String label;
  final Map<String, String> keyToItem;
  const SinglePhaseDevice(this.thingUid, this.label, this.keyToItem);
}

class SinglePhaseSnapshot {
  final SinglePhaseDevice device;
  final PowerMeterData data;
  final DateTime lastChange;
  const SinglePhaseSnapshot(
      {required this.device, required this.data, required this.lastChange});
}

/// Jalur data power meter (1 fasa & 3 fasa): openHAB REST API saja.
/// Tidak ada broker/topic MQTT dan tidak ada UID Thing di-hardcode.
/// Thing mana pun yang channel-nya mengikuti konvensi (voltage_phase_a,
/// active_power_total, ...) otomatis dikenali sebagai power meter.
class OpenHabPowerMeterService with WidgetsBindingObserver {
  static final OpenHabPowerMeterService instance = OpenHabPowerMeterService._();
  OpenHabPowerMeterService._();

  static const _signatureChannels = {'voltage_phase_a', 'active_power_total'};

  final _ep = OpenHabEndpoint.instance;
  final http.Client _client = http.Client();
  final _controller =
      StreamController<Map<String, PowerMeterSnapshot>>.broadcast();

  Map<String, PowerMeterSnapshot> _last = {};
  final Map<String, String> _signature = {};
  final Map<String, DateTime> _lastChange = {};
  List<PowerMeterDevice> _devices = [];
  List<SinglePhaseDevice> _singleDevices = [];
  Map<String, SinglePhaseSnapshot> _singleLast = {};
  final _singleController =
      StreamController<Map<String, SinglePhaseSnapshot>>.broadcast();
  Timer? _timer;
  bool _polling = false;

  // ── Hemat CPU/baterai/jaringan ──────────────────────────────────────
  Duration _interval = const Duration(seconds: 3);
  String _runningUrl = '';
  bool _observing = false;
  int _tick = 0;
  String _lastEmitSig = '';
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  bool _errorEmitted = false;
  String _lastDiscoverLog = '';
  static const _heartbeat = Duration(seconds: 15);

  bool get _isRunning => _timer?.isActive ?? false;

  /// Berhenti polling saat app di background, lanjut saat kembali aktif.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_runningUrl.isNotEmpty && !_isRunning) {
        _startTimer();
        _pollOnce();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _timer?.cancel();
    }
  }

  Stream<Map<String, PowerMeterSnapshot>> get stream => _controller.stream;
  Map<String, PowerMeterSnapshot> get lastSnapshots => _last;
  List<PowerMeterDevice> get devices => _devices;
  Stream<Map<String, SinglePhaseSnapshot>> get singleStream => _singleController.stream;
  Map<String, SinglePhaseSnapshot> get singleSnapshots => _singleLast;
  List<SinglePhaseDevice> get singleDevices => _singleDevices;

  /// Aman dipanggil berkali-kali (tiap halaman memanggilnya di initState):
  /// kalau sudah berjalan untuk server yang sama, tidak membuat timer baru
  /// dan tidak discovery ulang.
  Future<void> start({Duration interval = const Duration(seconds: 3)}) async {
    if (!_ep.isConfigured) {
      debugPrint('OpenHabPowerMeterService: OpenHabEndpoint belum di-configure()');
      return;
    }
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    if (_isRunning && _runningUrl == _ep.baseUrl) return;

    if (_runningUrl != _ep.baseUrl) {
      // Server berganti → buang data server lama.
      _devices = [];
      _singleDevices = [];
      _last = {};
      _singleLast = {};
      _signature.clear();
      _lastChange.clear();
      _lastEmitSig = '';
    }
    _runningUrl = _ep.baseUrl;
    _interval = interval;
    await discoverMeters();
    await _pollOnce();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    // Cek ulang meter baru kira-kira tiap 60 detik.
    final rediscoverEvery = (60000 ~/ _interval.inMilliseconds).clamp(1, 1000);
    _timer = Timer.periodic(_interval, (_) async {
      if (++_tick % rediscoverEvery == 0) await discoverMeters();
      await _pollOnce();
    });
  }

  void stop() {
    _timer?.cancel();
    _runningUrl = '';
  }

  Future<Map<String, String>> _thingLabels() async {
    final res = await _client
        .get(Uri.parse('${_ep.baseUrl}/rest/things?summary=true'),
            headers: _ep.headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return {};
    return {
      for (final t in jsonDecode(res.body) as List)
        if (t['UID'] != null) t['UID'] as String: (t['label'] ?? t['UID']).toString(),
    };
  }

  // Konvensi 1 fasa: dikenali dari channelId ATAU akhiran nama Item.
  static const _singleAliases = <String, List<String>>{
    'power': ['activepower', 'power'],
    'voltage': ['voltage', 'volt'],
    'current': ['current', 'amp', 'ampere'],
    'frequency': ['frequency', 'freq'],
    'pf': ['powerfactor', 'pf'],
    'energyTotal': ['energytotal', 'totalenergy'],
    'energyToday': ['energytoday'],
    'energyYesterday': ['energyyesterday'],
    'status': ['status'],
  };
  static const _singleRequired = {'power', 'voltage', 'current'};

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String? _singleKeyFor(String channelId, String itemName) {
    final c = _norm(channelId);
    for (final e in _singleAliases.entries) {
      if (e.value.contains(c)) return e.key;
    }
    final i = _norm(itemName);
    String? best;
    var bestLen = 0;
    for (final e in _singleAliases.entries) {
      for (final a in e.value) {
        if (i.endsWith(a) && a.length > bestLen) {
          best = e.key;
          bestLen = a.length;
        }
      }
    }
    return best;
  }

  /// Cari semua power meter. Panggil ulang (pull-to-refresh) kalau ada meter baru.
  Future<void> discoverMeters() async {
    try {
      final res = await _client
          .get(Uri.parse('${_ep.baseUrl}/rest/links'), headers: _ep.headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;

      final byThing = <String, Map<String, String>>{};
      for (final l in jsonDecode(res.body) as List) {
        final channelUid = (l['channelUID'] as String?) ?? '';
        final item = (l['itemName'] as String?) ?? '';
        final cut = channelUid.lastIndexOf(':');
        if (cut < 0 || item.isEmpty) continue;
        byThing
            .putIfAbsent(channelUid.substring(0, cut), () => {})[channelUid.substring(cut + 1)] = item;
      }
      final labels = await _thingLabels();
      _devices = [
        for (final e in byThing.entries)
          if (_signatureChannels.every(e.value.containsKey))
            PowerMeterDevice(e.key, labels[e.key] ?? e.key, e.value),
      ]..sort((a, b) => a.label.compareTo(b.label));

      // Thing non-3-fasa: coba kenali sebagai meter 1 fasa.
      final threePhase = _devices.map((d) => d.thingUid).toSet();
      final singles = <SinglePhaseDevice>[];
      for (final e in byThing.entries) {
        if (threePhase.contains(e.key)) continue;
        final map = <String, String>{};
        e.value.forEach((channelId, item) {
          final k = _singleKeyFor(channelId, item);
          if (k != null) map.putIfAbsent(k, () => item);
        });
        if (_singleRequired.every(map.containsKey)) {
          singles.add(SinglePhaseDevice(e.key, labels[e.key] ?? e.key, map));
        } else if (map.length >= 2) {
          // (dilewati tanpa log berulang — bukan error)
        }
      }
      singles.sort((a, b) => a.label.compareTo(b.label));
      _singleDevices = singles;
      final summary = '${_devices.length} meter 3 fasa, '
          '${_singleDevices.length} meter 1 fasa ditemukan';
      if (summary != _lastDiscoverLog) {
        _lastDiscoverLog = summary;
        debugPrint('OpenHabPowerMeterService: $summary');
      }
    } catch (e) {
      debugPrint('OpenHabPowerMeterService: discover gagal — $e');
    }
  }

  // State openHAB bisa "230.5 V" (QuantityType) — ambil angka depannya saja.
  static final _num = RegExp(r'^\s*-?\d+(\.\d+)?([eE][-+]?\d+)?');
  static double _parse(String? raw) {
    if (raw == null) return 0;
    final m = _num.firstMatch(raw);
    return m == null ? 0 : double.tryParse(m.group(0)!.trim()) ?? 0;
  }

  /// Paksa polling sekarang (mis. tombol refresh di UI).
  Future<void> refresh() => _pollOnce();

  Future<void> _pollOnce() async {
    if (_polling) return;
    _polling = true;
    try {
      // Tanpa meter: jangan discovery tiap 3 dtk — rediscovery sudah dijadwalkan
      // tiap 60 dtk oleh timer.
      if (_devices.isEmpty && _singleDevices.isEmpty) return;

      // 2 request untuk berapa pun jumlah meter.
      final thingsRes = await _client
          .get(Uri.parse('${_ep.baseUrl}/rest/things?summary=true'),
              headers: _ep.headers)
          .timeout(const Duration(seconds: 8));
      final itemsRes = await _client
          .get(Uri.parse('${_ep.baseUrl}/rest/items?fields=name,state'),
              headers: _ep.headers)
          .timeout(const Duration(seconds: 8));
      if (thingsRes.statusCode != 200 || itemsRes.statusCode != 200) {
        throw Exception('HTTP ${thingsRes.statusCode}/${itemsRes.statusCode}');
      }

      final online = <String, bool>{
        for (final t in jsonDecode(thingsRes.body) as List)
          t['UID'] as String:
              ((t['statusInfo']?['status'] ?? '') as String).toUpperCase() == 'ONLINE',
      };
      final state = <String, String>{
        for (final i in jsonDecode(itemsRes.body) as List)
          i['name'] as String: (i['state'] ?? '') as String,
      };

      final now = DateTime.now();
      final out = <String, PowerMeterSnapshot>{};
      for (final d in _devices) {
        double v(String ch) => _parse(state[d.channelToItem[ch]]);

        final sig = d.channelToItem.values.map((i) => state[i]).join('|');
        if (_signature[d.thingUid] != sig) {
          _signature[d.thingUid] = sig;
          _lastChange[d.thingUid] = now;
        }

        out[d.thingUid] = PowerMeterSnapshot(
          device: d,
          lastChange: _lastChange[d.thingUid] ?? now,
          data: PowerMeter3PhaseData(
            voltA: v('voltage_phase_a'), voltB: v('voltage_phase_b'), voltC: v('voltage_phase_c'),
            currentA: v('current_phase_a'), currentB: v('current_phase_b'), currentC: v('current_phase_c'),
            freqA: v('frequency_phase_a'), freqB: v('frequency_phase_b'), freqC: v('frequency_phase_c'),
            angleVoltBtoA: v('phase_angle_voltage_b_to_a'),
            angleVoltCtoA: v('phase_angle_voltage_c_to_a'),
            angleCurrAtoVoltA: v('phase_angle_current_a_to_voltage_a'),
            angleCurrBtoVoltA: v('phase_angle_current_b_to_voltage_a'),
            angleCurrCtoVoltA: v('phase_angle_current_c_to_voltage_a'),
            activePowerA: v('active_power_phase_a'), activePowerB: v('active_power_phase_b'),
            activePowerC: v('active_power_phase_c'), activePowerTotal: v('active_power_total'),
            reactivePowerA: v('reactive_power_phase_a'), reactivePowerB: v('reactive_power_phase_b'),
            reactivePowerC: v('reactive_power_phase_c'), reactivePowerTotal: v('reactive_power_total'),
            apparentPowerA: v('apparent_power_phase_a'), apparentPowerB: v('apparent_power_phase_b'),
            apparentPowerC: v('apparent_power_phase_c'), apparentPowerTotal: v('apparent_power_total'),
            pfA: v('power_factor_phase_a'), pfB: v('power_factor_phase_b'),
            pfC: v('power_factor_phase_c'), pfTotal: v('power_factor_total'),
            activeEnergyA: v('active_energy_phase_a'), activeEnergyB: v('active_energy_phase_b'),
            activeEnergyC: v('active_energy_phase_c'), activeEnergyTotal: v('active_energy_total'),
            reactiveEnergyA: v('reactive_energy_phase_a'), reactiveEnergyB: v('reactive_energy_phase_b'),
            reactiveEnergyC: v('reactive_energy_phase_c'), reactiveEnergyTotal: v('reactive_energy_total'),
            apparentEnergyA: v('apparent_energy_phase_a'), apparentEnergyB: v('apparent_energy_phase_b'),
            apparentEnergyC: v('apparent_energy_phase_c'), apparentEnergyTotal: v('apparent_energy_total'),
            status: state[d.channelToItem['status']] ?? 'OFF',
            deviceOnline: online[d.thingUid] ?? false,
          ),
        );
      }
      _last = out;

      final sOut = <String, SinglePhaseSnapshot>{};
      for (final d in _singleDevices) {
        double v(String k) => _parse(state[d.keyToItem[k]]);
        final sig = d.keyToItem.values.map((i) => state[i]).join('|');
        if (_signature[d.thingUid] != sig) {
          _signature[d.thingUid] = sig;
          _lastChange[d.thingUid] = now;
        }
        sOut[d.thingUid] = SinglePhaseSnapshot(
          device: d,
          lastChange: _lastChange[d.thingUid] ?? now,
          data: PowerMeterData(
            power: v('power'), volt: v('voltage'), amp: v('current'),
            freq: v('frequency'), pf: v('pf'),
            energyTotal: v('energyTotal'), energyToday: v('energyToday'),
            energyYesterday: v('energyYesterday'),
            status: state[d.keyToItem['status']] ?? 'OFF',
            deviceOnline: online[d.thingUid] ?? false,
          ),
        );
      }
      _singleLast = sOut;

      // Kabari UI HANYA kalau ada perubahan (atau heartbeat 15 dtk untuk
      // deteksi stale). Sebelumnya emit tiap 3 dtk → Home/Floor Plan/Energy
      // rebuild terus walau data sama.
      final emitSig = [
        ...out.entries.map((e) =>
            '${e.key}:${_signature[e.key]}:${e.value.data.deviceOnline}'),
        ...sOut.entries.map((e) =>
            '${e.key}:${_signature[e.key]}:${e.value.data.deviceOnline}'),
      ].join('#');
      final dueHeartbeat = now.difference(_lastEmit) >= _heartbeat;
      if (emitSig != _lastEmitSig || dueHeartbeat || _errorEmitted) {
        _lastEmitSig = emitSig;
        _lastEmit = now;
        _errorEmitted = false;
        if (!_controller.isClosed) _controller.add(out);
        if (!_singleController.isClosed) _singleController.add(sOut);
      }
    } catch (e) {
      if (!_errorEmitted) debugPrint('OpenHabPowerMeterService: poll error — $e');
      if (_errorEmitted) return; // sudah ditandai offline, jangan emit berulang
      _errorEmitted = true;
      _last = {
        for (final e in _last.entries)
          e.key: PowerMeterSnapshot(
              device: e.value.device,
              lastChange: e.value.lastChange,
              data: e.value.data.copyWith(deviceOnline: false)),
      };
      if (!_controller.isClosed) _controller.add(_last);
      _singleLast = {
        for (final e in _singleLast.entries)
          e.key: SinglePhaseSnapshot(
              device: e.value.device,
              lastChange: e.value.lastChange,
              data: e.value.data.copyWith(deviceOnline: false)),
      };
      if (!_singleController.isClosed) _singleController.add(_singleLast);
    } finally {
      _polling = false;
    }
  }
}