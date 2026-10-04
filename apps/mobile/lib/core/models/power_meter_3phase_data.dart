import 'dart:math' as math;

/// Model data power meter 3 fasa. Diisi dari openHAB (lihat
/// openhab_power_meter_service.dart) — tidak lagi dari payload MQTT.
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
