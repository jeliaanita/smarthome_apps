import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mobile/core/services/openhab_management_service.dart';
import 'package:mobile/core/controllers/openhab_controller.dart';
import '../../../../core/providers/installation_provider.dart';
import '../../../../core/providers/role_provider.dart';
import 'package:mobile/core/widget/access_denied_view.dart';
import '../../../../core/theme/app_colors.dart';

class AddonStorePage extends StatefulWidget {
  const AddonStorePage({super.key});

  @override
  State<AddonStorePage> createState() => _AddonStorePageState();
}

class _AddonStorePageState extends State<AddonStorePage>
    with SingleTickerProviderStateMixin {
  final _mgmt = OpenHABManagementService();
  final _ctrl = OpenHABController.instance;

  late TabController _tabController;

  final _tabs = const [
    _TabItem('All',         null,          FontAwesomeIcons.store),
    _TabItem('Bindings',    'binding',     FontAwesomeIcons.plug),
    _TabItem('Automation',  'automation',  FontAwesomeIcons.robot),
    _TabItem('UI',          'ui',          FontAwesomeIcons.paintbrush),
    _TabItem('Persistence', 'persistence', FontAwesomeIcons.database),
    _TabItem('Transform',   'transform',   FontAwesomeIcons.shuffle),
    _TabItem('Voice',       'voice',       FontAwesomeIcons.microphone),
  ];

  final Map<String, List<OHAddon>> _addonCache   = {};
  final Map<String, bool>          _loadingMap   = {};
  final Map<String, String?>       _errorMap     = {};
  final Map<String, bool>          _installingMap = {};

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadTab(_tabs[_tabController.index].type);
      }
    });
    _initAndLoad();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initAndLoad() async {
    // Sama seperti add_thing_page.dart — indikator "sudah dikonfigurasi"
    // yang benar adalah server URL terisi, bukan ada-tidaknya token/username
    // (openHAB defaultnya tidak butuh auth sama sekali).
    if (_ctrl.serverUrl.isEmpty) {
      if (mounted) {
        setState(() => _errorMap['all'] =
          'openHAB belum dikonfigurasi. Silakan atur di Settings → openHAB Server.');
      }
      return;
    }

    final config = context.read<InstallationProvider>().config;
    final token    = config?.apiToken;
    final username = config?.username;
    final password = config?.password;

    _mgmt.setBaseUrl(_ctrl.serverUrl);
    if (token != null && token.isNotEmpty) {
      _mgmt.setApiToken(token);
    } else if (username != null && password != null) {
      _mgmt.setBasicAuth(username, password);
    }
    await _loadTab(null);
  }

  Future<void> _loadTab(String? type) async {
    final key = type ?? 'all';
    if (_addonCache.containsKey(key)) return;

    setState(() { _loadingMap[key] = true; _errorMap[key] = null; });
    try {
      final addons = await _mgmt.getAddons(type: type);
      setState(() => _addonCache[key] = addons);
    } catch (e) {
      setState(() => _errorMap[key] = e.toString());
    } finally {
      setState(() => _loadingMap[key] = false);
    }
  }

  Future<void> _toggleAddon(OHAddon addon) async {
    setState(() => _installingMap[addon.id] = true);
    try {
      final ok = addon.installed
          ? await _mgmt.uninstallAddon(addon.id)
          : await _mgmt.installAddon(addon.id);

      if (ok) {
        await Future.delayed(const Duration(seconds: 3));
        setState(() => _addonCache.clear());
        await _loadTab(_tabs[_tabController.index].type);
        if (mounted) {
          _showSnack(
            addon.installed
                ? '${addon.name} berhasil di-uninstall'
                : '${addon.name} berhasil di-install',
            addon.installed ? Colors.orange : AppColors.success,
          );
        }
      }
    } catch (e) {
      if (mounted) _showSnack('Gagal: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _installingMap.remove(addon.id));
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Inter', fontSize: 13)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  List<OHAddon> _filtered(String key) {
    final list = _addonCache[key] ?? [];
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list.where((a) =>
        a.name.toLowerCase().contains(q) ||
        a.description.toLowerCase().contains(q) ||
        a.id.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Guard app-level: openHAB tidak tahu konsep role di app ini,
    // jadi ini satu-satunya lapisan proteksi untuk halaman admin-only.
    if (!context.watch<RoleProvider>().isAdmin) {
      return const AccessDeniedView(featureName: 'Addon Store');
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      appBar: _buildAppBar(context),
      body: Column(children: [
        _buildSearchBar(context),
        _buildTabBar(context),
        Expanded(child: _buildTabViews(context)),
      ]),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      backgroundColor: cs.surface,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new, size: 18, color: cs.onSurface),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text('Add-on Store',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
              fontSize: 18, color: cs.onSurface)),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1,
            color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF0F0F0)),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _searchQuery = v.trim()),
          style: TextStyle(fontFamily: 'Inter', fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Cari addon...',
            hintStyle: TextStyle(fontFamily: 'Inter', fontSize: 13,
                color: isDark ? Colors.white38 : Colors.grey.shade400),
            prefixIcon: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FaIcon(FontAwesomeIcons.magnifyingGlass, size: 14,
                  color: isDark ? Colors.white38 : Colors.grey.shade400),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            suffixIcon: _searchQuery.isNotEmpty
                ? GestureDetector(
                    onTap: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: FaIcon(FontAwesomeIcons.xmark, size: 14,
                          color: isDark ? Colors.white38 : Colors.grey.shade400),
                    ),
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        labelColor: AppColors.primary,
        unselectedLabelColor: isDark ? Colors.white38 : Colors.grey.shade400,
        indicatorColor: AppColors.primary,
        indicatorWeight: 2.5,
        labelStyle: const TextStyle(
            fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelStyle: const TextStyle(
            fontFamily: 'Inter', fontWeight: FontWeight.w400, fontSize: 12),
        tabs: _tabs.map((t) => Tab(
          child: Row(children: [
            FaIcon(t.icon, size: 12),
            const SizedBox(width: 6),
            Text(t.label),
          ]),
        )).toList(),
        onTap: (i) => _loadTab(_tabs[i].type),
      ),
    );
  }

  Widget _buildTabViews(BuildContext context) {
    return TabBarView(
      controller: _tabController,
      children: _tabs.map((t) {
        final key       = t.type ?? 'all';
        final isLoading = _loadingMap[key] ?? false;
        final error     = _errorMap[key];
        final list      = _filtered(key);

        if (isLoading) return _buildLoading();
        if (error != null) return _buildError(error, t.type);
        if (list.isEmpty && _addonCache.containsKey(key)) return _buildEmpty(context);
        if (!_addonCache.containsKey(key)) return _buildLoading();

        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _addonCache.remove(key));
            await _loadTab(t.type);
          },
          color: AppColors.primary,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            itemCount: list.length,
            itemBuilder: (ctx, i) => _AddonCard(
              addon: list[i],
              isInstalling: _installingMap[list[i].id] ?? false,
              onToggle: () => _toggleAddon(list[i]),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLoading() {
    return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircularProgressIndicator(),
      SizedBox(height: 12),
      Text('Memuat addons...',
          style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: Color(0xFF71717A))),
    ]));
  }

  Widget _buildError(String error, String? type) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off, color: Colors.red, size: 48),
        const SizedBox(height: 12),
        Text(error, textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.red)),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            final key = type ?? 'all';
            setState(() => _addonCache.remove(key));
            _loadTab(type);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0,
          ),
          child: const Text('Coba Lagi',
              style: TextStyle(fontFamily: 'Inter', color: Colors.white,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    ));
  }

  Widget _buildEmpty(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.search_off, size: 48,
          color: isDark ? Colors.white24 : Colors.grey.shade300),
      const SizedBox(height: 12),
      Text(
        _searchQuery.isNotEmpty
            ? 'Tidak ada hasil untuk "$_searchQuery"'
            : 'Tidak ada addon tersedia',
        style: TextStyle(fontFamily: 'Inter', fontSize: 14,
            color: isDark ? Colors.white38 : Colors.grey.shade500),
      ),
    ]));
  }
}


class _AddonCard extends StatelessWidget {
  final OHAddon addon;
  final bool isInstalling;
  final VoidCallback onToggle;
  const _AddonCard({required this.addon, required this.isInstalling, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
              blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: addon.installed
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: FaIcon(_iconForType(addon.type), size: 20,
                color: addon.installed ? AppColors.primary
                    : (isDark ? Colors.white54 : const Color(0xFF71717A)))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(addon.name,
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
                      fontSize: 15, color: cs.onSurface))),
              if (addon.installed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Installed',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 10,
                          fontWeight: FontWeight.w600, color: AppColors.primary)),
                ),
            ]),
            if (addon.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(addon.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 12,
                      color: AppColors.textMuted)),
            ],
            const SizedBox(height: 8),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(addon.type,
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 10,
                        fontWeight: FontWeight.w600, color: AppColors.textMuted)),
              ),
              if (addon.version.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text('v${addon.version}',
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 11,
                        color: AppColors.textMuted)),
              ],
              const Spacer(),
              GestureDetector(
                onTap: isInstalling ? null : onToggle,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: addon.installed
                        ? (isDark ? Colors.red.shade900.withValues(alpha: 0.4) : Colors.red.shade50)
                        : AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: isInstalling
                      ? SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2,
                              color: addon.installed ? Colors.red : Colors.white))
                      : Text(
                          addon.installed ? 'Uninstall' : 'Install',
                          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: addon.installed
                                  ? (isDark ? Colors.red.shade300 : Colors.red.shade600)
                                  : Colors.white),
                        ),
                ),
              ),
            ]),
          ])),
        ]),
      ),
    );
  }

  FaIconData _iconForType(String type) {
    switch (type) {
      case 'binding':     return FontAwesomeIcons.plug;
      case 'automation':  return FontAwesomeIcons.robot;
      case 'ui':          return FontAwesomeIcons.paintbrush;
      case 'persistence': return FontAwesomeIcons.database;
      case 'transform':   return FontAwesomeIcons.shuffle;
      case 'voice':       return FontAwesomeIcons.microphone;
      default:            return FontAwesomeIcons.puzzlePiece;
    }
  }
}

class _TabItem {
  final String label;
  final String? type;
  final FaIconData icon;
  const _TabItem(this.label, this.type, this.icon);
}