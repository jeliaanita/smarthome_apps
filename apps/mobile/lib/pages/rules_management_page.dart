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
import 'package:url_launcher/url_launcher.dart';

class OHRule {
  final String uid;
  final String name;
  final String description;
  final bool enabled;
  final String status;
  final List<String> tags;
  final List<Map<String, dynamic>> triggers;
  final List<Map<String, dynamic>> actions;
  final List<Map<String, dynamic>> conditions;

  const OHRule({
    required this.uid,
    required this.name,
    required this.description,
    required this.enabled,
    required this.status,
    required this.tags,
    required this.triggers,
    required this.actions,
    required this.conditions,
  });

  factory OHRule.fromJson(Map<String, dynamic> json) {
    return OHRule(
      uid: json['uid'] as String? ?? '',
      name: json['name'] as String? ?? json['uid'] as String? ?? '-',
      description: json['description'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      status: (json['status'] as Map<String, dynamic>?)?['status'] as String? ??
          (json['enabled'] == false ? 'DISABLED' : 'IDLE'),
      tags: List<String>.from(json['tags'] as List? ?? []),
      triggers:
          List<Map<String, dynamic>>.from(json['triggers'] as List? ?? []),
      actions: List<Map<String, dynamic>>.from(json['actions'] as List? ?? []),
      conditions:
          List<Map<String, dynamic>>.from(json['conditions'] as List? ?? []),
    );
  }

  /// Sama seperti web openHAB: Scene = Rule bertag "Scene" (tanpa trigger),
  /// Script = Rule bertag "Script". Keduanya punya halaman sendiri, jadi
  /// tidak ditampilkan di daftar Rules biasa.
  bool get isScene => tags.contains('Scene');
  bool get isScript => tags.contains('Script');

  OHRule copyWith({bool? enabled, String? status}) => OHRule(
        uid: uid,
        name: name,
        description: description,
        enabled: enabled ?? this.enabled,
        status: status ?? this.status,
        tags: tags,
        triggers: triggers,
        actions: actions,
        conditions: conditions,
      );
}

class RulesService {
  final String baseUrl;
  final Map<String, String> headers;
  // ⚠️ FIX: pakai http.Client() persisten (keep-alive), bukan top-level
  // http.get()/post() yang bikin koneksi baru tiap request — penyebab
  // "loading lama tapi akhirnya jalan" yang muncul random.
  final http.Client _client = http.Client();

  RulesService({required this.baseUrl, required this.headers});

  Uri _uri(String path) => Uri.parse('$baseUrl/rest$path');

  Future<List<OHRule>> getRules() async {
    final res = await _client
        .get(_uri('/rules'), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final list = jsonDecode(res.body) as List;
    return list
        .map((e) => OHRule.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> setEnabled(String uid, bool enabled) async {
    final res = await _client.post(
      _uri('/rules/$uid/enable'),
      headers: {...headers, 'Content-Type': 'text/plain'},
      body: enabled.toString(),
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200 && res.statusCode != 202) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }

  Future<void> runNow(String uid) async {
    final res = await _client.post(
      _uri('/rules/$uid/runnow'),
      headers: headers,
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200 && res.statusCode != 202) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }
}

class RulesManagementPage extends StatefulWidget {
  const RulesManagementPage({super.key});

  @override
  State<RulesManagementPage> createState() => _RulesManagementPageState();
}

class _RulesManagementPageState extends State<RulesManagementPage>
    with SingleTickerProviderStateMixin {
  final _ctrl = OpenHABController.instance;

  RulesService? _svc;
  List<OHRule> _allRules = [];
  List<OHRule> _filteredRules = [];
  bool _isLoading = false;
  String? _errorMsg;

  String _filterStatus = 'all';
  final Set<String> _runningUids = {};

  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _initAndLoad();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _initAndLoad() async {
    // Sama seperti add_thing_page.dart & addon_store_page.dart — cek dulu
    // server URL-nya, biar kalau memang belum dikonfigurasi, pesannya jelas
    // ("openHAB belum dikonfigurasi...") bukan raw exception teknis dari
    // gagalnya request HTTP ke URL kosong. Auth (token/username) TIDAK
    // dipakai sebagai indikator "sudah dikonfigurasi" karena openHAB
    // defaultnya tidak butuh auth sama sekali.
    if (_ctrl.serverUrl.isEmpty) {
      if (mounted) {
        setState(() => _errorMsg =
          'openHAB belum dikonfigurasi. Silakan atur di Settings → openHAB Server.');
      }
      return;
    }

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

    _svc = RulesService(baseUrl: _ctrl.serverUrl, headers: headers);
    await _loadRules();
  }

  Future<void> _loadRules() async {
    if (_svc == null) return;
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      final rules = await _svc!.getRules();
      // Satu objek, satu tempat: Scene & Script tetap tersimpan sebagai
      // Rule di openHAB, tapi ditampilkan di menu masing-masing.
      final plain = rules.where((r) => !r.isScene && !r.isScript).toList();
      setState(() {
        _allRules = plain;
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
        case 'enabled':
          _filteredRules = _allRules.where((r) => r.enabled).toList();
          break;
        case 'disabled':
          _filteredRules = _allRules.where((r) => !r.enabled).toList();
          break;
        default:
          _filteredRules = List.from(_allRules);
      }
    });
  }

  int get _enabledCount  => _allRules.where((r) => r.enabled).length;
  int get _disabledCount => _allRules.where((r) => !r.enabled).length;

  Future<void> _toggleEnabled(OHRule rule, bool value) async {
    final idx = _allRules.indexWhere((r) => r.uid == rule.uid);
    if (idx < 0) return;
    setState(() {
      _allRules[idx] = rule.copyWith(
          enabled: value, status: value ? 'IDLE' : 'DISABLED');
      _applyFilter();
    });
    try {
      await _svc!.setEnabled(rule.uid, value);
      _showSnack(value ? 'Rule diaktifkan' : 'Rule dinonaktifkan',
          isError: false);
    } catch (e) {
      setState(() { _allRules[idx] = rule; _applyFilter(); });
      _showSnack('Gagal mengubah status: $e', isError: true);
    }
  }

  Future<void> _runNow(OHRule rule) async {
    if (_runningUids.contains(rule.uid)) return;
    setState(() => _runningUids.add(rule.uid));
    try {
      await _svc!.runNow(rule.uid);
      _showSnack('Rule "${rule.name}" dijalankan', isError: false);
    } catch (e) {
      _showSnack('Gagal menjalankan: $e', isError: true);
    } finally {
      if (mounted) {
        await Future.delayed(const Duration(seconds: 2));
        setState(() => _runningUids.remove(rule.uid));
      }
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'Inter', fontSize: 13)),
      backgroundColor:
          isError ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
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
      return const AccessDeniedView(featureName: 'Rules Management');
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      appBar: _buildAppBar(isDark),
      body: _isLoading
          ? _buildLoading()
          : _errorMsg != null
              ? _buildError()
              : _buildContent(isDark),
    );
  }

  AppBar _buildAppBar(bool isDark) {
    return AppBar(
      backgroundColor: isDark ? const Color(0xFF27272A) : Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new,
            size: 18,
            color: isDark ? Colors.white : const Color(0xFF18181B)),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text('Rules',
          style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: isDark ? Colors.white : const Color(0xCC18181B))),
      actions: [
        IconButton(
          icon: Icon(Icons.info_outline_rounded,
              size: 22,
              color: isDark ? Colors.white : const Color(0xFF18181B)),
          onPressed: _showInfoSheet,
          tooltip: 'Apa itu Rule?',
        ),
        IconButton(
          icon: Icon(Icons.add_rounded,
              size: 24,
              color: isDark ? Colors.white : const Color(0xFF18181B)),
          onPressed: () async {
            final url =
                Uri.parse('${_ctrl.serverUrl}/settings/rules/add');
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
          tooltip: 'Buat Rule Baru',
        ),
        IconButton(
          icon: Icon(Icons.refresh_rounded,
              size: 22,
              color: isDark ? Colors.white : const Color(0xFF18181B)),
          onPressed: _loadRules,
          tooltip: 'Refresh',
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  void _showInfoSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF18181B);
    final bodyColor = isDark ? Colors.white70 : const Color(0xFF52525B);
    Widget section(IconData icon, Color color, String title, String body) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: titleColor)),
                const SizedBox(height: 3),
                Text(body,
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12.5,
                        height: 1.5,
                        color: bodyColor)),
              ]),
            ),
          ]),
        );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
            24, 12, 24, 24 + MediaQuery.of(ctx).padding.bottom),
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
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Rule dan Scene',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: titleColor)),
            const SizedBox(height: 16),
            section(
                Icons.auto_awesome_rounded,
                const Color(0xFFF59E0B),
                'Scene',
                'Menyimpan sekumpulan aksi Item, misalnya mematikan lampu dan '
                'AC sekaligus. Dijalankan dari tombol Aktifkan, atau dipanggil '
                'oleh sebuah Rule. Scene tidak punya trigger atau kondisi sendiri.'),
            section(
                Icons.bolt_rounded,
                const Color(0xFF6366F1),
                'Rule',
                'Automasi berbasis pemicu: pada waktu atau kejadian tertentu, '
                'jalankan aksi, dengan kondisi opsional. Contoh: setiap pukul '
                '22.00, matikan lampu teras jika tidak ada gerakan.'),
            section(
                Icons.link_rounded,
                const Color(0xFF22C55E),
                'Satu objek, satu tempat',
                'Sama seperti openHAB, Scene disimpan sebagai Rule bertag '
                '"Scene" dan dikelola di halaman Scenes, sehingga tidak '
                'ditampilkan lagi di daftar Rules.'),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: 14),
        const Text('Memuat Rules...',
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: Color(0xFF71717A))),
      ]),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_off_rounded,
              size: 56, color: Colors.red.shade300),
          const SizedBox(height: 14),
          Text('Gagal memuat Rules',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Colors.red.shade700)),
          const SizedBox(height: 6),
          Text(_errorMsg!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: Colors.red.shade400)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadRules,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
            label: const Text('Coba Lagi',
                style: TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.white,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadRules,
      color: AppColors.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFilterChips(isDark),
                  const SizedBox(height: 16),
                  _buildListHeader(isDark),
                  const SizedBox(height: 2),
                  Text('Automasi berbasis pemicu dan kondisi',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: isDark ? Colors.white38 : const Color(0xFF71717A))),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          _filteredRules.isEmpty
              ? SliverFillRemaining(child: _buildEmpty(isDark))
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final rule = _filteredRules[i];
                        return AnimatedBuilder(
                          animation: _animCtrl,
                          builder: (ctx, child) {
                            final delay = (i * 0.04).clamp(0.0, 0.6);
                            final progress =
                                ((_animCtrl.value - delay) / (1.0 - delay))
                                    .clamp(0.0, 1.0);
                            return Opacity(
                              opacity: progress,
                              child: Transform.translate(
                                offset: Offset(0, 18 * (1 - progress)),
                                child: child,
                              ),
                            );
                          },
                          child: _RuleCard(
                            rule: rule,
                            isDark: isDark,
                            isRunning: _runningUids.contains(rule.uid),
                            onToggle: (v) => _toggleEnabled(rule, v),
                            onRunNow: () => _runNow(rule),
                            onTap: () => _showDetail(rule),
                          ),
                        );
                      },
                      childCount: _filteredRules.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(bool isDark) {
    final filters = [
      {'key': 'all',      'label': 'Semua',   'count': _allRules.length},
      {'key': 'enabled',  'label': 'Aktif',   'count': _enabledCount},
      {'key': 'disabled', 'label': 'Nonaktif','count': _disabledCount},
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
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
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
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(f['label']! as String,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: isSelected
                              ? Colors.white
                              : (isDark
                                  ? Colors.white70
                                  : const Color(0xFF71717A)))),
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
                    child: Text('${f['count']}',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            color: isSelected
                                ? Colors.white
                                : (isDark
                                    ? Colors.white70
                                    : const Color(0xFF71717A)))),
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
          '${_filteredRules.length} Rule${_filteredRules.length != 1 ? 's' : ''}',
          style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: isDark ? Colors.white : const Color(0xCC18181B))),
      const Spacer(),
      Text('Tarik untuk refresh',
          style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: isDark ? Colors.white38 : Colors.grey.shade400)),
    ]);
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.auto_awesome_outlined,
            size: 56,
            color: isDark ? Colors.white24 : Colors.grey.shade300),
        const SizedBox(height: 12),
        Text('Tidak ada Rule',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: isDark ? Colors.white54 : Colors.grey.shade500)),
        const SizedBox(height: 4),
        Text(
          _filterStatus == 'all'
              ? 'Belum ada rule yang dibuat di openHAB.'
              : 'Tidak ada rule dengan status ini.',
          style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: isDark ? Colors.white38 : Colors.grey.shade400),
        ),
      ]),
    );
  }

  void _showDetail(OHRule rule) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RuleDetailSheet(rule: rule, isDark: isDark),
    );
  }
}

class _RuleCard extends StatelessWidget {
  final OHRule rule;
  final bool isDark;
  final bool isRunning;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRunNow;
  final VoidCallback onTap;

  const _RuleCard({
    required this.rule,
    required this.isDark,
    required this.isRunning,
    required this.onToggle,
    required this.onRunNow,
    required this.onTap,
  });

  Color get _statusColor {
    if (!rule.enabled) return const Color(0xFF94A3B8);
    switch (rule.status) {
      case 'RUNNING': return const Color(0xFF3B82F6);
      case 'IDLE':    return const Color(0xFF22C55E);
      default:        return const Color(0xFFEF4444);
    }
  }

  String get _statusLabel {
    if (!rule.enabled) return 'Nonaktif';
    switch (rule.status) {
      case 'RUNNING':       return 'Berjalan';
      case 'IDLE':          return 'Idle';
      case 'UNINITIALIZED': return 'Uninitialized';
      default:              return rule.status;
    }
  }

  FaIconData get _statusIcon {
    if (!rule.enabled) return FontAwesomeIcons.circlePause;
    switch (rule.status) {
      case 'RUNNING': return FontAwesomeIcons.circlePlay;
      case 'IDLE':    return FontAwesomeIcons.circleCheck;
      default:        return FontAwesomeIcons.circleExclamation;
    }
  }

  String get _triggerHint {
    if (rule.triggers.isEmpty) return 'Manual';
    final type = rule.triggers.first['type'] as String? ?? '';
    if (type.contains('Time') || type.contains('Cron')) return 'Terjadwal';
    if (type.contains('Item'))    return 'Item';
    if (type.contains('Thing'))   return 'Thing';
    if (type.contains('GenericEvent') || type.contains('Event')) return 'Event';
    if (type.contains('Channel')) return 'Channel';
    return 'Manual';
  }

  FaIconData get _triggerIcon {
    switch (_triggerHint) {
      case 'Terjadwal': return FontAwesomeIcons.clock;
      case 'Item':      return FontAwesomeIcons.toggleOn;
      case 'Thing':     return FontAwesomeIcons.microchip;
      case 'Event':     return FontAwesomeIcons.bolt;
      case 'Channel':   return FontAwesomeIcons.plug;
      default:          return FontAwesomeIcons.handPointer;
    }
  }

  Widget _statusBadge() => _Badge(
        icon: _statusIcon,
        label: _statusLabel,
        color: _statusColor,
        bg: _statusColor.withValues(alpha: 0.1),
      );

  Widget _triggerBadge(bool isDark) => _Badge(
        icon: FontAwesomeIcons.boltLightning,
        label: _triggerHint,
        color: isDark ? Colors.white70 : Colors.grey.shade600,
        bg: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5),
      );

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
              offset: const Offset(0, 3)),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                          color: _statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14)),
                      child: Center(
                          child: FaIcon(_triggerIcon,
                              size: 20, color: _statusColor)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rule.name,
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xCC18181B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (rule.description.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(rule.description,
                                style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white54
                                        : const Color(0xFF71717A)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ],

                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _statusBadge(),
                              _triggerBadge(isDark),
                              if (rule.tags.isNotEmpty)
                                _TagBadge(
                                  tag: rule.tags.first,
                                  isDark: isDark,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: rule.enabled,
                      onChanged: onToggle,
                      activeThumbColor: AppColors.primary,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                Divider(
                    height: 1,
                    color: isDark
                        ? const Color(0xFF3F3F46)
                        : const Color(0xFFF0F0F0)),
                const SizedBox(height: 12),
                Row(children: [
                  _miniStat(FontAwesomeIcons.boltLightning,
                      '${rule.triggers.length} trigger', isDark),
                  const SizedBox(width: 12),
                  _miniStat(FontAwesomeIcons.gears,
                      '${rule.actions.length} action', isDark),
                  if (rule.conditions.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    _miniStat(FontAwesomeIcons.filterCircleXmark,
                        '${rule.conditions.length} kondisi', isDark),
                  ],
                  const Spacer(),
                  GestureDetector(
                    onTap: rule.enabled ? onRunNow : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: rule.enabled
                            ? (isRunning
                                ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
                                : AppColors.primary.withValues(alpha: 0.08))
                            : (isDark
                                ? const Color(0xFF3F3F46)
                                : Colors.grey.shade100),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        isRunning
                            ? SizedBox(
                                width: 10, height: 10,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: rule.enabled
                                        ? AppColors.primary
                                        : Colors.grey))
                            : FaIcon(FontAwesomeIcons.play,
                                size: 10,
                                color: rule.enabled
                                    ? AppColors.primary
                                    : (isDark
                                        ? Colors.white38
                                        : Colors.grey.shade400)),
                        const SizedBox(width: 6),
                        Text(
                          isRunning ? 'Berjalan...' : 'Jalankan',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: rule.enabled
                                  ? (isRunning
                                      ? const Color(0xFF3B82F6)
                                      : AppColors.primary)
                                  : (isDark
                                      ? Colors.white38
                                      : Colors.grey.shade400)),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniStat(FaIconData icon, String label, bool isDark) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      FaIcon(icon,
          size: 10,
          color: isDark ? Colors.white54 : const Color(0xFF71717A)),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: isDark ? Colors.white54 : const Color(0xFF71717A))),
    ]);
  }
}

class _Badge extends StatelessWidget {
  final FaIconData icon;
  final String label;
  final Color color;
  final Color bg;

  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FaIcon(icon, size: 9, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 10,
                color: color)),
      ]),
    );
  }
}
class _TagBadge extends StatelessWidget {
  final String tag;
  final bool isDark;

  const _TagBadge({required this.tag, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 120),
      child: Text(
        '• $tag',
        style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 10,
            color: isDark ? Colors.white54 : const Color(0xFF71717A)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _RuleDetailSheet extends StatelessWidget {
  final OHRule rule;
  final bool isDark;

  const _RuleDetailSheet({required this.rule, required this.isDark});

  Color get _statusColor {
    if (!rule.enabled) return const Color(0xFF94A3B8);
    switch (rule.status) {
      case 'RUNNING': return const Color(0xFF3B82F6);
      case 'IDLE':    return const Color(0xFF22C55E);
      default:        return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF27272A) : Colors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 32),
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF3F3F46)
                          : const Color(0xFFE4E4E7),
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                        color: _statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16)),
                    child: Center(
                        child: FaIcon(FontAwesomeIcons.scroll,
                            size: 22, color: _statusColor))),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(rule.name,
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                            color: isDark
                                ? Colors.white
                                : const Color(0xCC18181B))),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: _statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(
                          rule.enabled ? rule.status : 'DISABLED',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color: _statusColor)),
                    ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            Divider(
                height: 1,
                color: isDark
                    ? const Color(0xFF3F3F46)
                    : const Color(0xFFE4E4E7)),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(children: [
                _InfoRow(label: 'UID', value: rule.uid, isDark: isDark),
                if (rule.description.isNotEmpty)
                  _InfoRow(
                      label: 'Deskripsi',
                      value: rule.description,
                      isDark: isDark),
                _InfoRow(
                    label: 'Status',
                    value: rule.enabled ? 'Aktif' : 'Nonaktif',
                    isDark: isDark),
                _InfoRow(
                    label: 'Tags',
                    value: rule.tags.isEmpty ? '-' : rule.tags.join(', '),
                    isDark: isDark),
              ]),
            ),
            if (rule.triggers.isNotEmpty) ...[
              const SizedBox(height: 8),
              Divider(
                  height: 1,
                  color: isDark
                      ? const Color(0xFF3F3F46)
                      : const Color(0xFFE4E4E7)),
              const SizedBox(height: 16),
              _buildSection(context,
                  icon: FontAwesomeIcons.boltLightning,
                  title: 'Triggers (${rule.triggers.length})',
                  color: const Color(0xFFF59E0B),
                  items: rule.triggers),
            ],
            if (rule.conditions.isNotEmpty) ...[
              Divider(
                  height: 1,
                  color: isDark
                      ? const Color(0xFF3F3F46)
                      : const Color(0xFFE4E4E7)),
              const SizedBox(height: 16),
              _buildSection(context,
                  icon: FontAwesomeIcons.filterCircleXmark,
                  title: 'Conditions (${rule.conditions.length})',
                  color: const Color(0xFF6366F1),
                  items: rule.conditions),
            ],
            if (rule.actions.isNotEmpty) ...[
              Divider(
                  height: 1,
                  color: isDark
                      ? const Color(0xFF3F3F46)
                      : const Color(0xFFE4E4E7)),
              const SizedBox(height: 16),
              _buildSection(context,
                  icon: FontAwesomeIcons.gears,
                  title: 'Actions (${rule.actions.length})',
                  color: const Color(0xFF22C55E),
                  items: rule.actions),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required FaIconData icon,
    required String title,
    required Color color,
    required List<Map<String, dynamic>> items,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          FaIcon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(title,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: color)),
        ]),
        const SizedBox(height: 10),
        ...items.map((item) {
          final type       = item['type'] as String? ?? '-';
          final id         = item['id']   as String? ?? '';
          final cfg        = item['configuration'] as Map<String, dynamic>? ?? {};
          final cfgPreview = cfg.entries
              .take(2)
              .map((e) => '${e.key}: ${e.value}')
              .join(', ');
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: isDark
                    ? color.withValues(alpha: 0.08)
                    : color.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: color.withValues(alpha: isDark ? 0.2 : 0.12))),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(type,
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: color)),
              if (id.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('ID: $id',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: isDark
                            ? Colors.white54
                            : const Color(0xFF71717A))),
              ],
              if (cfgPreview.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(cfgPreview,
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: isDark
                            ? Colors.white54
                            : const Color(0xFF71717A)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ]),
          );
        }),
        const SizedBox(height: 16),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  const _InfoRow(
      {required this.label, required this.value, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: isDark
                      ? Colors.white54
                      : const Color(0xFF71717A),
                  fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: isDark ? Colors.white : const Color(0xCC18181B),
                  fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }
}