import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mobile/core/services/auth_service.dart';
import 'package:mobile/core/services/weather_service.dart';
import 'package:mobile/core/providers/installation_provider.dart';
import 'package:mobile/pages/add_item_page.dart';
import 'package:mobile/pages/add_thing_page.dart';
import 'package:mobile/pages/energy_page.dart';
import 'package:mobile/pages/floor_plan_page.dart';
import 'package:mobile/pages/notification_page.dart';
import 'package:mobile/pages/rooms_management_page.dart';
import 'package:mobile/pages/settings_page.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../core/controllers/openhab_controller.dart';
import '../core/models/openhab_item.dart';
import 'package:mobile/core/services/openhab_management_service.dart' show OHThing;
import 'package:mobile/core/services/mqtt_service.dart';
import 'package:mobile/core/utils/responsive_utils.dart';
import 'package:mobile/core/services/app_notification_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  final _ctrl = OpenHABController.instance;
  WeatherData? _weatherData;

  StreamSubscription? _dataSub;
  PowerMeterData _energyData = const PowerMeterData();
  bool _mqttConnected = false;

  int _selectedTab  = 0;
  int _selectedRoom = 0;
  String _selectedCameraGroup = 'Semua';

  // ── Nama item OpenHAB untuk data energi ────────────────────────
  // PENTING: cek betul nama item ini persis sama dengan yang ada
  // di server openHAB kamu (case-sensitive). Kalau beda, ganti di sini.
  static const _itemEnergyToday     = 'pow_test_mqtt_Energy_Today';
  static const _itemEnergyYesterday = 'pow_test_mqtt_Energy_Yesterday';

  List<String> get _rooms {
    final labels = _ctrl.locations.map((loc) {
        final label = loc['label'] as String? ?? '';
        final name  = loc['name']  as String? ?? '';
        return label.isNotEmpty ? label : name;
    }).where((l) => l.isNotEmpty).toList();
    return ['All', ...labels];
}

String get _userName {
  final name = AuthService.currentUser?.displayName ?? '';
  if (name.isEmpty) return 'User';
  return name.split(' ').first; 
}

String get _greeting {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good Morning';
  if (hour < 17) return 'Good Afternoon';
  return 'Good Evening';
}

// Ambil dari _ctrl (item openHAB, di-update real-time lewat SSE),
// bukan lewat polling HTTP manual terpisah — mencegah dua sumber data
// yang bisa nggak sinkron untuk item MQTT yang sama.
double get _energyToday =>
    _ctrl.getItem(_itemEnergyToday)?.numericValue ?? _energyData.energyToday;

double get _energyYesterday =>
    _ctrl.getItem(_itemEnergyYesterday)?.numericValue ?? _energyData.energyYesterday;

  @override
  @override
void initState() {
  super.initState();
  _ctrl.addListener(_onControllerUpdate);
  // _ctrl.initialize() DIHAPUS — controller sudah diinisialisasi
  // dari login_page.dart via initializeWithConfig()/resetConnection()
  // sesuai akun yang login. Memanggilnya lagi di sini akan
  // override balik ke config lama/default.
  _loadWeather();

  final mqtt = MqttService.instance;

  _energyData    = mqtt.lastData;
  _mqttConnected = mqtt.isConnected;

  mqtt.connect();

  _dataSub = mqtt.stream.listen((data) {
    if (mounted) {
      setState(() {
        _energyData    = data;
        _mqttConnected = mqtt.isConnected;
      });
    }
  });

  // Aktifkan pemantau notifikasi sejak app dibuka
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) AppNotificationService.instance.startFromContext(context);
  });

}

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerUpdate);
    _dataSub?.cancel();
    super.dispose();
  }

  Future<void> _loadWeather() async {
  final data = await WeatherService.instance.getWeather();
  if (mounted && data != null) {
    setState(() => _weatherData = data);
  }
}

  void _onControllerUpdate() {
    if (!mounted) return;
    setState(() {});
  }

  bool _isSupportedItem(OpenHABItem i) =>
      i.isSwitch || i.isDimmer || i.type == 'Player' || i.isColor ||
      i.isContact || i.isRollershutter || i.isImage || i.isString;

  /// Nama semua Item yang sudah ditampilkan di kartu AC (power, mode,
  /// fan, setpoint, dst). Item ini disembunyikan dari grid supaya tidak
  /// muncul dua kali — semuanya ada di halaman detail AC.
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

  List<OpenHABItem> get _filteredItems {
    if (!_ctrl.hasItems) return [];
    // Sertakan juga sensor (Contact), tirai (Rollershutter), dan snapshot
    // (Image) — sebelumnya cuma Switch/Dimmer/Player/Color yang tampil.
    final acNames = _acItemNames;
    final all = _ctrl.items
        .where((i) => _isSupportedItem(i) && !acNames.contains(i.name))
        .toList();
    if (_selectedRoom == 0) return all;

    final selectedLabel = _rooms[_selectedRoom];

    final matchedGroup = _ctrl.locations.firstWhere(
        (loc) {
            final label = (loc['label'] as String? ?? '').toLowerCase();
            final name  = (loc['name']  as String? ?? '').toLowerCase();
            return label == selectedLabel.toLowerCase() ||
                   name  == selectedLabel.toLowerCase();
        },
        orElse: () => <String, dynamic>{},
    );

    if (matchedGroup.isEmpty) return [];

    final groupName = matchedGroup['name'] as String? ?? '';
    if (groupName.isEmpty) return [];

    final locationItems = _ctrl.getItemsForLocation(groupName);

    return locationItems
        .where((i) => _isSupportedItem(i) && !acNames.contains(i.name))
        .toList();
}

  /// Kelompokkan Item per perangkat (Equipment). Dipakai subtitle kartu
  /// lama (roomGuess = awalan nama Item, mis. TV_ORCHID / Philips_Wiz)
  /// sebagai kunci grup. Urutan kemunculan dipertahankan.
  Map<String, List<OpenHABItem>> _groupByEquipment(List<OpenHABItem> items) {
    final map = <String, List<OpenHABItem>>{};
    for (final i in items) {
      final key = i.roomGuess.isNotEmpty ? i.roomGuess : 'Lainnya';
      map.putIfAbsent(key, () => []).add(i);
    }
    return map;
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
              padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveUtils.horizontalPadding(context)),
              child: ResponsiveUtils.constrainWidth(context, Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  _buildHeader(context),
                  const SizedBox(height: 20),
                  _buildRoomFilter(context),
                  const SizedBox(height: 16),
                  _buildWeatherCard(context),
                  const SizedBox(height: 4),
                  _buildEnergyCard(context),
                  const SizedBox(height: 12),
                  _buildDevicesHeader(context),
                  const SizedBox(height: 8),
                  ..._ctrl.acUnits.expand((unit) => [
                        _buildAcSummaryCard(context, unit),
                        const SizedBox(height: 12),
                      ]),
                  _buildDeviceGrid(context),
                  if (_ctrl.hasCameraThings) ...[
                    const SizedBox(height: 12),
                    _buildCameraSection(context),
                  ],
                  const SizedBox(height: 12),
                  _buildEnergySavingCard(context),
                  const SizedBox(height: 16),
                ],
              )),
            ),
          ),
        ),
        _buildBottomNav(context),
      ],
    ),
  );
}

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        _buildAvatar(context),
        const SizedBox(width: 10),
        Expanded(child: _buildGreeting(context)),
        const SizedBox(width: 8),
        _buildHeaderActions(context),
      ],
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? const Color(0xFF3F3F46) : Colors.grey.shade300,
      ),
      child: Icon(Icons.person, color: isDark ? Colors.white70 : Colors.grey),
    );
  }

  Widget _buildGreeting(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Hello, $_userName',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w400,
          fontSize: 14,
          color: isDark ? Colors.white60 : const Color(0xFF71717A),
        ),
      ),
      Text(
        _greeting,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          fontSize: 20,
          color: isDark ? Colors.white.withValues(alpha: 0.85) : const Color(0xCC18181B),
        ),
      ),
    ],
  );
}

  

  Widget _buildHeaderActions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE3E3E3),
        borderRadius: BorderRadius.circular(37),
      ),
      child: Row(
        children: [
          _buildNotificationButton(context),
          const SizedBox(width: 6),
          _buildConnectionBadge(context),
          const SizedBox(width: 6),
          _buildMenuButton(context),
        ],
      ),
    );
  }

  Widget _buildConnectionBadge(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? const Color(0xFF3F3F46) : Colors.white;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: _ctrl.isConnected ? 'openHAB Connected' : 'openHAB Disconnected',
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _ctrl.isConnected ? Colors.green : Colors.red,
              border: Border.all(color: borderColor, width: 1.5),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: _mqttConnected
              ? 'MQTT Connected · Device: ${_energyData.deviceOnline ? "Online" : "Offline"}'
              : 'MQTT Disconnected',
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _mqttConnected ? Colors.green : Colors.orange,
              border: Border.all(color: borderColor, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationPage()),
            );
          },
          child: _circleButton(
            context: context,
            child: FaIcon(
              FontAwesomeIcons.bell,
              size: 16,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ),
        Positioned(
          right: 2,
          top: 2,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? const Color(0xFF27272A) : Colors.white,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _showAddMenu(context),
      child: _circleButton(
        context: context,
        child: FaIcon(
          FontAwesomeIcons.bars,
          size: 16,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
      ),
    );
  }

  void _showAddMenu(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
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
            Text('Tambah',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xCC18181B),
              ),
            ),
            const SizedBox(height: 20),
            _buildAddMenuRow(
              context: context,
              icon: FontAwesomeIcons.microchip,
              title: 'Add Thing',
              subtitle: 'Daftarkan perangkat fisik ke openHAB',
              color: AppColors.primary,
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddThingPage()),
                );
                if (result == true) await _ctrl.loadItems();
              },
            ),
            const SizedBox(height: 12),
            _buildAddMenuRow(
              context: context,
              icon: FontAwesomeIcons.toggleOn,
              title: 'Add Item',
              subtitle: 'Tambah kontrol item ke dashboard',
              color: const Color(0xFF6366F1),
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddItemPage()),
                );
                if (result == true) await _ctrl.loadItems();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddMenuRow({
    required BuildContext context,
    required FaIconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? color.withValues(alpha: 0.12) : color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: isDark ? 0.25 : 0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: FaIcon(icon, size: 20, color: color)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: isDark ? Colors.white.withValues(alpha: 0.85) : const Color(0xCC18181B),
                      )),
                  Text(subtitle,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: isDark ? Colors.white60 : const Color(0xFF71717A),
                      )),
                ],
              ),
            ),
            FaIcon(FontAwesomeIcons.chevronRight,
                size: 12, color: color.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _circleButton({required BuildContext context, required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        shape: BoxShape.circle,
      ),
      child: Center(child: child),
    );
  }

  Widget _buildRoomFilter(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        GestureDetector(
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RoomsManagementPage()),
            );
            await _ctrl.loadLocations();
          },
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF27272A) : Colors.white,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(Icons.add, size: 18, color: isDark ? Colors.white70 : Colors.black87),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_rooms.length, (i) {
                final isSelected = _selectedRoom == i;
                return GestureDetector(
                  onTap: () => setState(() => _selectedRoom = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFE3E3E3)),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Text(
                      _rooms[i],
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white70 : const Color(0xFF71717A)),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

    Widget _buildWeatherCard(BuildContext context) {
  final weather = _weatherData;

  final date        = weather?.formattedDate   ?? 'Loading...';
  final description = weather?.description     ?? 'Cloudy';
  final detail      = weather?.descriptionDetail ?? 'Limited Sunshine';
  final temp        = weather != null
      ? '${weather.tempC.toStringAsFixed(0)}°C'
      : '24°C'; 

  return Stack(
    clipBehavior: Clip.none,
    children: [
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.only(
            left: 110, right: 24, top: 16, bottom: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF8BF82), Color(0xFFFF9523)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(date,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w400)),
                  const SizedBox(height: 2),
                  Text(description,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700)),
                  Text(detail,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w400)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(temp,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      Positioned(
        left: -1,
        bottom: -8,
        child: Image.asset('assets/images/cloudsun.png',
            width: 120, height: 120, fit: BoxFit.contain),
      ),
    ],
  );
}

  Widget _buildEnergyCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final today     = _energyToday;
    final yesterday = _energyYesterday;

    final diff = yesterday > 0
        ? ((today - yesterday) / yesterday * 100).toStringAsFixed(0)
        : '0';
    final isDown = today < yesterday;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EnergyPage()),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: double.infinity,
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Today's Energy Usage",
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xCC18181B)),
                      ),
                      const SizedBox(height: 10),
                      RichText(
                        text: TextSpan(children: [
                          TextSpan(
                            text: today.toStringAsFixed(2),
                            style: const TextStyle(
                                fontFamily: 'PlusJakartaSans',
                                fontWeight: FontWeight.w600,
                                fontSize: 36,
                                color: Color(0xFF34C759)),
                          ),
                          TextSpan(
                            text: ' kWh',
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                                fontSize: 17,
                                color: isDark ? Colors.white60 : const Color(0x9918181B)),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          FaIcon(
                            isDown
                                ? FontAwesomeIcons.batteryQuarter
                                : FontAwesomeIcons.batteryFull,
                            size: 14,
                            color: isDown
                                ? const Color(0xCCFB0004)
                                : const Color(0xFF34C759),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${isDown ? "" : "+"}$diff%',
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isDown
                                    ? const Color(0xFFFC0004)
                                    : const Color(0xFF34C759)),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'vs yesterday',
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: isDark ? Colors.white60 : const Color(0x9918181B)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildMiniStat(
                            icon: FontAwesomeIcons.bolt,
                            value: '${_energyData.volt.toStringAsFixed(0)} V',
                            color: const Color(0xFFFFCC00),
                          ),
                          const SizedBox(width: 12),
                          _buildMiniStat(
                            icon: FontAwesomeIcons.plug,
                            value: '${_energyData.powerKw.toStringAsFixed(2)} kW',
                            color: const Color(0xFFFF6B35),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 110),
              ],
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(28),
                  bottomRight: Radius.circular(28)),
              child: Image.asset(
                'assets/images/house_energy.png',
                width: 170,
                height: 110,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -1.25),
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _energyData.deviceOnline
                    ? const Color(0xFF34C759).withValues(alpha: 0.15)
                    : Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _energyData.deviceOnline
                          ? const Color(0xFF34C759)
                          : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _energyData.deviceOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: _energyData.deviceOnline
                          ? const Color(0xFF34C759)
                          : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat({
    required FaIconData icon,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FaIcon(icon, size: 10, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildDevicesHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text('Devices',
                style: AppTypography.headingSmall.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: cs.onSurface,
                )),
            if (_ctrl.hasItems) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_ctrl.items.where((i) {
                    if (i.isSwitch) return i.isOn;
                    if (i.isDimmer) return (i.numericValue ?? 0) > 0;
                    if (i.type == 'Player') return i.state?.toUpperCase() == 'PLAY';
                    if (i.isContact) return i.state?.toUpperCase() == 'OPEN';
                    if (i.isRollershutter) return (i.numericValue ?? 100) < 100;
                    if (i.isColor) return (i.hsbColor?.value ?? 0) > 0;
                    return false;
                  }).length} On',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
        GestureDetector(
          onTap: () {
            _ctrl.loadItems();
          },
          child: Text('Refresh',
              style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textMuted, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  // ── Ringkasan AC (kartu ringkas di Home) ──────────────────────
  // Home hanya menampilkan nama, suhu ruang, mode, setpoint, dan power.
  // Kontrol lengkap (mode, fan, +/-) ada di halaman detail.
  Widget _buildAcSummaryCard(BuildContext context, OHAcUnit unit) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOn = _ctrl.getItem(unit.powerItem)?.isOn ?? false;
    final setTemp = unit.setTempItem != null
        ? _ctrl.getItem(unit.setTempItem!)?.numericValue
        : null;
    final roomTemp = unit.roomTempItem != null
        ? _ctrl.getItem(unit.roomTempItem!)?.numericValue
        : null;
    final modeText = unit.stateModeItem != null
        ? _ctrl.getItem(unit.stateModeItem!)?.state
        : null;

    final parts = <String>[
      if (roomTemp != null) 'Ruang ${roomTemp.toStringAsFixed(1)}°C',
      if (_ohHasValue(modeText)) modeText!,
    ];

    final fg = isOn ? Colors.white : (isDark ? Colors.white.withValues(alpha: 0.8) : AppColors.textPrimary80);
    final muted = isOn ? Colors.white70 : (isDark ? Colors.white60 : AppColors.textSubtle);

    return GestureDetector(
      onTap: () => _showAcDetail(context, unit),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: isOn ? AppColors.primary : (isDark ? const Color(0xFF27272A) : Colors.white),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            FaIcon(FontAwesomeIcons.wind, size: 22, color: fg),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(unit.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: fg)),
                  const SizedBox(height: 2),
                  Text(parts.isEmpty ? 'Air Conditioner' : parts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'Inter', fontSize: 12, color: muted)),
                ],
              ),
            ),
            if (setTemp != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text('${setTemp.toInt()}°',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 26,
                        color: fg)),
              ),
            Switch(
              value: isOn,
              onChanged: (v) =>
                  _ctrl.sendCommand(unit.powerItem, v ? 'ON' : 'OFF'),
              activeThumbColor: Colors.white,
              activeTrackColor: Colors.white38,
            ),
            FaIcon(FontAwesomeIcons.chevronRight, size: 12, color: muted),
          ],
        ),
      ),
    );
  }

  /// Halaman detail AC: power, mode, setpoint, suhu aktual, fan speed.
  /// IP/diagnostik ada di bagian "Informasi teknis" (tertutup default).
  void _showAcDetail(BuildContext context, OHAcUnit unit) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => ListenableBuilder(
          listenable: _ctrl,
          builder: (ctx, __) {
            final techItems = <String?>[
              unit.powerItem, unit.modeItem, unit.fanItem, unit.setTempItem,
              unit.roomTempItem, unit.roomHumidityItem, unit.statusItem,
              unit.stateModeItem, unit.stateFanItem,
            ].whereType<String>().map(_ctrl.getItem).whereType<OpenHABItem>().toList();

            return _detailShell(
              ctx,
              isDark: isDark,
              scrollController: scrollController,
              title: unit.label,
              subtitle: 'Air Conditioner',
              children: [
                _buildAcCard(ctx, unit),
                const SizedBox(height: 16),
                _buildTechInfo(ctx, techItems),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Halaman detail perangkat: semua fungsi (kontrol + nilai) milik satu
  /// perangkat, dengan informasi teknis dipisah di bagian bawah.
  void _showEquipmentDetail(BuildContext context, String key) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            final acNames = _acItemNames;
            final items = _ctrl.items.where((i) =>
                _isSupportedItem(i) &&
                !acNames.contains(i.name) &&
                (i.roomGuess.isNotEmpty ? i.roomGuess : 'Lainnya') == key).toList();
            final active = items.where(_itemIsActive).length;

            return _detailShell(
              ctx,
              isDark: isDark,
              scrollController: scrollController,
              title: key,
              subtitle: '${items.length} fungsi · $active aktif',
              children: [
                ..._buildEquipmentSections(ctx, items),
                const SizedBox(height: 16),
                _buildTechInfo(ctx, items),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Daftar ringkas satu baris per fungsi (bukan kartu besar), dipecah:
  /// "Kontrol utama" selalu terbuka; switch alarm/deteksi dilipat
  /// supaya tidak memenuhi layar.
  List<Widget> _buildEquipmentSections(
      BuildContext context, List<OpenHABItem> items) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool isAlarm(OpenHABItem i) {
      final l = i.label.toLowerCase();
      return i.isSwitch && (l.contains('alarm') || l.contains('motion') || l.contains('detect'));
    }

    final main = items.where((i) => !isAlarm(i)).toList();
    final alarms = items.where(isAlarm).toList();

    Widget panel(List<Widget> rows) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF27272A) : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(children: rows),
        );

    Widget rowsOf(List<OpenHABItem> list) => panel([
          for (var i = 0; i < list.length; i++) ...[
            _CompactItemRow(item: list[i], ctrl: _ctrl),
            if (i < list.length - 1)
              Divider(height: 1, indent: 60,
                  color: isDark ? Colors.white10 : Colors.black12),
          ],
        ]);

    return [
      if (main.isNotEmpty) ...[
        Text('Kontrol utama',
            style: TextStyle(
                fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13,
                color: isDark ? Colors.white60 : const Color(0xFF71717A))),
        const SizedBox(height: 8),
        rowsOf(main),
      ],
      if (alarms.isNotEmpty) ...[
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF27272A) : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Text(
                  'Alarm & deteksi (${alarms.where((i) => i.isOn).length}/${alarms.length} aktif)',
                  style: TextStyle(
                      fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14,
                      color: isDark ? Colors.white.withValues(alpha: 0.85) : const Color(0xCC18181B))),
              children: [rowsOf(alarms)],
            ),
          ),
        ),
      ],
    ];
  }

  Widget _detailShell(
    BuildContext context, {
    required bool isDark,
    required ScrollController scrollController,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: isDark ? Colors.white : const Color(0xFF18181B))),
                    Text(subtitle,
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: isDark ? Colors.white60 : const Color(0xFF71717A))),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close,
                    color: isDark ? Colors.white70 : Colors.black54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  /// Bagian "Informasi teknis" — tertutup secara default supaya tidak
  /// mendominasi. Isinya nama Item, tipe, dan state mentah untuk
  /// diagnostik. (IP address ditambahkan di sini begitu tersedia dari
  /// Thing — lihat catatan di bawah.)
  Widget _buildTechInfo(BuildContext context, List<OpenHABItem> items) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white60 : const Color(0xFF71717A);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: FaIcon(FontAwesomeIcons.screwdriverWrench, size: 14, color: muted),
          title: Text('Informasi teknis',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: isDark ? Colors.white.withValues(alpha: 0.85) : const Color(0xCC18181B))),
          children: [
            for (final i in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text('${i.name}\n${i.type}',
                          style: TextStyle(
                              fontFamily: 'monospace', fontSize: 10, color: muted)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: Text(i.state ?? '-',
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: 'monospace', fontSize: 10, color: muted)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcCard(BuildContext context, OHAcUnit unit) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
      child: Column(
        children: [
          _buildAcTitleRow(context, unit),
          const SizedBox(height: 12),
          _buildAcInfoRow(context, unit),
          const SizedBox(height: 8),
          _buildAcTemperatureControl(context, unit),
          const SizedBox(height: 16),
          _buildAcModeFanSelectors(context, unit),
        ],
      ),
    );
  }

  Widget _buildAcTitleRow(BuildContext context, OHAcUnit unit) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final power = _ctrl.getItem(unit.powerItem);
    final isOn = power?.isOn ?? false;
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Air Conditioner',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: isDark ? Colors.white.withValues(alpha: 0.8) : AppColors.textPrimary80)),
            const SizedBox(height: 2),
            Text(unit.label,
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: isDark ? Colors.white60 : AppColors.textSubtle)),
          ],
        ),
        const Spacer(),
        Switch(
          value: isOn,
          onChanged: (value) {
            _ctrl.sendCommand(unit.powerItem, value ? 'ON' : 'OFF');
          },
          activeThumbColor: AppColors.primary,
        ),
      ],
    );
  }

  /// Baris info tambahan: suhu ruang aktual & humidity (kalau Item-nya
  /// ada), plus status device mentah dari MQTT LWT. Baris ini otomatis
  /// nyusut/hilang kalau Item-nya nggak ke-link di openHAB.
  /// openHAB pakai literal string "NULL"/"UNDEF" buat Item yang belum
  /// pernah dapet update state — itu bukan data valid, jadi harus
  /// dianggap "belum ada" di UI, bukan ditampilkan mentah-mentah.
  bool _ohHasValue(String? s) =>
      s != null && s.isNotEmpty && s.toUpperCase() != 'NULL' && s.toUpperCase() != 'UNDEF';

  Widget _buildAcInfoRow(BuildContext context, OHAcUnit unit) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final roomTemp = unit.roomTempItem != null
        ? _ctrl.getItem(unit.roomTempItem!)?.numericValue
        : null;
    final roomHumidity = unit.roomHumidityItem != null
        ? _ctrl.getItem(unit.roomHumidityItem!)?.numericValue
        : null;
    final status =
        unit.statusItem != null ? _ctrl.getItem(unit.statusItem!)?.state : null;
    final chips = <Widget>[];
    if (roomTemp != null) {
      chips.add(_acInfoChip(FontAwesomeIcons.temperatureHalf,
          '${roomTemp.toStringAsFixed(1)}°C', isDark));
    }
    if (roomHumidity != null) {
      chips.add(_acInfoChip(
          FontAwesomeIcons.droplet, '${roomHumidity.toStringAsFixed(0)}%', isDark));
    }
    if (_ohHasValue(status)) {
      final isOnline = status!.toLowerCase() == 'online';
      chips.add(_acInfoChip(
          isOnline ? FontAwesomeIcons.circleCheck : FontAwesomeIcons.circleExclamation,
          status,
          isDark,
          color: isOnline ? Colors.green : Colors.redAccent));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 4,
      children: chips,
    );
  }

  Widget _acInfoChip(FaIconData icon, String text, bool isDark, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FaIcon(icon,
            size: 12, color: color ?? (isDark ? Colors.white70 : AppColors.textPrimary)),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: color ?? (isDark ? Colors.white60 : AppColors.textMuted))),
      ],
    );
  }

  Widget _buildAcTemperatureControl(BuildContext context, OHAcUnit unit) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final setTempItem = unit.setTempItem;
    final currentTemp =
        (setTempItem != null ? _ctrl.getItem(setTempItem)?.numericValue : null) ?? 24;

    void changeTemp(double delta) {
      if (setTempItem == null) return;
      final newTemp = (currentTemp + delta).clamp(16.0, 30.0);
      _ctrl.setTemperature(setTempItem, newTemp);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: setTempItem == null ? null : () => changeTemp(-1),
          child: _tempControlButton(
              context: context,
              child: Icon(Icons.remove,
                  size: 20, color: isDark ? Colors.white70 : AppColors.textPrimary)),
        ),
        const SizedBox(width: 24),
        Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentTemp.toInt().toString(),
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 65,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white.withValues(alpha: 0.8) : AppColors.textPrimary80,
                      height: 1),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('°',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 24,
                          fontWeight: FontWeight.w400,
                          color: isDark ? Colors.white60 : AppColors.textMuted)),
                ),
              ],
            ),
            Text('Celsius',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: isDark ? Colors.white.withValues(alpha: 0.8) : AppColors.textPrimary80)),
          ],
        ),
        const SizedBox(width: 24),
        GestureDetector(
          onTap: setTempItem == null ? null : () => changeTemp(1),
          child: _tempControlButton(
              context: context,
              child: Icon(Icons.add,
                  size: 20, color: isDark ? Colors.white70 : AppColors.textPrimary)),
        ),
      ],
    );
  }

  Widget _tempControlButton({required BuildContext context, required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3F3F46) : Colors.grey.shade100,
        shape: BoxShape.circle,
      ),
      child: Center(child: child),
    );
  }

  /// Selector Mode & Fan — dikontrol lewat channel Number (command) dan
  /// ditampilkan pakai channel String "State" (nama mode/fan asli dari
  /// device, bukan cuma angka 1-5/1-4 mentah). Range 1-5 (mode) dan 1-4
  /// (fan) sesuai definisi channel di Thing template MQTT AC ini — kalau
  /// ada unit AC lain dengan range beda, sesuaikan konstanta ini.
  Widget _buildAcModeFanSelectors(BuildContext context, OHAcUnit unit) {
    if (unit.modeItem == null && unit.fanItem == null) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        if (unit.modeItem != null)
          _acCycleSelector(
            context: context,
            icon: FontAwesomeIcons.wind,
            label: 'Mode',
            commandItem: unit.modeItem!,
            stateItem: unit.stateModeItem,
            min: 1,
            max: 5,
          ),
        if (unit.modeItem != null && unit.fanItem != null)
          const SizedBox(height: 10),
        if (unit.fanItem != null)
          _acCycleSelector(
            context: context,
            icon: FontAwesomeIcons.fan,
            label: 'Fan',
            commandItem: unit.fanItem!,
            stateItem: unit.stateFanItem,
            min: 1,
            max: 4,
          ),
      ],
    );
  }

  Widget _acCycleSelector({
    required BuildContext context,
    required FaIconData icon,
    required String label,
    required String commandItem,
    required String? stateItem,
    required int min,
    required int max,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentNum = _ctrl.getItem(commandItem)?.numericValue?.round() ?? min;
    final stateText = stateItem != null ? _ctrl.getItem(stateItem)?.state : null;
    final displayText =
        _ohHasValue(stateText) ? stateText! : '$label $currentNum';

    void cycle(int delta) {
      var next = currentNum + delta;
      if (next > max) next = min;
      if (next < min) next = max;
      _ctrl.sendCommand(commandItem, next.toString());
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3F3F46) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(49)),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => cycle(-1),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.chevron_left, size: 20),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FaIcon(icon,
                    size: 14, color: isDark ? Colors.white70 : AppColors.textPrimary),
                const SizedBox(width: 8),
                Text(displayText,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: isDark ? Colors.white.withValues(alpha: 0.85) : AppColors.textPrimary80)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => cycle(1),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.chevron_right, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceGrid(BuildContext context) {
    if (_ctrl.isLoading) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_ctrl.error != null && !_ctrl.hasItems) {
      return _buildErrorState(context);
    }

    if (_ctrl.isConnected && !_ctrl.hasItems) {
      return _buildEmptyState(context);
    }

    if (_ctrl.hasItems) {
      final displayItems = _filteredItems;
      if (displayItems.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Tidak ada device di ruangan ini',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textMuted),
            ),
          ),
        );
      }

      // Satu kartu per perangkat. Perangkat dengan banyak fungsi tampil
      // sebagai ringkasan yang bisa diklik; perangkat dengan satu fungsi
      // tetap memakai kartu kontrol langsung.
      final groups = _groupByEquipment(displayItems).entries.toList();

      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: ResponsiveUtils.gridColumns(context),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.1,
        ),
        itemCount: groups.length,
        itemBuilder: (context, i) {
          final entry = groups[i];
          if (entry.value.length == 1) {
            final item = entry.value.first;
            return _OpenHABDeviceCard(
              item: item,
              ctrl: _ctrl,
              onToggle: () => _ctrl.toggleItem(item.name),
            );
          }
          return _EquipmentSummaryCard(
            name: entry.key,
            items: entry.value,
            ctrl: _ctrl,
            onOpen: () => _showEquipmentDetail(context, entry.key),
          );
        },
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: ResponsiveUtils.gridColumns(context),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.95,
      ),
      itemCount: _dummyDevices.length,
      itemBuilder: (context, i) =>
          _DummyDeviceCard(device: _dummyDevices[i]),
    );
  }

  /// Kamera muncul otomatis dari Things binding IP Camera (thingTypeUID
  /// diawali "ipcamera:") — TANPA perlu bikin Item/set category manual,
  /// mirip pola MQTT: app selalu ngomong ke openHAB, bukan ke sumber
  /// aslinya (di sini: server file milik binding IP Camera).
  Widget _buildCameraSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cameras = _ctrl.cameraThings;

    // Grup diambil dari field "location" Thing (diisi lewat openHAB UI,
    // sama seperti field yang dipakai openHAB sendiri buat kelompokin
    // Things). Thing tanpa location dikelompokkan ke 'Lainnya'.
    final groups = <String>{
      for (final t in cameras) _cameraGroupLabel(t),
    }.toList()
      ..sort();

    if (!groups.contains(_selectedCameraGroup) &&
        _selectedCameraGroup != 'Semua') {
      _selectedCameraGroup = 'Semua';
    }

    final visibleCameras = _selectedCameraGroup == 'Semua'
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
            if (groups.length > 1) _buildCameraGroupChip(groups),
          ],
        ),
        const SizedBox(height: 8),
        ...visibleCameras.map((thing) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CameraThingCard(thing: thing, ctrl: _ctrl),
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

  Widget _buildErrorState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.red.shade900.withValues(alpha: 0.2) : Colors.red.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.wifi_off,
              color: isDark ? Colors.red.shade300 : Colors.red, size: 32),
          const SizedBox(height: 8),
          Text(
            _ctrl.error ?? 'Gagal terhubung ke openHAB',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: isDark ? Colors.red.shade300 : Colors.red),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              final config = context.read<InstallationProvider>().config;
              if (config != null) {
                _ctrl.initializeWithConfig(config);
              }
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Coba Lagi',
                  style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
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
      child: Column(
        children: [
          Icon(Icons.devices_other,
              color: isDark ? Colors.white38 : Colors.grey.shade400, size: 40),
          const SizedBox(height: 10),
          Text('Belum ada device',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xCC18181B))),
          const SizedBox(height: 6),
          Text(
            'Tambahkan Items di openHAB dashboard\nkemudian device akan muncul di sini.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _ctrl.loadItems(),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Refresh',
                  style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  static const _dummyDevices = [
    _DummyDevice(
        icon: FontAwesomeIcons.lightbulb,
        name: 'Smart Lamp',
        room: 'Office',
        count: '3 device',
        isOn: true),
    _DummyDevice(
        icon: FontAwesomeIcons.temperatureHalf,
        name: 'Thermostat',
        room: 'Bedroom',
        count: '1 device',
        isOn: false),
    _DummyDevice(
        icon: FontAwesomeIcons.tv,
        name: 'Android TV',
        room: 'Living Room',
        count: '1 device',
        isOn: false),
    _DummyDevice(
        icon: FontAwesomeIcons.volumeHigh,
        name: 'HomePod',
        room: 'Office',
        count: '1 device',
        isOn: true),
  ];

  Widget _buildEnergySavingCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: const Color(0xFF353F3F),
          borderRadius: BorderRadius.circular(28)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned(
              right: 10,
              bottom: -5,
              child: FaIcon(FontAwesomeIcons.leaf,
                  size: 120, color: Colors.white.withValues(alpha: 0.08)),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14)),
                    child: const Center(
                        child: Icon(Icons.auto_awesome,
                            color: Color(0xFF0D0D0D), size: 22)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Energy Saving',
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: Color(0xFFF5F5F5))),
                        const SizedBox(height: 4),
                        Text(
                          'Freq: ${_energyData.freq.toStringAsFixed(1)} Hz · '
                          'Yesterday: ${_energyYesterday.toStringAsFixed(2)} kWh · '
                          'Status: ${_energyData.status}',
                          style: const TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w400,
                              fontSize: 12,
                              color: Color(0xFFCDCDCD),
                              height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  const navItems = [
    _NavItem(icon: FontAwesomeIcons.house, label: 'Home'),
    _NavItem(icon: FontAwesomeIcons.bolt, label: 'Energy'),
    _NavItem(icon: FontAwesomeIcons.mapLocationDot, label: 'Floorplan'),
    _NavItem(icon: FontAwesomeIcons.gear, label: 'Settings'),
  ];

  final inactiveColor = isDark ? Colors.white38 : Colors.black38;

  return Container(
    padding: EdgeInsets.fromLTRB(
      16,
      10,
      16,
      10 + MediaQuery.of(context).padding.bottom,
    ),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF27272A) : Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
          blurRadius: 16,
          offset: const Offset(0, -4),
        )
      ],
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: List.generate(navItems.length, (i) {
        final isSelected = _selectedTab == i;
        return GestureDetector(
          onTap: () {
            if (i == 0) {
              // Sudah/kembali di Home — pastikan stack bersih ke root.
              Navigator.popUntil(context, (route) => route.isFirst);
              setState(() => _selectedTab = i);
              return;
            }
            Navigator.popUntil(context, (route) => route.isFirst);
            if (i == 1) {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const EnergyPage()));
              return;
            }
            if (i == 2) {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const FloorPlanPage()));
              return;
            }
            if (i == 3) {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()));
              return;
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(navItems[i].icon,
                  size: 20,
                  color: isSelected ? AppColors.primary : inactiveColor),
              const SizedBox(height: 4),
              Text(navItems[i].label,
                  style: AppTypography.bodySmall.copyWith(
                    fontSize: 11,
                    color: isSelected ? AppColors.primary : inactiveColor,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  )),
            ],
          ),
        );
      }),
    ),
  );
}
}

/// Status aktif sebuah Item — logika sama dengan _OpenHABDeviceCard._isActive,
/// dipakai juga untuk menghitung ringkasan per perangkat.
bool _itemIsActive(OpenHABItem item) {
  if (item.isSwitch) return item.isOn;
  if (item.isDimmer) return (item.numericValue ?? 0) > 0;
  if (item.isColor) {
    final parts = (item.state ?? '').split(',');
    return parts.length == 3 && (double.tryParse(parts[2].trim()) ?? 0) > 0;
  }
  if (item.type == 'Player') return item.state?.toUpperCase() == 'PLAY';
  if (item.isContact) return item.state?.toUpperCase() == 'OPEN';
  if (item.isRollershutter) return (item.numericValue ?? 100) < 100;
  return false;
}

FaIconData _iconForKey(String? key) {
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

/// Baris ringkas satu fungsi di halaman detail perangkat: ikon, nama,
/// lalu switch (untuk Switch) atau nilai + panah (untuk kontrol lain).
class _CompactItemRow extends StatelessWidget {
  final OpenHABItem item;
  final OpenHABController ctrl;
  const _CompactItemRow({required this.item, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = _OpenHABDeviceCard(
      item: item,
      ctrl: ctrl,
      onToggle: () => ctrl.toggleItem(item.name),
    );
    final active = card._isActive;
    final muted = isDark ? Colors.white60 : const Color(0xFF71717A);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => card._onTap(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primary
                    : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5)),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: FaIcon(card._icon, size: 13,
                    color: active ? Colors.white : muted),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 14,
                      color: isDark ? Colors.white.withValues(alpha: 0.85) : const Color(0xCC18181B))),
            ),
            if (item.isSwitch)
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: item.isOn,
                  onChanged: (_) => ctrl.toggleItem(item.name),
                  activeThumbColor: AppColors.primary,
                ),
              )
            else ...[
              Text(card._stateLabel,
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: muted)),
              const SizedBox(width: 6),
              FaIcon(FontAwesomeIcons.chevronRight, size: 10, color: muted),
            ],
          ],
        ),
      ),
    );
  }
}

/// Kartu ringkasan satu perangkat (Equipment) yang punya banyak fungsi:
/// nama, ikon, jumlah fungsi aktif, dan satu kontrol utama (power).
/// Tap kartu membuka halaman detail berisi semua kontrol dan nilai.
class _EquipmentSummaryCard extends StatelessWidget {
  final String name;
  final List<OpenHABItem> items;
  final OpenHABController ctrl;
  final VoidCallback onOpen;

  const _EquipmentSummaryCard({
    required this.name,
    required this.items,
    required this.ctrl,
    required this.onOpen,
  });

  static const _iconPriority = [
    'ac', 'tv', 'lightbulb', 'speaker', 'fan', 'camera', 'door', 'temperature',
  ];

  FaIconData get _icon {
    for (final k in _iconPriority) {
      if (items.any((i) => i.iconKey == k)) return _iconForKey(k);
    }
    return _iconForKey(items.first.iconKey);
  }

  /// Kontrol utama: Switch yang labelnya mengandung "power", atau
  /// Switch pertama kalau tidak ada.
  OpenHABItem? get _primarySwitch {
    final switches = items.where((i) => i.isSwitch).toList();
    if (switches.isEmpty) return null;
    return switches.firstWhere(
      (i) => i.label.toLowerCase().contains('power'),
      orElse: () => switches.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = _primarySwitch;
    final activeCount = items.where(_itemIsActive).length;
    final isActive = primary != null ? primary.isOn : activeCount > 0;

    final cardColor = isActive
        ? AppColors.primary
        : (isDark ? const Color(0xFF27272A) : Colors.white);
    final fg = isActive
        ? Colors.white
        : (isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xCC18181B));
    final muted = isActive
        ? Colors.white70
        : (isDark ? Colors.white60 : const Color(0xFF71717A));
    final pillBg = isActive
        ? Colors.white.withValues(alpha: 0.25)
        : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0x33787878));

    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: FaIcon(_icon, size: 22, color: fg),
                ),
                if (primary != null)
                  Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: primary.isOn,
                      onChanged: (_) => ctrl.toggleItem(primary.name),
                      activeThumbColor: Colors.white,
                      activeTrackColor: Colors.white38,
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: fg,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${items.length} fungsi · $activeCount aktif',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: muted,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: pillBg,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FaIcon(FontAwesomeIcons.chevronRight, size: 8, color: fg),
                  const SizedBox(width: 4),
                  Text('Lihat detail',
                      style: TextStyle(
                          fontFamily: 'Inter', fontSize: 8, color: fg)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenHABDeviceCard extends StatelessWidget {
  final OpenHABItem item;
  final VoidCallback onToggle;
  final OpenHABController ctrl;

  const _OpenHABDeviceCard({
    required this.item,
    required this.onToggle,
    required this.ctrl,
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
      case 'color':       return FontAwesomeIcons.palette;
      case 'remote':      return FontAwesomeIcons.gamepad;
      case 'command':     return FontAwesomeIcons.terminal;
      case 'player':      return FontAwesomeIcons.play;
      default:            return FontAwesomeIcons.powerOff;
    }
  }

  /// Parse brightness (komponen ke-3) dari state HSB "H,S,B" milik Item
  /// tipe Color. Dipakai untuk state label & status aktif — mengikuti
  /// format state Color item standar openHAB.
  double? _colorBrightness(String? state) {
    if (state == null) return null;
    final parts = state.split(',');
    if (parts.length != 3) return null;
    return double.tryParse(parts[2].trim());
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
    if (item.isColor) {
      final b = _colorBrightness(item.state);
      return (b != null && b > 0) ? '${b.toInt()}%' : 'Off';
    }
    if (item.isContact) {
      return item.state?.toUpperCase() == 'OPEN' ? 'Terbuka' : 'Tertutup';
    }
    if (item.isRollershutter) {
      final v = item.numericValue;
      return v != null ? '${v.toInt()}%' : '-';
    }
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
    if (item.isColor) return (_colorBrightness(item.state) ?? 0) > 0;
    if (item.type == 'Player') return item.state?.toUpperCase() == 'PLAY';
    // Contact (sensor pintu/jendela): OPEN dianggap "aktif" — konsisten
    // dengan konvensi status openHAB.
    if (item.isContact) return item.state?.toUpperCase() == 'OPEN';
    // Rollershutter: konvensi openHAB posisi 0=terbuka, 100=tertutup penuh.
    if (item.isRollershutter) return (item.numericValue ?? 100) < 100;
    // Camera/Image: read-only, tidak ada konsep on/off.
    return false;
  }

  void _onTap(BuildContext context) {
    if (item.isDimmer) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _DimmerSheet(item: item, ctrl: ctrl),
      );
    } else if (item.isColor) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _ColorSheet(item: item, ctrl: ctrl),
      );
    } else if (item.type == 'Player') {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _PlayerSheet(item: item, ctrl: ctrl),
      );
    } else if (item.isRollershutter) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _RollershutterSheet(item: item, ctrl: ctrl),
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
      onToggle();
    } else if (item.isCamera) {
      showDialog(
        context: context,
        builder: (_) => _CameraPlayerDialog(item: item, ctrl: ctrl),
      );
    } else if (item.isImage) {
      showDialog(
        context: context,
        builder: (_) => _CameraViewerDialog(item: item, ctrl: ctrl),
      );
    }
    // Contact: sensor read-only, sengaja tidak ada aksi tap.
  }

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
                FaIcon(_icon, size: 22, color: iconColor),
                Text(
                  _stateLabel,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                    fontSize: 11,
                    color: mutedColor,
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
            if (item.isDimmer || item.type == 'Player' || item.isColor || item.isRollershutter ||
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
                      item.isColor
                          ? FontAwesomeIcons.palette
                          : item.isDimmer
                              ? FontAwesomeIcons.sliders
                              : item.isRollershutter
                                  ? FontAwesomeIcons.tableColumns
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
                      (item.isDimmer || item.isColor || item.isString)
                          ? 'Tap to adjust'
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

class _DimmerSheet extends StatefulWidget {
  final OpenHABItem item;
  final OpenHABController ctrl;
  const _DimmerSheet({required this.item, required this.ctrl});

  @override
  State<_DimmerSheet> createState() => _DimmerSheetState();
}

class _DimmerSheetState extends State<_DimmerSheet> {
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
                  color: _isOn
                      ? AppColors.primary
                      : (isDark ? const Color(0xFF3F3F46) : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: FaIcon(FontAwesomeIcons.sliders,
                      size: 20,
                      color: _isOn ? Colors.white : (isDark ? Colors.white60 : Colors.grey)),
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
              Switch(
                value: _isOn,
                onChanged: (v) {
                  setState(() => _value = v ? 50 : 0);
                  widget.ctrl.sendCommand(widget.item.name, v ? '50' : '0');
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
              color: _isOn ? AppColors.primary : (isDark ? Colors.white38 : Colors.grey.shade400),
            ),
          ),
          const SizedBox(height: 8),
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
              value: _value,
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: (v) => setState(() => _value = v),
              onChangeEnd: (v) =>
                  widget.ctrl.sendCommand(widget.item.name, v.toInt().toString()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0%', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: isDark ? Colors.white60 : const Color(0xFF71717A))),
                Text('100%', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: isDark ? Colors.white60 : const Color(0xFF71717A))),
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
                  widget.ctrl.sendCommand(widget.item.name, preset.toString());
                },
                child: Container(
                  width: 60, height: 36,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? const Color(0xFF3F3F46) : Colors.grey.shade100),
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
                            : (isDark ? Colors.white70 : const Color(0xFF71717A)),
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

class _ColorSheet extends StatefulWidget {
  final OpenHABItem item;
  final OpenHABController ctrl;
  const _ColorSheet({required this.item, required this.ctrl});

  @override
  State<_ColorSheet> createState() => _ColorSheetState();
}

class _ColorSheetState extends State<_ColorSheet> {
  late double _hue;
  late double _saturation;
  late double _brightness;

  @override
  void initState() {
    super.initState();
    final hsb = _parseHsb(widget.item.state);
    _hue        = hsb[0];
    _saturation = hsb[1];
    _brightness = hsb[2];
  }

  /// Parse state HSB "H,S,B" milik Item tipe Color (format standar
  /// openHAB). Fallback ke putih penuh kalau state belum ada/tidak valid.
  List<double> _parseHsb(String? state) {
    if (state == null) return [0, 0, 100];
    final parts = state.split(',');
    if (parts.length != 3) return [0, 0, 100];
    final h = double.tryParse(parts[0].trim()) ?? 0;
    final s = double.tryParse(parts[1].trim()) ?? 0;
    final b = double.tryParse(parts[2].trim()) ?? 100;
    return [h.clamp(0, 360), s.clamp(0, 100), b.clamp(0, 100)];
  }

  bool get _isOn => _brightness > 0;

  Color get _previewColor => HSVColor.fromAHSV(
        1.0, _hue, _saturation / 100, _brightness > 0 ? 1.0 : 0.25,
      ).toColor();

  /// Kirim command dalam format HSBType openHAB: "H,S,B" (bukan ON/OFF
  /// atau angka biasa — command mapping khusus tipe Color).
  void _sendHsb() {
    final cmd = '${_hue.toStringAsFixed(0)},'
        '${_saturation.toStringAsFixed(0)},'
        '${_brightness.toStringAsFixed(0)}';
    widget.ctrl.sendCommand(widget.item.name, cmd);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: _previewColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isDark ? Colors.white24 : Colors.black12),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.item.label, style: TextStyle(
                    fontFamily: 'Inter', fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xCC18181B))),
                Text(widget.item.roomGuess, style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13,
                    color: isDark ? Colors.white60 : const Color(0xFF71717A))),
              ],
            )),
            Switch(
              value: _isOn,
              onChanged: (v) {
                setState(() => _brightness = v ? (_brightness > 0 ? _brightness : 100) : 0);
                _sendHsb();
              },
              activeThumbColor: AppColors.primary,
            ),
          ]),
          const SizedBox(height: 28),

          _buildGradientSlider(
            context,
            label: 'Warna (Hue)',
            value: _hue,
            max: 360,
            colors: const [
              Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
              Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000),
            ],
            onChanged: (v) => setState(() => _hue = v),
            onChangeEnd: (_) => _sendHsb(),
          ),
          const SizedBox(height: 18),
          _buildGradientSlider(
            context,
            label: 'Saturasi',
            value: _saturation,
            max: 100,
            colors: [Colors.white, HSVColor.fromAHSV(1, _hue, 1, 1).toColor()],
            onChanged: (v) => setState(() => _saturation = v),
            onChangeEnd: (_) => _sendHsb(),
          ),
          const SizedBox(height: 18),
          _buildGradientSlider(
            context,
            label: 'Brightness',
            value: _brightness,
            max: 100,
            colors: [Colors.black, HSVColor.fromAHSV(1, _hue, _saturation / 100, 1).toColor()],
            onChanged: (v) => setState(() => _brightness = v),
            onChangeEnd: (_) => _sendHsb(),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientSlider(
    BuildContext context, {
    required String label,
    required double value,
    required double max,
    required List<Color> colors,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
            fontSize: 13, color: isDark ? Colors.white70 : const Color(0xFF71717A))),
        Text(value.toInt().toString(), style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
            fontSize: 13, color: isDark ? Colors.white : const Color(0xFF18181B))),
      ]),
      const SizedBox(height: 6),
      Container(
        height: 36,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(colors: colors),
        ),
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.transparent,
            inactiveTrackColor: Colors.transparent,
            thumbColor: Colors.white,
            overlayColor: Colors.white.withValues(alpha: 0.2),
            trackHeight: 36,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
          ),
          child: Slider(
            value: value.clamp(0, max),
            min: 0,
            max: max,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ),
    ]);
  }
}


class _RollershutterSheet extends StatefulWidget {
  final OpenHABItem item;
  final OpenHABController ctrl;
  const _RollershutterSheet({required this.item, required this.ctrl});

  @override
  State<_RollershutterSheet> createState() => _RollershutterSheetState();
}

class _RollershutterSheetState extends State<_RollershutterSheet> {
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
                _RollerButton(
                  icon: FontAwesomeIcons.arrowUp,
                  label: 'Buka',
                  isDark: isDark,
                  onTap: () {
                    setState(() => _position = 0);
                    widget.ctrl.sendCommand(widget.item.name, 'UP');
                  },
                ),
              if (widget.item.supportsCommand('STOP'))
                _RollerButton(
                  icon: FontAwesomeIcons.stop,
                  label: 'Stop',
                  isDark: isDark,
                  onTap: () => widget.ctrl.sendCommand(widget.item.name, 'STOP'),
                ),
              if (widget.item.supportsCommand('DOWN'))
                _RollerButton(
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

class _RollerButton extends StatelessWidget {
  final FaIconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  const _RollerButton({
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

/// Kartu kamera untuk Thing hasil auto-discovery (binding IP Camera) —
/// gaya sama persis dengan kartu Video openHAB: kartu gelap, label kiri
/// atas, tombol play bulat di tengah. Sumbernya Thing + URL yang
/// dikonstruksi langsung, BUKAN dari state Item manapun.
class _CameraThingCard extends StatelessWidget {
  final OHThing thing;
  final OpenHABController ctrl;
  const _CameraThingCard({required this.thing, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final label = thing.label.isNotEmpty ? thing.label : thing.uid;
    final isOnline = thing.isOnline;
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => _VideoPlayerDialog(
          label: label,
          videoUrl: ctrl.cameraHlsUrl(thing),
          onBeforePlay: () => ctrl.startCameraStream(thing),
          httpHeaders: ctrl.authHeaders,
        ),
      ),
      child: Container(
        width: double.infinity,
        height: 160,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 14, top: 12,
              child: Text(label,
                  style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Colors.white)),
            ),
            if (!isOnline)
              Positioned(
                right: 12, top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Offline',
                      style: TextStyle(
                          fontFamily: 'Inter', fontSize: 10,
                          fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            Center(
              child: Container(
                width: 48, height: 48,
                decoration: const BoxDecoration(
                    color: Color(0xFFE4E4E7), shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.black, size: 26),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog kamera bergaya widget Video openHAB — kartu gelap dengan label
/// dan tombol play bulat di tengah. Belum ada integrasi video player
/// sungguhan (butuh package terpisah — video_player/webview untuk
/// MJPEG/HLS), jadi tap play menampilkan status apa adanya, bukan
/// pura-pura berhasil putar.
/// Wrapper: item Camera (category "Camera", type String/Image) langsung
/// pakai state-nya sendiri sebagai URL video (channel hlsUrl/mjpegUrl/
/// imageUrl openHAB biasanya memang berisi URL siap pakai di state-nya).
class _CameraPlayerDialog extends StatelessWidget {
  final OpenHABItem item;
  final OpenHABController ctrl;
  const _CameraPlayerDialog({required this.item, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final label = item.label.isNotEmpty ? item.label : item.name;
    final url = item.state;
    if (url == null || !(url.startsWith('http://') || url.startsWith('https://'))) {
      return _VideoUnavailableDialog(
        label: label,
        reason: 'State item ini bukan URL video yang valid.',
      );
    }
    return _VideoPlayerDialog(label: label, videoUrl: url, httpHeaders: ctrl.authHeaders);
  }
}

/// Dialog fallback kalau URL video belum/tidak valid — tetap gaya sama
/// (kartu gelap + label), tapi dengan pesan jelas alih-alih pura-pura.
class _VideoUnavailableDialog extends StatelessWidget {
  final String label;
  final String reason;
  const _VideoUnavailableDialog({required this.label, required this.reason});

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
/// IP Camera). Mulai dari tampilan poster (gelap + tombol play, mirip
/// widget Video openHAB) — begitu ditekan, baru mulai inisialisasi &
/// memutar stream. Kalau gagal (URL invalid/stream mati), tampilkan
/// pesan error yang jelas, bukan pura-pura berhasil.
class _VideoPlayerDialog extends StatefulWidget {
  final String label;
  final String videoUrl;
  /// Dijalankan sebelum mulai memutar (mis. nyalain channel startStream
  /// binding IP Camera). Return false kalau channel/Item startStream-nya
  /// tidak ditemukan — dipakai untuk kasih pesan error yang lebih spesifik
  /// ketimbang "gagal memutar video" generik. Opsional — biar widget ini
  /// tetap reusable buat kasus tanpa Thing (item Camera biasa yang
  /// state-nya langsung URL).
  final Future<bool> Function()? onBeforePlay;
  /// Header Authorization yang sama dipakai request REST openHAB lain —
  /// tanpa ini, request stream ke server openHAB yang butuh autentikasi
  /// akan selalu kena 401 walau URL dan stream-nya sendiri sudah benar.
  final Map<String, String> httpHeaders;
  const _VideoPlayerDialog({
    required this.label,
    required this.videoUrl,
    this.onBeforePlay,
    this.httpHeaders = const {},
  });

  @override
  State<_VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
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
        // tiap kamera/jaringan (bisa 2 detik, bisa >10 detik), jadi delay
        // TETAP tidak reliable. Sebagai gantinya, poll URL manifestnya
        // sampai server benar-benar siap (HTTP 200) atau timeout.
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
  /// [maxWait] tercapai. HEAD request dulu kalau server tidak izinkan
  /// HEAD (405/501), fallback ke GET biasa.
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
                          // URL yang beneran dicoba — biar bisa di-copy dan
                          // dites manual di browser/VLC buat mastiin ini
                          // masalah di app atau di server/binding kamera.
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
class _CameraViewerDialog extends StatefulWidget {
  final OpenHABItem item;
  final OpenHABController ctrl;
  const _CameraViewerDialog({required this.item, required this.ctrl});

  @override
  State<_CameraViewerDialog> createState() => _CameraViewerDialogState();
}

class _CameraViewerDialogState extends State<_CameraViewerDialog> {
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
/// command tombol (mis. "rcButton" binding LG webOS). Kode tombol yang
/// dikirim persis mengikuti daftar resmi binding LG webOS.
///
/// Tiap tombol dicek dulu lewat [OpenHABItem.supportsCommand] — kalau
/// server melaporkan daftar command yang didukung (commandOptions) dan
/// kode tombol ini TIDAK ada di daftar itu, tombolnya disembunyikan.
/// Kalau server tidak melaporkan batasan apapun (commandOptions kosong),
/// semua tombol ditampilkan (default aman, lihat OpenHABItem.supportsCommand).
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

    // Kalau server melaporkan commandOptions tapi TIDAK SATUPUN dari
    // kode remote yang kita tahu ada di daftar itu, D-pad bakal kosong
    // total — kasih fallback ke kotak command generik daripada nampilin
    // sheet kosong yang membingungkan.
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

/// Kontrol generik untuk Item String yang bukan remote button (mis.
/// channel "input"/"soundField" pada binding Sony, atau "appLauncher"
/// pada LG webOS) — kotak teks bebas, karena nilai yang diterima
/// spesifik per model/binding dan tidak ada daftar baku universal.
///
/// Kalau server MELAPORKAN daftar commandOptions (mis. beberapa
/// binding expose ini juga untuk channel non-tombol), pilihan itu
/// ditampilkan sebagai chip cepat di atas kotak teks.
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


class _PlayerSheet extends StatefulWidget {
  final OpenHABItem item;
  final OpenHABController ctrl;
  const _PlayerSheet({required this.item, required this.ctrl});

  @override
  State<_PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<_PlayerSheet> {
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
      setState(() => _currentState = fresh.state?.toUpperCase() ?? 'NULL');
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
    // Player sheet keeps its dark, immersive look in both themes (by design).
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      decoration: const BoxDecoration(
        color: Color(0xFF1C2526),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: FaIcon(
                _isPlaying ? FontAwesomeIcons.pause : FontAwesomeIcons.play,
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                onTap: () => _send(_isPlaying ? 'PAUSE' : 'PLAY'),
                child: Container(
                  width: 72, height: 72,
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
                      _isPlaying ? FontAwesomeIcons.pause : FontAwesomeIcons.play,
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
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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

  Widget _playerButton({required FaIconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52, height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Center(child: FaIcon(icon, size: 20, color: Colors.white)),
      ),
    );
  }
}

class _DummyDeviceCard extends StatelessWidget {
  final _DummyDevice device;
  const _DummyDeviceCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardColor = device.isOn
        ? AppColors.primary
        : (isDark ? const Color(0xFF27272A) : Colors.white);
    final mutedColor = isDark ? Colors.white60 : const Color(0xFF71717A);
    final iconColor = device.isOn ? Colors.white : mutedColor;
    final nameColor = device.isOn
        ? Colors.white
        : (isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xCC18181B));
    final pillBg = device.isOn
        ? Colors.white.withValues(alpha: 0.30)
        : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0x33787878));
    final pillText = device.isOn ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF18181B));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              FaIcon(device.icon, size: 24, color: iconColor),
              Text(device.isOn ? 'On' : 'Off',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      color: device.isOn ? Colors.white70 : mutedColor)),
            ],
          ),
          const Spacer(),
          Text(device.name,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: nameColor)),
          const SizedBox(height: 2),
          Text(device.room,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  color: device.isOn ? Colors.white70 : mutedColor)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: pillBg,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Text('• ${device.count}',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                    fontSize: 8,
                    color: pillText)),
          ),
        ],
      ),
    );
  }
}

class _DummyDevice {
  final FaIconData icon;
  final String name;
  final String room;
  final String count;
  final bool isOn;
  const _DummyDevice({
    required this.icon,
    required this.name,
    required this.room,
    required this.count,
    required this.isOn,
  });
}

class _NavItem {
  final FaIconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}