import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/config/openhab_config.dart';
import 'package:mobile/core/controllers/openhab_controller.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../../../../core/providers/installation_provider.dart';


class _HubInfo {
  final String version;
  final String uptime;
  final int thingsOnline;
  final int thingsOffline;
  final int thingsTotal;
  final int activeRules;
  final int totalRules;
  final int scripts;
  final int pingMs;
  final DateTime lastSynced;

  const _HubInfo({
    required this.version,
    required this.uptime,
    required this.thingsOnline,
    required this.thingsOffline,
    required this.thingsTotal,
    required this.activeRules,
    required this.totalRules,
    required this.scripts,
    required this.pingMs,
    required this.lastSynced,
  });
}

class HubConnectivityPage extends StatefulWidget {
  const HubConnectivityPage({super.key});

  @override
  State<HubConnectivityPage> createState() => _HubConnectivityPageState();
}

class _HubConnectivityPageState extends State<HubConnectivityPage>
    with SingleTickerProviderStateMixin {
  final _ctrl = OpenHABController.instance;

  _HubInfo?  _info;
  bool       _isLoading = true;
  String?    _errorMsg;
  Map<String, String> _headers = {};

  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _ctrl.addListener(_onCtrlUpdate);
    _initAndLoad();
  }

  void _onCtrlUpdate() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _animCtrl.dispose();
    _ctrl.removeListener(_onCtrlUpdate);
    super.dispose();
  }

  Future<void> _initAndLoad() async {
    // ⚠️ FIX: sebelumnya baca dari OpenHABConfig (SharedPreferences lokal),
    // padahal proses SAVE (lihat _ServerConfigSheetMinState._save di bawah)
    // sudah dipindah ke InstallationProvider/Firestore. Local storage itu
    // sudah tidak pernah ditulisi lagi sejak migrasi, jadi selalu kosong →
    // request selalu tanpa auth → 401 kalau server memang butuh login.
    final config = context.read<InstallationProvider>().config;
    final token    = config?.apiToken;
    final username = config?.username;
    final password = config?.password;

    _headers = {'Accept': 'application/json'};
    if (token != null && token.isNotEmpty) {
      _headers['Authorization'] = 'Bearer $token';
    } else if (username != null && password != null) {
      final encoded = base64Encode(utf8.encode('$username:$password'));
      _headers['Authorization'] = 'Basic $encoded';
    }

    await _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      final base = _ctrl.serverUrl;
      final pingStart = DateTime.now();
      final rootRes = await http.get(
        Uri.parse('$base/rest/'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final pingMs = DateTime.now().difference(pingStart).inMilliseconds;

      String version = '-';
      String uptime  = '-';
      if (rootRes.statusCode == 200) {
        final root = jsonDecode(rootRes.body) as Map<String, dynamic>;
        version = root['version'] as String? ?? '-';
        final runtimeInfo = root['runtimeInfo'] as Map<String, dynamic>?;
        if (runtimeInfo != null) {
          version = runtimeInfo['version'] as String? ?? version;
        }
      }

      int thingsOnline  = 0;
      int thingsOffline = 0;
      int thingsTotal   = 0;
      try {
        final thingsRes = await http.get(
          Uri.parse('$base/rest/things?fields=UID,statusInfo'),
          headers: _headers,
        ).timeout(const Duration(seconds: 10));
        if (thingsRes.statusCode == 200) {
          final things = jsonDecode(thingsRes.body) as List;
          thingsTotal = things.length;
          for (final t in things) {
            final status = ((t as Map<String, dynamic>)['statusInfo']
                as Map<String, dynamic>?)?['status'] as String? ?? '';
            if (status == 'ONLINE') {
              thingsOnline++;
            } else {
              thingsOffline++;
            }
          }
        }
      } catch (_) {}
      int activeRules = 0;
      int totalRules  = 0;
      try {
        final rulesRes = await http.get(
          Uri.parse('$base/rest/rules?fields=uid,status'),
          headers: _headers,
        ).timeout(const Duration(seconds: 10));
        if (rulesRes.statusCode == 200) {
          final rules = jsonDecode(rulesRes.body) as List;
          totalRules = rules.length;
          for (final r in rules) {
            final status = ((r as Map<String, dynamic>)['status']
                as Map<String, dynamic>?)?['status'] as String? ?? '';
            if (status == 'IDLE' || status == 'RUNNING') activeRules++;
          }
        }
      } catch (_) {}
      int scripts = 0;
      try {
        final scriptsRes = await http.get(
          Uri.parse('$base/rest/rules?tags=Script&fields=uid'),
          headers: _headers,
        ).timeout(const Duration(seconds: 10));
        if (scriptsRes.statusCode == 200) {
          scripts = (jsonDecode(scriptsRes.body) as List).length;
        }
      } catch (_) {}
      try {
        final sysRes = await http.get(
          Uri.parse('$base/rest/systeminfo'),
          headers: _headers,
        ).timeout(const Duration(seconds: 8));
        if (sysRes.statusCode == 200) {
          final sys = jsonDecode(sysRes.body) as Map<String, dynamic>;
          final runtime = sys['systemInfo'] as Map<String, dynamic>?;
          if (runtime != null) {
            final uptimeMs = runtime['uptime'] as int?;
            if (uptimeMs != null) uptime = _formatUptime(uptimeMs);
          }
        }
      } catch (_) {}

      setState(() {
        _info = _HubInfo(
          version: version,
          uptime: uptime,
          thingsOnline: thingsOnline,
          thingsOffline: thingsOffline,
          thingsTotal: thingsTotal,
          activeRules: activeRules,
          totalRules: totalRules,
          scripts: scripts,
          pingMs: pingMs,
          lastSynced: DateTime.now(),
        );
      });
      unawaited(_animCtrl.forward(from: 0));
    } catch (e) {
      setState(() => _errorMsg = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatUptime(int ms) {
    final d = Duration(milliseconds: ms);
    if (d.inDays > 0)    return '${d.inDays}d ${d.inHours.remainder(24)}h';
    if (d.inHours > 0)   return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return '${d.inMinutes}m';
  }

  String _lastSyncedLabel(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60)  return 'Just now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  void _showServerConfigSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ServerConfigSheetMin(ctrl: _ctrl, onSaved: _loadAll),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              size: 18, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Hub & Connectivity',
            style: TextStyle(fontFamily: 'Inter',
                fontWeight: FontWeight.w700, fontSize: 18,
                color: cs.onSurface)),
        actions: [
          IconButton(
            icon: _isLoading
                ? SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2,
                        color: cs.onSurface))
                : Icon(Icons.refresh_rounded,
                    size: 22, color: cs.onSurface),
            onPressed: _isLoading ? null : _loadAll,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _errorMsg != null
          ? _buildError(context)
          : _buildContent(context),
    );
  }

  Widget _buildError(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.wifi_off_rounded, size: 56,
            color: Colors.red.shade300),
        const SizedBox(height: 14),
        Text('Gagal memuat info', style: TextStyle(
            fontFamily: 'Inter', fontWeight: FontWeight.w700,
            fontSize: 16,
            color: isDark ? Colors.red.shade300 : Colors.red.shade700)),
        const SizedBox(height: 6),
        Text(_errorMsg!, textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                color: isDark ? Colors.red.shade200 : Colors.red.shade400)),
        const SizedBox(height: 20),
        
        // ✅ TAMBAH INI
        ElevatedButton.icon(
          onPressed: _showServerConfigSheet,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              elevation: 0),
          icon: const Icon(Icons.settings, color: Colors.white, size: 16),
          label: const Text('Ubah Konfigurasi', style: TextStyle(
              fontFamily: 'Inter', color: Colors.white,
              fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 10),
        
        ElevatedButton.icon(
          onPressed: _loadAll,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              elevation: 0),
          icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
          label: const Text('Coba Lagi', style: TextStyle(
              fontFamily: 'Inter', color: Colors.white,
              fontWeight: FontWeight.w600)),
        ),
      ]),
    ),
  );
}
  Widget _buildContent(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: AnimatedBuilder(
          animation: _animCtrl,
          builder: (_, child) => Opacity(
            opacity: _animCtrl.value,
            child: Transform.translate(
              offset: Offset(0, 20 * (1 - _animCtrl.value)),
              child: child,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildServerCard(context),
              const SizedBox(height: 16),
              _buildQuickStats(context),
              const SizedBox(height: 16),
              _sectionLabel('NETWORK INFO', context),
              const SizedBox(height: 8),
              _buildNetworkCard(context),
              const SizedBox(height: 16),
              _sectionLabel('THINGS STATUS', context),
              const SizedBox(height: 8),
              _buildThingsCard(context),
              const SizedBox(height: 16),
              _sectionLabel('AUTOMATION', context),
              const SizedBox(height: 8),
              _buildAutomationCard(context),
              const SizedBox(height: 16),
              if (_info != null)
                Center(
                  child: Text(
                    'Last synced: ${_lastSyncedLabel(_info!.lastSynced)}',
                    style: TextStyle(fontFamily: 'Inter',
                        fontSize: 12,
                        color: isDark ? Colors.white38 : const Color(0xFF9E9E9E)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;
    final isConnected = _ctrl.isConnected;
    final url = _ctrl.serverUrl;
    final dividerColor = isDark ? const Color(0xFF3F3F46) : const Color(0xFFF0F0F0);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: isConnected
                    ? const Color(0xFF34C759).withValues(alpha: 0.12)
                    : const Color(0xFFFF3B30).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: FaIcon(
                isConnected
                    ? FontAwesomeIcons.server
                    : FontAwesomeIcons.plugCircleExclamation,
                size: 18,
                color: isConnected
                    ? const Color(0xFF34C759)
                    : const Color(0xFFFF3B30),
              )),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected ? 'Server Connected' : 'Server Disconnected',
                  style: TextStyle(
                    fontFamily: 'Inter', fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: isConnected
                        ? (isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xCC18181B))
                        : const Color(0xFFFF3B30),
                  ),
                ),
                const SizedBox(height: 2),
                Text(url.isNotEmpty ? url : 'Belum dikonfigurasi',
                    style: TextStyle(fontFamily: 'Inter',
                        fontSize: 12,
                        color: isDark ? Colors.white60 : const Color(0xFF71717A)),
                    overflow: TextOverflow.ellipsis),
              ],
            )),
            _PulseDot(isOnline: isConnected),
          ]),
        ),
        if (_ctrl.hasItems) ...[
          Divider(height: 1, color: dividerColor),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              _statPill(FontAwesomeIcons.toggleOn,
                  '${_ctrl.switchItems.length}', 'Switches',
                  const Color(0xFF34C759), context),
              const SizedBox(width: 10),
              _statPill(FontAwesomeIcons.sliders,
                  '${_ctrl.dimmerItems.length}', 'Dimmers',
                  const Color(0xFFFFA500), context),
              const SizedBox(width: 10),
              _statPill(FontAwesomeIcons.play,
                  '${_ctrl.playerItems.length}', 'Players',
                  const Color(0xFF0088FF), context),
            ]),
          ),
        ],

        Divider(height: 1, color: dividerColor),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: _showServerConfigSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      FaIcon(FontAwesomeIcons.penToSquare,
                          size: 13, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Configure', style: TextStyle(
                          fontFamily: 'Inter', fontWeight: FontWeight.w600,
                          fontSize: 14, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _ctrl.isLoading ? null : () {
                // ⚠️ FIX: sebelumnya panggil _ctrl.initialize() yang baca
                // kredensial dari OpenHABConfig (storage lama, sudah tidak
                // ditulisi lagi sejak migrasi ke Firestore) — jadi tombol
                // retry ini bisa reconnect TANPA kredensial padahal server
                // butuh auth. Sekarang pakai initializeWithConfig() dengan
                // config dari InstallationProvider, sama seperti alur
                // startup normal (lihat home_page.dart).
                final config = context.read<InstallationProvider>().config;
                if (config != null) {
                  _ctrl.initializeWithConfig(config);
                } else {
                  _ctrl.initialize();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 13),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF2F2F2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _ctrl.isLoading
                    ? SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: isDark ? Colors.white60 : const Color(0xFF71717A)))
                    : FaIcon(FontAwesomeIcons.arrowsRotate,
                        size: 16,
                        color: isDark ? Colors.white60 : const Color(0xFF71717A)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _statPill(FaIconData icon, String count, String label, Color color,
      BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        FaIcon(icon, size: 14, color: color),
        const SizedBox(height: 4),
        Text(count, style: TextStyle(fontFamily: 'Inter',
            fontWeight: FontWeight.w700, fontSize: 16, color: color)),
        Text(label, style: TextStyle(fontFamily: 'Inter',
            fontSize: 10, color: isDark ? Colors.white60 : const Color(0xFF71717A))),
      ]),
    ));
  }

  Widget _buildQuickStats(BuildContext context) {
    if (_isLoading || _info == null) {
      return Row(children: [
        Expanded(child: _skeletonCard(context)),
        const SizedBox(width: 10),
        Expanded(child: _skeletonCard(context)),
        const SizedBox(width: 10),
        Expanded(child: _skeletonCard(context)),
      ]);
    }
    return Row(children: [
      Expanded(child: _QuickStatCard(
        icon: Icons.speed_rounded,
        value: '${_info!.pingMs}ms',
        label: 'Ping',
        color: _pingColor(_info!.pingMs),
      )),
      const SizedBox(width: 10),
      Expanded(child: _QuickStatCard(
        icon: Icons.memory_rounded,
        value: _info!.version != '-' ? _info!.version : '-',
        label: 'Version',
        color: AppColors.primary,
      )),
      const SizedBox(width: 10),
      Expanded(child: _QuickStatCard(
        icon: Icons.access_time_rounded,
        value: _info!.uptime != '-' ? _info!.uptime : '-',
        label: 'Uptime',
        color: const Color(0xFF22C55E),
      )),
    ]);
  }

  Color _pingColor(int ms) {
    if (ms < 100) return const Color(0xFF22C55E);
    if (ms < 300) return const Color(0xFFFFA500);
    return const Color(0xFFEF4444);
  }

  Widget _buildNetworkCard(BuildContext context) {
    if (_isLoading || _info == null) return _skeletonCard(context, height: 120);
    return _InfoCard(rows: [
      _InfoCardRow(
        icon: Icons.language_rounded,
        label: 'Server URL',
        value: _ctrl.serverUrl.isNotEmpty ? _ctrl.serverUrl : '-',
        color: AppColors.primary,
      ),
      _InfoCardRow(
        icon: Icons.info_outline_rounded,
        label: 'openHAB Version',
        value: _info!.version,
        color: const Color(0xFF6366F1),
      ),
      _InfoCardRow(
        icon: Icons.timer_outlined,
        label: 'Uptime',
        value: _info!.uptime,
        color: const Color(0xFF22C55E),
      ),
      _InfoCardRow(
        icon: Icons.network_ping_rounded,
        label: 'Response Time',
        value: '${_info!.pingMs} ms',
        color: _pingColor(_info!.pingMs),
        valueColor: _pingColor(_info!.pingMs),
      ),
    ]);
  }

  Widget _buildThingsCard(BuildContext context) {
    if (_isLoading || _info == null) return _skeletonCard(context, height: 140);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;
    final onlinePct = _info!.thingsTotal > 0
        ? _info!.thingsOnline / _info!.thingsTotal
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _dot(const Color(0xFF22C55E)),
          const SizedBox(width: 8),
          Text('${_info!.thingsOnline} Online',
              style: const TextStyle(fontFamily: 'Inter',
                  fontWeight: FontWeight.w600, fontSize: 14,
                  color: Color(0xFF22C55E))),
          const SizedBox(width: 16),
          _dot(const Color(0xFFEF4444)),
          const SizedBox(width: 8),
          Text('${_info!.thingsOffline} Offline',
              style: const TextStyle(fontFamily: 'Inter',
                  fontWeight: FontWeight.w600, fontSize: 14,
                  color: Color(0xFFEF4444))),
          const Spacer(),
          Text('${_info!.thingsTotal} Total',
              style: TextStyle(fontFamily: 'Inter',
                  fontSize: 13,
                  color: isDark ? Colors.white60 : const Color(0xFF71717A))),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: onlinePct,
            minHeight: 10,
            backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.2),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF22C55E)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          onlinePct == 1.0
              ? 'Semua perangkat online ✓'
              : '${(onlinePct * 100).toStringAsFixed(0)}% perangkat online',
          style: TextStyle(fontFamily: 'Inter', fontSize: 12,
              color: onlinePct == 1.0
                  ? const Color(0xFF22C55E)
                  : (isDark ? Colors.white60 : const Color(0xFF71717A))),
        ),
      ]),
    );
  }
  Widget _buildAutomationCard(BuildContext context) {
    if (_isLoading || _info == null) return _skeletonCard(context, height: 100);
    return _InfoCard(rows: [
      _InfoCardRow(
        icon: Icons.rule_rounded,
        label: 'Active Rules',
        value: '${_info!.activeRules} / ${_info!.totalRules}',
        color: const Color(0xFFF59E0B),
      ),
      _InfoCardRow(
        icon: Icons.code_rounded,
        label: 'Scripts',
        value: '${_info!.scripts}',
        color: const Color(0xFF8B5CF6),
      ),
    ]);
  }

  Widget _sectionLabel(String label, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 0),
      child: Text(label, style: TextStyle(fontFamily: 'Inter',
          fontWeight: FontWeight.w500, fontSize: 11,
          letterSpacing: 0.8,
          color: isDark ? Colors.white38 : const Color(0xFF9E9E9E))),
    );
  }

  Widget _dot(Color color) => Container(
    width: 8, height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Widget _skeletonCard(BuildContext context, {double height = 80}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(child: CircularProgressIndicator(
          strokeWidth: 2,
          color: isDark ? Colors.white24 : Colors.grey.shade300)),
    );
  }
}

class _QuickStatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _QuickStatCard({required this.icon, required this.value,
      required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.18 : 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Icon(icon, size: 18, color: color)),
        ),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontFamily: 'Inter',
            fontWeight: FontWeight.w700, fontSize: 15, color: color),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontFamily: 'Inter',
            fontSize: 11, color: isDark ? Colors.white60 : const Color(0xFF71717A))),
      ]),
    );
  }
}

class _InfoCardRow {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color? valueColor;

  const _InfoCardRow({required this.icon, required this.label,
      required this.value, required this.color, this.valueColor});
}

class _InfoCard extends StatelessWidget {
  final List<_InfoCardRow> rows;
  const _InfoCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;
    final dividerColor = isDark ? const Color(0xFF3F3F46) : const Color(0xFFF0F0F0);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: List.generate(rows.length, (i) {
          final row = rows[i];
          return Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: row.color.withValues(alpha: isDark ? 0.18 : 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(child: Icon(row.icon, size: 16, color: row.color)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(row.label,
                    style: TextStyle(fontFamily: 'Inter',
                        fontWeight: FontWeight.w500, fontSize: 14,
                        color: isDark ? Colors.white70 : const Color(0xFF52525B)))),
                Text(row.value,
                    style: TextStyle(fontFamily: 'Inter',
                        fontWeight: FontWeight.w600, fontSize: 14,
                        color: row.valueColor ??
                            (isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xCC18181B)))),
              ]),
            ),
            if (i < rows.length - 1)
              Divider(height: 1, color: dividerColor, indent: 64),
          ]);
        }),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final bool isOnline;
  const _PulseDot({required this.isOnline});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final color = widget.isOnline
        ? const Color(0xFF34C759)
        : const Color(0xFFFF3B30);
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 12, height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: widget.isOnline ? _anim.value : 1.0),
          boxShadow: widget.isOnline ? [
            BoxShadow(color: color.withValues(alpha: 0.5 * _anim.value),
                blurRadius: 6, spreadRadius: 1),
          ] : [],
        ),
      ),
    );
  }
}

class _ServerConfigSheetMin extends StatefulWidget {
  final OpenHABController ctrl;
  final VoidCallback onSaved;
  const _ServerConfigSheetMin({required this.ctrl, required this.onSaved});

  @override
  State<_ServerConfigSheetMin> createState() => _ServerConfigSheetMinState();
}

class _ServerConfigSheetMinState extends State<_ServerConfigSheetMin> {
  late TextEditingController _urlCtrl;
  late TextEditingController _tokenCtrl;
  late TextEditingController _userCtrl;
  late TextEditingController _passCtrl;
  bool _isTesting      = false;
  bool _obscureToken   = true;
  bool _obscurePass    = true;
  String? _testResult;
  bool    _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl   = TextEditingController(text: widget.ctrl.serverUrl);
    _tokenCtrl = TextEditingController();
    _userCtrl  = TextEditingController();
    _passCtrl  = TextEditingController();
    _load();
  }

  Future<void> _load() async {
  final config = context.read<InstallationProvider>().config;
  if (mounted && config != null) {
    _urlCtrl.text = config.openhabUrl;
    _tokenCtrl.text = config.apiToken ?? '';
    _userCtrl.text = config.username ?? '';
    _passCtrl.text = config.password ?? '';
  }
}

  @override
  void dispose() {
    _urlCtrl.dispose(); _tokenCtrl.dispose();
    _userCtrl.dispose(); _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
  setState(() {
    _isTesting = true;
    _testResult = null;
  });
  final url = _urlCtrl.text.trim();
  if (!OpenHABConfig.isValidUrl(url)) {
    setState(() {
      _isTesting = false;
      _testResult = 'URL tidak valid';
      _testSuccess = false;
    });
    return;
  }
  try {
    // Test koneksi langsung (tanpa simpan dulu) — tetap pakai ctrl yang ada
    final ok = await widget.ctrl.updateServerUrl(url);
    setState(() {
      _testResult = ok ? '✓ Berhasil terhubung' : '✗ Tidak dapat terhubung';
      _testSuccess = ok;
    });
  } catch (e) {
    setState(() {
      _testResult = '✗ Error: $e';
      _testSuccess = false;
    });
  } finally {
    setState(() => _isTesting = false);
  }
}
 
Future<void> _save() async {
  final url = _urlCtrl.text.trim();
  final token = _tokenCtrl.text.trim();
  final user = _userCtrl.text.trim();
  final pass = _passCtrl.text.trim();
  if (!OpenHABConfig.isValidUrl(url)) return;
 
  try {
    // Simpan ke Firestore (bukan local storage lagi)
    await context.read<InstallationProvider>().saveConfig(
          openhabUrl: url,
          apiToken: token.isNotEmpty ? token : null,
          username: user.isNotEmpty ? user : null,
          password: pass.isNotEmpty ? pass : null,
        );
 
    // Sinkronkan juga ke controller yang sedang jalan supaya UI langsung update
    await widget.ctrl.updateServerUrl(url);
 
    if (mounted) {
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konfigurasi disimpan')),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal simpan: $e')),
      );
    }
  }
}

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF3F3F46) : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Row(children: [
            Container(width: 40, height: 40,
                decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Center(child: FaIcon(FontAwesomeIcons.server,
                    size: 18, color: AppColors.primary))),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('openHAB Server', style: TextStyle(fontFamily: 'Inter',
                  fontWeight: FontWeight.w700, fontSize: 18,
                  color: isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xCC18181B))),
              Text('Configure connection', style: TextStyle(fontFamily: 'Inter',
                  fontSize: 13,
                  color: isDark ? Colors.white60 : const Color(0xFF71717A))),
            ]),
          ]),
          const SizedBox(height: 20),
          _field('Server URL', _urlCtrl, 'http://192.168.1.100:8080',
              FontAwesomeIcons.globe, context),
          const SizedBox(height: 12),
          _field('API Token', _tokenCtrl, 'oh.xxxxx (opsional)',
              FontAwesomeIcons.key, context,
              obscure: _obscureToken,
              toggleObscure: () => setState(() => _obscureToken = !_obscureToken)),
          const SizedBox(height: 12),
          _field('Username', _userCtrl, 'username', FontAwesomeIcons.user, context),
          const SizedBox(height: 12),
          _field('Password', _passCtrl, 'password', FontAwesomeIcons.lock, context,
              obscure: _obscurePass,
              toggleObscure: () => setState(() => _obscurePass = !_obscurePass)),
          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _testSuccess
                    ? (isDark ? const Color(0xFF34C759).withValues(alpha: 0.15) : const Color(0xFFEAF8EE))
                    : (isDark ? const Color(0xFFFF3B30).withValues(alpha: 0.15) : const Color(0xFFFFF0F0)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                FaIcon(_testSuccess
                    ? FontAwesomeIcons.circleCheck
                    : FontAwesomeIcons.circleXmark,
                    size: 14,
                    color: _testSuccess
                        ? const Color(0xFF34C759) : const Color(0xFFFF3B30)),
                const SizedBox(width: 8),
                Expanded(child: Text(_testResult!, style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13,
                    color: _testSuccess
                        ? const Color(0xFF34C759) : const Color(0xFFFF3B30)))),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: _isTesting ? null : _test,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF2F2F2),
                    borderRadius: BorderRadius.circular(14)),
                child: Center(child: _isTesting
                    ? SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2,
                            color: isDark ? Colors.white60 : const Color(0xFF71717A)))
                    : Text('Test', style: TextStyle(fontFamily: 'Inter',
                        fontWeight: FontWeight.w600, fontSize: 14,
                        color: isDark ? Colors.white60 : const Color(0xFF71717A)))),
              ),
            )),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: GestureDetector(
              onTap: _save,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14)),
                child: const Center(child: Text('Simpan & Connect',
                    style: TextStyle(fontFamily: 'Inter',
                        fontWeight: FontWeight.w600, fontSize: 14,
                        color: Colors.white))),
              ),
            )),
          ]),
        ]),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint,
    FaIconData icon, BuildContext context,
    {bool obscure = false, VoidCallback? toggleObscure}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return TextField(
    controller: ctrl,
    obscureText: obscure,
    textAlignVertical: TextAlignVertical.center,
    style: TextStyle(fontFamily: 'Inter', fontSize: 14,
        color: Theme.of(context).colorScheme.onSurface),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontFamily: 'Inter',
          color: isDark ? Colors.white38 : Colors.grey.shade400),
      filled: true,
      fillColor: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none),
      isDense: true,
      prefixIconConstraints: const BoxConstraints(
        minWidth: 44,
        minHeight: 44,
      ),
      prefixIcon: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: FaIcon(icon, size: 15,
            color: isDark ? Colors.white60 : const Color(0xFF71717A)),
      ),
      suffixIconConstraints: const BoxConstraints(
        minWidth: 44,
        minHeight: 44,
      ),
      suffixIcon: toggleObscure != null
          ? GestureDetector(
              onTap: toggleObscure,
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: FaIcon(obscure
                    ? FontAwesomeIcons.eye : FontAwesomeIcons.eyeSlash,
                    size: 15,
                    color: isDark ? Colors.white60 : const Color(0xFF71717A)),
              ))
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}}