import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:mobile/core/controllers/openhab_controller.dart';
import 'package:mobile/core/providers/installation_provider.dart';
import '../../../../core/theme/app_colors.dart';

String _friendlySceneError(Object e) {
  final s = e.toString().replaceFirst('Exception: ', '');
  if (e is TimeoutException) return 'Waktu tunggu habis, periksa koneksi ke server';
  if (s.contains('HTTP 401') || s.contains('HTTP 403')) {
    return 'Token/akun tidak punya izin untuk membuat Rule (perlu izin Administrator di openHAB), bukan cuma kontrol item';
  }
  if (s.contains('HTTP 404')) return 'Scene tidak ditemukan di server (mungkin sudah dihapus)';
  if (s.contains('HTTP 5')) return 'Server openHAB bermasalah, coba lagi nanti';
  if (s.contains('SocketException') || s.contains('Connection')) {
    return 'Tidak dapat terhubung ke server';
  }
  return s;
}

class OHScene {
  final String uid;
  final String name;
  final String description;
  final String type;        
  final String state;
  final List<String> tags;
  final List<String> groupNames;
  final String category;
  final bool active;
  final List<Map<String, dynamic>> actions;

  const OHScene({
    required this.uid,
    required this.name,
    required this.description,
    required this.type,
    required this.state,
    required this.tags,
    required this.groupNames,
    required this.category,
    required this.active,
    this.actions = const [],
  });

  factory OHScene.fromItemJson(Map<String, dynamic> json) {
    final label = json['label'] as String? ?? json['name'] as String? ?? '-';
    final state = json['state'] as String? ?? 'NULL';
    return OHScene(
      uid: json['name'] as String? ?? '',
      name: label,
      description: '',
      type: 'item',
      state: state,
      tags: List<String>.from(json['tags'] as List? ?? []),
      groupNames: List<String>.from(json['groupNames'] as List? ?? []),
      category: json['category'] as String? ?? '',
      active: state == 'ON',
    );
  }

  factory OHScene.fromRuleJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? json['uid'] as String? ?? '-';
    final enabled = json['enabled'] as bool? ?? true;
    return OHScene(
      uid: json['uid'] as String? ?? '',
      name: name,
      description: json['description'] as String? ?? '',
      type: 'rule',
      state: enabled ? 'IDLE' : 'DISABLED',
      tags: List<String>.from(json['tags'] as List? ?? []),
      groupNames: [],
      category: '',
      active: enabled,
      actions: List<Map<String, dynamic>>.from(json['actions'] as List? ?? [])
          .where((a) => a['type'] == 'core.ItemCommandAction')
          .toList(),
    );
  }

  OHScene copyWith({String? state, bool? active}) => OHScene(
        uid: uid,
        name: name,
        description: description,
        type: type,
        state: state ?? this.state,
        tags: tags,
        groupNames: groupNames,
        category: category,
        active: active ?? this.active,
        actions: actions,
      );
}

class OHItem {
  final String name;
  final String label;
  final String type;
  final String state;

  const OHItem({
    required this.name,
    required this.label,
    required this.type,
    required this.state,
  });

  factory OHItem.fromJson(Map<String, dynamic> json) {
    return OHItem(
      name: json['name'] as String? ?? '',
      label: json['label'] as String? ?? json['name'] as String? ?? '-',
      type: json['type'] as String? ?? 'Switch',
      state: json['state'] as String? ?? 'NULL',
    );
  }

  String get displayType {
    switch (type) {
      case 'Switch':       return 'Switch';
      case 'Dimmer':       return 'Dimmer';
      case 'Color':        return 'Color';
      case 'Number':       return 'Number';
      case 'String':       return 'String';
      case 'Rollershutter':return 'Rollershutter';
      default:             return type;
    }
  }
}

class SceneAction {
  final OHItem item;
  String command;
  int delaySeconds;
  SceneAction({required this.item, required this.command, this.delaySeconds = 0});
}

class ScenesService {
  final String baseUrl;
  final Map<String, String> headers;

  ScenesService({required this.baseUrl, required this.headers});

  Uri _uri(String path) => Uri.parse('$baseUrl/rest$path');

  Future<List<OHScene>> getScenesFromItems() async {
    final res = await http
        .get(_uri('/items?tags=Scene'), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List;
      return list.map((e) => OHScene.fromItemJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<List<OHScene>> getScenesFromRules() async {
    final res = await http
        .get(_uri('/rules?tags=Scene'), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List;
      return list.map((e) => OHScene.fromRuleJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<List<OHItem>> getAllItems() async {
    final res = await http
        .get(_uri('/items?fields=name,label,type,state'), headers: headers)
        .timeout(const Duration(seconds: 12));
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List;
      return list
          .map((e) => OHItem.fromJson(e as Map<String, dynamic>))
          .where((i) => ['Switch', 'Dimmer', 'Color', 'Number', 'String', 'Rollershutter']
              .contains(i.type))
          .toList();
    }
    return [];
  }

  Future<void> activateItemScene(String itemName) async {
    final res = await http
        .post(
          _uri('/items/$itemName'),
          headers: {...headers, 'Content-Type': 'text/plain'},
          body: 'ON',
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }

  Future<void> activateRuleScene(String uid) async {
    final res = await http
        .post(_uri('/rules/$uid/runnow'), headers: headers)
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200 && res.statusCode != 202) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }

  /// Builds ordered rule actions. Aksi dengan delaySeconds > 0 akan
  /// disisipi script sleep sebelum command dijalankan, sehingga urutan
  /// dan jeda antar aksi dijalankan sesuai konfigurasi di aplikasi.
  List<Map<String, dynamic>> _buildRuleActions(List<SceneAction> actions) {
    final ruleActions = <Map<String, dynamic>>[];
    for (var i = 0; i < actions.length; i++) {
      final a = actions[i];
      if (a.delaySeconds > 0) {
        ruleActions.add({
          'id': 'delay_$i',
          'type': 'script.ScriptAction',
          'configuration': {
            'type': 'application/javascript',
            'script': 'java.lang.Thread.sleep(${a.delaySeconds * 1000});',
          },
        });
      }
      ruleActions.add({
        'id': 'action_$i',
        'type': 'core.ItemCommandAction',
        'configuration': {
          'itemName': a.item.name,
          'command': a.command,
          'delay': a.delaySeconds,
        },
      });
    }
    return ruleActions;
  }

  Future<String> createSceneRule({
    required String name,
    required String description,
    required List<SceneAction> actions,
  }) async {
    final uid = 'scene_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}_${DateTime.now().millisecondsSinceEpoch}';

    final body = jsonEncode({
      'uid': uid,
      'name': name,
      'description': description,
      'tags': ['Scene'],
      'triggers': [],
      'conditions': [],
      'actions': _buildRuleActions(actions),
      'enabled': true,
    });

    final res = await http
        .post(
          _uri('/rules'),
          headers: headers,
          body: body,
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return uid;
  }

  Future<void> updateSceneRule({
    required String uid,
    required String name,
    required String description,
    required List<SceneAction> actions,
  }) async {
    final body = jsonEncode({
      'uid': uid,
      'name': name,
      'description': description,
      'tags': ['Scene'],
      'triggers': [],
      'conditions': [],
      'actions': _buildRuleActions(actions),
      'enabled': true,
    });

    final res = await http
        .put(
          _uri('/rules/$uid'),
          headers: headers,
          body: body,
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<void> deleteScene(String uid) async {
    final res = await http
        .delete(_uri('/rules/$uid'), headers: headers)
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }
}
class ScenesManagementPage extends StatefulWidget {
  const ScenesManagementPage({super.key});

  @override
  State<ScenesManagementPage> createState() => _ScenesManagementPageState();
}

class _ScenesManagementPageState extends State<ScenesManagementPage>
    with SingleTickerProviderStateMixin {
  final _ctrl = OpenHABController.instance;

  ScenesService? _svc;
  List<OHScene> _allScenes      = [];
  List<OHScene> _filteredScenes = [];
  bool   _isLoading = false;
  String? _errorMsg;

  String _filterType = 'all';
  final Set<String> _activatingUids = {};

  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _initAndLoad();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Map<String, String> _buildAuthHeaders() {
    final config = context.read<InstallationProvider>().config;
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (config?.apiToken != null && config!.apiToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.apiToken}';
    } else if (config?.username != null && config?.password != null) {
      final encoded = base64Encode(
          utf8.encode('${config!.username}:${config.password}'));
      headers['Authorization'] = 'Basic $encoded';
    }
    return headers;
  }

  Future<void> _initAndLoad() async {
    if (!mounted) return;
    final headers = _buildAuthHeaders();
    _svc = ScenesService(baseUrl: _ctrl.serverUrl, headers: headers);
    await _loadScenes();
  }

  Future<void> _loadScenes() async {
    if (_svc == null || !mounted) return;
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      final results = await Future.wait([
        _svc!.getScenesFromItems(),
        _svc!.getScenesFromRules(),
      ]);
      final allScenes = [...results[0], ...results[1]];
      final seen   = <String>{};
      final unique = allScenes.where((s) => seen.add(s.uid)).toList();
      if (!mounted) return;
      setState(() {
        _allScenes = unique;
        _applyFilter();
      });
      unawaited(_animCtrl.forward(from: 0));
    } catch (e) {
      if (mounted) setState(() => _errorMsg = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    setState(() {
      switch (_filterType) {
        case 'item':
          _filteredScenes = _allScenes.where((s) => s.type == 'item').toList();
          break;
        case 'rule':
          _filteredScenes = _allScenes.where((s) => s.type == 'rule').toList();
          break;
        default:
          _filteredScenes = List.from(_allScenes);
      }
    });
  }

  int get _itemScenesCount => _allScenes.where((s) => s.type == 'item').length;
  int get _ruleScenesCount => _allScenes.where((s) => s.type == 'rule').length;

  Future<void> _activateScene(OHScene scene) async {
    if (_activatingUids.contains(scene.uid)) return;
    setState(() => _activatingUids.add(scene.uid));
    try {
      if (scene.type == 'item') {
        await _svc!.activateItemScene(scene.uid);
      } else {
        await _svc!.activateRuleScene(scene.uid);
      }
      _showSnack('Scene "${scene.name}" diaktifkan ✓', isError: false);
    } catch (e) {
      _showSnack('Gagal mengaktifkan: ${_friendlyError(e)}', isError: true);
    } finally {
      if (mounted) {
        await Future.delayed(const Duration(seconds: 2));
        setState(() => _activatingUids.remove(scene.uid));
      }
    }
  }

  Future<void> _deleteScene(OHScene scene) async {
    if (scene.type != 'rule') {
      _showSnack('Hanya Rule Scene yang bisa dihapus dari sini', isError: true);
      return;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF27272A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Hapus Scene',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF18181B))),
        content: Text(
          'Hapus scene "${scene.name}"? Tindakan ini tidak bisa dibatalkan.',
          style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: isDark ? Colors.white60 : const Color(0xFF71717A)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Batal',
                style: TextStyle(
                    fontFamily: 'Inter',
                    color: isDark ? Colors.white54 : const Color(0xFF71717A))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus',
                style: TextStyle(
                    fontFamily: 'Inter',
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _svc!.deleteScene(scene.uid);
      if (!mounted) return;
      setState(() {
        _allScenes.removeWhere((s) => s.uid == scene.uid);
        _applyFilter();
      });
      _showSnack('Scene "${scene.name}" dihapus', isError: false);
    } catch (e) {
      _showSnack('Gagal menghapus: ${_friendlyError(e)}', isError: true);
    }
  }

  String _friendlyError(Object e) => _friendlySceneError(e);

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'Inter', fontSize: 13)),
      backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _openCreateScene() async {
    if (_svc == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    List<OHItem> items = [];
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Card(
          color: isDark ? const Color(0xFF27272A) : Colors.white,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16))),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 14),
              Text('Memuat items...',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      color: isDark ? Colors.white : const Color(0xFF18181B))),
            ]),
          ),
        ),
      ),
    ));

    try {
      items = await _svc!.getAllItems();
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnack('Gagal memuat items: $e', isError: true);
      return;
    }
    if (mounted) Navigator.pop(context);

    if (!mounted) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CreateSceneSheet(svc: _svc!, availableItems: items),
    );

    if (created == true && mounted) await _loadScenes();
  }

  Future<void> _openEditScene(OHScene scene) async {
    if (_svc == null || scene.type != 'rule') return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    List<OHItem> items = [];
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Card(
          color: isDark ? const Color(0xFF27272A) : Colors.white,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16))),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 14),
              Text('Memuat items...',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      color: isDark ? Colors.white : const Color(0xFF18181B))),
            ]),
          ),
        ),
      ),
    ));

    try {
      items = await _svc!.getAllItems();
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnack('Gagal memuat items: $e', isError: true);
      return;
    }
    if (mounted) Navigator.pop(context);

    if (!mounted) return;
    final updated = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CreateSceneSheet(
        svc: _svc!,
        availableItems: items,
        existingScene: scene,
      ),
    );

    if (updated == true && mounted) await _loadScenes();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      appBar: _buildAppBar(isDark, cs),
      body: _isLoading
          ? _buildLoading(isDark)
          : _errorMsg != null
              ? _buildError()
              : _buildContent(isDark),
    );
  }

  AppBar _buildAppBar(bool isDark, ColorScheme cs) {
    return AppBar(
      backgroundColor: cs.surface,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new, size: 18, color: cs.onSurface),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text('Scenes',
          style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: cs.onSurface)),
      actions: [
        IconButton(
          icon: Icon(Icons.add_rounded, size: 26, color: cs.onSurface),
          onPressed: _openCreateScene,
          tooltip: 'Buat Scene Baru',
        ),
        IconButton(
          icon: Icon(Icons.refresh_rounded, size: 22, color: cs.onSurface),
          onPressed: _loadScenes,
          tooltip: 'Refresh',
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildLoading(bool isDark) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: 14),
        Text('Memuat Scenes...',
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: isDark ? Colors.white54 : const Color(0xFF71717A))),
      ]),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_off_rounded, size: 56, color: Colors.red.shade300),
          const SizedBox(height: 14),
          Text('Gagal memuat Scenes',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Colors.red.shade700)),
          const SizedBox(height: 6),
          Text(_errorMsg!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Inter', fontSize: 12, color: Colors.red.shade400)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadScenes,
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
      onRefresh: _loadScenes,
      color: AppColors.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildSummaryCards(isDark),
                const SizedBox(height: 20),
                _buildFilterChips(isDark),
                const SizedBox(height: 16),
                _buildListHeader(isDark),
                const SizedBox(height: 10),
              ]),
            ),
          ),
          _filteredScenes.isEmpty
              ? SliverFillRemaining(child: _buildEmpty(isDark))
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final scene = _filteredScenes[i];
                        return AnimatedBuilder(
                          animation: _animCtrl,
                          builder: (ctx, child) {
                            final delay    = (i * 0.04).clamp(0.0, 0.6);
                            final progress = ((_animCtrl.value - delay) /
                                    (1.0 - delay))
                                .clamp(0.0, 1.0);
                            return Opacity(
                              opacity: progress,
                              child: Transform.translate(
                                offset: Offset(0, 18 * (1 - progress)),
                                child: child,
                              ),
                            );
                          },
                          child: _SceneCard(
                            scene: scene,
                            isActivating: _activatingUids.contains(scene.uid),
                            onActivate: () => _activateScene(scene),
                            onDelete: () => _deleteScene(scene),
                            onEdit: scene.type == 'rule'
                                ? () => _openEditScene(scene)
                                : null,
                            onTap: () => _showDetail(scene),
                          ),
                        );
                      },
                      childCount: _filteredScenes.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(bool isDark) {
    return Row(children: [
      Expanded(child: _SummaryCard(
          label: 'Total', count: _allScenes.length,
          color: const Color(0xFFF59E0B),
          icon: FontAwesomeIcons.wandMagicSparkles)),
      const SizedBox(width: 10),
      Expanded(child: _SummaryCard(
          label: 'Item Scene', count: _itemScenesCount,
          color: const Color(0xFF6366F1),
          icon: FontAwesomeIcons.toggleOn)),
      const SizedBox(width: 10),
      Expanded(child: _SummaryCard(
          label: 'Rule Scene', count: _ruleScenesCount,
          color: const Color(0xFF22C55E),
          icon: FontAwesomeIcons.scroll)),
    ]);
  }

  Widget _buildFilterChips(bool isDark) {
    final filters = [
      {'key': 'all',  'label': 'Semua',      'count': _allScenes.length},
      {'key': 'item', 'label': 'Item Scene', 'count': _itemScenesCount},
      {'key': 'rule', 'label': 'Rule Scene', 'count': _ruleScenesCount},
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final isSelected = _filterType == f['key'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() => _filterType = f['key']! as String);
                _applyFilter();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? const Color(0xFF27272A) : Colors.white),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                        blurRadius: 6,
                        offset: const Offset(0, 2))
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
          '${_filteredScenes.length} Scene${_filteredScenes.length != 1 ? 's' : ''}',
          style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: isDark ? Colors.white : const Color(0xCC18181B))),
      const Spacer(),
      GestureDetector(
        onTap: _openCreateScene,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: isDark ? 0.15 : 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_rounded, size: 14, color: AppColors.primary),
            const SizedBox(width: 4),
            Text('Buat Scene',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: AppColors.primary)),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.auto_awesome_outlined,
            size: 56,
            color: isDark ? Colors.white24 : Colors.grey.shade300),
        const SizedBox(height: 12),
        Text('Belum ada Scene',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: isDark ? Colors.white54 : Colors.grey.shade500)),
        const SizedBox(height: 4),
        Text('Tap + untuk membuat scene pertama kamu',
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.grey.shade400)),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _openCreateScene,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_rounded, size: 18, color: Colors.white),
              SizedBox(width: 8),
              Text('Buat Scene Pertama',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.white)),
            ]),
          ),
        ),
      ]),
    );
  }

  void _showDetail(OHScene scene) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SceneDetailSheet(
        scene: scene,
        onActivate: () => _activateScene(scene),
        onDelete: scene.type == 'rule' ? () => _deleteScene(scene) : null,
        onEdit: scene.type == 'rule' ? () => _openEditScene(scene) : null,
      ),
    );
  }
}

class _CreateSceneSheet extends StatefulWidget {
  final ScenesService svc;
  final List<OHItem> availableItems;
  final OHScene? existingScene;

  const _CreateSceneSheet({
    required this.svc,
    required this.availableItems,
    this.existingScene,
  });

  @override
  State<_CreateSceneSheet> createState() => _CreateSceneSheetState();
}

class _CreateSceneSheetState extends State<_CreateSceneSheet> {
  final _nameCtrl   = TextEditingController();
  final _descCtrl   = TextEditingController();
  final _searchCtrl = TextEditingController();

  final List<SceneAction> _actions = [];

  bool _isSaving   = false;
  String? _nameError;
  int _step        = 0;
  String _itemSearch = '';

  bool get _isEditing => widget.existingScene != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingScene;
    if (existing != null) {
      _nameCtrl.text = existing.name;
      _descCtrl.text = existing.description;
      for (final raw in existing.actions) {
        final cfg      = raw['configuration'] as Map<String, dynamic>? ?? {};
        final itemName = cfg['itemName'] as String? ?? '';
        final command  = cfg['command'] as String? ?? '';
        final delay    = (cfg['delay'] as num?)?.toInt() ?? 0;
        final item = widget.availableItems.firstWhere(
          (i) => i.name == itemName,
          orElse: () => OHItem(
              name: itemName, label: itemName, type: 'String', state: 'NULL'),
        );
        _actions.add(SceneAction(item: item, command: command, delaySeconds: delay));
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<OHItem> get _filteredItems {
    final q = _itemSearch.toLowerCase();
    return widget.availableItems
        .where((i) =>
            i.label.toLowerCase().contains(q) ||
            i.name.toLowerCase().contains(q))
        .toList();
  }

  bool _isItemAdded(OHItem item) =>
      _actions.any((a) => a.item.name == item.name);

  void _addItem(OHItem item) {
    if (_isItemAdded(item)) return;
    String defaultCmd = 'ON';
    if (item.type == 'Dimmer')        defaultCmd = '100';
    if (item.type == 'Number')        defaultCmd = '0';
    if (item.type == 'String')        defaultCmd = '';
    if (item.type == 'Rollershutter') defaultCmd = 'UP';
    setState(() => _actions.add(SceneAction(item: item, command: defaultCmd)));
  }

  void _removeAction(int idx) => setState(() => _actions.removeAt(idx));

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Nama scene tidak boleh kosong');
      return;
    }
    if (_actions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tambahkan minimal 1 aksi'),
        backgroundColor: Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        await widget.svc.updateSceneRule(
          uid: widget.existingScene!.uid,
          name: name,
          description: _descCtrl.text.trim(),
          actions: _actions,
        );
      } else {
        await widget.svc.createSceneRule(
          name: name,
          description: _descCtrl.text.trim(),
          actions: _actions,
        );
      }
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context, true);
        messenger.showSnackBar(SnackBar(
          content: Text(_isEditing
              ? 'Scene "$name" berhasil diperbarui ✓'
              : 'Scene "$name" berhasil dibuat ✓'),
          backgroundColor: const Color(0xFF22C55E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isEditing
            ? 'Gagal memperbarui scene: ${_friendlySceneError(e)}'
            : 'Gagal membuat scene: ${_friendlySceneError(e)}'),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF27272A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7),
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Center(child: Icon(Icons.auto_awesome_rounded,
                    size: 20, color: AppColors.primary)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_isEditing ? 'Edit Scene' : 'Buat Scene Baru',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: isDark ? Colors.white : const Color(0xCC18181B))),
                  Text('Atur aksi yang akan dijalankan sekaligus',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: isDark ? Colors.white54 : const Color(0xFF71717A))),
                ]),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.close_rounded,
                      size: 18,
                      color: isDark ? Colors.white54 : const Color(0xFF71717A)),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 16),

          _buildStepIndicator(isDark),

          const SizedBox(height: 16),
          Divider(height: 1,
              color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7)),
          Expanded(
            child: _step == 0
                ? _buildStepInfo(isDark)
                : _step == 1
                    ? _buildStepActions(isDark)
                    : _buildStepReview(isDark),
          ),
          _buildBottomButtons(isDark),
        ]),
      ),
    );
  }

  Widget _buildStepIndicator(bool isDark) {
    final steps = ['Info', 'Aksi', 'Simpan'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(children: List.generate(steps.length, (i) {
        final isDone    = i < _step;
        final isCurrent = i == _step;
        return Expanded(
          child: Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone
                    ? const Color(0xFF22C55E)
                    : isCurrent
                        ? AppColors.primary
                        : (isDark
                            ? const Color(0xFF3F3F46)
                            : const Color(0xFFF4F4F5)),
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                    : Text('${i + 1}',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: isCurrent
                                ? Colors.white
                                : (isDark
                                    ? Colors.white38
                                    : const Color(0xFF94A3B8)))),
              ),
            ),
            const SizedBox(width: 6),
            Text(steps[i],
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 12,
                    color: isCurrent
                        ? AppColors.primary
                        : (isDark ? Colors.white54 : const Color(0xFF71717A)))),
            if (i < steps.length - 1) ...[
              const SizedBox(width: 6),
              Expanded(
                  child: Container(
                      height: 1,
                      color: isDark
                          ? const Color(0xFF3F3F46)
                          : const Color(0xFFE4E4E7))),
            ],
          ]),
        );
      })),
    );
  }

  Widget _buildStepInfo(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Nama Scene *',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: isDark ? Colors.white60 : const Color(0xFF71717A))),
        const SizedBox(height: 8),
        TextField(
          controller: _nameCtrl,
          onChanged: (_) => setState(() => _nameError = null),
          style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: isDark ? Colors.white : const Color(0xFF18181B)),
          decoration: InputDecoration(
            hintText: 'contoh: Malam Hari, Nonton Film ...',
            hintStyle: TextStyle(
                fontFamily: 'Inter',
                color: isDark ? Colors.white38 : Colors.grey.shade400),
            errorText: _nameError,
            filled: true,
            fillColor: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
            prefixIcon:
                Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.primary),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        const SizedBox(height: 18),
        Text('Deskripsi (opsional)',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: isDark ? Colors.white60 : const Color(0xFF71717A))),
        const SizedBox(height: 8),
        TextField(
          controller: _descCtrl,
          maxLines: 3,
          style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: isDark ? Colors.white : const Color(0xFF18181B)),
          decoration: InputDecoration(
            hintText: 'Deskripsi singkat scene ini...',
            hintStyle: TextStyle(
                fontFamily: 'Inter',
                color: isDark ? Colors.white38 : Colors.grey.shade400),
            filled: true,
            fillColor: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: isDark ? 0.1 : 0.06),
              borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.lightbulb_outline_rounded, size: 16, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tips: Beri nama yang deskriptif seperti "Malam Hari" atau "Nonton Film" agar icon dan warna otomatis muncul di kartu scene.',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: AppColors.primary,
                    height: 1.5),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildStepActions(bool isDark) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: Column(children: [
          if (_actions.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF14532D).withValues(alpha: 0.4)
                      : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 14, color: Color(0xFF22C55E)),
                  const SizedBox(width: 6),
                  Text('${_actions.length} aksi dipilih',
                      style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: Color(0xFF22C55E))),
                ]),
                const SizedBox(height: 8),
                ..._actions.asMap().entries.map((entry) {
                  final i = entry.key;
                  final a = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Text('${i + 1}.',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white38
                                  : const Color(0xFF94A3B8))),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(a.item.label,
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF18181B)),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      _DelayEditor(
                          action: a,
                          onChanged: (v) =>
                              setState(() => _actions[i].delaySeconds = v)),
                      const SizedBox(width: 6),
                      _CommandEditor(
                          action: a,
                          onChanged: (v) => setState(() => _actions[i].command = v)),
                      const SizedBox(width: 2),
                      GestureDetector(
                        onTap: i == 0
                            ? null
                            : () => setState(() {
                                  final tmp = _actions[i - 1];
                                  _actions[i - 1] = _actions[i];
                                  _actions[i] = tmp;
                                }),
                        child: Icon(Icons.keyboard_arrow_up_rounded,
                            size: 18,
                            color: i == 0
                                ? (isDark ? Colors.white24 : Colors.grey.shade300)
                                : AppColors.primary),
                      ),
                      GestureDetector(
                        onTap: i == _actions.length - 1
                            ? null
                            : () => setState(() {
                                  final tmp = _actions[i + 1];
                                  _actions[i + 1] = _actions[i];
                                  _actions[i] = tmp;
                                }),
                        child: Icon(Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: i == _actions.length - 1
                                ? (isDark ? Colors.white24 : Colors.grey.shade300)
                                : AppColors.primary),
                      ),
                      const SizedBox(width: 2),
                      GestureDetector(
                        onTap: () => _removeAction(i),
                        child: const Icon(Icons.remove_circle_outline_rounded,
                            size: 18, color: Color(0xFFEF4444)),
                      ),
                    ]),
                  );
                }),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _itemSearch = v),
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF18181B)),
            decoration: InputDecoration(
              hintText: 'Cari item...',
              hintStyle: TextStyle(
                  fontFamily: 'Inter',
                  color: isDark ? Colors.white38 : Colors.grey.shade400),
              filled: true,
              fillColor:
                  isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              prefixIcon: Icon(Icons.search_rounded,
                  size: 18,
                  color: isDark ? Colors.white54 : const Color(0xFF71717A)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ]),
      ),

      const SizedBox(height: 8),

      Expanded(
        child: _filteredItems.isEmpty
            ? Center(
                child: Text('Tidak ada item ditemukan',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: isDark
                            ? Colors.white38
                            : const Color(0xFF71717A))))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _filteredItems.length,
                itemBuilder: (_, i) {
                  final item  = _filteredItems[i];
                  final added = _isItemAdded(item);
                  return _ItemPickerRow(
                    item: item,
                    isAdded: added,
                    onTap: () => added ? null : _addItem(item),
                  );
                },
              ),
      ),
    ]);
  }


  Widget _buildStepReview(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: isDark ? 0.1 : 0.06),
              borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_nameCtrl.text.trim(),
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColors.primary)),
              ),
            ]),
            if (_descCtrl.text.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_descCtrl.text.trim(),
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: isDark ? Colors.white54 : const Color(0xFF71717A))),
            ],
          ]),
        ),

        const SizedBox(height: 20),

        Text('${_actions.length} Aksi',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xCC18181B))),
        const SizedBox(height: 10),

        ..._actions.asMap().entries.map((entry) {
          final idx = entry.key;
          final a   = entry.value;
          return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
              color: isDark ? const Color(0xFF3F3F46) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ]),
          child: Row(children: [
            Text('${idx + 1}',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8))),
            const SizedBox(width: 8),
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10)),
              child: Center(child: Icon(_itemTypeIcon(a.item.type),
                  size: 16, color: AppColors.primary)),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.item.label,
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark ? Colors.white : const Color(0xCC18181B))),
              Text(
                  a.delaySeconds > 0
                      ? '${a.item.name} • delay ${a.delaySeconds}s'
                      : a.item.name,
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: isDark ? Colors.white54 : const Color(0xFF71717A))),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF14532D).withValues(alpha: 0.4)
                      : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.3))),
              child: Text(a.command,
                  style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: Color(0xFF22C55E))),
            ),
          ]),
        );
        }),

        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF78350F).withValues(alpha: 0.3)
                  : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.3))),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded,
                size: 16, color: Color(0xFFF59E0B)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(
              'Scene akan dibuat sebagai Rule di openHAB dan bisa diaktifkan kapan saja dari halaman ini.',
              style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: Color(0xFFF59E0B),
                  height: 1.5),
            )),
          ]),
        ),
      ]),
    );
  }

  IconData _itemTypeIcon(String type) {
    switch (type) {
      case 'Switch':       return Icons.toggle_on_rounded;
      case 'Dimmer':       return Icons.brightness_medium_rounded;
      case 'Color':        return Icons.palette_rounded;
      case 'Number':       return Icons.numbers_rounded;
      case 'Rollershutter':return Icons.window_rounded;
      default:             return Icons.device_hub_rounded;
    }
  }

  Widget _buildBottomButtons(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
          border: Border(
              top: BorderSide(
                  color: isDark
                      ? const Color(0xFF3F3F46)
                      : const Color(0xFFF0F0F0)))),
      child: Row(children: [
        if (_step > 0) ...[
          GestureDetector(
            onTap: () => setState(() => _step--),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF3F3F46)
                      : const Color(0xFFF4F4F5),
                  borderRadius: BorderRadius.circular(14)),
              child: Text('Kembali',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark
                          ? Colors.white70
                          : const Color(0xFF71717A))),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: GestureDetector(
            onTap: _isSaving
                ? null
                : () {
                    if (_step < 2) {
                      if (_step == 0 && _nameCtrl.text.trim().isEmpty) {
                        setState(() => _nameError = 'Nama scene tidak boleh kosong');
                        return;
                      }
                      setState(() => _step++);
                    } else {
                      _save();
                    }
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _isSaving
                    ? AppColors.primary.withValues(alpha: 0.6)
                    : AppColors.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: _isSaving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(
                        _step == 2
                            ? (_isEditing ? 'Simpan Perubahan' : 'Simpan Scene')
                            : 'Lanjut',
                        style: const TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Colors.white)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _CommandEditor extends StatefulWidget {
  final SceneAction action;
  final ValueChanged<String> onChanged;

  const _CommandEditor({required this.action, required this.onChanged});

  @override
  State<_CommandEditor> createState() => _CommandEditorState();
}

class _CommandEditorState extends State<_CommandEditor> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final type   = widget.action.item.type;

    if (type == 'Switch') {
      final isOn = widget.action.command == 'ON';
      return GestureDetector(
        onTap: () => widget.onChanged(isOn ? 'OFF' : 'ON'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: isOn
                  ? (isDark
                      ? const Color(0xFF14532D).withValues(alpha: 0.4)
                      : const Color(0xFFF0FDF4))
                  : (isDark
                      ? const Color(0xFF450A0A).withValues(alpha: 0.4)
                      : const Color(0xFFFEF2F2)),
              borderRadius: BorderRadius.circular(20)),
          child: Text(widget.action.command,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  color: isOn
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFEF4444))),
        ),
      );
    }

    if (type == 'Rollershutter') {
      final options = ['UP', 'DOWN', 'STOP'];
      final current = widget.action.command;
      return DropdownButton<String>(
        value: options.contains(current) ? current : 'UP',
        isDense: true,
        underline: const SizedBox(),
        dropdownColor: isDark ? const Color(0xFF27272A) : Colors.white,
        style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            color: isDark ? Colors.white : const Color(0xFF18181B)),
        items: options
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: (v) { if (v != null) widget.onChanged(v); },
      );
    }

    return GestureDetector(
      onTap: () async {
        final isDarkDialog = Theme.of(context).brightness == Brightness.dark;
        final ctrl = TextEditingController(text: widget.action.command);
        final result = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor:
                isDarkDialog ? const Color(0xFF27272A) : Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text('Set nilai untuk\n${widget.action.item.label}',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isDarkDialog ? Colors.white : const Color(0xFF18181B))),
            content: TextField(
              controller: ctrl,
              keyboardType: type == 'Dimmer' || type == 'Number'
                  ? TextInputType.number
                  : TextInputType.text,
              style: TextStyle(
                  fontFamily: 'Inter',
                  color: isDarkDialog ? Colors.white : const Color(0xFF18181B)),
              decoration: InputDecoration(
                hintText: type == 'Dimmer' ? '0–100' : 'nilai command',
                hintStyle: TextStyle(
                    color: isDarkDialog ? Colors.white38 : Colors.grey.shade400),
                filled: true,
                fillColor: isDarkDialog
                    ? const Color(0xFF3F3F46)
                    : const Color(0xFFF5F5F7),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Batal',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          color: isDarkDialog
                              ? Colors.white54
                              : const Color(0xFF71717A)))),
              TextButton(
                  onPressed: () => Navigator.pop(context, ctrl.text),
                  child: Text('OK',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary))),
            ],
          ),
        );
        if (!mounted) return;
        if (result != null && result.isNotEmpty) widget.onChanged(result);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(
              widget.action.command.isEmpty ? 'set...' : widget.action.command,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  color: AppColors.primary)),
          const SizedBox(width: 4),
          Icon(Icons.edit_rounded, size: 10, color: AppColors.primary),
        ]),
      ),
    );
  }
}

class _DelayEditor extends StatelessWidget {
  final SceneAction action;
  final ValueChanged<int> onChanged;

  const _DelayEditor({required this.action, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () async {
        final isDarkDialog = Theme.of(context).brightness == Brightness.dark;
        final ctrl = TextEditingController(
            text: action.delaySeconds > 0 ? '${action.delaySeconds}' : '');
        final result = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor:
                isDarkDialog ? const Color(0xFF27272A) : Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text('Delay sebelum\n${action.item.label} (detik)',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isDarkDialog ? Colors.white : const Color(0xFF18181B))),
            content: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: TextStyle(
                  fontFamily: 'Inter',
                  color: isDarkDialog ? Colors.white : const Color(0xFF18181B)),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: TextStyle(
                    color: isDarkDialog ? Colors.white38 : Colors.grey.shade400),
                filled: true,
                fillColor: isDarkDialog
                    ? const Color(0xFF3F3F46)
                    : const Color(0xFFF5F5F7),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Batal',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          color: isDarkDialog
                              ? Colors.white54
                              : const Color(0xFF71717A)))),
              TextButton(
                  onPressed: () => Navigator.pop(context, ctrl.text),
                  child: Text('OK',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary))),
            ],
          ),
        );
        if (result == null) return;
        final v = int.tryParse(result.trim()) ?? 0;
        onChanged(v < 0 ? 0 : v);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: (isDark ? Colors.white : const Color(0xFF18181B))
                .withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.timer_outlined,
              size: 11, color: isDark ? Colors.white54 : const Color(0xFF71717A)),
          const SizedBox(width: 3),
          Text('${action.delaySeconds}s',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  color: isDark ? Colors.white54 : const Color(0xFF71717A))),
        ]),
      ),
    );
  }
}

class _ItemPickerRow extends StatelessWidget {
  final OHItem item;
  final bool isAdded;
  final VoidCallback onTap;

  const _ItemPickerRow({
    required this.item,
    required this.isAdded,
    required this.onTap,
  });

  Color get _typeColor {
    switch (item.type) {
      case 'Switch':       return const Color(0xFF22C55E);
      case 'Dimmer':       return const Color(0xFFF59E0B);
      case 'Color':        return const Color(0xFFEC4899);
      case 'Number':       return const Color(0xFF3B82F6);
      case 'Rollershutter':return const Color(0xFF6366F1);
      default:             return const Color(0xFF94A3B8);
    }
  }

  IconData get _typeIcon {
    switch (item.type) {
      case 'Switch':       return Icons.toggle_on_rounded;
      case 'Dimmer':       return Icons.brightness_medium_rounded;
      case 'Color':        return Icons.palette_rounded;
      case 'Number':       return Icons.numbers_rounded;
      case 'Rollershutter':return Icons.window_rounded;
      default:             return Icons.device_hub_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: isAdded ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isAdded
              ? (isDark
                  ? const Color(0xFF14532D).withValues(alpha: 0.25)
                  : const Color(0xFFF0FDF4))
              : (isDark ? const Color(0xFF3F3F46) : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isAdded
                  ? const Color(0xFF22C55E).withValues(alpha: 0.4)
                  : (isDark
                      ? const Color(0xFF52525B)
                      : const Color(0xFFF0F0F0))),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: _typeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Center(child: Icon(_typeIcon, size: 16, color: _typeColor)),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.label,
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isDark ? Colors.white : const Color(0xCC18181B)),
                overflow: TextOverflow.ellipsis),
            Text('${item.name} • ${item.displayType}',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: isDark ? Colors.white54 : const Color(0xFF71717A))),
          ])),
          isAdded
              ? const Icon(Icons.check_circle_rounded,
                  size: 20, color: Color(0xFF22C55E))
              : Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8)),
                  child: Center(
                      child: Icon(Icons.add_rounded,
                          size: 16, color: AppColors.primary)),
                ),
        ]),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final FaIconData icon;

  const _SummaryCard({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Center(child: FaIcon(icon, size: 14, color: color)),
        ),
        const SizedBox(height: 10),
        Text('$count',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
                fontSize: 22,
                color: color)),
        Text(label,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: isDark ? Colors.white54 : const Color(0xFF71717A),
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

class _SceneCard extends StatelessWidget {
  final OHScene scene;
  final bool isActivating;
  final VoidCallback onActivate;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;
  final VoidCallback onTap;

  const _SceneCard({
    required this.scene,
    required this.isActivating,
    required this.onActivate,
    required this.onDelete,
    this.onEdit,
    required this.onTap,
  });

  Color get _accentColor {
    final n = scene.name.toLowerCase();
    if (n.contains('malam') || n.contains('night') || n.contains('tidur') || n.contains('sleep')) return const Color(0xFF6366F1);
    if (n.contains('pagi') || n.contains('morning') || n.contains('bangun')) return const Color(0xFFF59E0B);
    if (n.contains('film') || n.contains('movie') || n.contains('cinema') || n.contains('nonton')) return const Color(0xFFEF4444);
    if (n.contains('baca') || n.contains('read') || n.contains('study') || n.contains('belajar')) return const Color(0xFF3B82F6);
    if (n.contains('makan') || n.contains('dinner') || n.contains('lunch')) return const Color(0xFFF97316);
    if (n.contains('tamu') || n.contains('living') || n.contains('santai')) return const Color(0xFF22C55E);
    if (n.contains('away') || n.contains('pergi') || n.contains('off')) return const Color(0xFF94A3B8);
    if (n.contains('party') || n.contains('pesta')) return const Color(0xFFEC4899);
    return AppColors.primary;
  }

  FaIconData get _sceneIcon {
    final n = scene.name.toLowerCase();
    if (n.contains('malam') || n.contains('night') || n.contains('tidur')) return FontAwesomeIcons.moon;
    if (n.contains('pagi') || n.contains('morning') || n.contains('bangun')) return FontAwesomeIcons.sun;
    if (n.contains('film') || n.contains('movie') || n.contains('cinema') || n.contains('nonton')) return FontAwesomeIcons.film;
    if (n.contains('baca') || n.contains('read') || n.contains('study')) return FontAwesomeIcons.bookOpen;
    if (n.contains('makan') || n.contains('dinner') || n.contains('lunch')) return FontAwesomeIcons.utensils;
    if (n.contains('tamu') || n.contains('living') || n.contains('santai')) return FontAwesomeIcons.couch;
    if (n.contains('away') || n.contains('pergi')) return FontAwesomeIcons.personWalking;
    if (n.contains('party') || n.contains('pesta')) return FontAwesomeIcons.champagneGlasses;
    return FontAwesomeIcons.wandMagicSparkles;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color  = _accentColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3))
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
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: isDark ? 0.25 : 0.18),
                      color.withValues(alpha: isDark ? 0.12 : 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(child: FaIcon(_sceneIcon, size: 22, color: color)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(scene.name,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: isDark ? Colors.white : const Color(0xCC18181B)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (scene.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(scene.description,
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
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(scene.type == 'item' ? 'Item' : 'Rule',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                              color: color)),
                    ),
                    if (scene.actions.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text('• ${scene.actions.length} aksi',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 10,
                              color: isDark
                                  ? Colors.white38
                                  : const Color(0xFF71717A))),
                    ],
                  ]),
                ]),
              ),

              const SizedBox(width: 8),
              if (scene.type == 'rule') ...[
                if (onEdit != null) ...[
                  GestureDetector(
                    onTap: onEdit,
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10)),
                      child: Center(
                          child: Icon(Icons.edit_outlined, size: 16, color: color)),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Center(
                        child: Icon(Icons.delete_outline_rounded,
                            size: 16, color: Color(0xFFEF4444))),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              GestureDetector(
                onTap: isActivating ? null : onActivate,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: isActivating
                        ? color.withValues(alpha: 0.08)
                        : color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: isActivating
                        ? SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: color))
                        : FaIcon(FontAwesomeIcons.play, size: 14, color: color),
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

class _SceneDetailSheet extends StatelessWidget {
  final OHScene scene;
  final VoidCallback onActivate;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  const _SceneDetailSheet({
    required this.scene,
    required this.onActivate,
    this.onDelete,
    this.onEdit,
  });

  Color get _accentColor {
    final n = scene.name.toLowerCase();
    if (n.contains('malam') || n.contains('night') || n.contains('tidur')) return const Color(0xFF6366F1);
    if (n.contains('pagi') || n.contains('morning')) return const Color(0xFFF59E0B);
    if (n.contains('film') || n.contains('movie'))   return const Color(0xFFEF4444);
    if (n.contains('baca') || n.contains('read'))    return const Color(0xFF3B82F6);
    if (n.contains('makan') || n.contains('dinner')) return const Color(0xFFF97316);
    if (n.contains('away') || n.contains('pergi'))   return const Color(0xFF94A3B8);
    if (n.contains('party') || n.contains('pesta'))  return const Color(0xFFEC4899);
    return AppColors.primary;
  }

  FaIconData get _sceneIcon {
    final n = scene.name.toLowerCase();
    if (n.contains('malam') || n.contains('night') || n.contains('tidur')) return FontAwesomeIcons.moon;
    if (n.contains('pagi') || n.contains('morning')) return FontAwesomeIcons.sun;
    if (n.contains('film') || n.contains('movie'))   return FontAwesomeIcons.film;
    if (n.contains('baca') || n.contains('read'))    return FontAwesomeIcons.bookOpen;
    if (n.contains('makan') || n.contains('dinner')) return FontAwesomeIcons.utensils;
    if (n.contains('away') || n.contains('pergi'))   return FontAwesomeIcons.personWalking;
    if (n.contains('party') || n.contains('pesta'))  return FontAwesomeIcons.champagneGlasses;
    return FontAwesomeIcons.wandMagicSparkles;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color  = _accentColor;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF27272A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 32),
          children: [
            const SizedBox(height: 12),
            Center(
                child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF3F3F46)
                            : const Color(0xFFE4E4E7),
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 24),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: isDark ? 0.2 : 0.15),
                      color.withValues(alpha: isDark ? 0.08 : 0.05)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(18)),
                  child: Center(
                      child: FaIcon(_sceneIcon, size: 26, color: color)),
                ),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(scene.name,
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: isDark ? Colors.white : const Color(0xCC18181B))),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(
                          scene.type == 'item' ? 'Item Scene' : 'Rule Scene',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color: color)),
                    ),
                  ],
                )),
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
                _InfoRow(label: 'UID', value: scene.uid),
                if (scene.description.isNotEmpty)
                  _InfoRow(label: 'Deskripsi', value: scene.description),
                _InfoRow(label: 'Tipe',
                    value: scene.type == 'item' ? 'Item' : 'Rule'),
                _InfoRow(label: 'Tags',
                    value: scene.tags.isEmpty ? '-' : scene.tags.join(', ')),
                if (scene.actions.isNotEmpty)
                  _InfoRow(label: 'Aksi',
                      value: '${scene.actions.length} action(s)'),
              ]),
            ),

            if (scene.actions.isNotEmpty) ...[
              Divider(
                  height: 1,
                  color: isDark
                      ? const Color(0xFF3F3F46)
                      : const Color(0xFFE4E4E7)),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.grass, size: 13, color: color),
                      const SizedBox(width: 6),
                      Text('Actions (${scene.actions.length})',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: color)),
                    ]),
                    const SizedBox(height: 10),
                    ...scene.actions.map((a) {
                      final cfg      = a['configuration'] as Map<String, dynamic>? ?? {};
                      final itemName = cfg['itemName'] as String? ?? '';
                      final command  = cfg['command'] as String? ?? '';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: isDark ? 0.08 : 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: color.withValues(alpha: isDark ? 0.2 : 0.12))),
                        child: Row(children: [
                          Expanded(
                              child: Text(itemName,
                                  style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: color))),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF3F3F46)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(20)),
                            child: Text(command,
                                style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF18181B))),
                          ),
                        ]),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(children: [
                GestureDetector(
                  onTap: () { Navigator.pop(context); onActivate(); },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [color, color.withValues(alpha: 0.75)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: color.withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 6))
                      ],
                    ),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FaIcon(FontAwesomeIcons.wandMagicSparkles,
                              size: 14, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Aktifkan Scene',
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: Colors.white)),
                        ]),
                  ),
                ),
                if (onEdit != null) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () { Navigator.pop(context); onEdit!(); },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: isDark ? 0.12 : 0.08),
                          borderRadius: BorderRadius.circular(16)),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.edit_outlined, size: 16, color: color),
                            const SizedBox(width: 8),
                            Text('Edit Scene',
                                style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: color)),
                          ]),
                    ),
                  ),
                ],
                if (onDelete != null) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () { Navigator.pop(context); onDelete!(); },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF450A0A).withValues(alpha: 0.4)
                              : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(16)),
                      child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete_outline_rounded,
                                size: 16, color: Color(0xFFEF4444)),
                            SizedBox(width: 8),
                            Text('Hapus Scene',
                                style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: Color(0xFFEF4444))),
                          ]),
                    ),
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: isDark ? Colors.white54 : const Color(0xFF71717A),
                    fontWeight: FontWeight.w500))),
        Expanded(
            child: Text(value,
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: isDark ? Colors.white : const Color(0xCC18181B),
                    fontWeight: FontWeight.w500))),
      ]),
    );
  }
}