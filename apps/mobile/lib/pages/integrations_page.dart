import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/controllers/openhab_controller.dart';
import '../../../../core/providers/installation_provider.dart';
import '../../../../core/providers/role_provider.dart';
import 'package:mobile/core/widget/access_denied_view.dart';
import '../../../../core/theme/app_colors.dart';

class _Integration {
  final String id;
  final String addonId;
  final String name;
  final String description;
  final Widget icon;
  final Color color;
  final String category;
  bool isInstalled;
  bool isLoading;

  _Integration({
    required this.id,
    required this.addonId,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.category,
  }) : isInstalled = false,
     isLoading = false;
}

class IntegrationsPage extends StatefulWidget {
  const IntegrationsPage({super.key});

  @override
  State<IntegrationsPage> createState() => _IntegrationsPageState();
}

class _IntegrationsPageState extends State<IntegrationsPage>
    with SingleTickerProviderStateMixin {
  final _ctrl = OpenHABController.instance;

  bool    _isLoading = true;
  String? _errorMsg;
  Set<String> _installedAddonIds = {};
  String _selectedCategory = 'all';

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  late AnimationController _animCtrl;
  late List<_Integration> _integrations;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _initIntegrations();
    _loadAddons();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _initIntegrations() {
    _integrations = [
      _Integration(
        id: 'google_home',
        addonId: 'org.openhab.io.openhabcloud',
        name: 'Google Home',
        description: 'Kontrol perangkat via Google Assistant',
        icon: _GoogleIcon(),
        color: const Color(0xFF4285F4),
        category: 'voice',
      ),
      _Integration(
        id: 'alexa',
        addonId: 'org.openhab.io.openhabcloud',
        name: 'Amazon Alexa',
        description: 'Integrasi dengan Amazon Echo & Alexa',
        icon: _AlexaIcon(),
        color: const Color(0xFF00CAFF),
        category: 'voice',
      ),
      _Integration(
        id: 'homekit',
        addonId: 'org.openhab.io.homekit',
        name: 'Apple HomeKit',
        description: 'Kontrol via Siri & Apple Home app',
        icon: _HomeKitIcon(),
        color: const Color(0xFFFFA500),
        category: 'voice',
      ),
      _Integration(
        id: 'mqtt',
        addonId: 'org.openhab.binding.mqtt',
        name: 'MQTT',
        description: 'Protokol messaging IoT ringan',
        icon: const _AddonIcon(icon: FontAwesomeIcons.networkWired, color: Color(0xFF6366F1)),
        color: const Color(0xFF6366F1),
        category: 'protocol',
      ),
      _Integration(
        id: 'zigbee',
        addonId: 'org.openhab.binding.zigbee',
        name: 'Zigbee',
        description: 'Protokol wireless hemat daya',
        icon: const _AddonIcon(icon: FontAwesomeIcons.bolt, color: Color(0xFFF59E0B)),
        color: const Color(0xFFF59E0B),
        category: 'protocol',
      ),
      _Integration(
        id: 'zwave',
        addonId: 'org.openhab.binding.zwave',
        name: 'Z-Wave',
        description: 'Protokol mesh untuk smart home',
        icon: const _AddonIcon(icon: FontAwesomeIcons.wifi, color: Color(0xFF8B5CF6)),
        color: const Color(0xFF8B5CF6),
        category: 'protocol',
      ),
      _Integration(
        id: 'matter',
        addonId: 'org.openhab.binding.matter',
        name: 'Matter',
        description: 'Standar interoperabilitas smart home terbaru',
        icon: const _AddonIcon(icon: FontAwesomeIcons.atom, color: Color(0xFF06B6D4)),
        color: const Color(0xFF06B6D4),
        category: 'protocol',
      ),
      _Integration(
        id: 'philips_hue',
        addonId: 'org.openhab.binding.hue',
        name: 'Philips Hue',
        description: 'Lampu pintar Philips Hue',
        icon: const _AddonIcon(icon: FontAwesomeIcons.lightbulb, color: Color(0xFFEAB308)),
        color: const Color(0xFFEAB308),
        category: 'protocol',
      ),
      _Integration(
        id: 'openhab_cloud',
        addonId: 'org.openhab.io.openhabcloud',
        name: 'openHAB Cloud',
        description: 'Remote access & notifikasi via cloud',
        icon: const _AddonIcon(icon: FontAwesomeIcons.cloud, color: Color(0xFF3B82F6)),
        color: const Color(0xFF3B82F6),
        category: 'cloud',
      ),
      _Integration(
        id: 'influxdb',
        addonId: 'org.openhab.persistence.influxdb',
        name: 'InfluxDB',
        description: 'Simpan data historis ke InfluxDB',
        icon: const _AddonIcon(icon: FontAwesomeIcons.database, color: Color(0xFF22D3EE)),
        color: const Color(0xFF22D3EE),
        category: 'cloud',
      ),
      _Integration(
        id: 'modbus',
        addonId: 'org.openhab.binding.modbus',
        name: 'Modbus',
        description: 'Protokol industri untuk sensor & aktuator',
        icon: const _AddonIcon(icon: FontAwesomeIcons.industry, color: Color(0xFF64748B)),
        color: const Color(0xFF64748B),
        category: 'local',
      ),
      _Integration(
        id: 'knx',
        addonId: 'org.openhab.binding.knx',
        name: 'KNX',
        description: 'Bus instalasi bangunan standar Eropa',
        icon: const _AddonIcon(icon: FontAwesomeIcons.buildingShield, color: Color(0xFFEC4899)),
        color: const Color(0xFFEC4899),
        category: 'local',
      ),
    ];
  }

  Future<void> _loadAddons() async {
    setState(() { _isLoading = true; _errorMsg = null; });
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

      final res = await http.get(
        Uri.parse('${_ctrl.serverUrl}/rest/addons?fields=id,installed'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        _installedAddonIds = list
            .where((a) => (a as Map<String, dynamic>)['installed'] == true)
            .map((a) => (a as Map<String, dynamic>)['id'] as String)
            .toSet();

        for (final intg in _integrations) {
          intg.isInstalled = _installedAddonIds.any(
            (id) => id.contains(intg.addonId) || intg.addonId.contains(id),
          );
        }
      }

      unawaited(_animCtrl.forward(from: 0));
    } catch (e) {
      setState(() => _errorMsg = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<_Integration> get _filtered {
    Iterable<_Integration> list = _selectedCategory == 'all'
        ? _integrations
        : _integrations.where((i) => i.category == _selectedCategory);

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((i) =>
          i.name.toLowerCase().contains(q) ||
          i.description.toLowerCase().contains(q));
    }

    return list.toList();
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
  }

  int get _installedCount => _integrations.where((i) => i.isInstalled).length;

  Future<void> _toggleAddon(_Integration intg) async {
    setState(() => intg.isLoading = true);
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

      String? exactId;
      try {
        final listRes = await http.get(
          Uri.parse('${_ctrl.serverUrl}/rest/addons?fields=id,installed,type'),
          headers: headers,
        ).timeout(const Duration(seconds: 10));

        if (listRes.statusCode == 200) {
          final list = jsonDecode(listRes.body) as List;
          final shortName = intg.addonId.split('.').last;
          for (final a in list.cast<Map<String, dynamic>>()) {
            final id = a['id'] as String;
            if (id == intg.addonId || id.endsWith(shortName) || id.contains(shortName)) {
              exactId = id;
              break;
            }
          }
        }
      } catch (_) {}

      if (exactId == null) {
        _showSnack(
          'Addon "${intg.name}" tidak ditemukan di server. Coba install melalui Add-on Store.',
          isError: true,
        );
        return;
      }

      final action = intg.isInstalled ? 'uninstall' : 'install';
      final url = Uri.parse('${_ctrl.serverUrl}/rest/addons/$exactId/$action');

      final res = await http.post(url, headers: headers)
          .timeout(const Duration(seconds: 30));

      if (res.statusCode == 200 || res.statusCode == 202 || res.statusCode == 204) {
        setState(() => intg.isInstalled = !intg.isInstalled);
        _showSnack(
          !intg.isInstalled
              ? '${intg.name} berhasil diinstall'
              : '${intg.name} berhasil dihapus',
          isError: false,
        );
      } else {
        _showSnack(
          'Gagal install "${intg.name}" (HTTP ${res.statusCode}). Coba via Add-on Store.',
          isError: true,
        );
      }
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => intg.isLoading = false);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Inter', fontSize: 13)),
      backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Guard app-level: openHAB tidak tahu konsep role di app ini,
    // jadi ini satu-satunya lapisan proteksi untuk halaman admin-only.
    if (!context.watch<RoleProvider>().isAdmin) {
      return const AccessDeniedView(featureName: 'Integrations');
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 18, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Integrations',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: cs.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: _isLoading
                ? SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.onSurface))
                : Icon(Icons.refresh_rounded, size: 22, color: cs.onSurface),
            onPressed: _isLoading ? null : _loadAddons,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _errorMsg != null ? _buildError() : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_off_rounded, size: 56, color: Colors.red.shade300),
          const SizedBox(height: 14),
          Text('Gagal memuat integrasi',
              style: TextStyle(fontFamily: 'Inter',
                  fontWeight: FontWeight.w700, fontSize: 16,
                  color: Colors.red.shade700)),
          const SizedBox(height: 6),
          Text(_errorMsg!, textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                  color: Colors.red.shade400)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadAddons,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                elevation: 0),
            icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
            label: const Text('Coba Lagi',
                style: TextStyle(fontFamily: 'Inter',
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  Widget _buildContent() {
    return RefreshIndicator(
      onRefresh: _loadAddons,
      color: AppColors.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummary(),
                  const SizedBox(height: 16),
                  _buildSearchBar(),
                  const SizedBox(height: 16),
                  _buildCategoryChips(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          _filtered.isEmpty
              ? SliverFillRemaining(child: _buildEmpty())
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final intg = _filtered[i];
                        return AnimatedBuilder(
                          animation: _animCtrl,
                          builder: (_, child) {
                            final delay = (i * 0.05).clamp(0.0, 0.6);
                            final progress =
                                ((_animCtrl.value - delay) / (1.0 - delay)).clamp(0.0, 1.0);
                            return Opacity(
                              opacity: _isLoading ? 1.0 : progress,
                              child: Transform.translate(
                                offset: Offset(0, _isLoading ? 0 : 16 * (1 - progress)),
                                child: child,
                              ),
                            );
                          },
                          child: _IntegrationCard(
                            integration: intg,
                            isLoading: _isLoading,
                            onToggle: () => _toggleAddon(intg),
                            onTap: () => _showDetail(intg),
                          ),
                        );
                      },
                      childCount: _filtered.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    return Row(children: [
      Expanded(child: _SummaryCard(
        label: 'Total',
        count: _integrations.length,
        color: AppColors.primary,
        icon: Icons.extension_rounded,
        isLoading: _isLoading,
      )),
      const SizedBox(width: 10),
      Expanded(child: _SummaryCard(
        label: 'Installed',
        count: _installedCount,
        color: const Color(0xFF22C55E),
        icon: Icons.check_circle_rounded,
        isLoading: _isLoading,
      )),
      const SizedBox(width: 10),
      Expanded(child: _SummaryCard(
        label: 'Available',
        count: _integrations.length - _installedCount,
        color: const Color(0xFF94A3B8),
        icon: Icons.download_rounded,
        isLoading: _isLoading,
      )),
    ]);
  }

  Widget _buildSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: isDark ? Colors.white : const Color(0xFF18181B),
        ),
        decoration: InputDecoration(
          hintText: 'Cari integrasi...',
          hintStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: isDark ? Colors.white38 : Colors.grey.shade400,
          ),
          prefixIcon: Icon(Icons.search_rounded,
              size: 20,
              color: isDark ? Colors.white38 : Colors.grey.shade400),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close_rounded,
                      size: 18,
                      color: isDark ? Colors.white38 : Colors.grey.shade400),
                  onPressed: () {
                    _searchCtrl.clear();
                    _onSearchChanged('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final categories = [
      {'key': 'all',      'label': 'Semua',   'icon': Icons.grid_view_rounded},
      {'key': 'voice',    'label': 'Voice',    'icon': Icons.mic_rounded},
      {'key': 'protocol', 'label': 'Protocol', 'icon': Icons.hub_rounded},
      {'key': 'cloud',    'label': 'Cloud',    'icon': Icons.cloud_rounded},
      {'key': 'local',    'label': 'Local',    'icon': Icons.home_rounded},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((cat) {
          final isSelected = _selectedCategory == cat['key'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedCategory = cat['key']! as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? const Color(0xFF27272A) : Colors.white),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7)),
                    width: 1.5,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(cat['icon']! as IconData,
                      size: 13,
                      color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.white60 : const Color(0xFF71717A))),
                  const SizedBox(width: 6),
                  Text(cat['label']! as String,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white70 : const Color(0xFF52525B)))),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmpty() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.extension_off_rounded,
              size: 56,
              color: isDark ? const Color(0xFF3F3F46) : Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'Tidak ada integrasi',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: isDark ? Colors.white38 : Colors.grey.shade500,
            ),
          ),
          Text(
            _searchQuery.isNotEmpty
                ? 'Tidak ada integrasi yang cocok dengan "$_searchQuery".'
                : 'Tidak ada integrasi pada kategori ini.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: isDark ? Colors.white30 : Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  void _showDetail(_Integration intg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _IntegrationDetailSheet(
        integration: intg,
        onToggle: () {
          Navigator.pop(context);
          _toggleAddon(intg);
        },
      ),
    );
  }
}

class _IntegrationCard extends StatelessWidget {
  final _Integration integration;
  final bool isLoading;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  const _IntegrationCard({
    required this.integration,
    required this.isLoading,
    required this.onToggle,
    required this.onTap,
  });

  String get _categoryLabel {
    switch (integration.category) {
      case 'voice':    return 'Voice';
      case 'protocol': return 'Protocol';
      case 'cloud':    return 'Cloud';
      case 'local':    return 'Local';
      default:         return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = integration.color;
    final installed = integration.isInstalled;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              // Icon
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.15 : 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(child: SizedBox(width: 28, height: 28, child: integration.icon)),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(integration.name,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: isDark ? Colors.white : const Color(0xCC18181B))),
                  const SizedBox(height: 3),
                  Text(integration.description,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: isDark ? Colors.white54 : const Color(0xFF71717A))),
                  const SizedBox(height: 6),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_categoryLabel,
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                              color: color)),
                    ),
                    const SizedBox(width: 6),
                    if (!isLoading)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: installed
                              ? const Color(0xFF22C55E).withValues(alpha: isDark ? 0.2 : 0.1)
                              : const Color(0xFF94A3B8).withValues(alpha: isDark ? 0.2 : 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 6, height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: installed
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(installed ? 'Installed' : 'Not installed',
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                  color: installed
                                      ? const Color(0xFF22C55E)
                                      : const Color(0xFF94A3B8))),
                        ]),
                      ),
                    if (isLoading)
                      Container(
                        width: 60, height: 18,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF3F3F46) : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                  ]),
                ],
              )),

              const SizedBox(width: 10),
              if (integration.isLoading)
                SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2,
                        color: isDark ? Colors.white54 : const Color(0xFF71717A)))
              else if (isLoading)
                Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF3F3F46) : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(10)))
              else
                GestureDetector(
                  onTap: onToggle,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: installed
                          ? const Color(0xFFEF4444).withValues(alpha: isDark ? 0.15 : 0.08)
                          : color.withValues(alpha: isDark ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      installed
                          ? Icons.remove_circle_outline_rounded
                          : Icons.download_rounded,
                      size: 18,
                      color: installed ? const Color(0xFFEF4444) : color,
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _IntegrationDetailSheet extends StatelessWidget {
  final _Integration integration;
  final VoidCallback onToggle;

  const _IntegrationDetailSheet({required this.integration, required this.onToggle});

  String get _categoryLabel {
    switch (integration.category) {
      case 'voice':    return 'Voice Assistant';
      case 'protocol': return 'Protocol / Binding';
      case 'cloud':    return 'Cloud Service';
      case 'local':    return 'Local Protocol';
      default:         return 'Integration';
    }
  }

  String get _detailDesc {
    switch (integration.id) {
      case 'google_home':
        return 'Hubungkan openHAB dengan Google Home untuk mengontrol perangkat via Google Assistant. Memerlukan openHAB Cloud Connector.';
      case 'alexa':
        return 'Integrasikan openHAB dengan Amazon Alexa. Kontrol lampu, thermostat, dan perangkat lain via suara. Memerlukan openHAB Cloud Connector.';
      case 'homekit':
        return 'Expose item openHAB ke Apple HomeKit sehingga bisa dikontrol via Siri, iPhone, dan Apple Watch.';
      case 'mqtt':
        return 'MQTT adalah protokol messaging ringan untuk IoT. Binding ini memungkinkan openHAB berkomunikasi dengan broker MQTT seperti Mosquitto.';
      case 'zigbee':
        return 'Zigbee adalah protokol wireless mesh berdaya rendah. Dukung ratusan perangkat dari berbagai merek.';
      case 'zwave':
        return 'Z-Wave adalah protokol wireless untuk smart home. Aman, stabil, dan kompatibel dengan ribuan perangkat.';
      case 'matter':
        return 'Matter adalah standar interoperabilitas terbaru yang didukung oleh Apple, Google, Amazon, dan Samsung.';
      case 'philips_hue':
        return 'Integrasi langsung dengan Philips Hue Bridge untuk mengontrol lampu, grup, dan scene Hue.';
      case 'openhab_cloud':
        return 'openHAB Cloud Connector menghubungkan instalasi lokal ke myopenhab.org untuk akses remote dan notifikasi push.';
      case 'influxdb':
        return 'Simpan data historis item openHAB ke database InfluxDB untuk analitik dan visualisasi dengan Grafana.';
      case 'modbus':
        return 'Modbus adalah protokol komunikasi serial untuk sistem otomasi industri. Dukung Modbus RTU dan TCP.';
      case 'knx':
        return 'KNX adalah standar bus instalasi bangunan yang banyak digunakan di Eropa untuk otomasi gedung.';
      default:
        return integration.description;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = integration.color;
    final installed = integration.isInstalled;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7),
                borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 24),

        Row(children: [
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(18)),
            child: Center(child: SizedBox(width: 32, height: 32, child: integration.icon)),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(integration.name,
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: isDark ? Colors.white : const Color(0xCC18181B))),
              const SizedBox(height: 4),
              Row(children: [
                _pill(_categoryLabel, color),
                const SizedBox(width: 8),
                _pill(
                  installed ? 'Installed' : 'Not installed',
                  installed ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
                ),
              ]),
            ],
          )),
        ]),

        const SizedBox(height: 20),
        Divider(height: 1, color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF0F0F0)),
        const SizedBox(height: 16),

        Text(_detailDesc,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: isDark ? Colors.white70 : const Color(0xFF52525B),
                height: 1.6)),

        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
              borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.code_rounded, size: 14,
                color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
            const SizedBox(width: 8),
            Expanded(child: Text(integration.addonId,
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8)))),
          ]),
        ),

        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onToggle,
            style: ElevatedButton.styleFrom(
              backgroundColor: installed ? const Color(0xFFEF4444) : color,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            icon: Icon(
              installed ? Icons.delete_outline_rounded : Icons.download_rounded,
              color: Colors.white, size: 18,
            ),
            label: Text(
              installed ? 'Uninstall' : 'Install',
              style: const TextStyle(fontFamily: 'Inter',
                  fontWeight: FontWeight.w600, fontSize: 15, color: Colors.white),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20)),
    child: Text(label,
        style: TextStyle(fontFamily: 'Inter',
            fontWeight: FontWeight.w700, fontSize: 11, color: color)),
  );
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  final bool isLoading;

  const _SummaryCard({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Center(child: Icon(icon, size: 16, color: color))),
        const SizedBox(height: 10),
        isLoading
            ? Container(
                width: 30, height: 22,
                decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF3F3F46) : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(6)))
            : Text('$count',
                style: TextStyle(fontFamily: 'Inter',
                    fontWeight: FontWeight.w800, fontSize: 22, color: color)),
        Text(label,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: isDark ? Colors.white54 : const Color(0xFF71717A),
                fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

class _AddonIcon extends StatelessWidget {
  final FaIconData icon;
  final Color color;
  const _AddonIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) =>
      Center(child: FaIcon(icon, size: 20, color: color));
}

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GooglePainter());
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

class _AlexaIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
        color: const Color(0xFF00CAFF),
        borderRadius: BorderRadius.circular(8)),
    child: const Center(
        child: Text('a',
            style: TextStyle(fontFamily: 'Inter',
                fontWeight: FontWeight.w700, fontSize: 16,
                color: Colors.white, height: 1))),
  );
}

class _HomeKitIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
        color: const Color(0xFFFFA500),
        borderRadius: BorderRadius.circular(8)),
    child: const Center(
        child: FaIcon(FontAwesomeIcons.house, size: 14, color: Colors.white)),
  );
}