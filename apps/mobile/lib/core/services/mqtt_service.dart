import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:mobile/core/config/mqtt_config.dart';

class PowerMeterData {
  final double power;
  final double volt;
  final double amp;
  final double freq;
  final double pf;
  final double energyTotal;
  final double energyToday;
  final double energyYesterday;
  final String status;
  final bool deviceOnline;

  const PowerMeterData({
    this.power = 0,
    this.volt = 0,
    this.amp = 0,
    this.freq = 0,
    this.pf = 0,
    this.energyTotal = 0,
    this.energyToday = 0,
    this.energyYesterday = 0,
    this.status = 'OFF',
    this.deviceOnline = false,
  });

  factory PowerMeterData.fromJson(
    Map<String, dynamic> json, {
    bool deviceOnline = true,
  }) {
    final d = (json['pow_pop_mbloc'] as Map<String, dynamic>?) ?? {};

    double safe(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    return PowerMeterData(
      power:           safe(d['POWER']),
      volt:            safe(d['VOLT']),
      amp:             safe(d['AMP']),
      freq:            safe(d['FREQ']),
      pf:              safe(d['PF']),
      energyTotal:     safe(d['ENERGY_TOTAL']),
      energyToday:     safe(d['ENERGY_TODAY']),
      energyYesterday: safe(d['ENERGY_YESTERDAY']),
      status:          (d['STATUS'] ?? 'OFF').toString(),
      deviceOnline:    deviceOnline,
    );
  }

  PowerMeterData copyWith({bool? deviceOnline}) => PowerMeterData(
    power: power, volt: volt, amp: amp, freq: freq, pf: pf,
    energyTotal: energyTotal, energyToday: energyToday,
    energyYesterday: energyYesterday, status: status,
    deviceOnline: deviceOnline ?? this.deviceOnline,
  );

  double get powerKw => power / 1000;
}

/// Status koneksi yang lebih informatif dibanding bool isConnected saja,
/// supaya UI bisa membedakan "sedang mencoba konek" vs "putus total".
enum MqttConnState { disconnected, connecting, connected }

class MqttService {
  static final MqttService instance = MqttService._();
  MqttService._();

  MqttServerClient? _client;
  final _controller = StreamController<PowerMeterData>.broadcast();
  final _statusController = StreamController<MqttConnState>.broadcast();

  PowerMeterData _lastData = const PowerMeterData();
  MqttConnState _status = MqttConnState.disconnected;
  Timer? _offlineTimer;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  static const _maxRetryDelaySec = 30;

  String _topicData = MqttConfig.defaultTopicData;
  String _topicLwt  = MqttConfig.defaultTopicLwt;

  Stream<PowerMeterData> get stream => _controller.stream;
  Stream<MqttConnState> get statusStream => _statusController.stream;

  PowerMeterData get lastData => _lastData;
  MqttConnState get status => _status;
  bool get isConnected => _status == MqttConnState.connected;

  void _setStatus(MqttConnState value) {
    if (_status == value) return;
    _status = value;
    if (!_statusController.isClosed) _statusController.add(value);
  }

  void _resetOfflineTimer() {
    _offlineTimer?.cancel();
    _offlineTimer = Timer(const Duration(seconds: 60), () {
      _lastData = _lastData.copyWith(deviceOnline: false);
      if (!_controller.isClosed) _controller.add(_lastData);
    });
  }

  /// Konek ke broker sesuai konfigurasi tersimpan (MqttConfig).
  /// Mencoba TCP dan WebSocket SEKALIGUS (race) — yang lebih dulu
  /// berhasil dipakai, yang satu lagi diputus. Berguna karena sebagian
  /// broker expose keduanya, dan sebagian jaringan cuma bisa lewat
  /// WebSocket (mis. port TCP non-standar diblokir firewall).
  Future<void> connect() async {
    if (_status == MqttConnState.connected ||
        _status == MqttConnState.connecting) {
      return;
    }
    _retryTimer?.cancel();
    _setStatus(MqttConnState.connecting);

    final host     = await MqttConfig.getBroker();
    final port     = await MqttConfig.getPort();
    final wsPort   = await MqttConfig.getWsPort();
    final username = await MqttConfig.getUsername();
    final password = await MqttConfig.getPassword();
    final useTls   = await MqttConfig.getUseTls();
    _topicData     = await MqttConfig.getTopicData();
    _topicLwt      = await MqttConfig.getTopicLwt();

    bool resolved = false;

    Future<void> tryTransport(bool useWebSocket) async {
      final label = useWebSocket ? 'WebSocket' : 'TCP';
      // WebSocket butuh host berbentuk URL lengkap (ws://host:port/mqtt),
      // beda dari TCP yang cukup hostname polos.
      final wsScheme    = useTls ? 'wss' : 'ws';
      final connectHost = useWebSocket ? '$wsScheme://$host:$wsPort/mqtt' : host;
      final connectPort = useWebSocket ? wsPort : port;
      final clientId =
          'flutter_mqtt_${DateTime.now().millisecondsSinceEpoch}_$label';

      final client = MqttServerClient(connectHost, clientId)
        ..port                       = connectPort
        ..useWebSocket               = useWebSocket
        ..secure                     = !useWebSocket && useTls
        ..keepAlivePeriod            = 30
        ..connectTimeoutPeriod       = 8000
        ..autoReconnect              = true
        ..resubscribeOnAutoReconnect = true
        ..logging(on: false);

      if (!useWebSocket && useTls) {
        client.securityContext = SecurityContext.defaultContext;
      }

      final connMsg = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean();
      if (username != null && username.isNotEmpty) {
        connMsg.authenticateAs(username, password ?? '');
      }
      client.connectionMessage = connMsg;

      try {
        await client.connect();
      } catch (e) {
        debugPrint('MqttService: $label gagal — $e');
        client.disconnect();
        return;
      }

      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        debugPrint('MqttService: $label status bukan connected — '
            '${client.connectionStatus?.state}');
        client.disconnect();
        return;
      }

      if (resolved) {
        client.disconnect();
        return;
      }
      resolved = true;
      _client = client
        ..onConnected       = _onConnected
        ..onDisconnected    = _onDisconnected
        ..onAutoReconnected = _onAutoReconnected;
      _client!.subscribe(_topicData, MqttQos.atLeastOnce);
      _client!.subscribe(_topicLwt, MqttQos.atLeastOnce);
      _client!.updates?.listen(_onMessage);
      debugPrint('MqttService: berhasil connect via $label');
      _onConnected();
    }

    await Future.wait([tryTransport(false), tryTransport(true)]);

    if (!resolved) _scheduleRetry();
  }

  void _scheduleRetry() {
    _setStatus(MqttConnState.disconnected);
    _retryTimer?.cancel();
    final delaySec = (5 * (1 << _retryAttempt)).clamp(5, _maxRetryDelaySec);
    _retryAttempt++;
    debugPrint('MqttService: retry connect dalam ${delaySec}s '
        '(percobaan ke-$_retryAttempt)');
    _retryTimer = Timer(Duration(seconds: delaySec), () {
      if (_status != MqttConnState.connected) connect();
    });
  }

  /// Dipanggil dari halaman Settings setelah user mengubah konfigurasi
  /// broker, supaya koneksi lama diputus dan langsung konek ulang
  /// pakai konfigurasi yang baru — bukan menunggu retry timer.
  Future<void> reloadConfig() async {
    _retryTimer?.cancel();
    _retryAttempt = 0;
    try {
      _client?.disconnect();
    } catch (_) {}
    _setStatus(MqttConnState.disconnected);
    await connect();
  }

  /// Publish pesan ke topic tertentu. Tidak melakukan apa-apa kalau
  /// sedang tidak konek — dipanggil aman dari mana saja.
  void publish(
    String topic,
    String payload, {
    MqttQos qos = MqttQos.atLeastOnce,
    bool retain = false,
  }) {
    final client = _client;
    if (client == null || _status != MqttConnState.connected) return;
    final builder = MqttClientPayloadBuilder()..addString(payload);
    client.publishMessage(topic, qos, builder.payload!, retain: retain);
  }

  void disconnect() {
    _retryTimer?.cancel();
    _offlineTimer?.cancel();
    _client?.disconnect();
    _setStatus(MqttConnState.disconnected);
    // Sengaja TIDAK menutup _controller/_statusController: MqttService
    // singleton hidup selama app berjalan, dan connect() bisa dipanggil
    // lagi kapan saja (mis. setelah reloadConfig). Menutup broadcast
    // controller di sini akan membuat connect() berikutnya gagal saat
    // add() ke controller yang sudah closed.
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final payload = (event.payload as MqttPublishMessage).payload.message;
      final raw     = MqttPublishPayload.bytesToStringAsString(payload);
      final topic   = event.topic;

      if (topic == _topicData) {
        try {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          _lastData = PowerMeterData.fromJson(json, deviceOnline: true);
          if (!_controller.isClosed) _controller.add(_lastData);
          _resetOfflineTimer();
        } catch (_) {}
      }

      if (topic == _topicLwt) {
        final isOnline = raw.trim().toUpperCase() == 'ONLINE';
        _lastData = _lastData.copyWith(deviceOnline: isOnline);
        if (!_controller.isClosed) _controller.add(_lastData);
        if (isOnline) _resetOfflineTimer();
      }
    }
  }

  void _onConnected() {
    _retryAttempt = 0;
    _setStatus(MqttConnState.connected);
    debugPrint('MqttService: connected');
  }

  void _onDisconnected() {
    final wasConnected = _status == MqttConnState.connected;
    _setStatus(MqttConnState.disconnected);
    debugPrint('MqttService: disconnected');
    // Jaring pengaman: autoReconnect bawaan package harusnya menangani
    // ini, tapi kalau package menyerah/gagal, kita tetap coba lagi
    // dengan exponential backoff.
    if (wasConnected) _scheduleRetry();
  }

  void _onAutoReconnected() {
    _retryAttempt = 0;
    _retryTimer?.cancel();
    _setStatus(MqttConnState.connected);
    debugPrint('MqttService: reconnected');
  }
}