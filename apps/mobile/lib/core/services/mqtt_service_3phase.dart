import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Sesuai Thing openHAB "Power Meter Office SBY"
/// (mqtt:topic:38d561eeba76:pow_office_sby, bridge: MQTT Broker Local)
/// Topic: powermeter/office/sby/data
/// Payload root object: "panel_busol"
class PowerMeter3PhaseData {
  // Tegangan fasa-netral (V)
  final double voltA, voltB, voltC;
  // Arus per fasa (A)
  final double currentA, currentB, currentC;
  // Frekuensi per fasa (Hz) — device kirim per-fasa, bukan satu nilai global
  final double freqA, freqB, freqC;
  // Sudut fasa (derajat), referensi ke Voltage A (= 0°)
  final double angleVoltBtoA, angleVoltCtoA;
  final double angleCurrAtoVoltA, angleCurrBtoVoltA, angleCurrCtoVoltA;
  // Daya aktif (kW)
  final double activePowerA, activePowerB, activePowerC, activePowerTotal;
  // Daya reaktif (kVAR)
  final double reactivePowerA, reactivePowerB, reactivePowerC, reactivePowerTotal;
  // Daya semu (kVA)
  final double apparentPowerA, apparentPowerB, apparentPowerC, apparentPowerTotal;
  // Power factor
  final double pfA, pfB, pfC, pfTotal;
  // Energi aktif (kWh)
  final double activeEnergyA, activeEnergyB, activeEnergyC, activeEnergyTotal;
  // Energi reaktif (kVARh)
  final double reactiveEnergyA, reactiveEnergyB, reactiveEnergyC, reactiveEnergyTotal;
  // Energi semu (kVAh)
  final double apparentEnergyA, apparentEnergyB, apparentEnergyC, apparentEnergyTotal;

  final String status;
  final bool deviceOnline;

  const PowerMeter3PhaseData({
    this.voltA = 0, this.voltB = 0, this.voltC = 0,
    this.currentA = 0, this.currentB = 0, this.currentC = 0,
    this.freqA = 0, this.freqB = 0, this.freqC = 0,
    this.angleVoltBtoA = 0, this.angleVoltCtoA = 0,
    this.angleCurrAtoVoltA = 0, this.angleCurrBtoVoltA = 0, this.angleCurrCtoVoltA = 0,
    this.activePowerA = 0, this.activePowerB = 0, this.activePowerC = 0, this.activePowerTotal = 0,
    this.reactivePowerA = 0, this.reactivePowerB = 0, this.reactivePowerC = 0, this.reactivePowerTotal = 0,
    this.apparentPowerA = 0, this.apparentPowerB = 0, this.apparentPowerC = 0, this.apparentPowerTotal = 0,
    this.pfA = 0, this.pfB = 0, this.pfC = 0, this.pfTotal = 0,
    this.activeEnergyA = 0, this.activeEnergyB = 0, this.activeEnergyC = 0, this.activeEnergyTotal = 0,
    this.reactiveEnergyA = 0, this.reactiveEnergyB = 0, this.reactiveEnergyC = 0, this.reactiveEnergyTotal = 0,
    this.apparentEnergyA = 0, this.apparentEnergyB = 0, this.apparentEnergyC = 0, this.apparentEnergyTotal = 0,
    this.status = 'OFF',
    this.deviceOnline = false,
  });

  factory PowerMeter3PhaseData.fromJson(
    Map<String, dynamic> json, {
    bool deviceOnline = true,
  }) {
    final d = (json['panel_busol'] as Map<String, dynamic>?) ?? {};

    Map<String, dynamic> sub(String key) =>
        (d[key] as Map<String, dynamic>?) ?? {};

    double safe(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    final voltage       = sub('voltage');
    final current        = sub('current');
    final frequency       = sub('frequency');
    final phaseAngle      = sub('phase_angle');
    final activePower      = sub('active_power');
    final reactivePower     = sub('reactive_power');
    final apparentPower      = sub('apparent_power');
    final powerFactor         = sub('power_factor');
    final activeEnergy         = sub('active_energy');
    final reactiveEnergy        = sub('reactive_energy');
    final apparentEnergy         = sub('apparent_energy');

    return PowerMeter3PhaseData(
      voltA: safe(voltage['phase_a']), voltB: safe(voltage['phase_b']), voltC: safe(voltage['phase_c']),
      currentA: safe(current['phase_a']), currentB: safe(current['phase_b']), currentC: safe(current['phase_c']),
      freqA: safe(frequency['phase_a']), freqB: safe(frequency['phase_b']), freqC: safe(frequency['phase_c']),
      angleVoltBtoA: safe(phaseAngle['voltage_b_to_a']),
      angleVoltCtoA: safe(phaseAngle['voltage_c_to_a']),
      angleCurrAtoVoltA: safe(phaseAngle['current_a_to_voltage_a']),
      angleCurrBtoVoltA: safe(phaseAngle['current_b_to_voltage_a']),
      angleCurrCtoVoltA: safe(phaseAngle['current_c_to_voltage_a']),
      activePowerA: safe(activePower['phase_a']), activePowerB: safe(activePower['phase_b']),
      activePowerC: safe(activePower['phase_c']), activePowerTotal: safe(activePower['total']),
      reactivePowerA: safe(reactivePower['phase_a']), reactivePowerB: safe(reactivePower['phase_b']),
      reactivePowerC: safe(reactivePower['phase_c']), reactivePowerTotal: safe(reactivePower['total']),
      apparentPowerA: safe(apparentPower['phase_a']), apparentPowerB: safe(apparentPower['phase_b']),
      apparentPowerC: safe(apparentPower['phase_c']), apparentPowerTotal: safe(apparentPower['total']),
      pfA: safe(powerFactor['phase_a']), pfB: safe(powerFactor['phase_b']),
      pfC: safe(powerFactor['phase_c']), pfTotal: safe(powerFactor['total']),
      activeEnergyA: safe(activeEnergy['phase_a']), activeEnergyB: safe(activeEnergy['phase_b']),
      activeEnergyC: safe(activeEnergy['phase_c']), activeEnergyTotal: safe(activeEnergy['total']),
      reactiveEnergyA: safe(reactiveEnergy['phase_a']), reactiveEnergyB: safe(reactiveEnergy['phase_b']),
      reactiveEnergyC: safe(reactiveEnergy['phase_c']), reactiveEnergyTotal: safe(reactiveEnergy['total']),
      apparentEnergyA: safe(apparentEnergy['phase_a']), apparentEnergyB: safe(apparentEnergy['phase_b']),
      apparentEnergyC: safe(apparentEnergy['phase_c']), apparentEnergyTotal: safe(apparentEnergy['total']),
      status: (d['status'] ?? 'OFF').toString(),
      deviceOnline: deviceOnline,
    );
  }

  PowerMeter3PhaseData copyWith({bool? deviceOnline}) => PowerMeter3PhaseData(
    voltA: voltA, voltB: voltB, voltC: voltC,
    currentA: currentA, currentB: currentB, currentC: currentC,
    freqA: freqA, freqB: freqB, freqC: freqC,
    angleVoltBtoA: angleVoltBtoA, angleVoltCtoA: angleVoltCtoA,
    angleCurrAtoVoltA: angleCurrAtoVoltA, angleCurrBtoVoltA: angleCurrBtoVoltA, angleCurrCtoVoltA: angleCurrCtoVoltA,
    activePowerA: activePowerA, activePowerB: activePowerB, activePowerC: activePowerC, activePowerTotal: activePowerTotal,
    reactivePowerA: reactivePowerA, reactivePowerB: reactivePowerB, reactivePowerC: reactivePowerC, reactivePowerTotal: reactivePowerTotal,
    apparentPowerA: apparentPowerA, apparentPowerB: apparentPowerB, apparentPowerC: apparentPowerC, apparentPowerTotal: apparentPowerTotal,
    pfA: pfA, pfB: pfB, pfC: pfC, pfTotal: pfTotal,
    activeEnergyA: activeEnergyA, activeEnergyB: activeEnergyB, activeEnergyC: activeEnergyC, activeEnergyTotal: activeEnergyTotal,
    reactiveEnergyA: reactiveEnergyA, reactiveEnergyB: reactiveEnergyB, reactiveEnergyC: reactiveEnergyC, reactiveEnergyTotal: reactiveEnergyTotal,
    apparentEnergyA: apparentEnergyA, apparentEnergyB: apparentEnergyB, apparentEnergyC: apparentEnergyC, apparentEnergyTotal: apparentEnergyTotal,
    status: status,
    deviceOnline: deviceOnline ?? this.deviceOnline,
  );

  // ── Turunan (dihitung sendiri di app) ───────────────────────────────────

  double get freqAvg => (freqA + freqB + freqC) / 3;
  double get voltAvg => (voltA + voltB + voltC) / 3;
  double get currentAvg => (currentA + currentB + currentC) / 3;

  double get voltImbalancePercent {
    if (voltAvg <= 0) return 0;
    final maxDev = [
      (voltA - voltAvg).abs(), (voltB - voltAvg).abs(), (voltC - voltAvg).abs(),
    ].reduce((a, b) => a > b ? a : b);
    return (maxDev / voltAvg) * 100;
  }

  double get currentImbalancePercent {
    if (currentAvg <= 0) return 0;
    final maxDev = [
      (currentA - currentAvg).abs(), (currentB - currentAvg).abs(), (currentC - currentAvg).abs(),
    ].reduce((a, b) => a > b ? a : b);
    return (maxDev / currentAvg) * 100;
  }

  static const double _phaseLossThreshold = 50.0;
  bool get isPhaseALost => voltA < _phaseLossThreshold && voltAvg > _phaseLossThreshold;
  bool get isPhaseBLost => voltB < _phaseLossThreshold && voltAvg > _phaseLossThreshold;
  bool get isPhaseCLost => voltC < _phaseLossThreshold && voltAvg > _phaseLossThreshold;
  List<String> get lostPhases => [
    if (isPhaseALost) 'A',
    if (isPhaseBLost) 'B',
    if (isPhaseCLost) 'C',
  ];

  /// Tegangan antar-fasa (L-L), dihitung dari magnitude + sudut fasa tegangan
  /// (hukum kosinus) karena device tidak mengirim V L-L langsung.
  /// Referensi: sudut Voltage A = 0°.
  static double _lineVoltage(double vX, double vY, double angleDiffDeg) {
    final rad = angleDiffDeg * math.pi / 180.0;
    final sq = vX * vX + vY * vY - 2 * vX * vY * math.cos(rad);
    return sq > 0 ? math.sqrt(sq) : 0;
  }

  double get voltAB => _lineVoltage(voltA, voltB, angleVoltBtoA);
  double get voltBC => _lineVoltage(voltB, voltC, angleVoltBtoA - angleVoltCtoA);
  double get voltCA => _lineVoltage(voltC, voltA, angleVoltCtoA);
}

class _Mqtt3PhaseConfig {
  static const broker    = 'broker.emqx.io';
  static const port      = 1883;
  static const wsBroker  = 'ws://broker.emqx.io:8083/mqtt';
  static const wsPort    = 8083;
  // Sesuai stateTopic di Thing openHAB "Power Meter Office SBY"
  static const topicData = 'powermeter/office/sby/data';
}

class Mqtt3PhaseService {
  static final Mqtt3PhaseService instance = Mqtt3PhaseService._();
  Mqtt3PhaseService._();

  late MqttServerClient _client;
  final _controller = StreamController<PowerMeter3PhaseData>.broadcast();
  PowerMeter3PhaseData _lastData = const PowerMeter3PhaseData();
  bool _isConnected = false;
  bool _isConnecting = false;
  Timer? _offlineTimer;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  static const _maxRetryDelaySec = 30;

  void _resetOfflineTimer() {
    _offlineTimer?.cancel();
    _offlineTimer = Timer(const Duration(seconds: 60), () {
      _lastData = _lastData.copyWith(deviceOnline: false);
      _controller.add(_lastData);
    });
  }

  Stream<PowerMeter3PhaseData> get stream => _controller.stream;
  PowerMeter3PhaseData get lastData => _lastData;
  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_isConnected || _isConnecting) return;
    _isConnecting = true;
    _retryTimer?.cancel();

    bool resolved = false;

    Future<void> tryTransport(bool useWebSocket) async {
      final label = useWebSocket ? 'WebSocket' : 'TCP';
      final host  = useWebSocket ? _Mqtt3PhaseConfig.wsBroker : _Mqtt3PhaseConfig.broker;
      final port  = useWebSocket ? _Mqtt3PhaseConfig.wsPort : _Mqtt3PhaseConfig.port;
      final clientId =
          'flutter_mqtt3ph_${DateTime.now().millisecondsSinceEpoch}_$label';

      final client = MqttServerClient(host, clientId)
        ..port                       = port
        ..useWebSocket               = useWebSocket
        ..keepAlivePeriod            = 30
        ..connectTimeoutPeriod       = 8000
        ..autoReconnect              = true
        ..resubscribeOnAutoReconnect = true
        ..logging(on: false);

      client.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean();

      try {
        await client.connect();
      } catch (e) {
        debugPrint('Mqtt3PhaseService: $label gagal — $e');
        client.disconnect();
        return;
      }

      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        debugPrint('Mqtt3PhaseService: $label status bukan connected — '
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
      _client.subscribe(_Mqtt3PhaseConfig.topicData, MqttQos.atLeastOnce);
      _client.updates?.listen(_onMessage);
      debugPrint('Mqtt3PhaseService: berhasil connect via $label');
      _onConnected();
    }

    await Future.wait([tryTransport(false), tryTransport(true)]);

    _isConnecting = false;
    if (!resolved) _scheduleRetry();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delaySec = (5 * (1 << _retryAttempt)).clamp(5, _maxRetryDelaySec);
    _retryAttempt++;
    debugPrint('Mqtt3PhaseService: retry connect dalam ${delaySec}s (percobaan ke-$_retryAttempt)');
    _retryTimer = Timer(Duration(seconds: delaySec), () {
      if (!_isConnected) connect();
    });
  }

  void disconnect() {
    _retryTimer?.cancel();
    _offlineTimer?.cancel();
    _client.disconnect();
    _controller.close();
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final payload = (event.payload as MqttPublishMessage).payload.message;
      final raw     = MqttPublishPayload.bytesToStringAsString(payload);
      final topic   = event.topic;

      if (topic == _Mqtt3PhaseConfig.topicData) {
        try {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          _lastData = PowerMeter3PhaseData.fromJson(json, deviceOnline: true);
          _controller.add(_lastData);
          _resetOfflineTimer();
        } catch (_) {}
      }
    }
  }

  void _onConnected() {
    _isConnected = true;
    _retryAttempt = 0;
    debugPrint('Mqtt3PhaseService: connected');
  }

  void _onDisconnected() {
    _isConnected = false;
    debugPrint('Mqtt3PhaseService: disconnected');
    _scheduleRetry();
  }

  void _onAutoReconnected() {
    _isConnected = true;
    _retryAttempt = 0;
    debugPrint('Mqtt3PhaseService: reconnected');
  }
}