import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mobile/core/providers/installation_provider.dart';
import 'package:mobile/core/providers/role_provider.dart';
import 'package:mobile/core/services/openhab_management_service.dart';
import 'package:mobile/core/controllers/openhab_controller.dart';
import 'package:mobile/pages/add_thing_page.dart';
import 'package:mobile/pages/edit_thing_page.dart';
import 'package:mobile/pages/discovery_page.dart';
import 'package:mobile/pages/map_thing_to_room_page.dart'; // [MAPPING]
import 'package:mobile/core/utils/responsive_utils.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';

class ThingsManagementPage extends StatefulWidget {
  const ThingsManagementPage({super.key});

  @override
  State<ThingsManagementPage> createState() => _ThingsManagementPageState();
}

class _ThingsManagementPageState extends State<ThingsManagementPage>
    with SingleTickerProviderStateMixin {
  final _mgmt = OpenHABManagementService();
  final _ctrl = OpenHABController.instance;

  List<OHThing> _allThings = [];
  List<OHThing> _filteredThings = [];
  bool _isLoading = false;
  String? _errorMsg;

  String _filterStatus = 'all';

  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _mgmt.setBaseUrl(_ctrl.serverUrl);
    _initAndLoad();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _initAndLoad() async {
  final config = context.read<InstallationProvider>().config;
 
  if (config != null) {
    if (config.apiToken != null && config.apiToken!.isNotEmpty) {
      _mgmt.setApiToken(config.apiToken!);
    } else if (config.username != null && config.password != null) {
      _mgmt.setBasicAuth(config.username!, config.password!);
    }
    _mgmt.setBaseUrl(config.openhabUrl);
  }
 
  await _loadThings(); // atau _loadItems() untuk ItemsManagementPage
}

  Future<void> _loadThings() async {
    setState(() {
      _isLoading = true;
      _errorMsg  = null;
    });
    try {
      final things = await _mgmt.getThings();
      setState(() {
        _allThings = things;
        _applyFilter();
      });
      unawaited(_animCtrl.forward(from: 0));
    } catch (e) {
      setState(() => _errorMsg = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    setState(() {
      switch (_filterStatus) {
        case 'online':
          _filteredThings =
              _allThings.where((t) => t.status == 'ONLINE').toList();
          break;
        case 'offline':
          _filteredThings =
              _allThings.where((t) => t.status == 'OFFLINE').toList();
          break;
        case 'error':
          _filteredThings = _allThings
              .where((t) => t.status != 'ONLINE' && t.status != 'OFFLINE')
              .toList();
          break;
        default:
          _filteredThings = List.from(_allThings);
      }
    });
  }
  int get _onlineCount  => _allThings.where((t) => t.status == 'ONLINE').length;
  int get _offlineCount => _allThings.where((t) => t.status == 'OFFLINE').length;
  int get _errorCount   => _allThings
      .where((t) => t.status != 'ONLINE' && t.status != 'OFFLINE').length;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      appBar: _buildAppBar(isDark),
      body: _isLoading
          ? _buildLoadingState()
          : _errorMsg != null
              ? _buildErrorState()
              : _buildContent(isDark),
    );
  }

  AppBar _buildAppBar(bool isDark) {
    final isAdmin = context.watch<RoleProvider>().isAdmin;
    return AppBar(
      backgroundColor: isDark ? const Color(0xFF27272A) : Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new,
            size: 18,
            color: isDark ? Colors.white : const Color(0xFF18181B)),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Things',
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: isDark ? Colors.white : const Color(0xCC18181B),
        ),
      ),
      actions: [
        if (isAdmin)
          IconButton(
            icon: Icon(Icons.add_rounded,
                size: 24,
                color: isDark ? Colors.white : const Color(0xFF18181B)),
            tooltip: 'Tambah Thing',
            onPressed: () async {
              final before = _allThings.map((t) => t.uid).toSet(); // [MAPPING]
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddThingPage()),
              );
              if (result == true) {
                await _loadThings();
                await _offerMapping(before); // [MAPPING]
              }
            },
          ),
        if (isAdmin)
          IconButton(
            icon: FaIcon(FontAwesomeIcons.magnifyingGlass,
                size: 20,
                color: isDark ? Colors.white : const Color(0xFF18181B)),
            tooltip: 'Discovery',
            onPressed: () async {
              final before = _allThings.map((t) => t.uid).toSet(); // [MAPPING]
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DiscoveryPage()),
              );
              if (result == true) {
                await _loadThings();
                await _offerMapping(before); // [MAPPING]
              }
            },
          ),
        IconButton(
          icon: Icon(Icons.refresh_rounded,
              size: 22,
              color: isDark ? Colors.white : const Color(0xFF18181B)),
          onPressed: _loadThings,
          tooltip: 'Refresh',
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: 14),
        const Text(
          'Memuat Things...',
          style: TextStyle(
              fontFamily: 'Inter', fontSize: 13, color: AppColors.textMuted),
        ),
      ]),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_off_rounded, size: 56, color: Colors.red.shade300),
          const SizedBox(height: 14),
          Text(
            'Gagal memuat Things',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Colors.red.shade700),
          ),
          const SizedBox(height: 6),
          Text(
            _errorMsg!,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Inter', fontSize: 12, color: Colors.red.shade400),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadThings,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
            label: const Text(
              'Coba Lagi',
              style: TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.white,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadThings,
      color: AppColors.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  ResponsiveUtils.horizontalPadding(context), 16,
                  ResponsiveUtils.horizontalPadding(context), 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryCards(isDark),
                  const SizedBox(height: 20),
                  _buildFilterChips(isDark),
                  const SizedBox(height: 16),
                  _buildListHeader(isDark),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          _filteredThings.isEmpty
              ? SliverFillRemaining(child: _buildEmptyState(isDark))
              : SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      ResponsiveUtils.horizontalPadding(context), 0,
                      ResponsiveUtils.horizontalPadding(context), 40),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final thing = _filteredThings[i];
                        return AnimatedBuilder(
                          animation: _animCtrl,
                          builder: (ctx, child) {
                            final delay =
                                (i * 0.05).clamp(0.0, 0.5);
                            final progress =
                                ((_animCtrl.value - delay) / (1.0 - delay))
                                    .clamp(0.0, 1.0);
                            return Opacity(
                              opacity: progress,
                              child: Transform.translate(
                                offset: Offset(0, 20 * (1 - progress)),
                                child: child,
                              ),
                            );
                          },
                          child: _ThingCard(
                            thing: thing,
                            isDark: isDark,
                            onTap: () => _showThingDetail(thing),
                          ),
                        );
                      },
                      childCount: _filteredThings.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(bool isDark) {
    return Row(children: [
      Expanded(
        child: _SummaryCard(
          isDark: isDark,
          label: 'Total',
          count: _allThings.length,
          color: const Color(0xFF6366F1),
          icon: FontAwesomeIcons.microchip,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _SummaryCard(
          isDark: isDark,
          label: 'Online',
          count: _onlineCount,
          color: const Color(0xFF22C55E),
          icon: FontAwesomeIcons.circleCheck,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _SummaryCard(
          isDark: isDark,
          label: 'Error',
          count: _errorCount,
          color: const Color(0xFFEF4444),
          icon: FontAwesomeIcons.circleExclamation,
        ),
      ),
    ]);
  }

  Widget _buildFilterChips(bool isDark) {
    final filters = [
      {'key': 'all',     'label': 'Semua',   'count': _allThings.length},
      {'key': 'online',  'label': 'Online',  'count': _onlineCount},
      {'key': 'offline', 'label': 'Offline', 'count': _offlineCount},
      {'key': 'error',   'label': 'Error',   'count': _errorCount},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final isSelected = _filterStatus == f['key'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() => _filterStatus = f['key']! as String);
                _applyFilter();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? const Color(0xFF27272A) : Colors.white),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: isDark ? 0.2 : 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    f['label']! as String,
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
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.25)
                          : (isDark
                              ? const Color(0xFF3F3F46)
                              : const Color(0xFFF4F4F5)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${f['count']}',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: isSelected
                            ? Colors.white
                            : (isDark
                                ? Colors.white70
                                : const Color(0xFF71717A)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildListHeader(bool isDark) {
    return Row(children: [
      Text(
        '${_filteredThings.length} Thing${_filteredThings.length != 1 ? 's' : ''}',
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: isDark ? Colors.white : const Color(0xCC18181B),
        ),
      ),
      const Spacer(),
      Text(
        'Tarik untuk refresh',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          color: isDark ? Colors.white38 : Colors.grey.shade400,
        ),
      ),
    ]);
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.device_unknown_rounded,
            size: 56,
            color: isDark ? Colors.white24 : Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(
          'Tidak ada Thing',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: isDark ? Colors.white54 : Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _filterStatus == 'all'
              ? 'Belum ada Thing yang ditambahkan.'
              : 'Tidak ada Thing dengan status ini.',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: isDark ? Colors.white38 : Colors.grey.shade400,
          ),
        ),
      ]),
    );
  }

  // [MAPPING] Setelah Thing baru ditambahkan, tawarkan langsung pasang ke ruangan.
  Future<void> _offerMapping(Set<String> uidsBefore) async {
    if (!mounted) return;
    final added = _allThings.where((t) => !uidsBefore.contains(t.uid)).toList();
    if (added.isEmpty) return;
    final thing = added.first;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thing ditambahkan'),
        content: Text(
            'Pasang "${thing.label.isNotEmpty ? thing.label : thing.uid}" ke '
            'ruangan sekarang agar tampil dan bisa dikontrol di Floorplan?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nanti')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Pasang Sekarang')),
        ],
      ),
    );
    if (go == true && mounted) await _openMapping(thing);
  }

  Future<void> _openMapping(OHThing thing) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MapThingToRoomPage(thing: thing)),
    );
    if (mounted) await _loadThings(); // status link channel ikut ter-update
  }

  void _showThingDetail(OHThing thing) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ThingDetailSheet(
        thing: thing,
        isDark: isDark,
        onMap: () {
          Navigator.pop(context); // tutup bottom sheet
          _openMapping(thing); // [MAPPING]
        },
        onEdit: () async {
          Navigator.pop(context); // tutup bottom sheet dulu
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EditThingPage(thing: thing)),
          );
          // Selalu muat ulang dari server (bukan update state lokal) supaya
          // yang tampil adalah konfigurasi yang benar-benar tersimpan.
          if (result == true) await _loadThings();
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final bool isDark;
  final String label;
  final int count;
  final Color color;
  final FaIconData icon;

  const _SummaryCard({
    required this.isDark,
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: FaIcon(icon, size: 14, color: color)),
        ),
        const SizedBox(height: 10),
        Text(
          '$count',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w800,
            fontSize: 22,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            color: isDark ? Colors.white54 : AppColors.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ]),
    );
  }
}

class _ThingCard extends StatelessWidget {
  final OHThing thing;
  final bool isDark;
  final VoidCallback onTap;

  const _ThingCard({
    required this.thing,
    required this.isDark,
    required this.onTap,
  });

  Color get _statusColor {
    switch (thing.status) {
      case 'ONLINE':  return const Color(0xFF22C55E);
      case 'OFFLINE': return const Color(0xFF94A3B8);
      default:        return const Color(0xFFEF4444);
    }
  }

  FaIconData get _statusIcon {
    switch (thing.status) {
      case 'ONLINE':  return FontAwesomeIcons.circleCheck;
      case 'OFFLINE': return FontAwesomeIcons.circleXmark;
      default:        return FontAwesomeIcons.circleExclamation;
    }
  }

  String get _statusLabel {
    switch (thing.status) {
      case 'ONLINE':  return 'Online';
      case 'OFFLINE': return 'Offline';
      default:        return thing.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
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
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: FaIcon(FontAwesomeIcons.microchip,
                      size: 20, color: _statusColor),
                ),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thing.label.isNotEmpty ? thing.label : thing.uid,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: isDark ? Colors.white : const Color(0xCC18181B),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      thing.thingTypeUID,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: isDark ? Colors.white54 : AppColors.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          FaIcon(_statusIcon, size: 10, color: _statusColor),
                          const SizedBox(width: 4),
                          Text(
                            _statusLabel,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                              color: _statusColor,
                            ),
                          ),
                        ]),
                      ),
                      if (thing.channels.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${thing.channels.length} channels',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 10,
                              color:
                                  isDark ? Colors.white54 : AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  color: isDark
                      ? const Color(0xFF3F3F46)
                      : const Color(0xFFD4D4D8),
                  size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ThingDetailSheet extends StatelessWidget {
  final OHThing thing;
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback onMap; // [MAPPING]

  const _ThingDetailSheet({
    required this.thing,
    required this.isDark,
    required this.onEdit,
    required this.onMap, // [MAPPING]
  });

  Color get _statusColor {
    switch (thing.status) {
      case 'ONLINE':  return const Color(0xFF22C55E);
      case 'OFFLINE': return const Color(0xFF94A3B8);
      default:        return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF3F3F46)
                  : const Color(0xFFE4E4E7),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: FaIcon(FontAwesomeIcons.microchip,
                    size: 22, color: _statusColor),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                  thing.label.isNotEmpty ? thing.label : thing.uid,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: isDark ? Colors.white : const Color(0xCC18181B),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    thing.status,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: _statusColor,
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),

        const SizedBox(height: 20),
        Divider(
            height: 1,
            color:
                isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7)),
        const SizedBox(height: 16),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(children: [
            _InfoRow(label: 'UID',        value: thing.uid,        isDark: isDark),
            _InfoRow(label: 'Thing Type', value: thing.thingTypeUID, isDark: isDark),
            if (thing.statusDetail.isNotEmpty)
              _InfoRow(label: 'Detail', value: thing.statusDetail, isDark: isDark),
            _InfoRow(
                label: 'Channels',
                value: '${thing.channels.length} channel',
                isDark: isDark),
          ]),
        ),

        if (thing.channels.isNotEmpty) ...[
          const SizedBox(height: 16),
          Divider(
              height: 1,
              color: isDark
                  ? const Color(0xFF3F3F46)
                  : const Color(0xFFE4E4E7)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Channels',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color:
                        isDark ? Colors.white : const Color(0xCC18181B),
                  ),
                ),
                const SizedBox(height: 10),
                ...thing.channels.take(5).map((ch) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            color: ch.linkedItems.isNotEmpty
                                ? const Color(0xFF22C55E)
                                : (isDark
                                    ? const Color(0xFF3F3F46)
                                    : const Color(0xFFD4D4D8)),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            ch.label.isNotEmpty ? ch.label : ch.id,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xCC18181B),
                            ),
                          ),
                        ),
                        Text(
                          ch.itemType,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            color: isDark
                                ? Colors.white54
                                : AppColors.textMuted,
                          ),
                        ),
                      ]),
                    )),
                if (thing.channels.length > 5)
                  Text(
                    '+${thing.channels.length - 5} channel lainnya',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: isDark ? Colors.white54 : AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),
        // [MAPPING] Tombol utama: pasang Thing ke ruangan/floorplan
        if (thing.channels.any((c) => c.itemType.isNotEmpty))
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: onMap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.meeting_room_outlined,
                    size: 18, color: Colors.white),
                label: const Text('Pasang ke Ruangan',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Colors.white)),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: onEdit,
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                FaIcon(FontAwesomeIcons.penToSquare, size: 15,
                    color: isDark ? const Color(0xFF18181B) : Colors.white),
                const SizedBox(width: 10),
                Text('Edit Thing',
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: isDark ? const Color(0xFF18181B) : Colors.white)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _InfoRow({
      required this.label, required this.value, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: isDark ? Colors.white54 : AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: isDark ? const Color.fromARGB(255, 184, 89, 89) : const Color(0xCC18181B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ]),
    );
  }
}