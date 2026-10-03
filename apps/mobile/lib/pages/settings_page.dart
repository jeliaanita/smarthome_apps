import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mobile/core/providers/installation_provider.dart';
import 'package:mobile/core/providers/role_provider.dart';
import 'package:mobile/core/theme/theme_provider.dart';
import 'package:mobile/pages/addon_store_page.dart';
import 'package:mobile/pages/hub_connectivity_page.dart';
import 'package:mobile/pages/integrations_page.dart';
import 'package:mobile/pages/items_management_page.dart';
import 'package:mobile/pages/rooms_management_page.dart';
import 'package:mobile/pages/rules_management_page.dart';
import 'package:mobile/pages/scenes_management_page.dart';
import 'package:mobile/pages/things_management_page.dart';
import 'package:mobile/pages/energy_page.dart';
import 'package:mobile/pages/floor_plan_page.dart';
import 'package:mobile/pages/user_management_page.dart';
import 'package:mobile/schedule_management_page.dart';
import 'package:mobile/scripts_management_page.dart';
import 'package:mobile/core/utils/responsive_utils.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/config/openhab_config.dart';
import '../../../../core/config/mqtt_config.dart';
import 'package:mobile/core/services/mqtt_service.dart';
import '../../../../core/controllers/openhab_controller.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/auth_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class _SC {
  static const background   = Color(0xFFF5F5F7);
  static const textPrimary  = Color(0xCC18181B);
  static const textMuted    = Color(0xFF71717A);
  static const divider      = Color(0xFFE3E3E3);
  static const orange       = Color(0xFFFFA500);
  static const white        = Colors.white;
  static const sectionLabel = Color(0xFF9E9E9E);
  static const signOutBg    = Color(0xFFFFF0D6);
  static const signOutText  = Color(0xFFFF8C00);
  static const linkedGreen  = Color(0xFF34C759);
  static const notLinkedRed = Color(0xFFFF3B30);
  static const blue         = Color(0xFF0088FF);

  static const darkBg      = Color(0xFF18181B);
  static const darkSurface = Color(0xFF27272A);
  static const darkBorder  = Color(0xFF3F3F46);

  static List<BoxShadow> cardShadow(bool isDark) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.055),
      blurRadius: 12,
      offset: const Offset(0, 3),
    ),
  ];

  static TextStyle pageTitle(bool isDark) => TextStyle(
    fontFamily: 'Inter', fontWeight: FontWeight.w600,
    fontSize: 20,
    color: isDark ? Colors.white : textPrimary,
  );
  static TextStyle profileName(bool isDark) => TextStyle(
    fontFamily: 'Inter', fontWeight: FontWeight.w700,
    fontSize: 17, height: 1.3,
    color: isDark ? Colors.white : textPrimary,
  );
  static TextStyle profileEmail(bool isDark) => TextStyle(
    fontFamily: 'Inter', fontWeight: FontWeight.w400,
    fontSize: 13,
    color: isDark ? Colors.white54 : textMuted,
  );
  static TextStyle sectionHeader(bool isDark) => TextStyle(
    fontFamily: 'Inter', fontWeight: FontWeight.w500,
    fontSize: 11, letterSpacing: 0.8,
    color: isDark ? Colors.white38 : sectionLabel,
  );
  static TextStyle rowLabel(bool isDark) => TextStyle(
    fontFamily: 'Inter', fontWeight: FontWeight.w500,
    fontSize: 15,
    color: isDark ? Colors.white : textPrimary,
  );
  static TextStyle rowTrailing(bool isDark) => TextStyle(
    fontFamily: 'Inter', fontWeight: FontWeight.w400,
    fontSize: 13,
    color: isDark ? Colors.white54 : textMuted,
  );
  static const signOut = TextStyle(
    fontFamily: 'Inter', fontWeight: FontWeight.w600,
    fontSize: 16, color: signOutText,
  );
  static const navLabel = TextStyle(
    fontFamily: 'Inter', fontSize: 11,
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _ctrl = OpenHABController.instance;
  int _roomsCount = 0;

  final bool _darkMode       = false;
  final bool _hapticFeedback = true;
  final bool _faceId         = true;
  String _displayName  = '';
  String _email        = '';

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onCtrlUpdate);
    _loadRoomsCount();
    _loadUserData();
  }

  void _loadUserData() async {
    final user = AuthService.currentUser;
    if (user == null) return;
    await user.reload();
    final freshUser = AuthService.currentUser;
    if (mounted) {
      setState(() {
        _displayName = freshUser?.displayName ?? '';
        _email       = freshUser?.email ?? '';
      });
    }
  }

  String get _initials {
    final parts = _displayName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '?';
  }

  void _onCtrlUpdate() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrlUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? _SC.darkBg : _SC.background,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveUtils.horizontalPadding(context)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    _buildAppBar(isDark),
                    const SizedBox(height: 20),
                    _buildProfileCard(isDark),
                    const SizedBox(height: 24),
                    _buildSectionLabel('OPENHAB SERVER', isDark),
                    const SizedBox(height: 8),
                    _buildOpenHABCard(isDark),
                    const SizedBox(height: 20),
                    _buildSectionLabel('HOME MANAGEMENT', isDark),
                    const SizedBox(height: 8),
                    _buildHomeManagementCard(isDark),
                    const SizedBox(height: 20),
                    _buildSectionLabel('INTEGRATIONS', isDark),
                    const SizedBox(height: 8),
                    _buildIntegrationsCard(isDark),
                    const SizedBox(height: 20),
                    _buildSectionLabel('PREFERENCES', isDark),
                    const SizedBox(height: 8),
                    _buildPreferencesCard(isDark),
                    const SizedBox(height: 20),
                    const SizedBox(height: 8),
                    _buildSignOutButton(isDark),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
          _buildBottomNav(isDark),
        ],
      ),
    );
  }

  Future<void> _loadRoomsCount() async {
    try {
      final config = context.read<InstallationProvider>().config;
      final token    = config?.apiToken;
      final username = config?.username;
      final password = config?.password;

      final headers = <String, String>{'Accept': 'application/json'};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      } else if (username != null && password != null) {
        final encoded = base64Encode(utf8.encode('$username:$password'));
        headers['Authorization'] = 'Basic $encoded';
      }

      final uri = Uri.parse(
          '${_ctrl.serverUrl}/rest/items?type=Group&fields=name,tags');
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        final count = list.where((e) {
          final tags = List<String>.from(e['tags'] as List? ?? []);
          return tags.any((tag) {
            final t = tag.toLowerCase();
            return t.contains('location') || t.contains('room') ||
                t.contains('floor')       || t.contains('building') ||
                t.contains('indoor')      || t.contains('outdoor') ||
                t.contains('corridor')    || t.contains('garage') ||
                t.contains('garden')      || t.contains('terrace') ||
                t.contains('office')      || t.contains('cellar') ||
                t.contains('bedroom')     || t.contains('kitchen') ||
                t.contains('bathroom')    || t.contains('livingroom');
          });
        }).length;
        if (mounted) setState(() => _roomsCount = count);
      }
    } catch (_) {}
  }
  Widget _buildAppBar(bool isDark) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: SizedBox(
            width: 28, height: 28,
            child: Center(
              child: FaIcon(FontAwesomeIcons.arrowLeft,
                  size: 18,
                  color: isDark ? Colors.white : _SC.textPrimary),
            ),
          ),
        ),
        Expanded(
          child: Text('Settings',
              textAlign: TextAlign.center,
              style: _SC.pageTitle(isDark)),
        ),
        const SizedBox(width: 28),
      ],
    );
  }

  Widget _buildProfileCard(bool isDark) {
    return Row(
      children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: isDark ? _SC.darkBorder : _SC.divider, width: 1.5),
          ),
          child: ClipOval(
            child: Container(
              color: _SC.orange.withValues(alpha: isDark ? 0.2 : 0.15),
              child: Center(
                child: Text(
                  _initials,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: _SC.orange,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _displayName.isNotEmpty ? _displayName : 'User',
                style: _SC.profileName(isDark),
              ),
              const SizedBox(height: 2),
              Text(
                _email.isNotEmpty ? _email : '-',
                style: _SC.profileEmail(isDark),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: _showEditProfileSheet,
          child: Container(
            width: 44, height: 44,
            decoration: const BoxDecoration(
              color: _SC.orange, shape: BoxShape.circle,
            ),
            child: const Center(
              child: FaIcon(FontAwesomeIcons.penToSquare,
                  size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  void _showEditProfileSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameCtrl = TextEditingController(text: _displayName);
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            decoration: BoxDecoration(
              color: isDark ? _SC.darkSurface : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? _SC.darkBorder
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Edit Profile',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: isDark ? Colors.white : const Color(0xCC18181B),
                    )),
                const SizedBox(height: 20),

                Text('Full Name',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isDark ? Colors.white54 : const Color(0xFF71717A),
                    )),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      color: isDark ? Colors.white : const Color(0xFF18181B)),
                  decoration: InputDecoration(
                    hintText: 'Nama lengkap',
                    hintStyle: TextStyle(
                        fontFamily: 'Inter',
                        color: isDark
                            ? Colors.white30
                            : Colors.grey.shade400),
                    filled: true,
                    fillColor: isDark
                        ? _SC.darkBg
                        : const Color(0xFFF5F5F7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: FaIcon(FontAwesomeIcons.user,
                          size: 15,
                          color: isDark
                              ? Colors.white38
                              : const Color(0xFF71717A)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 14),

                Text('Email',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isDark ? Colors.white54 : const Color(0xFF71717A),
                    )),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? _SC.darkBg
                        : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      FaIcon(FontAwesomeIcons.envelope,
                          size: 15,
                          color: isDark
                              ? Colors.white24
                              : const Color(0xFFAAAAAA)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _email.isNotEmpty
                              ? _email
                              : (AuthService.currentUser?.email ?? '-'),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            color: isDark
                                ? Colors.white30
                                : const Color(0xFFAAAAAA),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('read only',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            color: isDark
                                ? Colors.white24
                                : const Color(0xFFCCCCCC),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: isSaving
                        ? null
                        : () async {
                            final newName = nameCtrl.text.trim();
                            if (newName.isEmpty) return;
                            setSheetState(() => isSaving = true);
                            try {
                              await AuthService.currentUser
                                  ?.updateDisplayName(newName);
                              await AuthService.currentUser?.reload();
                              if (mounted) {
                                setState(
                                    () => _displayName = newName);
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: const Text(
                                      'Profil berhasil diperbarui'),
                                  backgroundColor: Colors.green[600],
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ));
                              }
                            } catch (e) {
                              setSheetState(() => isSaving = false);
                              if (mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: Text('Gagal memperbarui: $e'),
                                  backgroundColor: Colors.red[400],
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ));
                              }
                            }
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: isSaving
                            ? _SC.orange.withValues(alpha: 0.5)
                            : _SC.orange,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: isSaving
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2))
                            : const Text('Simpan',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: Colors.white,
                                )),
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

  Widget _buildSectionLabel(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(label, style: _SC.sectionHeader(isDark)),
    );
  }

  Widget _buildOpenHABCard(bool isDark) {
  final isAdmin = context.watch<RoleProvider>().isAdmin;
  final isConnected = _ctrl.isConnected;
  final url = _ctrl.serverUrl;
 
  return Container(
    decoration: BoxDecoration(
      color: isDark ? _SC.darkSurface : _SC.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: _SC.cardShadow(isDark),
    ),
    child: Column(
      children: [
        // Status bar — tetap tampil untuk semua role
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              SizedBox(
                width: 28, height: 28,
                child: Center(
                  child: FaIcon(FontAwesomeIcons.server,
                      size: 16,
                      color: isDark ? Colors.white38 : _SC.textMuted),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isConnected ? 'Server Connected' : 'Server Disconnected',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: isConnected
                            ? (isDark ? Colors.white : _SC.textPrimary)
                            : _SC.notLinkedRed,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      url.isNotEmpty ? url : 'Belum dikonfigurasi',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: isDark ? Colors.white38 : _SC.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected ? _SC.linkedGreen : _SC.notLinkedRed,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1,
            color: isDark ? _SC.darkBorder : const Color(0xFFF0F0F0)),
 
        // Things — tampil untuk SEMUA role
        _openHABRow(
          isDark: isDark,
          icon: FontAwesomeIcons.microchip,
          label: 'Things',
          subtitle: isAdmin ? 'Kelola perangkat fisik' : 'Lihat & kontrol perangkat',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ThingsManagementPage())),
        ),
        Divider(height: 1, thickness: 1,
            color: isDark ? _SC.darkBorder : const Color(0xFFF0F0F0)),
 
        // Items — tampil untuk SEMUA role (view + control; add/edit/delete admin only)
        _openHABRow(
          isDark: isDark,
          icon: FontAwesomeIcons.toggleOn,
          label: 'Items',
          subtitle: isAdmin ? 'Kontrol & kelola semua item' : 'Kontrol semua item',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ItemsManagementPage())),
        ),
 
        // Sisanya — ADMIN ONLY
        if (isAdmin) ...[
          Divider(height: 1, thickness: 1,
              color: isDark ? _SC.darkBorder : const Color(0xFFF0F0F0)),
          _openHABRow(
            isDark: isDark,
            icon: FontAwesomeIcons.store,
            label: 'Add-on Store',
            subtitle: 'Install & kelola binding dan addon',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AddonStorePage())),
          ),
          Divider(height: 1, thickness: 1,
              color: isDark ? _SC.darkBorder : const Color(0xFFF0F0F0)),
          _openHABRow(
            isDark: isDark,
            icon: FontAwesomeIcons.scroll,
            label: 'Rules',
            subtitle: 'Kelola & jalankan automation rules',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RulesManagementPage())),
          ),
          Divider(height: 1, thickness: 1,
              color: isDark ? _SC.darkBorder : const Color(0xFFF0F0F0)),
          _openHABRow(
            isDark: isDark,
            icon: FontAwesomeIcons.wandMagicSparkles,
            label: 'Scenes',
            subtitle: 'Aktifkan scene rumah pintar',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ScenesManagementPage())),
          ),
          Divider(height: 1, thickness: 1,
              color: isDark ? _SC.darkBorder : const Color(0xFFF0F0F0)),
          _openHABRow(
            isDark: isDark,
            icon: FontAwesomeIcons.code,
            label: 'Scripts',
            subtitle: 'Kelola & jalankan automation scripts',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ScriptsManagementPage())),
          ),
          Divider(height: 1, thickness: 1,
              color: isDark ? _SC.darkBorder : const Color(0xFFF0F0F0)),
          _openHABRow(
            isDark: isDark,
            icon: FontAwesomeIcons.calendarDays,
            label: 'Schedule',
            subtitle: 'View upcoming time-based rules',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ScheduleManagementPage())),
          ),
        ],
      ],
    ),
  );
}

  Widget _openHABRow({
    required bool isDark,
    required FaIconData icon,
    required String label,
    required String subtitle,
    Color? subtitleColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            SizedBox(
              width: 28, height: 28,
              child: Center(
                child: FaIcon(icon,
                    size: 16,
                    color: isDark ? Colors.white38 : _SC.textMuted),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: isDark ? Colors.white : const Color(0xCC18181B),
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: subtitleColor ??
                            (isDark
                                ? Colors.white38
                                : const Color(0xFF71717A)),
                      )),
                ],
              ),
            ),
            FaIcon(FontAwesomeIcons.chevronRight,
                size: 11,
                color: isDark ? Colors.white24 : const Color(0xFFD4D4D8)),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceStat(
      FaIconData icon, String count, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            FaIcon(icon, size: 14, color: color),
            const SizedBox(height: 4),
            Text(count,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: color,
                )),
            Text(label,
                style: const TextStyle(
                  fontFamily: 'Inter', fontSize: 10, color: _SC.textMuted,
                )),
          ],
        ),
      ),
    );
  }

  void _showServerConfigSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ServerConfigSheet(ctrl: _ctrl),
    );
  }

  void _showMqttConfigSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _MqttConfigSheet(),
    ).then((_) => setState(() {})); // refresh status Connected/Disconnected
  }

  Widget _buildHomeManagementCard(bool isDark) {
  final isAdmin = context.watch<RoleProvider>().isAdmin;
  if (!isAdmin) return const SizedBox.shrink();
 
  return _SettingsCard(
    isDark: isDark,
    children: [
      _SettingsNavRow(
        isDark: isDark,
        icon: FontAwesomeIcons.house,
        label: 'Rooms',
        trailing: '$_roomsCount Room${_roomsCount != 1 ? 's' : ''}',
        onTap: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const RoomsManagementPage()));
          await _loadRoomsCount();
        },
      ),
      _SettingsNavRow(
        isDark: isDark,
        icon: FontAwesomeIcons.wifi,
        label: 'Hub & Connectivity',
        trailing: _ctrl.isConnected ? 'Connected' : 'Disconnected',
        trailingColor: _ctrl.isConnected ? _SC.linkedGreen : _SC.notLinkedRed,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const HubConnectivityPage())),
      ),
      _SettingsNavRow(
        isDark: isDark,
        icon: FontAwesomeIcons.satelliteDish,
        label: 'MQTT Broker',
        trailing: MqttService.instance.isConnected ? 'Connected' : 'Disconnected',
        trailingColor: MqttService.instance.isConnected
            ? _SC.linkedGreen : _SC.notLinkedRed,
        onTap: _showMqttConfigSheet,
      ),

            _SettingsNavRow(
        isDark: isDark,
        icon: FontAwesomeIcons.users, 
        label: 'Kelola User',
        trailing: 'Assign role & instalasi',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const UserManagementPage())),
      ),
    ],
  );
}
 
Widget _buildIntegrationsCard(bool isDark) {
  final isAdmin = context.watch<RoleProvider>().isAdmin;
  if (!isAdmin) return const SizedBox.shrink();
 
  return _SettingsCard(
    isDark: isDark,
    children: [
      _SettingsNavRow(
        isDark: isDark,
        customIcon: _GoogleIcon(),
        label: 'Integrations',
        trailing: 'Kelola addon & binding',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const IntegrationsPage())),
      ),
    ],
  );
}

  Widget _buildPreferencesCard(bool isDark) {
    final themeProvider = context.watch<ThemeProvider>();
    return _SettingsCard(
      isDark: isDark,
      children: [
        _SettingsToggleRow(
          isDark: isDark,
          icon: FontAwesomeIcons.moon,
          label: 'Dark Mode',
          value: themeProvider.isDark,
          onChanged: (v) => themeProvider.setDark(v),
        ),
      ],
    );
  }

  Widget _buildSignOutButton(bool isDark) {
    return GestureDetector(
      onTap: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor:
                isDark ? _SC.darkSurface : Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: Text('Sign Out',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : _SC.textPrimary,
                )),
            content: Text(
              'Are you sure you want to sign out?',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: isDark ? Colors.white70 : _SC.textMuted,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel',
                    style: TextStyle(
                        color: isDark
                            ? Colors.white54
                            : _SC.textMuted)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sign Out',
                    style: TextStyle(
                        color: _SC.signOutText,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
        if (confirm == true && mounted) {
          await AuthService.signOut();
          await OpenHABConfig.clearAll(); // bersihkan sisa data lama di device
          context.read<RoleProvider>().reset();
          context.read<InstallationProvider>().reset();
          OpenHABController.instance.resetConnection();
          if (mounted) context.go('/login');
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isDark
              ? _SC.signOutText.withValues(alpha: 0.1)
              : _SC.signOutBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            FaIcon(FontAwesomeIcons.rightFromBracket,
                size: 16, color: _SC.signOutText),
            SizedBox(width: 10),
            Text('Sign Out', style: _SC.signOut),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav(bool isDark) {
    const navItems = [
      _NavItem(icon: FontAwesomeIcons.house,          label: 'Home'),
      _NavItem(icon: FontAwesomeIcons.bolt,           label: 'Energy'),
      _NavItem(icon: FontAwesomeIcons.mapLocationDot, label: 'Floorplan'),
      _NavItem(icon: FontAwesomeIcons.gear,           label: 'Settings'),
    ];
    const selectedIndex = 3;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16, 10, 16,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? _SC.darkSurface : _SC.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(navItems.length, (i) {
          final isSelected = i == selectedIndex;
          final unselectedColor =
              isDark ? Colors.white38 : Colors.black38;
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
                case 2:
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const FloorPlanPage()));
                  break;
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FaIcon(navItems[i].icon,
                    size: 20,
                    color: isSelected
                        ? AppColors.primary
                        : unselectedColor),
                const SizedBox(height: 4),
                Text(navItems[i].label,
                    style: _SC.navLabel.copyWith(
                      color: isSelected
                          ? AppColors.primary
                          : unselectedColor,
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

class _ServerConfigSheet extends StatefulWidget {
  final OpenHABController ctrl;
  const _ServerConfigSheet({required this.ctrl});

  @override
  State<_ServerConfigSheet> createState() => _ServerConfigSheetState();
}

class _ServerConfigSheetState extends State<_ServerConfigSheet> {
  late TextEditingController _urlController;
  late TextEditingController _tokenController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  bool _isTesting       = false;
  bool _obscureToken    = true;
  bool _obscurePassword = true;
  String? _testResult;
  bool _testSuccess     = false;

  @override
  void initState() {
    super.initState();
    _urlController      = TextEditingController(text: widget.ctrl.serverUrl);
    _tokenController    = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    // ⚠️ FIX: kredensial dibaca dari InstallationProvider (Firestore),
    // bukan lagi OpenHABConfig (SharedPreferences lokal — method
    // kredensialnya sudah dihapus, lihat catatan keamanan di openhab_config.dart).
    final config = context.read<InstallationProvider>().config;
    if (mounted) {
      if (config?.apiToken != null) _tokenController.text = config!.apiToken!;
      if (config?.username != null) _usernameController.text = config!.username!;
      if (config?.password != null) _passwordController.text = config!.password!;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() { _isTesting = true; _testResult = null; });
    final url      = _urlController.text.trim();
    final token    = _tokenController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (!OpenHABConfig.isValidUrl(url)) {
      setState(() {
        _isTesting   = false;
        _testResult  = 'URL tidak valid. Contoh: http://192.168.1.100:8080';
        _testSuccess = false;
      });
      return;
    }
    try {
      // ⚠️ FIX: simpan lewat InstallationProvider (Firestore), bukan
      // OpenHABConfig lokal — konsisten dengan sistem yang aktif dipakai.
      await context.read<InstallationProvider>().saveConfig(
        openhabUrl: url,
        apiToken: token.isNotEmpty ? token : null,
        username: username.isNotEmpty ? username : null,
        password: password.isNotEmpty ? password : null,
      );
      final ok = await widget.ctrl.updateServerUrl(url);
      setState(() {
        _testResult = ok
            ? '✓ Berhasil terhubung ke server'
            : '✗ Tidak dapat terhubung. Cek URL dan pastikan server menyala.';
        _testSuccess = ok;
      });
    } catch (e) {
      setState(() { _testResult = '✗ Error: $e'; _testSuccess = false; });
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<void> _saveConfig() async {
    final url      = _urlController.text.trim();
    final token    = _tokenController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (!OpenHABConfig.isValidUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URL tidak valid')));
      return;
    }
    // ⚠️ FIX: simpan lewat InstallationProvider (Firestore), bukan
    // OpenHABConfig lokal — konsisten dengan sistem yang aktif dipakai.
    await context.read<InstallationProvider>().saveConfig(
      openhabUrl: url,
      apiToken: token.isNotEmpty ? token : null,
      username: username.isNotEmpty ? username : null,
      password: password.isNotEmpty ? password : null,
    );
    await widget.ctrl.updateServerUrl(url);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Konfigurasi disimpan'),
        backgroundColor: Color(0xFF34C759),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor =
        isDark ? _SC.darkBg : const Color(0xFFF5F5F7);
    final hintColor =
        isDark ? Colors.white30 : Colors.grey.shade400;
    final iconColor =
        isDark ? Colors.white38 : const Color(0xFF71717A);
    final labelColor =
        isDark ? Colors.white54 : const Color(0xFF71717A);
    final textColor =
        isDark ? Colors.white : const Color(0xFF18181B);

    InputDecoration fieldDeco({
      required String hint,
      required FaIconData prefixIcon,
      Widget? suffix,
    }) =>
        InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontFamily: 'Inter', color: hintColor),
          filled: true,
          fillColor: fillColor,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: FaIcon(prefixIcon, size: 15, color: iconColor),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: suffix,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        );

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: BoxDecoration(
          color: isDark ? _SC.darkSurface : Colors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? _SC.darkBorder
                      : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: FaIcon(FontAwesomeIcons.server,
                        size: 18, color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('openHAB Server',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: isDark ? Colors.white : const Color(0xCC18181B),
                        )),
                    Text('Configure connection',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: isDark ? Colors.white54 : const Color(0xFF71717A),
                        )),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Server URL',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: labelColor)),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: textColor),
              decoration: fieldDeco(
                  hint: 'http://192.168.1.100:8080',
                  prefixIcon: FontAwesomeIcons.globe),
            ),
            const SizedBox(height: 14),
            Text('API Token (opsional)',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: labelColor)),
            const SizedBox(height: 8),
            TextField(
              controller: _tokenController,
              obscureText: _obscureToken,
              style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: textColor),
              decoration: fieldDeco(
                hint: 'oh.xxxxx.yyy (kosongkan jika tidak ada)',
                prefixIcon: FontAwesomeIcons.key,
                suffix: GestureDetector(
                  onTap: () =>
                      setState(() => _obscureToken = !_obscureToken),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: FaIcon(
                      _obscureToken
                          ? FontAwesomeIcons.eye
                          : FontAwesomeIcons.eyeSlash,
                      size: 15, color: iconColor,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Token bisa dibuat di openHAB → Settings → API Tokens',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  color: isDark ? Colors.white30 : const Color(0xFF9E9E9E)),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                  child: Divider(
                      color: isDark
                          ? _SC.darkBorder
                          : const Color(0xFFE0E0E0))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('atau',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: isDark
                            ? Colors.white38
                            : Colors.grey.shade400)),
              ),
              Expanded(
                  child: Divider(
                      color: isDark
                          ? _SC.darkBorder
                          : const Color(0xFFE0E0E0))),
            ]),
            const SizedBox(height: 14),
            Text('Username',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: labelColor)),
            const SizedBox(height: 8),
            TextField(
              controller: _usernameController,
              style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: textColor),
              decoration: fieldDeco(
                  hint: 'openHAB username',
                  prefixIcon: FontAwesomeIcons.user),
            ),
            const SizedBox(height: 14),
            Text('Password',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: labelColor)),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: textColor),
              decoration: fieldDeco(
                hint: 'openHAB password',
                prefixIcon: FontAwesomeIcons.lock,
                suffix: GestureDetector(
                  onTap: () => setState(
                      () => _obscurePassword = !_obscurePassword),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: FaIcon(
                      _obscurePassword
                          ? FontAwesomeIcons.eye
                          : FontAwesomeIcons.eyeSlash,
                      size: 15, color: iconColor,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_testResult != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _testSuccess
                      ? (isDark
                          ? const Color(0xFF34C759).withValues(alpha: 0.12)
                          : const Color(0xFFEAF8EE))
                      : (isDark
                          ? const Color(0xFFFF3B30).withValues(alpha: 0.12)
                          : const Color(0xFFFFF0F0)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  FaIcon(
                    _testSuccess
                        ? FontAwesomeIcons.circleCheck
                        : FontAwesomeIcons.circleXmark,
                    size: 14,
                    color: _testSuccess
                        ? const Color(0xFF34C759)
                        : const Color(0xFFFF3B30),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_testResult!,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: _testSuccess
                              ? const Color(0xFF34C759)
                              : const Color(0xFFFF3B30),
                        )),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
            ],
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: _isTesting ? null : _testConnection,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? _SC.darkBorder
                          : const Color(0xFFF2F2F2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: _isTesting
                          ? SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: iconColor))
                          : Text('Test',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: iconColor,
                              )),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: _saveConfig,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Text('Simpan & Connect',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Colors.white,
                          )),
                    ),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _MqttConfigSheet extends StatefulWidget {
  const _MqttConfigSheet();

  @override
  State<_MqttConfigSheet> createState() => _MqttConfigSheetState();
}

class _MqttConfigSheetState extends State<_MqttConfigSheet> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _topicDataController;
  late TextEditingController _topicLwtController;
  bool _useTls          = false;
  bool _obscurePassword = true;
  bool _isSaving        = false;
  String? _resultMsg;
  bool _resultSuccess   = false;

  @override
  void initState() {
    super.initState();
    _hostController      = TextEditingController();
    _portController      = TextEditingController();
    _usernameController  = TextEditingController();
    _passwordController  = TextEditingController();
    _topicDataController = TextEditingController();
    _topicLwtController  = TextEditingController();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final host      = await MqttConfig.getBroker();
    final port      = await MqttConfig.getPort();
    final username  = await MqttConfig.getUsername();
    final password  = await MqttConfig.getPassword();
    final useTls    = await MqttConfig.getUseTls();
    final topicData = await MqttConfig.getTopicData();
    final topicLwt  = await MqttConfig.getTopicLwt();
    if (!mounted) return;
    setState(() {
      _hostController.text      = host;
      _portController.text      = port.toString();
      _usernameController.text  = username ?? '';
      _passwordController.text  = password ?? '';
      _useTls                   = useTls;
      _topicDataController.text = topicData;
      _topicLwtController.text  = topicLwt;
    });
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _topicDataController.dispose();
    _topicLwtController.dispose();
    super.dispose();
  }

  Future<void> _save({bool reconnect = false}) async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());

    if (host.isEmpty) {
      setState(() {
        _resultMsg     = 'Host broker tidak boleh kosong';
        _resultSuccess = false;
      });
      return;
    }
    if (port == null || !MqttConfig.isValidPort(port)) {
      setState(() {
        _resultMsg     = 'Port tidak valid (1-65535)';
        _resultSuccess = false;
      });
      return;
    }

    setState(() { _isSaving = true; _resultMsg = null; });
    try {
      await MqttConfig.setBroker(host);
      await MqttConfig.setPort(port);
      await MqttConfig.setUsername(_usernameController.text.trim());
      await MqttConfig.setPassword(_passwordController.text.trim());
      await MqttConfig.setUseTls(_useTls);
      if (_topicDataController.text.trim().isNotEmpty) {
        await MqttConfig.setTopicData(_topicDataController.text.trim());
      }
      if (_topicLwtController.text.trim().isNotEmpty) {
        await MqttConfig.setTopicLwt(_topicLwtController.text.trim());
      }

      if (reconnect) {
        await MqttService.instance.reloadConfig();
      }

      if (mounted) {
        if (reconnect) {
          setState(() {
            _resultSuccess = MqttService.instance.isConnected;
            _resultMsg = _resultSuccess
                ? '✓ Berhasil terhubung ke broker'
                : '✗ Tidak dapat terhubung. Cek host/port/kredensial.';
          });
        } else {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Konfigurasi MQTT disimpan'),
            backgroundColor: Color(0xFF34C759),
          ));
        }
      }
    } catch (e) {
      setState(() { _resultMsg = '✗ Error: $e'; _resultSuccess = false; });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor  = isDark ? _SC.darkBg : const Color(0xFFF5F5F7);
    final hintColor  = isDark ? Colors.white30 : Colors.grey.shade400;
    final iconColor  = isDark ? Colors.white38 : const Color(0xFF71717A);
    final labelColor = isDark ? Colors.white54 : const Color(0xFF71717A);
    final textColor  = isDark ? Colors.white : const Color(0xFF18181B);

    InputDecoration fieldDeco({
      required String hint,
      required FaIconData prefixIcon,
      Widget? suffix,
    }) =>
        InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontFamily: 'Inter', color: hintColor),
          filled: true,
          fillColor: fillColor,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: FaIcon(prefixIcon, size: 15, color: iconColor),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: suffix,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        );

    Widget fieldLabel(String text) => Text(text,
        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
            fontSize: 13, color: labelColor));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: BoxDecoration(
          color: isDark ? _SC.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? _SC.darkBorder : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: FaIcon(FontAwesomeIcons.satelliteDish,
                        size: 18, color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('MQTT Broker',
                      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                          fontSize: 18, color: isDark ? Colors.white : const Color(0xCC18181B))),
                  Text('Konfigurasi koneksi broker',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 13,
                          color: isDark ? Colors.white54 : const Color(0xFF71717A))),
                ]),
              ]),
              const SizedBox(height: 24),

              fieldLabel('Host Broker'),
              const SizedBox(height: 8),
              TextField(
                controller: _hostController,
                keyboardType: TextInputType.url,
                style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: textColor),
                decoration: fieldDeco(
                    hint: 'broker.emqx.io atau 192.168.1.50',
                    prefixIcon: FontAwesomeIcons.server),
              ),
              const SizedBox(height: 14),

              fieldLabel('Port'),
              const SizedBox(height: 8),
              TextField(
                controller: _portController,
                keyboardType: TextInputType.number,
                style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: textColor),
                decoration: fieldDeco(hint: '1883', prefixIcon: FontAwesomeIcons.plug),
              ),
              const SizedBox(height: 14),

              Row(children: [
                Expanded(child: Text('Gunakan TLS/SSL',
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
                        fontSize: 13, color: labelColor))),
                Switch(
                  value: _useTls,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setState(() => _useTls = v),
                ),
              ]),
              const SizedBox(height: 8),

              fieldLabel('Username (opsional)'),
              const SizedBox(height: 8),
              TextField(
                controller: _usernameController,
                style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: textColor),
                decoration: fieldDeco(hint: 'mqtt username', prefixIcon: FontAwesomeIcons.user),
              ),
              const SizedBox(height: 14),

              fieldLabel('Password (opsional)'),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: textColor),
                decoration: fieldDeco(
                  hint: 'mqtt password',
                  prefixIcon: FontAwesomeIcons.lock,
                  suffix: GestureDetector(
                    onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: FaIcon(
                        _obscurePassword ? FontAwesomeIcons.eye : FontAwesomeIcons.eyeSlash,
                        size: 15, color: iconColor,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              fieldLabel('Topic Data'),
              const SizedBox(height: 8),
              TextField(
                controller: _topicDataController,
                style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: textColor),
                decoration: fieldDeco(
                    hint: 'powermeter/pop/mbloc/jkt/data',
                    prefixIcon: FontAwesomeIcons.tag),
              ),
              const SizedBox(height: 14),

              fieldLabel('Topic LWT (status online/offline)'),
              const SizedBox(height: 8),
              TextField(
                controller: _topicLwtController,
                style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: textColor),
                decoration: fieldDeco(
                    hint: 'powermeter/pop/mbloc/jkt/LWT',
                    prefixIcon: FontAwesomeIcons.tag),
              ),

              if (_resultMsg != null) ...[
                const SizedBox(height: 14),
                Text(_resultMsg!,
                    style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600,
                        color: _resultSuccess ? const Color(0xFF34C759) : const Color(0xFFFF3B30))),
              ],

              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : () => _save(reconnect: true),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: BorderSide(color: AppColors.primary),
                    ),
                    child: _isSaving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Test Koneksi',
                            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
                                color: AppColors.primary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : () => _save(reconnect: false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text('Simpan',
                        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  final bool isDark;
  const _SettingsCard({required this.children, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? _SC.darkSurface : _SC.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: _SC.cardShadow(isDark),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsNavRow extends StatelessWidget {
  final FaIconData?   icon;
  final Widget?       customIcon;
  final String        label;
  final String        trailing;
  final Color?        trailingColor;
  final VoidCallback? onTap;
  final bool          isDark;

  const _SettingsNavRow({
    this.icon, this.customIcon,
    required this.label,
    required this.trailing,
    this.trailingColor,
    this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 28, height: 28,
              child: Center(
                child: customIcon ??
                    FaIcon(icon!,
                        size: 16,
                        color: isDark ? Colors.white38 : _SC.textMuted),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label, style: _SC.rowLabel(isDark))),
            Text(trailing,
                style: _SC.rowTrailing(isDark).copyWith(
                    color: trailingColor ??
                        (isDark ? Colors.white54 : _SC.textMuted))),
            const SizedBox(width: 6),
            FaIcon(FontAwesomeIcons.chevronRight,
                size: 11,
                color: isDark ? Colors.white24 : _SC.textMuted),
          ],
        ),
      ),
    );
  }
}

class _SettingsToggleRow extends StatelessWidget {
  final FaIconData         icon;
  final String             label;
  final bool               value;
  final ValueChanged<bool> onChanged;
  final bool               isDark;

  const _SettingsToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 28, height: 28,
            child: Center(
              child: FaIcon(icon,
                  size: 16,
                  color: isDark ? Colors.white38 : _SC.textMuted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: _SC.rowLabel(isDark))),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: _SC.orange,
            inactiveTrackColor: isDark
                ? _SC.darkBorder
                : const Color(0xFFE0E0E0),
          ),
        ],
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 24, height: 24,
        child: CustomPaint(painter: _GooglePainter()),
      );
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final colors = [
      const Color(0xFF4285F4),
      const Color(0xFF34A853),
      const Color(0xFFFBBC05),
      const Color(0xFFEA4335),
    ];
    final paint = Paint()
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final angles = [
      [0.0, 1.57], [1.57, 3.14], [3.14, 4.71], [4.71, 6.28],
    ];
    for (int i = 0; i < 4; i++) {
      paint.color = colors[i];
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 1.5),
        angles[i][0], angles[i][1] - angles[i][0], false, paint,
      );
    }
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx, center.dy),
      Offset(center.dx + radius - 1.5, center.dy),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HomeIosIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 24, height: 24,
        decoration: BoxDecoration(
          color: _SC.orange, borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: FaIcon(FontAwesomeIcons.house,
              size: 12, color: Colors.white),
        ),
      );
}

class _AlexaIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 24, height: 24,
        decoration: BoxDecoration(
          color: const Color(0xFF00CAFF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: Text('a',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Colors.white,
                height: 1,
              )),
        ),
      );
}

class _NavItem {
  final FaIconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}