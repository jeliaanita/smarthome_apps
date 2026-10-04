import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/providers/installation_provider.dart';
import 'package:mobile/pages/settings_page.dart';
import 'package:mobile/pages/energy_page.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/controllers/openhab_controller.dart';
import '../../../../core/models/openhab_item.dart';
import 'package:mobile/core/services/openhab_management_service.dart' show OHThing;
import 'package:mobile/core/models/power_meter_data.dart';
import 'package:mobile/core/widget/camera_widgets.dart';
import 'package:mobile/core/services/openhab_power_meter_service.dart';
import 'package:mobile/core/utils/responsive_utils.dart';
import 'package:mobile/core/providers/role_provider.dart'; // [MAPPING]
import 'package:mobile/pages/map_thing_to_room_page.dart'; // [MAPPING]
import 'package:mobile/core/widget/ac_unit_widgets.dart';

class _NavItem {
  final FaIconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

class FloorPlanPage extends StatefulWidget {
  const FloorPlanPage({super.key});

  @override
  State<FloorPlanPage> createState() => _FloorPlanPageState();
}

class _FloorPlanPageState extends State<FloorPlanPage>
    with WidgetsBindingObserver {
  final _ctrl = OpenHABController.instance;
  int _selectedModeIndex = 0;
  String _selectedCameraGroup = 'Semua';
  List<Map<String, dynamic>> _scenes = [];
  bool _scenesLoading = false;
  static const bool _showFloorPlanImage = false;
  String? _runningSceneUid;
  int _selectedLocationIdx = 0;

  StreamSubscription? _dataSub;
  Timer? _statusRefreshTimer;
  Map<String, double> _ohItems = {};

  // ── Data power meter dari OpenHabPowerMeterService (sumber yang sama
  // dengan energy_page.dart). Dijumlahkan dari semua meter 1-fasa. ──
  final _meterSvc = OpenHabPowerMeterService.instance;

  Iterable<PowerMeterData> get _meters =>
      _meterSvc.singleSnapshots.values.map((s) => s.data);

  double get _powerKw => _meters.fold(0.0, (sum, m) => sum + m.powerKw);

  void _startMeterService() {
    final config = context.read<InstallationProvider>().config;
    OpenHabEndpoint.instance.configure(
      baseUrl: config?.openhabUrl ?? '',
      apiToken: config?.apiToken,
      username: config?.username,
      password: config?.password,
    );
    _meterSvc.start();
    _dataSub = _meterSvc.singleStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  double get _energyToday =>
      _ohItems['pow_test_mqtt_Energy_Today'] ??
      _meters.fold(0.0, (sum, m) => sum + m.energyToday);

  List<double> _weeklyData = [];
  List<String> _weeklyLabels = [];
  bool _weeklyLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ctrl.addListener(_onCtrlUpdate);
    // _ctrl.initialize() DIHAPUS — controller sudah diinisialisasi
    // dari login_page.dart sesuai akun yang login.
    _loadScenes();
    _loadOpenHABItems();
    _loadWeeklyConsumption();

    _startMeterService();

    // Refresh berkala status perangkat, supaya tetap real-time terutama
    // untuk penggunaan di iPad/wall panel yang menyala terus tanpa
    // interaksi manual (tidak mengandalkan tap tombol Refresh saja).
    _statusRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _ctrl.isConnected) _ctrl.loadItems();
    });
  }

  bool _dataLoaded = false;

  void _onCtrlUpdate() {
    if (mounted) setState(() {});
    if (_ctrl.isConnected && !_dataLoaded) {
      _dataLoaded = true;
      _loadOpenHABItems();
      _loadWeeklyConsumption();
    }
  }

  Map<String, String> _buildAuthHeaders() {
    final config = context.read<InstallationProvider>().config;
    final headers = <String, String>{'Accept': 'application/json'};
    if (config?.apiToken != null && config!.apiToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.apiToken}';
    } else if (config?.username != null && config?.password != null) {
      final enc = base64Encode(
          utf8.encode('${config!.username}:${config.password}'));
      headers['Authorization'] = 'Basic $enc';
    }
    return headers;
  }

  Future<void> _loadOpenHABItems() async {
    try {
      if (!_ctrl.isConnected) return;

      final headers = _buildAuthHeaders();
      final uri =
          Uri.parse('${_ctrl.serverUrl}/rest/items?fields=name,state,type');
      final res =
          await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 && mounted) {
        final list = jsonDecode(res.body) as List;
        final numMap = <String, double>{};
        for (final item in list) {
          final name = item['name'] as String? ?? '';
          final state = item['state'] as String? ?? '';
          final value = double.tryParse(state);
          if (value != null) numMap[name] = value;
        }
        setState(() => _ohItems = numMap);
      }
    } catch (e) {
      debugPrint('loadOpenHABItems error: $e');
    }
  }

  // Ambil histori 7 hari terakhir dari openHAB Persistence API.
  // Item 'pow_test_mqtt_Energy_Today' reset tiap tengah malam dan naik
  // sepanjang hari, jadi nilai TERTINGGI per hari = total konsumsi hari itu.
  Future<void> _loadWeeklyConsumption() async {
    setState(() => _weeklyLoading = true);
    try {
      if (!_ctrl.isConnected) return;

      final now = DateTime.now();
      final start =
          DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));

      final headers = _buildAuthHeaders();
      final uri = Uri.parse(
        '${_ctrl.serverUrl}/rest/persistence/items/pow_test_mqtt_Energy_Today'
        '?starttime=${start.toUtc().toIso8601String()}'
        '&endtime=${now.toUtc().toIso8601String()}',
      );

      final res =
          await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));

      debugPrint('🔋 Weekly consumption status: ${res.statusCode}');
      if (res.statusCode != 200) {
        debugPrint('🔋 Weekly consumption body: ${res.body}');
      }

      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final points = (body['data'] as List? ?? []).cast<Map<String, dynamic>>();

        // Kelompokkan per tanggal kalender, ambil nilai maksimum tiap hari.
        final maxPerDay = <String, double>{};
        for (final p in points) {
          final t = DateTime.fromMillisecondsSinceEpoch((p['time'] as num).toInt());
          final key = '${t.year}-${t.month}-${t.day}';
          final v = double.tryParse(p['state'].toString()) ?? 0;
          if (!maxPerDay.containsKey(key) || v > maxPerDay[key]!) {
            maxPerDay[key] = v;
          }
        }

        const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        final values = <double>[];
        final labels = <String>[];
        for (int i = 6; i >= 0; i--) {
          final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
          final key = '${day.year}-${day.month}-${day.day}';
          values.add(maxPerDay[key] ?? 0);
          labels.add(dayNames[day.weekday % 7]); // weekday: Mon=1..Sun=7
        }

        setState(() {
          _weeklyData = values;
          _weeklyLabels = labels;
        });
      }
    } catch (e) {
      debugPrint('loadWeeklyConsumption error: $e');
    } finally {
      if (mounted) setState(() => _weeklyLoading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAll();
  }

  Future<void> _refreshAll() async {
    if (!mounted) return;
    await _ctrl.loadItems();
    await _loadOpenHABItems();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.removeListener(_onCtrlUpdate);
    _dataSub?.cancel();
    _statusRefreshTimer?.cancel();
    super.dispose();
  }

  String get _locationTitle {
    if (!_ctrl.hasLocations) return 'My Home';
    if (_selectedLocationIdx < _ctrl.locations.length) {
      final loc = _ctrl.locations[_selectedLocationIdx];
      final label = loc['label'] as String?;
      final name = loc['name'] as String?;
      if (label != null && label.isNotEmpty) return label;
      if (name != null && name.isNotEmpty) {
        return name.replaceAllMapped(
            RegExp(r'(?<=[a-z])([A-Z])'), (m) => ' ${m[0]}');
      }
    }
    return 'My Home';
  }

  String get _locationRawName {
    if (!_ctrl.hasLocations) return '';
    if (_selectedLocationIdx < _ctrl.locations.length) {
      return _ctrl.locations[_selectedLocationIdx]['name'] as String? ?? '';
    }
    return '';
  }

  String get _locationChipLabel {
    if (!_ctrl.hasLocations) return 'Home';
    if (_selectedLocationIdx < _ctrl.locations.length) {
      final loc = _ctrl.locations[_selectedLocationIdx];
      final name = loc['name'] as String?;
      return name ?? 'Home';
    }
    return 'Home';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      body: Column(children: [
        Expanded(
          child: SafeArea(
            bottom: false,
            child: RefreshIndicator(
            onRefresh: _refreshAll,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveUtils.horizontalPadding(context)),
              child: ResponsiveUtils.constrainWidth(context, Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  _buildAppBar(context),
                  const SizedBox(height: 16),
                  _buildFloorPlanCard(context),
                  const SizedBox(height: 12),
                  _buildStatsRow(context),
                  const SizedBox(height: 12),
                  _buildModeSelector(context),
                  const SizedBox(height: 16),
                  _buildDevicesHeader(context),
                  const SizedBox(height: 8),
                  _buildDevicesGrid(context),
                  if (_camerasForLocation.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildCameraSection(context),
                  ],
                  const SizedBox(height: 16),
                  _buildAnalyticsHeader(context),
                  const SizedBox(height: 8),
                  _buildAnalyticsCard(context),
                  const SizedBox(height: 16),
                ],
              )),
            ),
            ),
          ),
        ),
        _buildBottomNav(context),
      ]),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xCC18181B);

    return Row(children: [
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: SizedBox(
            width: 24,
            height: 24,
            child: Center(
                child: FaIcon(FontAwesomeIcons.arrowLeft,
                    size: 18, color: textColor))),
      ),
      Expanded(
          child: Text('Floorplan',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                  height: 1.34,
                  color: textColor))),
      GestureDetector(
        onTap: _refreshAll,
        child: Stack(children: [
          SizedBox(
              width: 24,
              height: 24,
              child: Center(
                  child: FaIcon(FontAwesomeIcons.arrowsRotate,
                      size: 16, color: textColor))),
          Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _ctrl.isConnected
                      ? const Color(0xFF34C759)
                      : const Color(0xFFF31260),
                  border: Border.all(
                    color: isDark ? const Color(0xFF18181B) : Colors.white,
                    width: 1,
                  ),
                ),
              )),
        ]),
      ),
    ]);
  }

  Widget _buildFloorPlanCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(_locationTitle,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: cs.onSurface)),
              ),
              const SizedBox(width: 8),
              _buildFloorChip(),
            ],
          ),
        ),
        if (_showFloorPlanImage)
        SizedBox(
          width: double.infinity,
          height: 220,
          child: InteractiveViewer(
            minScale: 1.0,
            maxScale: 4.0,
            child: Image.asset('assets/images/floor_plan.png',
              width: double.infinity,
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                    width: double.infinity,
                    height: 220,
                    color: isDark
                        ? const Color(0xFF3F3F46)
                        : const Color(0xFFF0EDE8),
                    child: const Center(
                        child: Icon(Icons.map_outlined,
                            size: 64, color: Colors.grey)),
                  )),
          ),
        )
        else
          SizedBox(
            width: double.infinity,
            height: 100,
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Container(
              width: double.infinity,
              height: 100,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF0EDE8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FaIcon(FontAwesomeIcons.mapLocationDot,
                      size: 18,
                      color: isDark ? Colors.white38 : const Color(0xFF71717A)),
                  const SizedBox(width: 8),
                  // Text('Floor plan segera hadir',
                  //     style: TextStyle(
                  //         fontFamily: 'Inter',
                  //         fontWeight: FontWeight.w500,
                  //         fontSize: 13,
                  //         color: isDark ? Colors.white38 : const Color(0xFF71717A))),
                ],
              ),
            ),
          ),
        ),
        ]),
      );
    }

  Widget _buildFloorChip() {
    final hasMultiple = _ctrl.locations.length > 1;
    return GestureDetector(
      onTap: hasMultiple ? _showLocationPicker : null,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFFFA500),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(_locationChipLabel,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: Colors.white)),
          ),
          if (hasMultiple) ...[
            const SizedBox(width: 4),
            const FaIcon(FontAwesomeIcons.chevronDown,
                size: 10, color: Colors.white),
          ],
        ]),
      ),
    );
  }

  void _showLocationPicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF27272A) : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color:
                        isDark ? Colors.white24 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
                const SizedBox(height: 20),
                Text('Pilih Lokasi',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: isDark
                            ? Colors.white
                            : const Color(0xCC18181B))),
                const SizedBox(height: 16),
                Flexible(
                    child: ListView.builder(
                  controller: scrollController,
                  shrinkWrap: true,
                  itemCount: _ctrl.locations.length,
                  itemBuilder: (_, i) {
                    final loc = _ctrl.locations[i];
                    final label = loc['label'] as String?;
                    final name = loc['name'] as String?;
                    final displayName =
                        (label != null && label.isNotEmpty)
                            ? label
                            : (name ?? 'Unknown');
                    final isSelected = i == _selectedLocationIdx;

                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedLocationIdx = i);
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFFFA500).withValues(alpha: 0.1)
                              : (isDark
                                  ? const Color(0xFF3F3F46)
                                  : const Color(0xFFF5F5F7)),
                          borderRadius: BorderRadius.circular(14),
                          border: isSelected
                              ? Border.all(
                                  color: const Color(0xFFFFA500),
                                  width: 1.5)
                              : null,
                        ),
                        child: Row(children: [
                          FaIcon(FontAwesomeIcons.locationDot,
                              size: 14,
                              color: isSelected
                                  ? const Color(0xFFFFA500)
                                  : const Color(0xFF71717A)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(displayName,
                                  style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      fontSize: 15,
                                      color: isSelected
                                          ? const Color(0xFFFFA500)
                                          : (isDark
                                              ? Colors.white
                                              : const Color(
                                                  0xCC18181B))))),
                          if (isSelected)
                            const FaIcon(FontAwesomeIcons.check,
                                size: 12,
                                color: Color(0xFFFFA500)),
                        ]),
                      ),
                    );
                  },
                )),
              ]),
        ),
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locItems = _getLocItems();
    final total = locItems.length;
    final active = locItems.where((i) {
      if (i.isSwitch) return i.isOn;
      if (i.isDimmer) return (i.numericValue ?? 0) > 0;
      if (i.type == 'Player') return i.state?.toUpperCase() == 'PLAY';
      if (i.isContact) return i.state?.toUpperCase() == 'OPEN';
      if (i.isRollershutter) return (i.numericValue ?? 100) < 100;
      if (i.isColor) return (i.hsbColor?.value ?? 0) > 0;
      return false;
    }).length;

    final tempItem = locItems
        .where((i) =>
            i.isNumber &&
            (i.name.toLowerCase().contains('temp') ||
                i.label.toLowerCase().contains('temp')))
        .firstOrNull;
    final tempStr = tempItem?.numericValue != null
        ? '${tempItem!.numericValue!.toStringAsFixed(1)}°C'
        : '–';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(children: [
          _buildStatItem(
              'Active Devices',
              _ctrl.hasItems ? '$active/$total' : '–',
              isDark ? Colors.white : const Color(0xCC18181B),
              context),
          _buildStatDivider(context),
          _buildStatItem('Consumption',
              '${_powerKw.toStringAsFixed(2)} kW',
              const Color(0xFFF31260), context),
          _buildStatDivider(context),
          _buildStatItem(
              'Temperature', tempStr, const Color(0xFF0088FF), context),
        ]),
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, Color valueColor, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
        child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                fontSize: 10,
                letterSpacing: -0.11,
                color: isDark
                    ? Colors.white54
                    : const Color(0xFF71717A))),
        const SizedBox(height: 3),
        Text(value,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: -0.176,
                color: valueColor)),
      ],
    ));
  }

  Widget _buildStatDivider(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
        width: 1,
        color:
            isDark ? const Color(0xFF3F3F46) : const Color(0xFFE3E3E3));
  }

  Widget _buildModeSelector(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_scenesLoading) {
      return Container(
        height: 44,
        alignment: Alignment.centerLeft,
        child: Row(children: [
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFFFFA500))),
          const SizedBox(width: 10),
          Text('Memuat scenes...',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  color: isDark
                      ? Colors.white54
                      : const Color(0xFF71717A))),
        ]),
      );
    }

    if (_scenes.isEmpty) {
      return GestureDetector(
        onTap: _loadScenes,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF3F3F46)
                : const Color(0xFFE3E3E3),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const FaIcon(FontAwesomeIcons.wandMagicSparkles,
                size: 13, color: Color(0xFF71717A)),
            const SizedBox(width: 8),
            Text('Belum ada Scene di openHAB',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: isDark
                        ? Colors.white54
                        : const Color(0xFF71717A))),
            const SizedBox(width: 8),
            const FaIcon(FontAwesomeIcons.arrowsRotate,
                size: 11, color: Color(0xFF71717A)),
          ]),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _scenes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final scene = _scenes[i];
          final uid = scene['uid'] as String? ?? '';
          final name = scene['name'] as String? ?? 'Scene';
          final tags = List<String>.from(scene['tags'] ?? []);
          final isSelected = _selectedModeIndex == i;
          final isRunning = _runningSceneUid == uid;

          return GestureDetector(
            onTap: isRunning
                ? null
                : () {
                    setState(() => _selectedModeIndex = i);
                    _runScene(uid);
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFFFA500)
                    : (isDark
                        ? const Color(0xFF27272A)
                        : Colors.white),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black
                          .withValues(alpha: isDark ? 0.2 : 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
                border: isSelected
                    ? null
                    : Border.all(
                        color: isDark
                            ? const Color(0xFF3F3F46)
                            : const Color(0xFFE3E3E3),
                        width: 1,
                      ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                isRunning
                    ? SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFFFFA500)))
                    : FaIcon(_sceneIcon(tags, name),
                        size: 13,
                        color: isSelected
                            ? Colors.white
                            : (isDark
                                ? Colors.white54
                                : const Color(0xFF71717A))),
                const SizedBox(width: 7),
                Text(name,
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: isSelected
                            ? Colors.white
                            : (isDark
                                ? Colors.white
                                : const Color(0xCC18181B)))),
              ]),
            ),
          );
        },
      ),
    );
  }

  FaIconData _sceneIcon(List<String> tags, String name) {
    final combined = '${tags.join(' ')} $name'.toLowerCase();
    if (combined.contains('away') || combined.contains('pergi')) {
      return FontAwesomeIcons.personWalking;
    }
    if (combined.contains('night') ||
        combined.contains('malam') ||
        combined.contains('sleep')) {
      return FontAwesomeIcons.moon;
    }
    if (combined.contains('morning') ||
        combined.contains('day') ||
        combined.contains('pagi')) {
      return FontAwesomeIcons.sun;
    }
    if (combined.contains('lock') ||
        combined.contains('kunci') ||
        combined.contains('secure')) {
      return FontAwesomeIcons.lock;
    }
    if (combined.contains('relax') ||
        combined.contains('santai') ||
        combined.contains('movie')) {
      return FontAwesomeIcons.mugHot;
    }
    if (combined.contains('party') || combined.contains('pesta')) {
      return FontAwesomeIcons.music;
    }
    if (combined.contains('work') || combined.contains('kerja')) {
      return FontAwesomeIcons.briefcase;
    }
    if (combined.contains('guest') || combined.contains('tamu')) {
      return FontAwesomeIcons.userGroup;
    }
    if (combined.contains('eco') || combined.contains('hemat')) {
      return FontAwesomeIcons.leaf;
    }
    if (combined.contains('alarm') || combined.contains('emergency')) {
      return FontAwesomeIcons.bell;
    }
    return FontAwesomeIcons.wandMagicSparkles;
  }

  Widget _buildDevicesHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final groups = _groupByEquipment(_displayItems);
    final acUnits = _locAcUnits;
    final totalDevices = groups.length + acUnits.length;
    final activeCount = groups.values
            .where((its) => its.any(_floorItemIsActive))
            .length +
        acUnits.where((u) => _ctrl.getItem(u.powerItem)?.isOn ?? false).length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Devices',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: cs.onSurface)),
          Text('$activeCount dari $totalDevices perangkat aktif',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  color: isDark
                      ? Colors.white54
                      : const Color(0xFF71717A))),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          // [MAPPING] Tambah device ke ruangan ini (admin saja)
          if (context.watch<RoleProvider>().isAdmin) ...[
            _buildAddDeviceButton(),
            const SizedBox(width: 8),
          ],
          GestureDetector(
            onTap: () => _ctrl.loadItems(),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFA500).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: const [
                FaIcon(FontAwesomeIcons.arrowsRotate,
                    size: 11, color: Color(0xFFFFA500)),
                SizedBox(width: 6),
                Text('Refresh',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFFA500))),
              ]),
            ),
          ),
        ]),
      ],
    );
  }

  // [MAPPING] Pilih Thing -> wizard, ruangan aktif sudah terpilih.
  Future<void> _addDeviceToCurrentRoom() async {
    final saved = await openThingMapper(
      context,
      locationName: _locationRawName.isNotEmpty ? _locationRawName : null,
    );
    if (saved == true && mounted) await _ctrl.loadItems();
  }

  Widget _buildAddDeviceButton() {
    return GestureDetector(
      onTap: _addDeviceToCurrentRoom,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFA500),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: const [
          Icon(Icons.add, size: 14, color: Colors.white),
          SizedBox(width: 4),
          Text('Tambah',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ]),
      ),
    );
  }

  /// Kamera muncul otomatis dari Things binding IP Camera — dikelompokkan
  /// pakai field "location" Thing (bukan groupNames Item). Selector-nya
  /// pakai pola pill oranye + bottom sheet yang sama kayak _buildFloorChip
  /// biar konsisten sama filter lokasi lain di halaman ini.
  Widget _buildCameraSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cameras = _camerasForLocation;
    if (cameras.isEmpty) return const SizedBox.shrink();

    final groups = <String>{
      for (final t in cameras) _cameraGroupLabel(t),
    }.toList()
      ..sort();

    if (!groups.contains(_selectedCameraGroup) &&
        _selectedCameraGroup != 'Semua') {
      _selectedCameraGroup = 'Semua';
    }

    final visibleCameras = (_locationRawName.isNotEmpty || _selectedCameraGroup == 'Semua')
        ? cameras
        : cameras.where((t) => _cameraGroupLabel(t) == _selectedCameraGroup).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Kamera',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isDark ? Colors.white : const Color(0xFF18181B))),
            if (_locationRawName.isEmpty && groups.length > 1)
              _buildCameraGroupChip(groups),
          ],
        ),
        const SizedBox(height: 8),
        ...visibleCameras.map((thing) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CameraThingCard(thing: thing, ctrl: _ctrl),
            )),
      ],
    );
  }

  /// Label grup Thing kamera lewat Semantic Model (lihat
  /// OpenHABController.locationForThing) — fallback 'Lainnya' kalau
  /// Item di balik channel-nya belum masuk Group Location manapun.
  String _cameraGroupLabel(OHThing thing) =>
      _ctrl.locationForThing(thing) ?? 'Lainnya';

  Widget _buildCameraGroupChip(List<String> groups) {
    return GestureDetector(
      onTap: () => _showCameraGroupPicker(groups),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFFFA500),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(_selectedCameraGroup,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: Colors.white)),
          ),
          const SizedBox(width: 4),
          const FaIcon(FontAwesomeIcons.chevronDown,
              size: 10, color: Colors.white),
        ]),
      ),
    );
  }

  void _showCameraGroupPicker(List<String> groups) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final options = ['Semua', ...groups];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF27272A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
                const SizedBox(height: 20),
                Text('Pilih Grup Kamera',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: isDark ? Colors.white : const Color(0xCC18181B))),
                const SizedBox(height: 16),
                Flexible(
                    child: ListView.builder(
                  controller: scrollController,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (_, i) {
                    final displayName = options[i];
                    final isSelected = displayName == _selectedCameraGroup;

                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedCameraGroup = displayName);
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFFFA500).withValues(alpha: 0.1)
                              : (isDark
                                  ? const Color(0xFF3F3F46)
                                  : const Color(0xFFF5F5F7)),
                          borderRadius: BorderRadius.circular(14),
                          border: isSelected
                              ? Border.all(color: const Color(0xFFFFA500), width: 1.5)
                              : null,
                        ),
                        child: Row(children: [
                          FaIcon(FontAwesomeIcons.video,
                              size: 14,
                              color: isSelected
                                  ? const Color(0xFFFFA500)
                                  : const Color(0xFF71717A)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(displayName,
                                  style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      fontSize: 15,
                                      color: isSelected
                                          ? const Color(0xFFFFA500)
                                          : (isDark
                                              ? Colors.white
                                              : const Color(0xCC18181B))))),
                          if (isSelected)
                            const FaIcon(FontAwesomeIcons.check,
                                size: 12, color: Color(0xFFFFA500)),
                        ]),
                      ),
                    );
                  },
                )),
              ]),
        ),
      ),
    );
  }

  List<OpenHABItem> _getLocItems() {
    if (!_ctrl.hasItems) return [];
    return _locationRawName.isNotEmpty
        ? _ctrl.getItemsForLocation(_locationRawName)
        : _ctrl.items;
  }

  // ── Tampilan device ringkas (sama dengan Home) ─────────────────────
  bool _isSupportedItem(OpenHABItem i) =>
      i.isSwitch || i.isDimmer || i.type == 'Player' || i.isColor ||
      i.isContact || i.isRollershutter || i.isImage || i.isString;

  /// Item yang sudah tampil di kartu/detail AC — disembunyikan dari grid.
  Set<String> get _acItemNames {
    final names = <String>{};
    for (final u in _ctrl.acUnits) {
      for (final n in [
        u.powerItem, u.modeItem, u.fanItem, u.setTempItem,
        u.roomTempItem, u.roomHumidityItem, u.statusItem,
        u.stateModeItem, u.stateFanItem,
      ]) {
        if (n != null) names.add(n);
      }
    }
    return names;
  }

  /// Hanya Item yang benar-benar anggota ruangan terpilih (termasuk
  /// sub-lokasinya), tanpa Item AC & tipe yang tidak didukung.
  List<OpenHABItem> get _displayItems {
    final acNames = _acItemNames;
    return _getLocItems()
        .where((i) => _isSupportedItem(i) && !acNames.contains(i.name))
        .toList();
  }

  List<OHAcUnit> get _locAcUnits {
    final units = _ctrl.acUnits;
    if (_locationRawName.isEmpty) return units;
    final names = _getLocItems().map((i) => i.name).toSet();
    return units.where((u) => names.contains(u.powerItem)).toList();
  }

  Map<String, List<OpenHABItem>> _groupByEquipment(List<OpenHABItem> items) {
    final map = <String, List<OpenHABItem>>{};
    for (final i in items) {
      final key = i.roomGuess.isNotEmpty ? i.roomGuess : 'Lainnya';
      map.putIfAbsent(key, () => []).add(i);
    }
    return map;
  }

  static const _iconPriority = [
    'ac', 'tv', 'lightbulb', 'speaker', 'fan', 'camera', 'door', 'temperature',
  ];

  FaIconData _groupIcon(List<OpenHABItem> items) {
    for (final k in _iconPriority) {
      if (items.any((i) => i.iconKey == k)) return _floorIconForKey(k);
    }
    return _floorIconForKey(items.first.iconKey);
  }

  /// Detail satu perangkat: HANYA fungsi milik ruangan ini.
  void _showEquipmentDetail(BuildContext context, String key) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => ListenableBuilder(
          listenable: _ctrl,
          builder: (ctx, __) {
            final items = _displayItems.where((i) =>
                (i.roomGuess.isNotEmpty ? i.roomGuess : 'Lainnya') == key).toList();
            final active = items.where(_floorItemIsActive).length;
            return DetailSheetShell(
              scrollController: scrollController,
              title: key,
              subtitle: '${items.length} fungsi · $active aktif',
              children: [
                ...buildEquipmentSections(
                  ctx,
                  items,
                  (item) => CompactItemRow(
                    item: item,
                    icon: _floorIconForKey(item.iconKey),
                    active: _floorItemIsActive(item),
                    stateLabel: _floorStateLabel(item),
                    onTap: () => _openFloorItemControl(ctx, _ctrl, item),
                    onToggle: () => _ctrl.toggleItem(item.name),
                  ),
                ),
                const SizedBox(height: 16),
                TechInfoSection(items: items),
              ],
            );
          },
        ),
      ),
    );
  }

  bool _cameraInLocation(OHThing t, String locName) {
    final names = _ctrl.getItemsForLocation(locName).map((i) => i.name).toSet();
    return t.channels.any((c) => c.linkedItems.any(names.contains));
  }

  List<OHThing> get _camerasForLocation {
    final all = _ctrl.cameraThings;
    if (_locationRawName.isEmpty) return all;
    return all.where((t) => _cameraInLocation(t, _locationRawName)).toList();
  }

  Widget _buildDevicesGrid(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_ctrl.isLoading) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF27272A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: const Center(
            child: CircularProgressIndicator(
                color: Color(0xFFFFA500), strokeWidth: 2)),
      );
    }

    final acUnits = _locAcUnits;
    final groups = _groupByEquipment(_displayItems).entries.toList();
    if (acUnits.isEmpty && groups.isEmpty) return _buildEmptyDevices(context);

    final crossAxisCount = ResponsiveUtils.gridColumns(context);
    final isWide = crossAxisCount > 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // AC: kartu lebar penuh (sama seperti Home), di atas grid.
        for (final unit in acUnits) ...[
          AcUnitSummaryCard(unit: unit, ctrl: _ctrl),
          const SizedBox(height: 12),
        ],
        if (groups.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.1,
            ),
            itemCount: groups.length,
            itemBuilder: (context, i) {
              final entry = groups[i];
              if (entry.value.length == 1) {
                final item = entry.value.first;
                return _FloorPlanDeviceCard(
                  item: item,
                  ctrl: _ctrl,
                  onToggle: () => _ctrl.toggleItem(item.name),
                  isWide: isWide,
                );
              }
              return EquipmentSummaryCard(
                name: entry.key,
                items: entry.value,
                icon: _groupIcon(entry.value),
                isActive: _floorItemIsActive,
                onToggle: (it) => _ctrl.toggleItem(it.name),
                onOpen: () => _showEquipmentDetail(context, entry.key),
              );
            },
          ),
      ],
    );
  }

  Widget _buildEmptyDevices(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        FaIcon(FontAwesomeIcons.plugCircleXmark,
            size: 32,
            color: const Color(0xFF71717A).withValues(alpha: 0.4)),
        const SizedBox(height: 12),
        Text('Tidak ada device di $_locationTitle',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: isDark
                    ? Colors.white38
                    : const Color(0xFF71717A))),
        const SizedBox(height: 4),
        Text(
            'Pasang perangkat ke ruangan ini langsung dari aplikasi.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: isDark
                    ? Colors.white38
                    : const Color(0xFF71717A),
                height: 1.5)),
        // [MAPPING] CTA menggantikan arahan "buka openHAB"
        if (context.watch<RoleProvider>().isAdmin) ...[
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _addDeviceToCurrentRoom,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFA500),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            icon: const Icon(Icons.add, size: 16, color: Colors.white),
            label: const Text('Tambah Device',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ),
        ],
      ]),
    );
  }

  Widget _buildAnalyticsHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Analytics',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: cs.onSurface)),
        GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const EnergyPage())),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Text('See All',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Color(0xFFFFA500))),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyticsCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    final hasWeeklyData = _weeklyData.isNotEmpty && _weeklyData.any((v) => v > 0);
    final data = hasWeeklyData ? _weeklyData : List<double>.filled(7, 0.0);
    final labels = _weeklyLabels.isNotEmpty
        ? _weeklyLabels
        : const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final maxValue = hasWeeklyData ? data.reduce((a, b) => a > b ? a : b) : 1.0;
    final weekTotal = data.fold<double>(0, (a, b) => a + b);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Consumption',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: cs.onSurface)),
        Text(
            _weeklyLoading
                ? 'Memuat data 7 hari...'
                : hasWeeklyData
                    ? 'This Week: ${weekTotal.toStringAsFixed(2)} kWh'
                    : 'Today: ${_energyToday.toStringAsFixed(2)} kWh',
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: isDark
                    ? Colors.white54
                    : const Color(0xFF71717A))),
        const SizedBox(height: 16),
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(
                data.length,
                (i) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                            right: i < data.length - 1 ? 6 : 0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Flexible(
                                child: FractionallySizedBox(
                              heightFactor: maxValue > 0
                                  ? (data[i] / maxValue).clamp(0.02, 1.0)
                                  : 0.02,
                              widthFactor: 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: i == data.length - 1
                                      ? const Color(0xFFFFA500)
                                      : const Color(0xFFFFA500)
                                          .withValues(alpha: 0.4),
                                  borderRadius:
                                      const BorderRadius.vertical(
                                          top: Radius.circular(6)),
                                ),
                              ),
                            )),
                            const SizedBox(height: 6),
                            Text(labels[i],
                                style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w400,
                                    fontSize: 10,
                                    color: isDark
                                        ? Colors.white54
                                        : const Color(0xFF71717A))),
                          ],
                        ),
                      ),
                    )),
          ),
        ),
      ]),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const navItems = [
      _NavItem(icon: FontAwesomeIcons.house, label: 'Home'),
      _NavItem(icon: FontAwesomeIcons.bolt, label: 'Energy'),
      _NavItem(
          icon: FontAwesomeIcons.mapLocationDot, label: 'Floorplan'),
      _NavItem(icon: FontAwesomeIcons.gear, label: 'Settings'),
    ];
    const selectedIndex = 2;

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(navItems.length, (i) {
          final isSelected = selectedIndex == i;
          return GestureDetector(
            onTap: () {
              if (isSelected) return;
              // Kembali ke root (Home) dulu, baru push tujuan — supaya
              // hasil navigasi konsisten berapapun dalamnya stack saat ini.
              Navigator.popUntil(context, (route) => route.isFirst);
              switch (i) {
                case 0:
                  break; // sudah di Home setelah popUntil
                case 1:
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const EnergyPage()));
                  break;
                case 3:
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SettingsPage()));
                  break;
              }
            },
            child:
                Column(mainAxisSize: MainAxisSize.min, children: [
              FaIcon(navItems[i].icon,
                  size: 20,
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? Colors.white38 : Colors.black38)),
              const SizedBox(height: 4),
              Text(navItems[i].label,
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: isSelected
                          ? AppColors.primary
                          : (isDark
                              ? Colors.white38
                              : Colors.black38),
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal)),
            ]),
          );
        }),
      ),
    );
  }

  Future<void> _loadScenes() async {
    if (!_ctrl.isConnected) return;
    setState(() => _scenesLoading = true);
    try {
      final headers = await _buildHeaders();
      final uri =
          Uri.parse('${_ctrl.serverUrl}/rest/rules?tags=Scene');
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        if (mounted) {
          setState(() {
            _scenes = list
                .map((e) => e as Map<String, dynamic>)
                .where((e) =>
                    e['status']?['status'] != 'DISABLED')
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint('loadScenes error: $e');
    } finally {
      if (mounted) setState(() => _scenesLoading = false);
    }
  }

  Future<void> _runScene(String uid) async {
    setState(() => _runningSceneUid = uid);
    try {
      final headers = await _buildHeaders();
      final uri = Uri.parse(
          '${_ctrl.serverUrl}/rest/rules/$uid/runnow');
      final res = await http
          .post(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            Icon(
                res.statusCode == 200 || res.statusCode == 204
                    ? Icons.check_circle_outline_rounded
                    : Icons.error_outline,
                color: Colors.white,
                size: 18),
            const SizedBox(width: 10),
            Text(
                res.statusCode == 200 || res.statusCode == 204
                    ? 'Scene dijalankan'
                    : 'Gagal menjalankan scene (${res.statusCode})',
                style: const TextStyle(
                    fontFamily: 'Inter', fontSize: 13)),
          ]),
          backgroundColor:
              res.statusCode == 200 || res.statusCode == 204
                  ? const Color(0xFF34C759)
                  : const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e',
              style: const TextStyle(
                  fontFamily: 'Inter', fontSize: 13)),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) setState(() => _runningSceneUid = null);
    }
  }

  Future<Map<String, String>> _buildHeaders() async {
    final config = context.read<InstallationProvider>().config;
    final h = <String, String>{'Accept': 'application/json'};
    if (config?.apiToken != null && config!.apiToken!.isNotEmpty) {
      h['Authorization'] = 'Bearer ${config.apiToken}';
    } else if (config?.username != null && config?.password != null) {
      final enc =
          base64Encode(utf8.encode('${config!.username}:${config.password}'));
      h['Authorization'] = 'Basic $enc';
    }
    return h;
  }
}

class _FloorPlanDeviceCard extends StatelessWidget {
  final OpenHABItem item;
  final VoidCallback onToggle;
  final OpenHABController ctrl;
  final bool isWide;

  const _FloorPlanDeviceCard({
    required this.item,
    required this.onToggle,
    required this.ctrl,
    this.isWide = false,
  });

  FaIconData get _icon {
    switch (item.iconKey) {
      case 'lightbulb':   return FontAwesomeIcons.lightbulb;
      case 'ac':          return FontAwesomeIcons.wind;
      case 'temperature': return FontAwesomeIcons.temperatureHalf;
      case 'tv':          return FontAwesomeIcons.tv;
      case 'speaker':     return FontAwesomeIcons.volumeHigh;
      case 'door':        return FontAwesomeIcons.doorOpen;
      case 'fan':         return FontAwesomeIcons.fan;
      case 'camera':      return FontAwesomeIcons.camera;
      case 'dimmer':      return FontAwesomeIcons.sliders;
      case 'remote':      return FontAwesomeIcons.gamepad;
      case 'command':     return FontAwesomeIcons.terminal;
      case 'player':      return FontAwesomeIcons.play;
      default:            return FontAwesomeIcons.powerOff;
    }
  }

  String get _stateLabel {
    if (item.type == 'Player') {
      switch (item.state?.toUpperCase()) {
        case 'PLAY':  return 'Playing';
        case 'PAUSE': return 'Paused';
        default:      return 'Idle';
      }
    }
    if (item.isSwitch) return item.isOn ? 'On' : 'Off';
    if (item.isDimmer) {
      final v = item.numericValue;
      return v != null ? '${v.toInt()}%' : 'Off';
    }
    if (item.isContact) {
      return item.state?.toUpperCase() == 'OPEN' ? 'Terbuka' : 'Tertutup';
    }
    if (item.isRollershutter) {
      final v = item.numericValue;
      return v != null ? '${v.toInt()}%' : '-';
    }
    if (item.isColor) return item.hsbColor != null ? 'Warna' : '-';
    if (item.isCamera) return 'Kamera';
    if (item.isImage) return item.imageBytes != null ? 'Live' : 'No signal';
    if (item.isString) {
      final s = item.state;
      if (s == null || s.isEmpty || s == 'NULL' || s == 'UNDEF') return 'Command';
      return s.length > 10 ? '${s.substring(0, 10)}…' : s;
    }
    return item.state ?? '-';
  }

  bool get _isActive {
    if (item.isSwitch) return item.isOn;
    if (item.isDimmer) return (item.numericValue ?? 0) > 0;
    if (item.type == 'Player') return item.state?.toUpperCase() == 'PLAY';
    // Contact (sensor pintu/jendela): OPEN dianggap "aktif" — konsisten
    // dengan konvensi status openHAB, supaya status aktif tidak salah baca.
    if (item.isContact) return item.state?.toUpperCase() == 'OPEN';
    // Rollershutter: konvensi openHAB posisi 0=terbuka, 100=tertutup penuh.
    if (item.isRollershutter) return (item.numericValue ?? 100) < 100;
    if (item.isColor) return (item.hsbColor?.value ?? 0) > 0;
    // Camera/Image: read-only, tidak ada konsep on/off.
    return false;
  }

  void _onTap(BuildContext context) =>
      _openFloorItemControl(context, ctrl, item, onToggle: onToggle);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardColor = _isActive
        ? AppColors.primary
        : (isDark ? const Color(0xFF27272A) : Colors.white);
    final mutedColor = _isActive
        ? Colors.white70
        : (isDark ? Colors.white60 : const Color(0xFF71717A));
    final iconColor = _isActive
        ? Colors.white
        : (isDark ? Colors.white70 : const Color(0xFF71717A));
    final labelColor = _isActive
        ? Colors.white
        : (isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xCC18181B));
    final pillBg = _isActive
        ? Colors.white.withValues(alpha: 0.25)
        : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0x33787878));
    final pillIconText = _isActive
        ? Colors.white
        : (isDark ? Colors.white70 : const Color(0xFF18181B));

    return GestureDetector(
      onTap: () => _onTap(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Icon + State label ──────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FaIcon(_icon, size: isWide ? 28 : 22, color: iconColor),
                Flexible(
                  child: Text(
                    _stateLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                      fontSize: 11,
                      color: mutedColor,
                    ),
                  ),
                ),
              ],
            ),

            const Spacer(),

            // ── Device name ─────────────────────────────────────────
            Text(
              item.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: labelColor,
              ),
            ),

            const SizedBox(height: 2),

            // ── Room name ───────────────────────────────────────────
            Text(
              item.roomGuess,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
                fontSize: 11,
                color: mutedColor,
              ),
            ),

            const SizedBox(height: 6),

            // ── Bottom pill ─────────────────────────────────────────
            if (item.isDimmer || item.type == 'Player' || item.isRollershutter || item.isColor ||
                item.isString ||
                (!item.isSwitch && (item.isImage || item.isCamera)))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FaIcon(
                      item.isDimmer
                          ? FontAwesomeIcons.sliders
                          : item.isRollershutter
                              ? FontAwesomeIcons.tableColumns
                              : item.isColor
                                  ? FontAwesomeIcons.palette
                                  : item.isString
                                      ? (item.looksLikeRemoteButton
                                          ? FontAwesomeIcons.gamepad
                                          : FontAwesomeIcons.terminal)
                                      : (item.isImage || item.isCamera)
                                          ? FontAwesomeIcons.video
                                          : FontAwesomeIcons.play,
                      size: 8,
                      color: pillIconText,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.isDimmer || item.isString
                          ? 'Tap to adjust'
                          : item.isColor
                              ? 'Tap to set color'
                              : (item.isImage || item.isCamera)
                                  ? 'Tap to view'
                                  : 'Tap to control',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                        fontSize: 8,
                        color: pillIconText,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: _isActive
                      ? Colors.white.withValues(alpha: 0.30)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0x33787878)),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Text(
                  '• ${item.type}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                    fontSize: 8,
                    color: pillIconText,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FloorDimmerSheet extends StatefulWidget {
  final OpenHABItem item;
  final OpenHABController ctrl;
  const _FloorDimmerSheet({required this.item, required this.ctrl});

  @override
  State<_FloorDimmerSheet> createState() => _FloorDimmerSheetState();
}

class _FloorDimmerSheetState extends State<_FloorDimmerSheet> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.item.numericValue ?? 0;
  }

  bool get _isOn => _value > 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF3F3F46)
                  : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _isOn
                      ? AppColors.primary
                      : (isDark
                          ? const Color(0xFF3F3F46)
                          : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: FaIcon(FontAwesomeIcons.sliders,
                      size: 20,
                      color: _isOn
                          ? Colors.white
                          : (isDark
                              ? Colors.white60
                              : Colors.grey)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.item.label,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.8)
                              : const Color(0xCC18181B),
                        )),
                    Text(widget.item.roomGuess,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: isDark
                              ? Colors.white60
                              : const Color(0xFF71717A),
                        )),
                  ],
                ),
              ),
              Switch(
                value: _isOn,
                onChanged: (v) {
                  setState(() => _value = v ? 50 : 0);
                  widget.ctrl.sendCommand(
                      widget.item.name, v ? '50' : '0');
                },
                activeThumbColor: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            '${_value.toInt()}%',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 48,
              color: _isOn
                  ? AppColors.primary
                  : (isDark
                      ? Colors.white38
                      : Colors.grey.shade400),
            ),
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: isDark
                  ? const Color(0xFF3F3F46)
                  : Colors.grey.shade200,
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.15),
              trackHeight: 8,
              thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 14),
            ),
            child: Slider(
              value: _value,
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: (v) => setState(() => _value = v),
              onChangeEnd: (v) => widget.ctrl.sendCommand(
                  widget.item.name, v.toInt().toString()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0%',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: isDark
                            ? Colors.white60
                            : const Color(0xFF71717A))),
                Text('100%',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: isDark
                            ? Colors.white60
                            : const Color(0xFF71717A))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [25, 50, 75, 100].map((preset) {
              final isSelected = _value == preset.toDouble();
              return GestureDetector(
                onTap: () {
                  setState(() => _value = preset.toDouble());
                  widget.ctrl.sendCommand(
                      widget.item.name, preset.toString());
                },
                child: Container(
                  width: 60,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : (isDark
                            ? const Color(0xFF3F3F46)
                            : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Text(
                      '$preset%',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: isSelected
                            ? Colors.white
                            : (isDark
                                ? Colors.white70
                                : const Color(0xFF71717A)),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}


class _FloorRollershutterSheet extends StatefulWidget {
  final OpenHABItem item;
  final OpenHABController ctrl;
  const _FloorRollershutterSheet({required this.item, required this.ctrl});

  @override
  State<_FloorRollershutterSheet> createState() => _FloorRollershutterSheetState();
}

class _FloorRollershutterSheetState extends State<_FloorRollershutterSheet> {
  late double _position; // 0 = terbuka penuh, 100 = tertutup penuh (konvensi openHAB)

  @override
  void initState() {
    super.initState();
    _position = widget.item.numericValue ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOpen = _position < 100;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF3F3F46) : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: isOpen
                      ? AppColors.primary
                      : (isDark ? const Color(0xFF3F3F46) : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: FaIcon(FontAwesomeIcons.tableColumns,
                      size: 20,
                      color: isOpen ? Colors.white : (isDark ? Colors.white60 : Colors.grey)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.item.label,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xCC18181B),
                        )),
                    Text(widget.item.roomGuess,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: isDark ? Colors.white60 : const Color(0xFF71717A),
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (widget.item.supportsCommand('UP'))
                _FloorRollerButton(
                  icon: FontAwesomeIcons.arrowUp,
                  label: 'Buka',
                  isDark: isDark,
                  onTap: () {
                    setState(() => _position = 0);
                    widget.ctrl.sendCommand(widget.item.name, 'UP');
                  },
                ),
              if (widget.item.supportsCommand('STOP'))
                _FloorRollerButton(
                  icon: FontAwesomeIcons.stop,
                  label: 'Stop',
                  isDark: isDark,
                  onTap: () => widget.ctrl.sendCommand(widget.item.name, 'STOP'),
                ),
              if (widget.item.supportsCommand('DOWN'))
                _FloorRollerButton(
                  icon: FontAwesomeIcons.arrowDown,
                  label: 'Tutup',
                  isDark: isDark,
                  onTap: () {
                    setState(() => _position = 100);
                    widget.ctrl.sendCommand(widget.item.name, 'DOWN');
                  },
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '${_position.toInt()}% tertutup',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 22,
              color: isDark ? Colors.white70 : const Color(0xFF52525B),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: isDark ? const Color(0xFF3F3F46) : Colors.grey.shade200,
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.15),
              trackHeight: 8,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
            ),
            child: Slider(
              value: _position,
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: (v) => setState(() => _position = v),
              onChangeEnd: (v) =>
                  widget.ctrl.sendCommand(widget.item.name, v.toInt().toString()),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloorRollerButton extends StatelessWidget {
  final FaIconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  const _FloorRollerButton({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 78, height: 64,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3F3F46) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(icon, size: 18, color: isDark ? Colors.white70 : const Color(0xFF52525B)),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : const Color(0xFF52525B),
                )),
          ],
        ),
      ),
    );
  }
}

class _FloorColorSheet extends StatefulWidget {
  final OpenHABItem item;
  final OpenHABController ctrl;
  const _FloorColorSheet({required this.item, required this.ctrl});

  @override
  State<_FloorColorSheet> createState() => _FloorColorSheetState();
}

class _FloorColorSheetState extends State<_FloorColorSheet> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = widget.item.hsbColor ?? HSVColor.fromAHSV(1.0, 0, 0, 1.0);
  }

  void _sendHsb() {
    final h = _hsv.hue.round();
    final s = (_hsv.saturation * 100).round();
    final b = (_hsv.value * 100).round();
    widget.ctrl.sendCommand(widget.item.name, '$h,$s,$b');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _hsv.toColor();

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF3F3F46) : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: isDark ? Colors.white24 : Colors.black12),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.item.label,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xCC18181B),
                        )),
                    Text(widget.item.roomGuess,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: isDark ? Colors.white60 : const Color(0xFF71717A),
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Warna (Hue)',
              style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                  color: isDark ? Colors.white54 : const Color(0xFF71717A))),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color, thumbColor: color),
            child: Slider(
              value: _hsv.hue, min: 0, max: 360,
              onChanged: (v) => setState(() => _hsv = _hsv.withHue(v)),
              onChangeEnd: (_) => _sendHsb(),
            ),
          ),
          Text('Saturasi',
              style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                  color: isDark ? Colors.white54 : const Color(0xFF71717A))),
          Slider(
            value: _hsv.saturation, min: 0, max: 1,
            onChanged: (v) => setState(() => _hsv = _hsv.withSaturation(v)),
            onChangeEnd: (_) => _sendHsb(),
          ),
          Text('Kecerahan',
              style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                  color: isDark ? Colors.white54 : const Color(0xFF71717A))),
          Slider(
            value: _hsv.value, min: 0, max: 1,
            onChanged: (v) => setState(() => _hsv = _hsv.withValue(v)),
            onChangeEnd: (_) => _sendHsb(),
          ),
        ],
      ),
    );
  }
}

/// Kartu kamera untuk Thing hasil auto-discovery (binding IP Camera) —
/// sumbernya Thing + URL yang dikonstruksi langsung dari _serverUrl,
/// BUKAN dari state Item manapun.
/// Wrapper: item Camera (category "Camera", type String/Image) langsung
/// pakai state-nya sendiri sebagai URL video.
class _FloorCameraPlayerDialog extends StatelessWidget {
  final OpenHABItem item;
  final OpenHABController ctrl;
  const _FloorCameraPlayerDialog({required this.item, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final label = item.label.isNotEmpty ? item.label : item.name;
    final url = item.state;
    if (url == null || !(url.startsWith('http://') || url.startsWith('https://'))) {
      return _FloorVideoUnavailableDialog(
        label: label,
        reason: 'State item ini bukan URL video yang valid.',
      );
    }
    return _FloorVideoPlayerDialog(label: label, videoUrl: url, httpHeaders: ctrl.authHeaders);
  }
}

class _FloorVideoUnavailableDialog extends StatelessWidget {
  final String label;
  final String reason;
  const _FloorVideoUnavailableDialog({required this.label, required this.reason});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: double.infinity,
        height: 220,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 16, top: 14,
              child: Text(label,
                  style: const TextStyle(
                      fontFamily: 'Inter', fontWeight: FontWeight.w700,
                      fontSize: 16, color: Colors.white)),
            ),
            Positioned(
              right: 8, top: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.videocam_off_outlined,
                      color: Colors.white38, size: 36),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(reason,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontFamily: 'Inter', fontSize: 12,
                            color: Colors.white54)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog video player HLS sungguhan (video_player + hlsUrl dari binding
/// IP Camera). Mulai dari tampilan poster, tap play baru mulai
/// inisialisasi & memutar stream. Gagal → pesan error jelas + coba lagi.
class _FloorVideoPlayerDialog extends StatefulWidget {
  final String label;
  final String videoUrl;
  final Future<bool> Function()? onBeforePlay;
  final Map<String, String> httpHeaders;
  const _FloorVideoPlayerDialog({
  required this.label,
  required this.videoUrl,
  // ignore: unused_element_parameter
  this.onBeforePlay,
  this.httpHeaders = const {},
});

  @override
  State<_FloorVideoPlayerDialog> createState() => _FloorVideoPlayerDialogState();
}

class _FloorVideoPlayerDialogState extends State<_FloorVideoPlayerDialog> {
  VideoPlayerController? _controller;
  bool _started = false;
  bool _loading = false;
  String? _error;
  bool _muted = false;

  Future<void> _startPlayback() async {
    setState(() { _started = true; _loading = true; _error = null; });
    try {
      if (widget.onBeforePlay != null) {
        final triggered = await widget.onBeforePlay!();
        if (!triggered) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = 'Channel "startStream" belum di-link ke Item — server '
                'tidak pernah dipicu untuk mulai membuat file stream. '
                'Cek konfigurasi Thing kamera ini di openHAB.';
          });
          return;
        }
        // FFmpeg butuh waktu buka koneksi RTSP + probe stream + generate
        // manifest .m3u8/.mjpeg pertama kali dipicu — durasinya beda-beda
        // tiap kamera/jaringan, jadi delay TETAP tidak reliable. Poll URL
        // manifestnya sampai server benar-benar siap (HTTP 200) atau timeout.
        final ready = await _waitUntilStreamReady(widget.videoUrl, widget.httpHeaders);
        if (!mounted) return;
        if (!ready) {
          setState(() {
            _loading = false;
            _error = 'Stream belum siap setelah menunggu — server openHAB '
                'mungkin gagal generate file (cek log FFmpeg/RTSP di server) '
                'atau kamera tidak reachable.';
          });
          return;
        }
      }
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
        formatHint: VideoFormat.hls,
        httpHeaders: widget.httpHeaders,
      );
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) { controller.dispose(); return; }
      setState(() { _controller = controller; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Gagal memutar video.\nPastikan stream aktif & URL benar.';
      });
    }
  }

  /// Poll URL manifest/stream sampai server balas 200 (artinya FFmpeg
  /// sudah selesai generate file), dicoba tiap 1.5 detik sampai
  /// [maxWait] tercapai. HEAD request dulu, fallback ke GET kalau server
  /// tidak izinkan HEAD (405/501).
  Future<bool> _waitUntilStreamReady(
    String url,
    Map<String, String> headers, {
    Duration maxWait = const Duration(seconds: 15),
    Duration interval = const Duration(milliseconds: 1500),
  }) async {
    final deadline = DateTime.now().add(maxWait);
    while (DateTime.now().isBefore(deadline)) {
      if (!mounted) return false;
      try {
        var res = await http
            .head(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 3));
        if (res.statusCode == 405 || res.statusCode == 501) {
          res = await http
              .get(Uri.parse(url), headers: headers)
              .timeout(const Duration(seconds: 3));
        }
        if (res.statusCode == 200) return true;
      } catch (_) {
        // belum siap / server belum reachable, coba lagi
      }
      await Future.delayed(interval);
    }
    return false;
  }

  void _toggleMute() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      _muted = !_muted;
      c.setVolume(_muted ? 0 : 1);
    });
  }

  void _togglePlayPause() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      c.value.isPlaying ? c.pause() : c.play();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final hasVideo = controller != null && controller.value.isInitialized;
    final aspectRatio = hasVideo ? controller.value.aspectRatio : 16 / 9;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Container(
            color: const Color(0xFF0A0A0A),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasVideo)
                  GestureDetector(
                    onTap: _togglePlayPause,
                    child: VideoPlayer(controller),
                  ),
                Positioned(
                  left: 16, top: 14,
                  child: Text(widget.label,
                      style: const TextStyle(
                          fontFamily: 'Inter', fontWeight: FontWeight.w700,
                          fontSize: 16, color: Colors.white)),
                ),
                Positioned(
                  right: 8, top: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                if (hasVideo)
                  Positioned(
                    right: 8, bottom: 8,
                    child: IconButton(
                      icon: Icon(_muted ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white70),
                      onPressed: _toggleMute,
                    ),
                  ),
                if (!_started)
                  Center(
                    child: GestureDetector(
                      onTap: _startPlayback,
                      child: Container(
                        width: 56, height: 56,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE4E4E7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.black, size: 30),
                      ),
                    ),
                  )
                else if (_loading)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white70),
                  )
                else if (_error != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: SingleChildScrollView(
                        child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.white38, size: 36),
                          const SizedBox(height: 8),
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontFamily: 'Inter', fontSize: 12,
                                  color: Colors.white54)),
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: widget.videoUrl));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('URL disalin ke clipboard'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(widget.videoUrl,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        style: const TextStyle(
                                            fontFamily: 'monospace', fontSize: 10,
                                            color: Colors.white38)),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.copy, size: 12, color: Colors.white38),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _startPlayback,
                            child: const Text('Coba lagi',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog viewer snapshot kamera (item Image). Bukan live-streaming
/// (RTSP/ONVIF) — hanya menampilkan snapshot terakhir dari state item,
/// dengan tombol refresh untuk polling ulang lewat controller.
class _FloorCameraViewerDialog extends StatefulWidget {
  final OpenHABItem item;
  final OpenHABController ctrl;
  const _FloorCameraViewerDialog({required this.item, required this.ctrl});

  @override
  State<_FloorCameraViewerDialog> createState() => _FloorCameraViewerDialogState();
}

class _FloorCameraViewerDialogState extends State<_FloorCameraViewerDialog> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await widget.ctrl.loadItems();
    } catch (_) {
      // Diamkan — snapshot lama tetap ditampilkan kalau refresh gagal.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = widget.ctrl.items
        .firstWhere((i) => i.name == widget.item.name, orElse: () => widget.item);
    final bytes = current.imageBytes;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF27272A) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    current.label.isNotEmpty ? current.label : current.name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: isDark ? Colors.white : const Color(0xFF18181B),
                    ),
                  ),
                ),
                IconButton(
                  icon: _refreshing
                      ? SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: isDark ? Colors.white70 : Colors.black54))
                      : Icon(Icons.refresh,
                          color: isDark ? Colors.white70 : Colors.black54),
                  onPressed: _refreshing ? null : _refresh,
                ),
                IconButton(
                  icon: Icon(Icons.close,
                      color: isDark ? Colors.white70 : Colors.black54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: bytes != null
                  ? Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Container(
                        width: double.infinity,
                        height: 220,
                        alignment: Alignment.center,
                        color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam_off_outlined, size: 40,
                                color: isDark ? Colors.white38 : const Color(0xFF71717A)),
                            const SizedBox(height: 8),
                            Text('Gagal memuat snapshot',
                                style: TextStyle(fontFamily: 'Inter', fontSize: 13,
                                    color: isDark ? Colors.white54 : const Color(0xFF71717A))),
                          ],
                        ),
                      ),
                    )
                  : Container(
                      width: double.infinity,
                      height: 220,
                      alignment: Alignment.center,
                      color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.videocam_off_outlined, size: 40,
                              color: isDark ? Colors.white38 : const Color(0xFF71717A)),
                          const SizedBox(height: 8),
                          Text('Belum ada snapshot',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 13,
                                  color: isDark ? Colors.white54 : const Color(0xFF71717A))),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Kontrol remote D-pad untuk Item String yang berfungsi sebagai channel
/// command tombol (mis. "rcButton" binding LG webOS). Tiap tombol dicek
/// lewat [OpenHABItem.supportsCommand] — kalau server melaporkan daftar
/// command yang didukung dan kode ini tidak ada di situ, disembunyikan.
class _RemoteControlSheet extends StatelessWidget {
  final OpenHABItem item;
  final OpenHABController ctrl;
  const _RemoteControlSheet({required this.item, required this.ctrl});

  void _send(String code) => ctrl.sendCommand(item.name, code);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF18181B);

    Widget roundBtn(IconData icon, String code, {double size = 52}) {
      if (!item.supportsCommand(code)) return const SizedBox.shrink();
      return GestureDetector(
        onTap: () => _send(code),
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: size * 0.4, color: textColor),
        ),
      );
    }

    Widget textBtn(String label, String code, {Color? bg, Color? fg}) {
      if (!item.supportsCommand(code)) return const SizedBox.shrink();
      return GestureDetector(
        onTap: () => _send(code),
        child: Container(
          width: 52, height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg ?? (isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                  fontSize: 13, color: fg ?? textColor)),
        ),
      );
    }

    const knownCodes = ['UP','DOWN','LEFT','RIGHT','ENTER','BACK','HOME','EXIT',
        'PLAY','PAUSE','STOP','RED','GREEN','YELLOW','BLUE'];
    final anySupported = item.commandOptions.isEmpty ||
        knownCodes.any((c) => item.supportsCommand(c));
    if (!anySupported) {
      return _StringCommandSheet(item: item, ctrl: ctrl);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF3F3F46) : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        Text(item.label, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
            fontSize: 17, color: textColor)),
        const SizedBox(height: 20),

        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          textBtn('BACK', 'BACK'),
          roundBtn(Icons.home_rounded, 'HOME'),
          textBtn('EXIT', 'EXIT'),
        ]),
        const SizedBox(height: 20),

        Column(children: [
          roundBtn(Icons.keyboard_arrow_up_rounded, 'UP', size: 56),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            roundBtn(Icons.keyboard_arrow_left_rounded, 'LEFT', size: 56),
            const SizedBox(width: 8),
            if (item.supportsCommand('ENTER'))
              GestureDetector(
                onTap: () => _send('ENTER'),
                child: Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: const Center(child: Text('OK',
                      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                          fontSize: 13, color: Colors.white))),
                ),
              ),
            const SizedBox(width: 8),
            roundBtn(Icons.keyboard_arrow_right_rounded, 'RIGHT', size: 56),
          ]),
          const SizedBox(height: 8),
          roundBtn(Icons.keyboard_arrow_down_rounded, 'DOWN', size: 56),
        ]),
        const SizedBox(height: 20),

        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          roundBtn(Icons.play_arrow_rounded, 'PLAY', size: 44),
          roundBtn(Icons.pause_rounded, 'PAUSE', size: 44),
          roundBtn(Icons.stop_rounded, 'STOP', size: 44),
        ]),
        const SizedBox(height: 20),

        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          textBtn('', 'RED', bg: Colors.red, fg: Colors.white),
          textBtn('', 'GREEN', bg: Colors.green, fg: Colors.white),
          textBtn('', 'YELLOW', bg: Colors.amber, fg: Colors.black),
          textBtn('', 'BLUE', bg: Colors.blue, fg: Colors.white),
        ]),

        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () {
            Navigator.pop(context);
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (_) => _StringCommandSheet(item: item, ctrl: ctrl),
            );
          },
          icon: const Icon(Icons.keyboard, size: 16),
          label: const Text('Kirim command lain (teks bebas)',
              style: TextStyle(fontFamily: 'Inter', fontSize: 12)),
        ),
      ]),
    );
  }
}

/// Kontrol generik untuk Item String yang bukan remote button — kotak
/// teks bebas, plus chip pilihan cepat kalau server melaporkan
/// commandOptions untuk channel ini.
class _StringCommandSheet extends StatefulWidget {
  final OpenHABItem item;
  final OpenHABController ctrl;
  const _StringCommandSheet({required this.item, required this.ctrl});

  @override
  State<_StringCommandSheet> createState() => _StringCommandSheetState();
}

class _StringCommandSheetState extends State<_StringCommandSheet> {
  late final TextEditingController _ctrl2;

  @override
  void initState() {
    super.initState();
    final current = widget.item.state;
    _ctrl2 = TextEditingController(
        text: (current == null || current == 'NULL' || current == 'UNDEF') ? '' : current);
  }

  @override
  void dispose() {
    _ctrl2.dispose();
    super.dispose();
  }

  void _send([String? value]) {
    final v = (value ?? _ctrl2.text).trim();
    if (v.isEmpty) return;
    widget.ctrl.sendCommand(widget.item.name, v);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF18181B);
    final options = widget.item.commandOptions;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF27272A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF3F3F46) : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          )),
          const SizedBox(height: 16),
          Text(widget.item.label, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
              fontSize: 17, color: textColor)),
          Text(widget.item.name, style: const TextStyle(fontFamily: 'Inter', fontSize: 12,
              color: AppColors.textMuted)),
          const SizedBox(height: 16),
          if (options.isNotEmpty) ...[
            Text('Pilihan cepat', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
                fontSize: 12, color: isDark ? Colors.white54 : const Color(0xFF71717A))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: options.map((opt) =>
              GestureDetector(
                onTap: () => _send(opt),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(opt, style: const TextStyle(fontFamily: 'Inter',
                      fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.primary)),
                ),
              ),
            ).toList()),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _ctrl2,
            autofocus: options.isEmpty,
            style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: textColor),
            decoration: InputDecoration(
              hintText: 'Ketik nilai command (mis. HDMI1, Spotify)',
              filled: true,
              fillColor: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onSubmitted: (_) => _send(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: () => _send(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text('Kirim',
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }
}


class _FloorPlayerSheet extends StatefulWidget {
  final OpenHABItem item;
  final OpenHABController ctrl;
  const _FloorPlayerSheet({required this.item, required this.ctrl});

  @override
  State<_FloorPlayerSheet> createState() => _FloorPlayerSheetState();
}

class _FloorPlayerSheetState extends State<_FloorPlayerSheet> {
  late String _currentState;

  @override
  void initState() {
    super.initState();
    _currentState = widget.item.state?.toUpperCase() ?? 'NULL';
    widget.ctrl.addListener(_onCtrlUpdate);
  }

  void _onCtrlUpdate() {
    if (!mounted) return;
    final fresh = widget.ctrl.getItem(widget.item.name);
    if (fresh != null) {
      setState(
          () => _currentState = fresh.state?.toUpperCase() ?? 'NULL');
    }
  }

  @override
  void dispose() {
    widget.ctrl.removeListener(_onCtrlUpdate);
    super.dispose();
  }

  bool get _isPlaying => _currentState == 'PLAY';

  void _send(String command) {
    widget.ctrl.sendCommand(widget.item.name, command);
    final cmd = command.toUpperCase();
    // Hanya PLAY/PAUSE representasi state Player yang valid.
    // NEXT/PREVIOUS/STOP adalah command transport, bukan state — jangan
    // dipaksa jadi _currentState, biar tidak salah tampil "Idle" padahal
    // masih Playing. State asli datang lewat _onCtrlUpdate.
    if (cmd == 'PLAY' || cmd == 'PAUSE') {
      setState(() => _currentState = cmd);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      decoration: const BoxDecoration(
        color: Color(0xFF1C2526),
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: FaIcon(
                _isPlaying
                    ? FontAwesomeIcons.pause
                    : FontAwesomeIcons.play,
                size: 32,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(widget.item.label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 22,
                color: Colors.white,
              )),
          const SizedBox(height: 4),
          Text(widget.item.roomGuess,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.5),
              )),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _isPlaying
                  ? 'Playing'
                  : _currentState == 'PAUSE'
                      ? 'Paused'
                      : 'Idle',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: _isPlaying
                    ? AppColors.primary
                    : Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.item.supportsCommand('PREVIOUS')) ...[
                _playerButton(
                  icon: FontAwesomeIcons.backwardStep,
                  onTap: () => _send('PREVIOUS'),
                ),
                const SizedBox(width: 24),
              ],
              GestureDetector(
                onTap: () =>
                    _send(_isPlaying ? 'PAUSE' : 'PLAY'),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: FaIcon(
                      _isPlaying
                          ? FontAwesomeIcons.pause
                          : FontAwesomeIcons.play,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              if (widget.item.supportsCommand('NEXT')) ...[
                const SizedBox(width: 24),
                _playerButton(
                  icon: FontAwesomeIcons.forwardStep,
                  onTap: () => _send('NEXT'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          if (widget.item.supportsCommand('STOP'))
          GestureDetector(
            onTap: () => _send('STOP'),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 32, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: const Text('Stop',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Colors.white,
                  )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerButton(
      {required FaIconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child:
            Center(child: FaIcon(icon, size: 20, color: Colors.white)),
      ),
    );
  }
}

extension _IterableExt<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

void _openFloorItemControl(BuildContext context, OpenHABController ctrl, OpenHABItem item,
    {VoidCallback? onToggle}) {
  if (item.isDimmer) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _FloorDimmerSheet(item: item, ctrl: ctrl),
    );
  } else if (item.type == 'Player') {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _FloorPlayerSheet(item: item, ctrl: ctrl),
    );
  } else if (item.isRollershutter) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _FloorRollershutterSheet(item: item, ctrl: ctrl),
    );
  } else if (item.isColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _FloorColorSheet(item: item, ctrl: ctrl),
    );
  } else if (item.isString) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => item.looksLikeRemoteButton
          ? _RemoteControlSheet(item: item, ctrl: ctrl)
          : _StringCommandSheet(item: item, ctrl: ctrl),
    );
  } else if (item.isSwitch) {
    (onToggle ?? () => ctrl.toggleItem(item.name))();
  } else if (item.isCamera) {
    showDialog(
      context: context,
      builder: (_) => _FloorCameraPlayerDialog(item: item, ctrl: ctrl),
    );
  } else if (item.isImage) {
    showDialog(
      context: context,
      builder: (_) => _FloorCameraViewerDialog(item: item, ctrl: ctrl),
    );
  }
  // Contact: sensor read-only, sengaja tidak ada aksi tap.
}

bool _floorItemIsActive(OpenHABItem item) {
  if (item.isSwitch) return item.isOn;
  if (item.isDimmer) return (item.numericValue ?? 0) > 0;
  if (item.type == 'Player') return item.state?.toUpperCase() == 'PLAY';
  if (item.isContact) return item.state?.toUpperCase() == 'OPEN';
  if (item.isRollershutter) return (item.numericValue ?? 100) < 100;
  if (item.isColor) return (item.hsbColor?.value ?? 0) > 0;
  return false;
}

String _floorStateLabel(OpenHABItem item) {
  if (item.type == 'Player') {
    switch (item.state?.toUpperCase()) {
      case 'PLAY':  return 'Playing';
      case 'PAUSE': return 'Paused';
      default:      return 'Idle';
    }
  }
  if (item.isSwitch) return item.isOn ? 'On' : 'Off';
  if (item.isDimmer || item.isRollershutter) {
    final v = item.numericValue;
    return v != null ? '${v.toInt()}%' : '-';
  }
  if (item.isContact) {
    return item.state?.toUpperCase() == 'OPEN' ? 'Terbuka' : 'Tertutup';
  }
  if (item.isColor) return item.hsbColor != null ? 'Warna' : '-';
  if (item.isImage) return item.imageBytes != null ? 'Live' : 'No signal';
  if (item.isString) {
    final st = item.state;
    if (st == null || st.isEmpty || st == 'NULL' || st == 'UNDEF') return 'Command';
    return st.length > 10 ? '${st.substring(0, 10)}…' : st;
  }
  return item.state ?? '-';
}

FaIconData _floorIconForKey(String? key) {
  switch (key) {
    case 'lightbulb':   return FontAwesomeIcons.lightbulb;
    case 'ac':          return FontAwesomeIcons.wind;
    case 'temperature': return FontAwesomeIcons.temperatureHalf;
    case 'tv':          return FontAwesomeIcons.tv;
    case 'speaker':     return FontAwesomeIcons.volumeHigh;
    case 'door':        return FontAwesomeIcons.doorOpen;
    case 'fan':         return FontAwesomeIcons.fan;
    case 'camera':      return FontAwesomeIcons.camera;
    case 'dimmer':      return FontAwesomeIcons.sliders;
    case 'color':       return FontAwesomeIcons.palette;
    case 'remote':      return FontAwesomeIcons.gamepad;
    case 'command':     return FontAwesomeIcons.terminal;
    case 'player':      return FontAwesomeIcons.play;
    default:            return FontAwesomeIcons.powerOff;
  }
}