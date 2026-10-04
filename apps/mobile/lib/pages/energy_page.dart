import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mobile/core/providers/installation_provider.dart';
import 'package:mobile/core/widget/data_logger.dart';
import 'package:mobile/pages/floor_plan_page.dart';
import 'package:mobile/pages/settings_page.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:mobile/core/models/power_meter_data.dart';
import 'package:mobile/core/services/openhab_power_meter_service.dart';
import 'energy_3phase_page.dart';

/// Entry point publik — dipanggil dari nav yang sudah ada (`EnergyPage()`),
/// tidak perlu diubah di tempat lain. Di dalamnya sekarang berupa halaman
/// yang bisa digeser kiri-kanan antar tipe meter (1-phase, 3-phase, dst).
///
/// Tab dibuat otomatis dari meter yang ditemukan di openHAB — tidak ada
/// daftar meter yang ditulis di kode.
class EnergyPage extends StatefulWidget {
  const EnergyPage({super.key});

  @override
  State<EnergyPage> createState() => _EnergyPageState();
}

enum _PhaseKind { one, three }

class _MeterRef {
  final String uid;
  final String label;
  const _MeterRef(this.uid, this.label);
}

class _EnergyPageState extends State<EnergyPage> {
  final PageController _pageController = PageController();
  StreamSubscription? _meterSub;
  String _tabKey = '';
  int _phaseIndex = 0; // index di dalam _groups

  // Meter hasil discovery openHAB, dikelompokkan per tipe.
  List<SinglePhaseDevice> _singles = [];
  List<PowerMeterDevice> _threes = [];
  String? _selSingle; // thingUid meter 1 fasa yang sedang dibuka
  String? _selThree; // thingUid meter 3 fasa yang sedang dibuka

  /// Segmen switcher: hanya tipe yang punya meter.
  List<_PhaseKind> get _groups => [
        if (_singles.isNotEmpty) _PhaseKind.one,
        if (_threes.isNotEmpty) _PhaseKind.three,
      ];

  @override
  void initState() {
    super.initState();
    // Konfigurasi openHAB diisi SEKALI di sini, lalu service jalan.
    final config = context.read<InstallationProvider>().config;
    OpenHabEndpoint.instance.configure(
      baseUrl: config?.openhabUrl ?? '',
      apiToken: config?.apiToken,
      username: config?.username,
      password: config?.password,
    );
    _start();
  }

  Future<void> _start() async {
    final meters = OpenHabPowerMeterService.instance;
    _meterSub = meters.stream.listen((_) => _refreshMeters());
    await meters.start();
    if (mounted) _refreshMeters();
  }

  void _refreshMeters() {
    final svc = OpenHabPowerMeterService.instance;
    final key = [
      ...svc.singleDevices.map((d) => '1:${d.thingUid}'),
      ...svc.devices.map((d) => '3:${d.thingUid}'),
    ].join(',');
    if (key == _tabKey || !mounted) return;
    _tabKey = key;
    setState(() {
      _singles = svc.singleDevices;
      _threes = svc.devices;
      if (!_singles.any((d) => d.thingUid == _selSingle)) {
        _selSingle = _singles.isEmpty ? null : _singles.first.thingUid;
      }
      if (!_threes.any((d) => d.thingUid == _selThree)) {
        _selThree = _threes.isEmpty ? null : _threes.first.thingUid;
      }
      if (_phaseIndex >= _groups.length) {
        _phaseIndex = 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) _pageController.jumpToPage(0);
        });
      }
    });
  }

  @override
  void dispose() {
    _meterSub?.cancel();
    OpenHabPowerMeterService.instance.stop();
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    setState(() => _phaseIndex = index);
    _pageController.animateToPage(index,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final groups = _groups;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _buildPhaseSwitcher(isDark, groups),
            ),
          ),
          Expanded(
            child: groups.isEmpty
                ? Center(
                    child: Text(
                      'Belum ada power meter ditemukan di openHAB',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: isDark ? Colors.white54 : Colors.black45),
                    ),
                  )
                // Status bar sudah ditangani switcher di atas, jadi SafeArea
                // di dalam tiap halaman tidak boleh menambah jarak lagi.
                : MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: (i) => setState(() => _phaseIndex = i),
                      children: [for (final g in groups) _buildGroup(g, isDark)],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Switcher utama: 1 Phase | 3 Phase ───────────────────────────────────
  Widget _buildPhaseSwitcher(bool isDark, List<_PhaseKind> groups) {
    // Cuma ada 1 tipe meter -> switcher tidak perlu.
    if (groups.length <= 1) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: List.generate(groups.length, (i) {
          final selected = i == _phaseIndex;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _goToPage(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(groups[i] == _PhaseKind.one ? '1 Phase' : '3 Phase',
                    maxLines: 1,
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13,
                        color: selected ? Colors.white
                            : (isDark ? Colors.white60 : Colors.black54))),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Isi satu tipe: (pemilih meter kalau > 1) + halaman meter terpilih ───
  Widget _buildGroup(_PhaseKind kind, bool isDark) {
    final isOne = kind == _PhaseKind.one;
    final refs = isOne
        ? _singles.map((d) => _MeterRef(d.thingUid, d.label)).toList()
        : _threes.map((d) => _MeterRef(d.thingUid, d.label)).toList();
    final selected = isOne ? _selSingle : _selThree;

    Widget page;
    if (isOne) {
      final d = _singles.firstWhere((d) => d.thingUid == selected);
      page = _Energy1PhaseView(key: ValueKey(d.thingUid), device: d);
    } else {
      final d = _threes.firstWhere((d) => d.thingUid == selected);
      page = Energy3PhasePage(key: ValueKey(d.thingUid), device: d);
    }

    return Column(
      children: [
        // Pemilih meter hanya muncul kalau tipe ini punya lebih dari 1 meter.
        if (refs.length > 1)
          SizedBox(
            height: 40,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              scrollDirection: Axis.horizontal,
              itemCount: refs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final r = refs[i];
                final sel = r.uid == selected;
                return GestureDetector(
                  onTap: () => setState(() {
                    if (isOne) {
                      _selSingle = r.uid;
                    } else {
                      _selThree = r.uid;
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: sel
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : (isDark ? const Color(0xFF27272A) : Colors.white),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: sel ? AppColors.primary : Colors.transparent),
                    ),
                    child: Text(r.label,
                        maxLines: 1,
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: sel
                                ? AppColors.primary
                                : (isDark ? Colors.white60 : Colors.black54))),
                  ),
                );
              },
            ),
          ),
        Expanded(child: page),
      ],
    );
  }
}

/// Konten asli halaman Energy 1-Phase (sebelumnya bernama `EnergyPage`).
/// Semua logic/UI di bawah ini TIDAK diubah sama sekali — cuma nama class-nya
/// yang di-private-kan karena sekarang dibungkus oleh `EnergyPage` di atas.
class _Energy1PhaseView extends StatefulWidget {
  final SinglePhaseDevice device;
  const _Energy1PhaseView({super.key, required this.device});

  @override
  State<_Energy1PhaseView> createState() => _Energy1PhaseViewState();
}

class _Energy1PhaseViewState extends State<_Energy1PhaseView> {
  String _selectedPeriod = 'Today';
  PowerMeterData _data = const PowerMeterData();
  bool _serverReachable = false; // REST openHAB terjangkau
  StreamSubscription? _dataSub;
  Timer? _staleCheckTimer;

  /// Kapan data live terakhir kali diperbarui (dari MQTT push ATAU dari
  /// polling openHAB items) — dipakai untuk label "Last update" dan
  /// deteksi stale (data berhenti mengalir walau koneksi masih "connected").
  DateTime? _lastUpdate;

  static const _staleThreshold = Duration(seconds: 90);

  bool get _isStale =>
      _lastUpdate == null || DateTime.now().difference(_lastUpdate!) > _staleThreshold;

  /// Status keseluruhan data live, dalam satu sumber kebenaran — dipakai
  /// konsisten di semua tempat (appbar, badge, dll) alih-alih tiap tempat
  /// nyimpulin sendiri dari _serverReachable/_data.deviceOnline secara
  /// terpisah (itu penyebab sebelumnya statusnya kelihatan berantakan).
  _LiveStatus get _liveStatus {
    if (!_serverReachable) return _LiveStatus.offline;
    if (!_data.deviceOnline) return _LiveStatus.offline;
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

  String get _lastUpdateLabel {
    if (_lastUpdate == null) return '-';
    final t = _lastUpdate!;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// Warna indikator berdasarkan KONDISI nilai (hijau normal, kuning
  /// peringatan, merah kritis) — pakai threshold yang sama persis dengan
  /// _computeAlarms(), supaya warna di kartu dan pesan alarm selalu
  /// konsisten (satu sumber kebenaran, bukan didefinisikan dua kali).
  Color _voltageColor() {
    if (_voltage <= 0) return const Color(0xFF71717A);
    if (_voltage < _voltMin || _voltage > _voltMax) return const Color(0xFFF59E0B);
    return const Color(0xFF34C759);
  }

  Color _currentColor() {
    if (_ampere > _currentMax) return const Color(0xFFF31260);
    return const Color(0xFF34C759);
  }

  Color _frequencyColor() {
    if (_frequency <= 0) return const Color(0xFF71717A);
    if (_frequency < _freqMin || _frequency > _freqMax) return const Color(0xFFF59E0B);
    return const Color(0xFF34C759);
  }

  Color _pfColor() {
    if (_pf <= 0) return const Color(0xFF71717A);
    if (_pf < _pfMin) return const Color(0xFFF59E0B);
    return const Color(0xFF34C759);
  }

 
  double get _voltage     => _data.volt;
  double get _powerW      => _data.powerKw * 1000;
  double get _powerKw     => _powerW / 1000;
  double get _ampere      => _data.amp;
  double get _energyToday => _data.energyToday;
  double get _energyTotal => _data.energyTotal;
  double get _energyYest  => _data.energyYesterday;
  double get _frequency   => _data.freq;
  double get _pf          => _data.pf;

  // ── Alarm thresholds (sumber 1-phase, standar rumah tangga) ─────────────
  static const double _voltMin    = 200;
  static const double _voltMax    = 240;
  static const double _freqMin    = 49.5;
  static const double _freqMax    = 50.5;
  static const double _pfMin      = 0.85;
  static const double _currentMax = 16;

  List<_EnergyAlarm> _computeAlarms() {
    final alarms = <_EnergyAlarm>[];

    if (!_serverReachable) {
      alarms.add(const _EnergyAlarm(
        severity: _AlarmSeverity.critical,
        message: 'Server openHAB tidak terjangkau — data mungkin tidak real-time',
      ));
    }
    if (!_data.deviceOnline) {
      alarms.add(const _EnergyAlarm(
        severity: _AlarmSeverity.critical,
        message: 'Perangkat meter offline',
      ));
    }
    if (_serverReachable && _data.deviceOnline && _isStale) {
      alarms.add(_EnergyAlarm(
        severity: _AlarmSeverity.warning,
        message: 'Data belum diperbarui sejak $_lastUpdateLabel — kemungkinan '
            'sensor macet walau koneksi masih tersambung',
      ));
    }

    if (_serverReachable && _data.deviceOnline) {
      if (_voltage > 0 && (_voltage < _voltMin || _voltage > _voltMax)) {
        alarms.add(_EnergyAlarm(
          severity: _AlarmSeverity.warning,
          message: 'Tegangan di luar batas normal (${_voltage.toStringAsFixed(1)} V, '
              'normal ${_voltMin.toStringAsFixed(0)}-${_voltMax.toStringAsFixed(0)} V)',
        ));
      }
      if (_ampere > _currentMax) {
        alarms.add(_EnergyAlarm(
          severity: _AlarmSeverity.critical,
          message: 'Arus melebihi batas aman (${_ampere.toStringAsFixed(2)} A, '
              'maks ${_currentMax.toStringAsFixed(0)} A)',
        ));
      }
      if (_frequency > 0 && (_frequency < _freqMin || _frequency > _freqMax)) {
        alarms.add(_EnergyAlarm(
          severity: _AlarmSeverity.warning,
          message: 'Frekuensi tidak stabil (${_frequency.toStringAsFixed(2)} Hz, '
              'normal ${_freqMin.toStringAsFixed(1)}-${_freqMax.toStringAsFixed(1)} Hz)',
        ));
      }
      if (_pf > 0 && _pf < _pfMin) {
        alarms.add(_EnergyAlarm(
          severity: _AlarmSeverity.warning,
          message: 'Power factor rendah (${(_pf * 100).toStringAsFixed(0)}%, '
              'minimal ${(_pfMin * 100).toStringAsFixed(0)}%)',
        ));
      }
    }

    return alarms;
  }

  @override
  void initState() {
    super.initState();
    final svc = OpenHabPowerMeterService.instance;
    final uid = widget.device.thingUid;
    final snap = svc.singleSnapshots[uid];
    if (snap != null) {
      _data = snap.data;
      _serverReachable = true;
      _lastUpdate = snap.lastChange;
    }
    _dataSub = svc.singleStream.listen((all) {
      final s = all[uid];
      if (s == null || !mounted) return;
      setState(() {
        _data = s.data;
        _serverReachable = true;
        // Waktu NILAI terakhir berubah, bukan waktu polling.
        _lastUpdate = s.lastChange;
      });
    });
    // Re-evaluasi status stale secara berkala walau tidak ada data baru
    // masuk — tanpa ini, badge "Data tidak diperbarui" tidak akan pernah
    // muncul otomatis kalau device berhenti kirim data (tidak ada trigger
    // setState lain yang membuat _isStale dievaluasi ulang).
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    _buildAppBar(context),
                    const SizedBox(height: 20),
                    _buildAlarmBanner(context),
                    _buildTotalEnergyHeader(context),
                    const SizedBox(height: 2),
                    _buildStatsRow(context),
                    const SizedBox(height: 8),
                    _buildEnergyFlow(context),
                    const SizedBox(height: 12),
                    _buildEnergySavingCard(),
                    const SizedBox(height: 12),
                    _buildCapacityCard(context),
                    const SizedBox(height: 12),
                    _buildDataLogger(context),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
          _buildBottomNav(context),
        ],
      ),
    );
  }

  // ── Alarm Banner ───────────────────────────────────────────────────────────

  Widget _buildAlarmBanner(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final alarms = _computeAlarms();
    if (alarms.isEmpty) return const SizedBox.shrink();

    final hasCritical = alarms.any((a) => a.severity == _AlarmSeverity.critical);
    final color = hasCritical ? const Color(0xFFF31260) : const Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Text('${alarms.length} Alarm Aktif',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                  fontSize: 13, color: color)),
        ]),
        const SizedBox(height: 8),
        ...alarms.map((a) {
          final dotColor = a.severity == _AlarmSeverity.critical
              ? const Color(0xFFF31260)
              : const Color(0xFFF59E0B);
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                margin: const EdgeInsets.only(top: 5),
                width: 4, height: 4,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(a.message,
                    style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.85)
                            : const Color(0xFF3F3F46))),
              ),
            ]),
          );
        }),
      ]),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────

  Widget _buildAppBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xCC18181B);
    // Sama persis dengan header halaman 3 fasa: tombol back, NAMA METER, badge status.
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
      _buildStatusBadge(context),
    ]);
  }

  /// Badge status tunggal — pengganti 2 titik kecil sebelumnya yang nyaris
  /// tak terlihat dan gak jelas mana yang "device" mana yang "koneksi".
  /// Sekarang: satu label teks jelas (Online/Offline/Data tidak
  /// diperbarui) + jam update terakhir, sumber kebenarannya satu
  /// (_liveStatus), konsisten dengan warna yang dipakai di kartu metrik.
  Widget _buildStatusBadge(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _liveStatusColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(_liveStatusLabel,
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
                fontSize: 11, color: color)),
      ]),
    );
  }

  // ── Total Energy Header ────────────────────────────────────────────────────

  Widget _buildTotalEnergyHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xCC18181B);

    return SizedBox(
      width: double.infinity,
      child: Stack(children: [
        Positioned(
          right: 0, top: 0,
          child: Image.asset('assets/images/solar_panel.png',
              width: 160, height: 120, fit: BoxFit.contain,
              alignment: Alignment.topRight,
              errorBuilder: (_, __, ___) => Container(
                width: 160, height: 120,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF27272A) : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.solar_power, size: 48, color: Colors.grey),
              )),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Total energy produced',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500,
                  fontSize: 16, letterSpacing: -0.176, color: textColor)),
          const SizedBox(height: 8),
          Row(children: [
            RichText(
              text: TextSpan(children: [
                TextSpan(
                  text: _selectedPeriod == 'Today'
                  ? _energyToday.toStringAsFixed(2)  
                  : _energyTotal.toStringAsFixed(2), 
                  style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                      fontSize: 36, letterSpacing: -0.396, color: Color(0xFFFFA500)),
                ),
                const TextSpan(text: ' kWh',
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500,
                        fontSize: 16, letterSpacing: -0.176, color: Color(0xFFFFA500))),
              ]),
            ),
            const Spacer(),
            _buildPeriodDropdown(),
          ]),
          const SizedBox(height: 5),
        ]),
      ]),
    );
  }

  Widget _buildPeriodDropdown() {
    return GestureDetector(
      onTap: () => setState(() =>
          _selectedPeriod = _selectedPeriod == 'Today' ? 'Total' : 'Today'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x33000000),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_selectedPeriod,
                  style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500,
                      fontSize: 12, color: Colors.white)),
              const SizedBox(width: 4),
              const FaIcon(FontAwesomeIcons.chevronDown, size: 10, color: Colors.white),
            ]),
          ),
        ),
      ),
    );
  }
  Widget _buildStatsRow(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.06),
              blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(children: [
          _buildStatItem('Energy Today',
          '${_energyToday.toStringAsFixed(2)} kWh', const Color(0xFF34C759), context),
          _buildStatItem('Active Power',
          '${_powerKw.toStringAsFixed(2)} kW', const Color(0xCCFC0004), context),
          _buildStatItem('Power Factor',
          '${(_pf * 100).toStringAsFixed(1)} %', _pfColor(), context,
          caption: 'Min ${(_pfMin * 100).toStringAsFixed(0)}%'),
        ]),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color valueColor, BuildContext context,
      {String? caption}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(label, textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500,
              fontSize: 10, letterSpacing: -0.11,
              color: isDark ? Colors.white54 : const Color(0xFF71717A))),
      const SizedBox(height: 3),
      Text(value, textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
              fontSize: 16, letterSpacing: -0.176, color: valueColor)),
      if (caption != null) ...[
        const SizedBox(height: 2),
        Text(caption, textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Inter', fontSize: 9,
                color: isDark ? Colors.white38 : const Color(0xFF94A3B8))),
      ],
    ]));
  }

  Widget _buildEnergyFlow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
              blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(children: [
        _buildInfoButton(),
        LayoutBuilder(builder: (context, constraints) =>
            _buildFlowDiagram(constraints.maxWidth)),
      ]),
    );
  }

  Widget _buildInfoButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFFFA500), width: 1.5),
          shape: BoxShape.circle,
        ),
        child: const Center(child: FaIcon(FontAwesomeIcons.info,
            size: 12, color: Color(0xFFFFA500))),
      ),
    );
  }

  Widget _buildFlowDiagram(double w) {
    const nodeW = 64.0;
    const nodeH = 64.0;
    const hubW  = 56.0;
    const hubH  = 56.0;
    const totalH = 340.0;

    final plnCX     = w / 2;
    const plnCY     = nodeH / 2;
    final solarCX   = nodeW / 2;
    const solarCY   = plnCY + 142.0;
    final hubCX     = w / 2;
    const hubCY     = solarCY;
    final homeCX    = w - nodeW / 2;
    const homeCY    = solarCY;
    const batteryCY = solarCY + 100.0;
    final batteryCX = w / 2;

    return SizedBox(
      height: totalH,
      child: Stack(clipBehavior: Clip.none, children: [
        CustomPaint(
          size: Size(w, totalH),
          painter: _FlowLinePainter(
            w: w,
            plnC: Offset(plnCX, plnCY),
            solarC: Offset(solarCX, solarCY),
            hubC: Offset(hubCX, hubCY),
            homeC: Offset(homeCX, homeCY),
            batteryC: Offset(batteryCX, batteryCY),
            nodeSize: nodeW, hubSize: hubW,
          ),
        ),
        Positioned(left: plnCX - nodeW / 2, top: 0,
            child: _buildFlowNode(
              child: Image.asset('assets/icons/icon_pln_source.png', width: 38, height: 38),
              bgColor: const Color(0xFFFFCC00).withValues(alpha: 0.20),
              borderColor: const Color(0xFFFFCC00),
              label: 'PLN Source',
              value: '${_voltage.toStringAsFixed(1)} V',
              valueColor: const Color(0xFFFFCC00),
              nodeW: nodeW, nodeH: nodeH,
            )),
        Positioned(left: solarCX - nodeW / 2, top: solarCY - nodeH / 2,
            child: _buildFlowNode(
              child: Image.asset('assets/icons/icon_solar_panel.png', width: 38, height: 38),
              bgColor: const Color(0xFF0088FF).withValues(alpha: 0.20),
              borderColor: const Color(0xFF4AA6F7),
              label: 'Solar',
              value: '${_energyToday.toStringAsFixed(2)} kWh',
              valueColor: const Color(0xFF0088FF),
              nodeW: nodeW, nodeH: nodeH,
            )),
        Positioned(left: hubCX - hubW / 2, top: hubCY - hubH / 2,
            child: Container(
              width: hubW, height: hubH,
              decoration: BoxDecoration(
                color: const Color(0xFFF31260).withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFB0004).withValues(alpha: 0.80), width: 0.87),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFF31260).withValues(alpha: 0.4),
                      blurRadius: 28, spreadRadius: 8),
                ],
              ),
              child: const Center(child: FaIcon(FontAwesomeIcons.bolt,
                  size: 26, color: Color(0xFFF31260))),
            )),
        Positioned(left: homeCX - nodeW / 2, top: homeCY - nodeH / 2,
            child: _buildFlowNode(
              child: Image.asset('assets/icons/icon_home.png', width: 38, height: 38),
              bgColor: const Color(0xFFFF6600).withValues(alpha: 0.20),
              borderColor: const Color(0xFFFFA500),
              label: 'Home',
              value: '${_powerKw.toStringAsFixed(2)} kW',
              valueColor: const Color(0xFFFFA500),
              nodeW: nodeW, nodeH: nodeH,
            )),
        Positioned(left: batteryCX - nodeW / 2, top: batteryCY - nodeH / 2,
            child: _buildFlowNode(
              child: Image.asset('assets/icons/icon_battery.png', width: 38, height: 38),
              bgColor: const Color(0xFF34C759).withValues(alpha: 0.20),
              borderColor: const Color(0xFF34C759),
              label: 'Current',
              value: '${_ampere.toStringAsFixed(2)} A',
              valueColor: const Color(0xFF34C759),
              nodeW: nodeW, nodeH: nodeH,
            )),
      ]),
    );
  }

  Widget _buildFlowNode({
    required Widget child,
    required Color bgColor,
    required String label,
    required String value,
    required Color valueColor,
    Color? borderColor,
    double nodeW = 64,
    double nodeH = 64,
  }) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: nodeW, height: nodeH,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: borderColor != null
              ? Border.all(color: borderColor, width: 0.87) : null,
        ),
        child: Center(child: child),
      ),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w400,
          fontSize: 11, color: Color(0xFF71717A))),
      Text(value, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
          fontSize: 13, color: valueColor)),
    ]);
  }
  Widget _buildEnergySavingCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF353F3F),
        borderRadius: BorderRadius.circular(28),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(children: [
          Positioned(right: 10, bottom: -5,
              child: FaIcon(FontAwesomeIcons.leaf, size: 120,
                  color: Colors.white.withValues(alpha: 0.08))),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(child: Icon(Icons.auto_awesome,
                    color: Color(0xFF0D0D0D), size: 22)),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Energy Saving',
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
                        fontSize: 16, color: Color(0xFFF5F5F5))),
                const SizedBox(height: 4),
                Text(
                  'Device: ${_data.deviceOnline ? "Online ✓" : "Offline"} · '
                  'Freq: ${_frequency.toStringAsFixed(2)} Hz · '
                  'Yesterday: ${_energyYest.toStringAsFixed(2)} kWh',
                  style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w400,
                      fontSize: 12, color: Color(0xFFCDCDCD), height: 1.5),
                ),
              ])),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildCapacityCard(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  const double maxCapacity = 20.0;
  final fillRatio   = (_energyTotal / maxCapacity).clamp(0.0, 1.0);
  final usedPercent = (fillRatio * 100).toStringAsFixed(0);

  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF27272A) : Colors.white,
      borderRadius: BorderRadius.circular(28),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Energy Total',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: isDark ? Colors.white : const Color(0xCC18181B))),
        GestureDetector(
          onTap: () => OpenHabPowerMeterService.instance.refresh(),
          child: Row(children: [
            Text(
              '${_energyTotal.toStringAsFixed(2)} / ${maxCapacity.toStringAsFixed(0)} kWh',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  color: isDark ? Colors.white54 : const Color(0xFF71717A)),
            ),
            const SizedBox(width: 6),
            const FaIcon(FontAwesomeIcons.arrowsRotate,
                size: 11, color: Color(0xFF71717A)),
          ]),
        ),
      ]),
      const SizedBox(height: 8),
      RichText(
        text: TextSpan(children: [
          TextSpan(
              text: '$usedPercent%',
              style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: Color(0xFFFC0004))),
          TextSpan(
              text: ' of daily capacity used',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  color: isDark ? Colors.white54 : const Color(0xFF71717A))),
        ]),
      ),
      const SizedBox(height: 12),
      _buildSegmentedBar(fillRatio, context),
      const SizedBox(height: 20),

      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _buildCapacityStat(
            'Voltage',
            '${_voltage.toStringAsFixed(1)} V',
            _voltageColor(),
            context,
            caption: 'Normal ${_voltMin.toStringAsFixed(0)}-${_voltMax.toStringAsFixed(0)} V'),
        _buildCapacityDivider(context),
        _buildCapacityStat(
            'Power',
            '${_powerW.toStringAsFixed(1)} W',
            const Color(0xFFFF6B35),
            context),
        _buildCapacityDivider(context),
        _buildCapacityStat(
            'Current',
            '${_ampere.toStringAsFixed(2)} A',
            _currentColor(),
            context,
            caption: 'Maks ${_currentMax.toStringAsFixed(0)} A'),
      ]),

      const SizedBox(height: 16),
      Divider(color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE3E3E3)),
      const SizedBox(height: 16),

      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _buildCapacityStat(
            'Frequency',
            '${_frequency.toStringAsFixed(2)} Hz',
            _frequencyColor(),
            context,
            caption: 'Normal ${_freqMin.toStringAsFixed(1)}-${_freqMax.toStringAsFixed(1)} Hz'),
        _buildCapacityDivider(context),
        _buildCapacityStat(
            'Yesterday',
            '${_energyYest.toStringAsFixed(2)} kWh',
            const Color(0xFF6366F1),
            context),
        _buildCapacityDivider(context),
        _buildCapacityStat(
        'Status',
        _data.status,
        (_data.status) == 'ON'
            ? const Color(0xFF34C759)
            : const Color(0xFFF31260),
        context),
      ]),
    ]),
  );
}
  Widget _buildSegmentedBar(double fillRatio, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const totalSegments = 10;
    final filledSegments = (totalSegments * fillRatio).round();
    return Row(
      children: List.generate(totalSegments, (i) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 4),
          height: 28,
          decoration: BoxDecoration(
            color: i < filledSegments
                ? const Color(0xFFFFCC00)
                : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFAEAEB2)),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      )),
    );
  }

  Widget _buildCapacityStat(String label, String value, Color valueColor, BuildContext context,
      {String? caption}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      Text(label, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w400,
          fontSize: 12, color: isDark ? Colors.white54 : const Color(0xFF71717A))),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
          fontSize: 16, color: valueColor)),
      if (caption != null) ...[
        const SizedBox(height: 2),
        Text(caption, style: TextStyle(fontFamily: 'Inter', fontSize: 9,
            color: isDark ? Colors.white38 : const Color(0xFF94A3B8))),
      ],
    ]);
  }

  Widget _buildCapacityDivider(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(width: 1, height: 32,
        color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE3E3E3));
  }

  // ── Data Logger (riwayat dari openHAB Persistence) ──────────────────────
  static const _loggerSeries = <LoggerSeries>[
    LoggerSeries(id: 'power', label: 'Daya Aktif', unit: 'kW', scale: 0.001,
        icon: Icons.bolt_rounded, color: Color(0xFFFFA500)),
    LoggerSeries(id: 'energyTotal', label: 'Energi', unit: 'kWh',
        kind: LoggerKind.cumulative, icon: Icons.speed_rounded, color: Color(0xFF34C759)),
    LoggerSeries(id: 'voltage', label: 'Tegangan', unit: 'V', decimals: 1,
        icon: Icons.electrical_services_rounded, color: Color(0xFFEF4444)),
    LoggerSeries(id: 'current', label: 'Arus', unit: 'A',
        icon: Icons.waves_rounded, color: Color(0xFF3B82F6)),
    LoggerSeries(id: 'pf', label: 'Faktor Daya', unit: '%', scale: 100,
        decimals: 1, icon: Icons.percent_rounded, color: Color(0xFF0088FF)),
    LoggerSeries(id: 'frequency', label: 'Frekuensi', unit: 'Hz',
        icon: Icons.graphic_eq_rounded, color: Color(0xFF34C759)),
    LoggerSeries(id: 'status', label: 'Status Meter', kind: LoggerKind.binary,
        icon: Icons.power_settings_new_rounded, activeLabel: 'ON', inactiveLabel: 'OFF'),
  ];

  // id series = kunci logis (power, voltage, ...) -> Item milik meter INI.
  late final LoggerFetcher _loggerFetcher = openHabLoggerFetcher(
    baseUrl: () => OpenHabEndpoint.instance.baseUrl,
    headers: () => OpenHabEndpoint.instance.headers,
    itemNameOf: (s) => widget.device.keyToItem[s.id],
  );

  Widget _buildDataLogger(BuildContext context) {
    return DataLoggerCard(
      title: 'Data Logger',
      series: _loggerSeries,
      fetcher: _loggerFetcher,
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = [
      _NavItem(icon: FontAwesomeIcons.house,          label: 'Home'),
      _NavItem(icon: FontAwesomeIcons.bolt,           label: 'Energy'),
      _NavItem(icon: FontAwesomeIcons.mapLocationDot, label: 'Floorplan'),
      _NavItem(icon: FontAwesomeIcons.gear,           label: 'Settings'),
    ];
    const selectedIndex = 1;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16, offset: const Offset(0, -4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (i) {
          final isSelected = selectedIndex == i;
          return GestureDetector(
            onTap: () {
              if (isSelected) return;
              // Kembali ke root (Home) dulu, baru push tujuan — supaya
              // hasil navigasi konsisten berapapun dalamnya stack saat ini.
              Navigator.popUntil(context, (route) => route.isFirst);
              if (i == 2) {
                Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const FloorPlanPage()));
              }
              if (i == 3) {
                Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()));
              }
            },
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FaIcon(items[i].icon, size: 20,
                  color: isSelected ? AppColors.primary
                      : (isDark ? Colors.white38 : Colors.black38)),
              const SizedBox(height: 4),
              Text(items[i].label,
                  style: TextStyle(fontFamily: 'Inter', fontSize: 11,
                      color: isSelected ? AppColors.primary
                          : (isDark ? Colors.white38 : Colors.black38),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
            ]),
          );
        }),
      ),
    );
  }
}

class _FlowLinePainter extends CustomPainter {
  final double w;
  final Offset plnC, solarC, hubC, homeC, batteryC;
  final double nodeSize, hubSize;

  const _FlowLinePainter({
    required this.w, required this.plnC, required this.solarC,
    required this.hubC, required this.homeC, required this.batteryC,
    required this.nodeSize, required this.hubSize,
  });

  static const _labelH = 28.0;
  static const _s = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.grey.shade400;

    final plnBottom  = plnC.dy + nodeSize / 2 + _labelH;
    final hubTop     = hubC.dy - hubSize / 2;
    canvas.drawLine(Offset(plnC.dx, plnBottom + 2), Offset(hubC.dx, hubTop - 2), line);
    _drawArrow(canvas, Offset(hubC.dx, hubTop - 2), ArrowDir.down);
    _drawDot(canvas, Offset(plnC.dx, plnBottom + (hubTop - plnBottom) * 0.45),
        const Color(0xFFFFCC00));

    final solarRight = solarC.dx + nodeSize / 2;
    final hubLeft    = hubC.dx - hubSize / 2;
    canvas.drawLine(Offset(solarRight + 2, solarC.dy), Offset(hubLeft - 2, hubC.dy), line);
    _drawArrow(canvas, Offset(hubLeft - 2, hubC.dy), ArrowDir.right);
    _drawDot(canvas, Offset(solarRight + (hubLeft - solarRight) * 0.35, solarC.dy),
        const Color(0xFF0088FF));

    final solarBottom = solarC.dy + nodeSize / 2 + _labelH;
    final batteryLeft = size.width / 2 - nodeSize / 2;
    final cornerY = batteryC.dy;
    final lPath = Path()
      ..moveTo(solarC.dx, solarBottom + 2)
      ..lineTo(solarC.dx, cornerY)
      ..lineTo(batteryLeft - 2, cornerY);
    canvas.drawPath(lPath, line);
    _drawArrow(canvas, Offset(batteryLeft - 2, cornerY), ArrowDir.right);
    _drawDot(canvas, Offset(solarC.dx, solarBottom + (cornerY - solarBottom) * 0.45),
        const Color(0xFF0088FF));

    final hubRight   = hubC.dx + hubSize / 2;
    final homeLeft   = homeC.dx - nodeSize / 2;
    canvas.drawLine(Offset(hubRight + 2, hubC.dy), Offset(homeLeft - 2, homeC.dy), line);
    _drawArrow(canvas, Offset(hubRight + 2, hubC.dy), ArrowDir.left);
    _drawArrow(canvas, Offset(homeLeft - 2, homeC.dy), ArrowDir.right);
    _drawDot(canvas, Offset(hubRight + (homeLeft - hubRight) * 0.50, hubC.dy),
        const Color(0xFFF31260));

    final hubBottom      = hubC.dy + hubSize / 2;
    final batteryTopEdge = batteryC.dy - nodeSize / 2;
    canvas.drawLine(Offset(hubC.dx, hubBottom + 2), Offset(hubC.dx, batteryTopEdge - 2), line);
    _drawArrow(canvas, Offset(hubC.dx, hubBottom + 2), ArrowDir.up);
    _drawDot(canvas, Offset(hubC.dx, hubBottom + (batteryTopEdge - hubBottom) * 0.45),
        const Color(0xFF34C759));
  }

  void _drawDot(Canvas canvas, Offset center, Color color) {
    canvas.drawCircle(center, 5, Paint()..color = color);
  }

  void _drawArrow(Canvas canvas, Offset tip, ArrowDir dir) {
    final paint = Paint()..color = Colors.grey.shade400..style = PaintingStyle.fill;
    final path  = Path();
    switch (dir) {
      case ArrowDir.down:
        path.moveTo(tip.dx, tip.dy);
        path.lineTo(tip.dx - _s, tip.dy - _s * 1.5);
        path.lineTo(tip.dx + _s, tip.dy - _s * 1.5);
        break;
      case ArrowDir.up:
        path.moveTo(tip.dx, tip.dy);
        path.lineTo(tip.dx - _s, tip.dy + _s * 1.5);
        path.lineTo(tip.dx + _s, tip.dy + _s * 1.5);
        break;
      case ArrowDir.right:
        path.moveTo(tip.dx, tip.dy);
        path.lineTo(tip.dx - _s * 1.5, tip.dy - _s);
        path.lineTo(tip.dx - _s * 1.5, tip.dy + _s);
        break;
      case ArrowDir.left:
        path.moveTo(tip.dx, tip.dy);
        path.lineTo(tip.dx + _s * 1.5, tip.dy - _s);
        path.lineTo(tip.dx + _s * 1.5, tip.dy + _s);
        break;
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_FlowLinePainter old) =>
      old.plnC != plnC || old.solarC != solarC ||
      old.hubC != hubC || old.homeC != homeC || old.batteryC != batteryC;
}

enum ArrowDir { down, up, right, left }

enum _LiveStatus { online, stale, offline }

enum _AlarmSeverity { warning, critical }

class _EnergyAlarm {
  final _AlarmSeverity severity;
  final String message;
  const _EnergyAlarm({required this.severity, required this.message});
}

class _NavItem {
  final FaIconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}