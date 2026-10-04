import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile/core/models/power_meter_3phase_data.dart';
import 'package:mobile/core/services/openhab_power_meter_service.dart';
import 'package:mobile/core/widget/data_logger.dart';

/// Halaman Energy 3 fasa untuk SATU meter hasil discovery openHAB.
///
/// Sumber data: openHAB REST API saja (lihat openhab_power_meter_service.dart).
/// Halaman ini tidak tahu topic/Thing UID apa pun — meter dikirim dari
/// EnergyPage. Service-nya sudah di-configure() dan di-start() oleh EnergyPage.
class Energy3PhasePage extends StatefulWidget {
  final PowerMeterDevice device;
  const Energy3PhasePage({super.key, required this.device});

  @override
  State<Energy3PhasePage> createState() => _Energy3PhasePageState();
}

class _Energy3PhasePageState extends State<Energy3PhasePage> {
  PowerMeter3PhaseData _data = const PowerMeter3PhaseData();
  bool _connected = false; // = status Thing openHAB (ONLINE/OFFLINE)
  StreamSubscription? _dataSub;
  Timer? _staleCheckTimer;

  /// Kapan data terakhir kali diterima dari stream service — dipakai untuk
  /// deteksi stale (Thing bisa aja masih berstatus ONLINE di openHAB tapi
  /// datanya berhenti mengalir, mis. sensor macet).
  DateTime? _lastUpdate;
  static const _staleThreshold = Duration(seconds: 90);
  bool get _isStale =>
      _lastUpdate == null || DateTime.now().difference(_lastUpdate!) > _staleThreshold;

  _LiveStatus get _liveStatus {
    if (!_connected) return _LiveStatus.offline;
    if (_isStale) return _LiveStatus.stale;
    return _LiveStatus.online;
  }

  String get _liveStatusLabel {
    switch (_liveStatus) {
      case _LiveStatus.online:  return 'Online';
      case _LiveStatus.stale:   return 'Data tidak diperbarui';
      case _LiveStatus.offline: return 'Offline';
    }
  }

  Color get _liveStatusColor {
    switch (_liveStatus) {
      case _LiveStatus.online:  return const Color(0xFF34C759);
      case _LiveStatus.stale:   return const Color(0xFFF59E0B);
      case _LiveStatus.offline: return const Color(0xFFF31260);
    }
  }

  // Ambang batas imbalance — standar umum industri (NEMA/IEC)
  static const double _voltImbalanceMax = 5;  // %
  static const double _ampImbalanceMax  = 10; // %

  @override
  void initState() {
    super.initState();
    final service = OpenHabPowerMeterService.instance;
    final uid = widget.device.thingUid;
    final snap = service.lastSnapshots[uid];
    if (snap != null) {
      _data = snap.data;
      _connected = snap.data.deviceOnline;
      _lastUpdate = snap.lastChange;
    }

    _dataSub = service.stream.listen((all) {
      final s = all[uid];
      if (s == null || !mounted) return;
      setState(() {
        _data = s.data;
        _connected = s.data.deviceOnline;
        // Waktu NILAI terakhir berubah, bukan waktu polling — supaya
        // "Data tidak diperbarui" benar-benar bisa muncul.
        _lastUpdate = s.lastChange;
      });
    });
    // Re-evaluasi status stale berkala walau tidak ada data baru masuk.
    _staleCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _staleCheckTimer?.cancel();
    super.dispose();
  }

  List<String> _computeAlarms() {
    final alarms = <String>[];
    if (_connected && _isStale) {
      alarms.add('Data tidak diperbarui sejak terakhir — perangkat online tapi '
          'sensor kemungkinan macet');
    }
    alarms.addAll(_data.lostPhases.map((p) => 'Fasa $p hilang (phase loss)'));
    return alarms;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              _buildAppBar(context),
              const SizedBox(height: 20),
              _buildAlarmBanner(context),
              _buildTotalEnergyCard(context),
              const SizedBox(height: 12),
              _buildOverviewRow(context),
              const SizedBox(height: 12),
              _buildPhaseTable(context),
              const SizedBox(height: 12),
              _buildLineVoltageCard(context),
              const SizedBox(height: 12),
              _buildPowerPfTable(context),
              const SizedBox(height: 12),
              _buildEnergyTable(context),
              const SizedBox(height: 12),
              _buildImbalanceCard(context),
              const SizedBox(height: 12),
              _buildDataLogger(context),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── AppBar ───────────────────────────────────────────────────────────────
  Widget _buildAppBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xCC18181B);
    final color = _liveStatusColor;
    return Row(children: [
      GestureDetector(
        onTap: () => Navigator.maybePop(context),
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF27272A) : Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
          ),
          child: Icon(Icons.arrow_back_ios_new, size: 16, color: textColor),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(widget.device.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                fontSize: 16, color: textColor)),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 6),
          Text(_liveStatusLabel,
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 11,
                  color: color)),
        ]),
      ),
    ]);
  }

  // ── Alarm banner — cuma phase loss (sesuai requirement) ─────────────────
  Widget _buildAlarmBanner(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final alarms = _computeAlarms();
    if (alarms.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF31260).withValues(alpha: isDark ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF31260).withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFF31260)),
          const SizedBox(width: 8),
          Text('${alarms.length} Alarm Aktif',
              style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                  fontSize: 13, color: Color(0xFFF31260))),
        ]),
        const SizedBox(height: 8),
        ...alarms.map((msg) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(margin: const EdgeInsets.only(top: 5), width: 4, height: 4,
                decoration: const BoxDecoration(color: Color(0xFFF31260), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(child: Text(msg,
                style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                    color: isDark ? Colors.white.withValues(alpha: 0.85) : const Color(0xFF3F3F46)))),
          ]),
        )),
      ]),
    );
  }

  Widget _cardWrap(BuildContext context, {required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: child,
    );
  }

  Widget _cardTitle(BuildContext context, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(text,
        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13,
            color: isDark ? Colors.white70 : const Color(0xFF52525B)));
  }

  // ── Total energi ─────────────────────────────────────────────────────────
  Widget _buildTotalEnergyCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xCC18181B);
    return _cardWrap(context, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Total Active Energy',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 14, color: textColor)),
      const SizedBox(height: 6),
      RichText(text: TextSpan(children: [
        TextSpan(text: _data.activeEnergyTotal.toStringAsFixed(2),
            style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                fontSize: 32, color: Color(0xFFFFA500))),
        const TextSpan(text: ' kWh',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500,
                fontSize: 14, color: Color(0xFFFFA500))),
      ])),
      const SizedBox(height: 4),
      Text('Reaktif: ${_data.reactiveEnergyTotal.toStringAsFixed(2)} kVARh  ·  '
          'Semu: ${_data.apparentEnergyTotal.toStringAsFixed(2)} kVAh',
          style: TextStyle(fontFamily: 'Inter', fontSize: 12,
              color: isDark ? Colors.white54 : const Color(0xFF71717A))),
    ]));
  }

  // ── Overview: daya aktif, PF, frekuensi ─────────────────────────────────
  Widget _buildOverviewRow(BuildContext context) {
    return _cardWrap(context, child: IntrinsicHeight(child: Row(children: [
      _statItem('Active Power', '${_data.activePowerTotal.toStringAsFixed(2)} kW', const Color(0xFFF31260)),
      _statItem('Power Factor', '${(_data.pfTotal * 100).toStringAsFixed(1)} %', const Color(0xFF0088FF)),
      _statItem('Frequency', '${_data.freqAvg.toStringAsFixed(2)} Hz', const Color(0xFF34C759)),
    ])));
  }

  Widget _statItem(String label, String value, Color color) {
    return Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(label, textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 10, color: Color(0xFF71717A))),
      const SizedBox(height: 3),
      Text(value, textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: color)),
    ]));
  }

  // ── Tabel per-fasa: Volt L-N & Arus ──────────────────────────────────────
  Widget _buildPhaseTable(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rows = [
      ('A', _data.voltA, _data.currentA, const Color(0xFFFB0004)),
      ('B', _data.voltB, _data.currentB, const Color(0xFFFFCC00)),
      ('C', _data.voltC, _data.currentC, const Color(0xFF0088FF)),
    ];
    return _cardWrap(context, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle(context, 'Tegangan & Arus per Fasa'),
      const SizedBox(height: 12),
      Row(children: [
        const SizedBox(width: 36),
        Expanded(child: Text('Volt (L-N)', style: _headStyle(isDark))),
        Expanded(child: Text('Arus', style: _headStyle(isDark))),
      ]),
      const SizedBox(height: 8),
      ...rows.map((r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(width: 24, height: 24,
              decoration: BoxDecoration(color: r.$4.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Center(child: Text(r.$1,
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 11, color: r.$4)))),
          const SizedBox(width: 12),
          Expanded(child: Text('${r.$2.toStringAsFixed(1)} V',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13,
                  color: isDark ? Colors.white : const Color(0xFF18181B)))),
          Expanded(child: Text('${r.$3.toStringAsFixed(2)} A',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13,
                  color: isDark ? Colors.white : const Color(0xFF18181B)))),
        ]),
      )),
      const Divider(height: 20),
      Row(children: [
        const SizedBox(width: 36),
        Expanded(child: Text('Netral (N)', style: _headStyle(isDark))),
        Expanded(child: Row(children: [
          Text('N/A', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13,
              color: isDark ? Colors.white38 : Colors.black38)),
        ])),
      ]),
      const SizedBox(height: 4),
      Text('Device belum mengirim data arus netral (tidak ada field current.neutral di payload)',
          style: TextStyle(fontFamily: 'Inter', fontSize: 10,
              color: isDark ? Colors.white38 : Colors.black38)),
    ]));
  }

  TextStyle _headStyle(bool isDark) => TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500,
      fontSize: 11, color: isDark ? Colors.white54 : const Color(0xFF71717A));

  // ── Tegangan antar-fasa (L-L) — dihitung dari sudut fasa ────────────────
  Widget _buildLineVoltageCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _cardWrap(context, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle(context, 'Tegangan Antar-Fasa (L-L)'),
      const SizedBox(height: 4),
      Text('Dihitung dari sudut fasa tegangan (bukan dikirim langsung oleh device)',
          style: TextStyle(fontFamily: 'Inter', fontSize: 10,
              color: isDark ? Colors.white38 : Colors.black38)),
      const SizedBox(height: 12),
      Row(children: [
        _llItem('A-B', _data.voltAB, isDark),
        _llItem('B-C', _data.voltBC, isDark),
        _llItem('C-A', _data.voltCA, isDark),
      ]),
    ]));
  }

  Widget _llItem(String label, double value, bool isDark) {
    return Expanded(child: Column(children: [
      Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 11,
          color: isDark ? Colors.white54 : const Color(0xFF71717A))),
      const SizedBox(height: 4),
      Text('${value.toStringAsFixed(1)} V',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15,
              color: isDark ? Colors.white : const Color(0xFF18181B))),
    ]));
  }

  // ── Daya aktif/reaktif/apparent & PF, per fasa + total ──────────────────
  Widget _buildPowerPfTable(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rows = [
      ('A', _data.activePowerA, _data.reactivePowerA, _data.apparentPowerA, _data.pfA),
      ('B', _data.activePowerB, _data.reactivePowerB, _data.apparentPowerB, _data.pfB),
      ('C', _data.activePowerC, _data.reactivePowerC, _data.apparentPowerC, _data.pfC),
      ('Total', _data.activePowerTotal, _data.reactivePowerTotal, _data.apparentPowerTotal, _data.pfTotal),
    ];
    return _cardWrap(context, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle(context, 'Daya & Power Factor'),
      const SizedBox(height: 12),
      Row(children: [
        SizedBox(width: 40, child: Text('', style: _headStyle(isDark))),
        Expanded(child: Text('Aktif (kW)', style: _headStyle(isDark))),
        Expanded(child: Text('Reaktif (kVAR)', style: _headStyle(isDark))),
        Expanded(child: Text('Semu (kVA)', style: _headStyle(isDark))),
        Expanded(child: Text('PF', style: _headStyle(isDark))),
      ]),
      const SizedBox(height: 8),
      ...rows.map((r) {
        final isTotal = r.$1 == 'Total';
        final textStyle = TextStyle(fontFamily: 'Inter',
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w600, fontSize: 12,
            color: isDark ? Colors.white : const Color(0xFF18181B));
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(width: 40, child: Text(r.$1,
                style: textStyle.copyWith(color: isTotal ? const Color(0xFFFFA500) : textStyle.color))),
            Expanded(child: Text(r.$2.toStringAsFixed(2), style: textStyle)),
            Expanded(child: Text(r.$3.toStringAsFixed(2), style: textStyle)),
            Expanded(child: Text(r.$4.toStringAsFixed(2), style: textStyle)),
            Expanded(child: Text(r.$5.toStringAsFixed(2), style: textStyle)),
          ]),
        );
      }),
    ]));
  }

  // ── Energi aktif/reaktif/apparent, per fasa + total ─────────────────────
  Widget _buildEnergyTable(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rows = [
      ('A', _data.activeEnergyA, _data.reactiveEnergyA, _data.apparentEnergyA),
      ('B', _data.activeEnergyB, _data.reactiveEnergyB, _data.apparentEnergyB),
      ('C', _data.activeEnergyC, _data.reactiveEnergyC, _data.apparentEnergyC),
      ('Total', _data.activeEnergyTotal, _data.reactiveEnergyTotal, _data.apparentEnergyTotal),
    ];
    return _cardWrap(context, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle(context, 'Energi'),
      const SizedBox(height: 12),
      Row(children: [
        SizedBox(width: 40, child: Text('', style: _headStyle(isDark))),
        Expanded(child: Text('Aktif (kWh)', style: _headStyle(isDark))),
        Expanded(child: Text('Reaktif (kVARh)', style: _headStyle(isDark))),
        Expanded(child: Text('Semu (kVAh)', style: _headStyle(isDark))),
      ]),
      const SizedBox(height: 8),
      ...rows.map((r) {
        final isTotal = r.$1 == 'Total';
        final textStyle = TextStyle(fontFamily: 'Inter',
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w600, fontSize: 12,
            color: isDark ? Colors.white : const Color(0xFF18181B));
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(width: 40, child: Text(r.$1,
                style: textStyle.copyWith(color: isTotal ? const Color(0xFFFFA500) : textStyle.color))),
            Expanded(child: Text(r.$2.toStringAsFixed(2), style: textStyle)),
            Expanded(child: Text(r.$3.toStringAsFixed(2), style: textStyle)),
            Expanded(child: Text(r.$4.toStringAsFixed(2), style: textStyle)),
          ]),
        );
      }),
    ]));
  }

  // ── Imbalance ────────────────────────────────────────────────────────────
  Widget _buildImbalanceCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final voltBad = _data.voltImbalancePercent > _voltImbalanceMax;
    final ampBad  = _data.currentImbalancePercent > _ampImbalanceMax;
    return _cardWrap(context, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle(context, 'Keseimbangan Beban (Imbalance)'),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _imbalanceItem('Tegangan', _data.voltImbalancePercent, voltBad, isDark)),
        const SizedBox(width: 16),
        Expanded(child: _imbalanceItem('Arus', _data.currentImbalancePercent, ampBad, isDark)),
      ]),
    ]));
  }

  Widget _imbalanceItem(String label, double percent, bool bad, bool isDark) {
    final color = bad ? const Color(0xFFF31260) : const Color(0xFF34C759);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 11,
          color: isDark ? Colors.white54 : const Color(0xFF71717A))),
      const SizedBox(height: 4),
      Row(children: [
        Text('${percent.toStringAsFixed(1)}%',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 18, color: color)),
        const SizedBox(width: 6),
        Icon(bad ? Icons.warning_amber_rounded : Icons.check_circle, size: 16, color: color),
      ]),
    ]);
  }

  // ── Data Logger (riwayat dari openHAB Persistence) ──────────────────────
  static const _loggerSeries = <LoggerSeries>[
    LoggerSeries(id: 'active_power_total', label: 'Daya Aktif', unit: 'kW',
        icon: Icons.bolt_rounded, color: Color(0xFFF31260)),
    LoggerSeries(id: 'active_energy_total', label: 'Energi', unit: 'kWh',
        kind: LoggerKind.cumulative, icon: Icons.speed_rounded, color: Color(0xFFFFA500)),
    LoggerSeries(id: 'voltage_phase_a', label: 'Tegangan A', unit: 'V', decimals: 1,
        icon: Icons.electrical_services_rounded, color: Color(0xFFEF4444)),
    LoggerSeries(id: 'voltage_phase_b', label: 'Tegangan B', unit: 'V', decimals: 1,
        icon: Icons.electrical_services_rounded, color: Color(0xFFF59E0B)),
    LoggerSeries(id: 'voltage_phase_c', label: 'Tegangan C', unit: 'V', decimals: 1,
        icon: Icons.electrical_services_rounded, color: Color(0xFF3B82F6)),
    LoggerSeries(id: 'current_phase_a', label: 'Arus A', unit: 'A',
        icon: Icons.waves_rounded, color: Color(0xFFEF4444)),
    LoggerSeries(id: 'current_phase_b', label: 'Arus B', unit: 'A',
        icon: Icons.waves_rounded, color: Color(0xFFF59E0B)),
    LoggerSeries(id: 'current_phase_c', label: 'Arus C', unit: 'A',
        icon: Icons.waves_rounded, color: Color(0xFF3B82F6)),
    LoggerSeries(id: 'power_factor_total', label: 'Faktor Daya', unit: '%', scale: 100, decimals: 1,
        icon: Icons.percent_rounded, color: Color(0xFF0088FF)),
    LoggerSeries(id: 'frequency_phase_a', label: 'Frekuensi', unit: 'Hz',
        icon: Icons.graphic_eq_rounded, color: Color(0xFF34C759)),
    LoggerSeries(id: 'status', label: 'Status Meter', kind: LoggerKind.binary,
        icon: Icons.power_settings_new_rounded, activeLabel: 'ON', inactiveLabel: 'OFF'),
  ];

  // channelId -> Item milik meter INI (hasil discovery /rest/links)
  late final LoggerFetcher _loggerFetcher = openHabLoggerFetcher(
    baseUrl: () => OpenHabEndpoint.instance.baseUrl,
    headers: () => OpenHabEndpoint.instance.headers,
    itemNameOf: (s) => widget.device.channelToItem[s.id],
  );

  Widget _buildDataLogger(BuildContext context) {
    return DataLoggerCard(
      title: 'Data Logger',
      series: _loggerSeries,
      fetcher: _loggerFetcher,
    );
  }
}

enum _LiveStatus { online, stale, offline }