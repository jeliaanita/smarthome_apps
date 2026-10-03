import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/core/providers/installation_provider.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:mobile/core/services/mqtt_service_3phase.dart' show PowerMeter3PhaseData;
import 'package:mobile/core/services/openhab_3phase_service.dart';

/// Halaman "Energy - 3 Phase" untuk Thing openHAB "Power Meter Office SBY".
///
/// Sumber data: openHAB REST API SAJA (bukan lagi koneksi MQTT langsung dari
/// app). Status online/offline & semua nilai di halaman ini akan selalu
/// sama persis dengan yang ditampilkan openHAB — karena memang datanya
/// datang dari sana. Lihat openhab_3phase_service.dart untuk detail caranya
/// (auto-discover nama Item lewat /rest/links, tidak ada nama yang di-hardcode).
class Energy3PhasePage extends StatefulWidget {
  const Energy3PhasePage({super.key});

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

  // ── Riwayat Energy (openHAB Persistence API) ─────────────────────────────
  _HistoryPeriod _historyPeriod = _HistoryPeriod.hour;
  List<_EnergyPoint> _historyPoints = [];
  bool _historyLoading = false;
  String? _historyError;
  bool _historyStale = false;

  @override
  void initState() {
    super.initState();
    final service = OpenHab3PhaseService.instance;
    _data = service.lastData;
    _connected = service.isConnected;

    final config = context.read<InstallationProvider>().config;
    service.configure(
      baseUrl: config?.openhabUrl ?? '',
      apiToken: config?.apiToken,
      username: config?.username,
      password: config?.password,
    );
    service.start();
    _loadHistory();

    _dataSub = service.stream.listen((data) {
      if (!mounted) return;
      setState(() {
        _data = data;
        _connected = service.isConnected;
        _lastUpdate = DateTime.now();
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

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });

    try {
      final now = DateTime.now();
      late DateTime start;
      late String channelId;
      switch (_historyPeriod) {
        case _HistoryPeriod.hour:
          start = now.subtract(const Duration(hours: 24));
          channelId = 'active_power_total';
          break;
        case _HistoryPeriod.day:
          start = now.subtract(const Duration(days: 8));
          channelId = 'active_energy_total';
          break;
        case _HistoryPeriod.month:
          start = now.subtract(const Duration(days: 396));
          channelId = 'active_energy_total';
          break;
      }

      final rawJson = await OpenHab3PhaseService.instance
          .fetchPersistence(channelId, start: start, end: now);

      if (rawJson == null) {
        throw Exception('Persistence belum aktif untuk item ini, atau item belum ter-link');
      }

      final raw = rawJson
          .map((m) {
            final t = m['time'];
            final v = double.tryParse('${m['state']}');
            if (t == null || v == null) return null;
            return _RawPoint(time: DateTime.fromMillisecondsSinceEpoch((t as num).toInt()), value: v);
          })
          .whereType<_RawPoint>()
          .toList()
        ..sort((a, b) => a.time.compareTo(b.time));

      List<_EnergyPoint> points;
      switch (_historyPeriod) {
        case _HistoryPeriod.hour:
          points = _aggregateHourly(raw);
          break;
        case _HistoryPeriod.day:
          points = _aggregateDelta(raw, byMonth: false);
          break;
        case _HistoryPeriod.month:
          points = _aggregateDelta(raw, byMonth: true);
          break;
      }

      if (!mounted) return;
      setState(() {
        _historyPoints = points;
        _historyLoading = false;
        _historyStale = raw.isNotEmpty && now.difference(raw.last.time) > const Duration(hours: 2);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyLoading = false;
        _historyPoints = [];
        _historyError = 'Gagal memuat histori: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  List<_EnergyPoint> _aggregateHourly(List<_RawPoint> raw) {
    if (raw.isEmpty) return [];
    final buckets = <DateTime, List<double>>{};
    for (final p in raw) {
      final key = DateTime(p.time.year, p.time.month, p.time.day, p.time.hour);
      buckets.putIfAbsent(key, () => []).add(p.value);
    }
    final keys = buckets.keys.toList()..sort();
    return keys.map((k) {
      final vals = buckets[k]!;
      final avg = vals.reduce((a, b) => a + b) / vals.length;
      return _EnergyPoint(time: k, value: avg); // sudah kW dari active_power_total
    }).toList();
  }

  /// Ambil pembacaan terakhir per hari/bulan lalu hitung selisihnya — cara
  /// standar menghitung konsumsi dari meter kumulatif (active_energy_total).
  List<_EnergyPoint> _aggregateDelta(List<_RawPoint> raw, {required bool byMonth}) {
    if (raw.isEmpty) return [];
    final lastPerBucket = <DateTime, double>{};
    for (final p in raw) {
      final key = byMonth
          ? DateTime(p.time.year, p.time.month)
          : DateTime(p.time.year, p.time.month, p.time.day);
      lastPerBucket[key] = p.value;
    }
    final keys = lastPerBucket.keys.toList()..sort();
    final result = <_EnergyPoint>[];
    for (var i = 1; i < keys.length; i++) {
      final delta = lastPerBucket[keys[i]]! - lastPerBucket[keys[i - 1]]!;
      result.add(_EnergyPoint(time: keys[i], value: delta < 0 ? 0 : delta));
    }
    return result;
  }

  String _historyUnit() => _historyPeriod == _HistoryPeriod.hour ? 'kW' : 'kWh';

  String _formatPointLabel(DateTime t) {
    switch (_historyPeriod) {
      case _HistoryPeriod.hour:
        return '${t.hour.toString().padLeft(2, '0')}:00';
      case _HistoryPeriod.day:
        return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
      case _HistoryPeriod.month:
        const months = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'];
        return months[t.month - 1];
    }
  }

  String _lastUpdatedLabel() {
    if (_historyPoints.isEmpty) return '-';
    final t = _historyPoints.last.time;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
  }

  double _historyMaxValue() {
    if (_historyPoints.isEmpty) return 0;
    return _historyPoints.map((p) => p.value).reduce((a, b) => a > b ? a : b);
  }

  String _formatAxisValue(double v) {
    if (v <= 0) return '0';
    return v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  TextStyle _yAxisLabelStyle(bool isDark) => TextStyle(fontFamily: 'Inter', fontSize: 9,
      color: isDark ? Colors.white38 : const Color(0xFF94A3B8));

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
              _buildHistoryCard(context),
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
        child: Text('Energy - 3 Phase',
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

  // ── Riwayat Energy (openHAB Persistence API) ─────────────────────────────
  Widget _buildHistoryCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _cardWrap(context, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _cardTitle(context, 'Riwayat Energy'),
        if (_historyStale)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10)),
            child: const Text('Data stale',
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
                    fontSize: 10, color: Color(0xFFF59E0B))),
          ),
      ]),
      const SizedBox(height: 12),
      _buildHistoryPeriodTabs(isDark),
      const SizedBox(height: 16),
      if (_historyLoading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
        )
      else if (_historyError != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(children: [
            Icon(Icons.error_outline_rounded, size: 28,
                color: isDark ? Colors.white38 : Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(_historyError!, textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                    color: isDark ? Colors.white54 : const Color(0xFF71717A))),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _loadHistory,
              child: const Text('Coba lagi',
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
                      fontSize: 12, color: Color(0xFFFFA500))),
            ),
          ]),
        )
      else if (_historyPoints.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Column(children: [
            Icon(Icons.bar_chart_rounded, size: 28,
                color: isDark ? Colors.white38 : Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('Belum ada data histori untuk periode ini',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                    color: isDark ? Colors.white54 : const Color(0xFF71717A))),
          ]),
        )
      else ...[
        SizedBox(
          height: 150,
          width: double.infinity,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 42,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_formatAxisValue(_historyMaxValue()), style: _yAxisLabelStyle(isDark)),
                  Text(_formatAxisValue(_historyMaxValue() / 2), style: _yAxisLabelStyle(isDark)),
                  Text('0', style: _yAxisLabelStyle(isDark)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CustomPaint(
                size: Size.infinite,
                painter: _HistoryBarPainter(points: _historyPoints, isDark: isDark,
                    barColor: const Color(0xFFF31260)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 50),
          child: _buildHistoryAxisLabels(isDark),
        ),
        const SizedBox(height: 10),
        Text('Satuan: ${_historyUnit()}  •  diperbarui ${_lastUpdatedLabel()}',
            style: TextStyle(fontFamily: 'Inter', fontSize: 10,
                color: isDark ? Colors.white38 : const Color(0xFF94A3B8))),
      ],
    ]));
  }

  Widget _buildHistoryPeriodTabs(bool isDark) {
    final options = <MapEntry<_HistoryPeriod, String>>[
      const MapEntry(_HistoryPeriod.hour, 'Jam'),
      const MapEntry(_HistoryPeriod.day, 'Harian'),
      const MapEntry(_HistoryPeriod.month, 'Bulanan'),
    ];
    return Row(
      children: options.map((o) {
        final selected = _historyPeriod == o.key;
        return Expanded(
          child: GestureDetector(
            onTap: selected ? null : () {
              setState(() => _historyPeriod = o.key);
              _loadHistory();
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFF31260).withValues(alpha: 0.15)
                    : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7)),
                borderRadius: BorderRadius.circular(12),
                border: selected ? Border.all(color: const Color(0xFFF31260)) : null,
              ),
              child: Text(o.value, textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12,
                      color: selected ? const Color(0xFFF31260)
                          : (isDark ? Colors.white54 : const Color(0xFF71717A)))),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHistoryAxisLabels(bool isDark) {
    final n = _historyPoints.length;
    final step = n <= 6 ? 1 : (n / 6).ceil();
    return Row(
      children: List.generate(n, (i) {
        final show = i % step == 0 || i == n - 1;
        return Expanded(
          child: Text(show ? _formatPointLabel(_historyPoints[i].time) : '',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Inter', fontSize: 9,
                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8))),
        );
      }),
    );
  }
}

enum _HistoryPeriod { hour, day, month }

enum _LiveStatus { online, stale, offline }

class _RawPoint {
  final DateTime time;
  final double value;
  const _RawPoint({required this.time, required this.value});
}

class _EnergyPoint {
  final DateTime time;
  final double value;
  const _EnergyPoint({required this.time, required this.value});
}

class _HistoryBarPainter extends CustomPainter {
  final List<_EnergyPoint> points;
  final bool isDark;
  final Color barColor;
  const _HistoryBarPainter({required this.points, required this.isDark, required this.barColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final maxVal = points.map((p) => p.value).fold<double>(0, (a, b) => b > a ? b : a);
    final safeMax = maxVal <= 0 ? 1.0 : maxVal;

    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height - (size.height / 3) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final barWidth = size.width / points.length;
    final barPaint = Paint()..color = barColor;
    for (var i = 0; i < points.length; i++) {
      final h = (points[i].value / safeMax) * (size.height - 4);
      final left = i * barWidth + barWidth * 0.2;
      final right = (i + 1) * barWidth - barWidth * 0.2;
      final rect = Rect.fromLTRB(left, size.height - h, right, size.height);
      canvas.drawRRect(RRect.fromRectAndCorners(rect,
          topLeft: const Radius.circular(4), topRight: const Radius.circular(4)), barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HistoryBarPainter old) =>
      old.points != points || old.isDark != isDark;
}