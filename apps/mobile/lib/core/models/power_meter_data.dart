/// Model data power meter 1 fasa. Diisi dari openHAB.
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

  PowerMeterData copyWith({bool? deviceOnline}) => PowerMeterData(
    power: power, volt: volt, amp: amp, freq: freq, pf: pf,
    energyTotal: energyTotal, energyToday: energyToday,
    energyYesterday: energyYesterday, status: status,
    deviceOnline: deviceOnline ?? this.deviceOnline,
  );

  double get powerKw => power / 1000;
}
