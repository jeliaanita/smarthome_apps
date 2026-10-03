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

class OHScript {
  final String uid;
  final String label;
  final String description;
  final String type;
  final String language;
  final String script;
  final bool enabled;
  final String status;
  final List<String> tags;
  final List<Map<String, dynamic>> actions;
  final List<Map<String, dynamic>> triggers;

  const OHScript({
    required this.uid,
    required this.label,
    required this.description,
    required this.type,
    required this.language,
    required this.script,
    required this.enabled,
    required this.status,
    required this.tags,
    required this.actions,
    required this.triggers,
  });

  factory OHScript.fromJson(Map<String, dynamic> json) {
    final actions = List<Map<String, dynamic>>.from(
        json['actions'] as List? ?? []);

    String language = 'dsl';
    String script   = '';
    String type     = 'script';

    if (actions.isNotEmpty) {
      final cfg        = actions.first['configuration'] as Map<String, dynamic>? ?? {};
      final actionType = (actions.first['type'] as String? ?? '').toLowerCase();

      if (actionType.contains('blockly')) type = 'blockly';

      final mime = cfg['type'] as String? ?? '';
      if (mime.contains('javascript')) {
        language = 'js';
      } else if (mime.contains('python') || mime.contains('jython')) language = 'jython';
      else if (mime.contains('groovy'))                            language = 'groovy';
      else if (mime.contains('rules'))                             language = 'rules';
      else if (mime.contains('ruby'))                              language = 'ruby';

      script = cfg['script'] as String? ?? '';
    }

    final statusMap = json['status'] as Map<String, dynamic>?;
    final statusVal = statusMap?['status'] as String?
        ?? (json['enabled'] == false ? 'DISABLED' : 'IDLE');

    return OHScript(
      uid: json['uid'] as String? ?? '',
      label: json['name'] as String? ?? json['label'] as String?
          ?? json['uid'] as String? ?? '-',
      description: json['description'] as String? ?? '',
      type: type,
      language: language,
      script: script,
      enabled: json['enabled'] as bool? ?? true,
      status: statusVal,
      tags: List<String>.from(json['tags'] as List? ?? []),
      actions: actions,
      triggers: List<Map<String, dynamic>>.from(
          json['triggers'] as List? ?? []),
    );
  }

  OHScript copyWith({bool? enabled, String? status}) => OHScript(
        uid: uid, label: label, description: description,
        type: type, language: language, script: script,
        enabled: enabled ?? this.enabled,
        status: status ?? this.status,
        tags: tags, actions: actions, triggers: triggers,
      );
}

class ScriptsService {
  final String baseUrl;
  final Map<String, String> headers;
  final http.Client _client = http.Client();

  ScriptsService({required this.baseUrl, required this.headers});

  Uri _uri(String path) => Uri.parse('$baseUrl/rest$path');

  Future<List<OHScript>> getScripts() async {
    final res = await _client
        .get(_uri('/rules'), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}: ${res.body}');
    final list = jsonDecode(res.body) as List;
    return list
        .map((e) => OHScript.fromJson(e as Map<String, dynamic>))
        .where(_isScriptRule)
        .toList();
  }

  bool _isScriptRule(OHScript s) {
    if (s.actions.isEmpty) return false;
    final t = (s.actions.first['type'] as String? ?? '').toLowerCase();
    return t.contains('script') || t.contains('blockly');
  }

  Future<OHScript> createScript({
    required String label,
    required String description,
    required String language,
    required String scriptContent,
    required List<String> tags,
  }) async {
    final uid      = 'script_${DateTime.now().millisecondsSinceEpoch}';
    final mimeType = _mimeType(language);

    final payload = {
      'uid': uid,
      'name': label,
      'description': description,
      'tags': tags,
      'visibility': 'VISIBLE',
      'triggers': [],
      'conditions': [],
      'actions': [
        {
          'id': '1',
          'type': 'script.ScriptAction',
          'configuration': {
            'type': mimeType,
            'script': scriptContent,
          },
        }
      ],
    };

    final res = await _client.post(
      _uri('/rules'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    if (res.body.isNotEmpty) {
      try {
        return OHScript.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      } catch (_) {
        // Response tidak sesuai skema OHScript (mis. server hanya balas body
        // kosong/berbeda) — bukan bug, fallback ke objek lokal di bawah sudah
        // cukup karena kita sudah tahu semua field dari payload yang dikirim.
      }
    }

    return OHScript(
      uid: uid,
      label: label,
      description: description,
      type: 'script',
      language: language,
      script: scriptContent,
      enabled: true,
      status: 'IDLE',
      tags: tags,
      actions: [
        {
          'id': '1',
          'type': 'script.ScriptAction',
          'configuration': {'type': mimeType, 'script': scriptContent},
        }
      ],
      triggers: [],
    );
  }

  String _mimeType(String language) {
    switch (language) {
      case 'js':     return 'application/javascript';
      case 'jython': return 'application/x-python';
      case 'groovy': return 'application/x-groovy';
      case 'ruby':   return 'application/x-ruby';
      case 'rules':  return 'application/vnd.openhab.dsl.rule';
      default:       return 'application/vnd.openhab.dsl.rule';
    }
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

  Future<void> delete(String uid) async {
    final res = await _client.delete(
      _uri('/rules/$uid'),
      headers: headers,
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }
}

Color langColor(String lang) {
  switch (lang) {
    case 'dsl':    return const Color(0xFF6366F1);
    case 'js':     return const Color(0xFFF59E0B);
    case 'jython': return const Color(0xFF3B82F6);
    case 'groovy': return const Color(0xFF10B981);
    case 'ruby':   return const Color(0xFFEF4444);
    case 'rules':  return const Color(0xFF8B5CF6);
    default:       return const Color(0xFF6366F1);
  }
}

String langLabel(String lang) {
  switch (lang) {
    case 'dsl':    return 'DSL';
    case 'js':     return 'JavaScript';
    case 'jython': return 'Jython';
    case 'groovy': return 'Groovy';
    case 'ruby':   return 'Ruby';
    case 'rules':  return 'Rules DSL';
    default:       return lang.toUpperCase();
  }
}

FaIconData langIcon(String lang) {
  switch (lang) {
    case 'js':     return FontAwesomeIcons.js;
    case 'jython': return FontAwesomeIcons.python;
    case 'groovy': return FontAwesomeIcons.java;
    case 'ruby':   return FontAwesomeIcons.gem;
    default:       return FontAwesomeIcons.code;
  }
}

class ScriptsManagementPage extends StatefulWidget {
  const ScriptsManagementPage({super.key});

  @override
  State<ScriptsManagementPage> createState() => _ScriptsManagementPageState();
}

class _ScriptsManagementPageState extends State<ScriptsManagementPage>
    with SingleTickerProviderStateMixin {
  final _ctrl = OpenHABController.instance;

  ScriptsService? _svc;
  List<OHScript> _allScripts      = [];
  List<OHScript> _filteredScripts = [];
  bool    _isLoading  = false;
  String? _errorMsg;

  String _filterStatus = 'all';
  String _selectedLang = 'all';
  String _searchQuery  = '';
  bool   _showSearch   = false;
  final  _searchCtrl   = TextEditingController();

  final Set<String> _runningUids = {};
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 340));
    _initAndLoad();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initAndLoad() async {
    // Sama seperti fix di add_thing_page.dart/rules_management_page.dart —
    // baca kredensial dari InstallationProvider (sistem baru/Firestore),
    // bukan OpenHABConfig (storage lama, sudah tidak ditulisi lagi sejak
    // migrasi) — itu penyebab 401 "Authentication required" sebelumnya.
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
    if (!mounted) return;

    final headers = <String, String>{'Accept': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    } else if (username != null && password != null) {
      final encoded = base64Encode(utf8.encode('$username:$password'));
      headers['Authorization'] = 'Basic $encoded';
    }

    _svc = ScriptsService(baseUrl: _ctrl.serverUrl, headers: headers);
    await _loadScripts();
  }

  Future<void> _loadScripts() async {
    if (_svc == null || !mounted) return;
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      final scripts = await _svc!.getScripts();
      if (!mounted) return;
      setState(() { _allScripts = scripts; _applyFilter(); });
      unawaited(_animCtrl.forward(from: 0));
    } catch (e) {
      if (mounted) setState(() => _errorMsg = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    setState(() {
      List<OHScript> base;
      switch (_filterStatus) {
        case 'enabled':  base = _allScripts.where((s) => s.enabled).toList();  break;
        case 'disabled': base = _allScripts.where((s) => !s.enabled).toList(); break;
        default:         base = List.from(_allScripts);
      }
      if (_selectedLang != 'all') {
        base = base.where((s) => s.language == _selectedLang).toList();
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        base = base.where((s) =>
          s.label.toLowerCase().contains(q) ||
          s.description.toLowerCase().contains(q) ||
          s.language.toLowerCase().contains(q) ||
          s.uid.toLowerCase().contains(q)).toList();
      }
      _filteredScripts = base;
    });
  }

  int get _enabledCount  => _allScripts.where((s) => s.enabled).length;
  int get _disabledCount => _allScripts.where((s) => !s.enabled).length;


  Future<void> _toggleEnabled(OHScript script, bool value) async {
    final idx = _allScripts.indexWhere((s) => s.uid == script.uid);
    if (idx < 0) return;
    setState(() {
      _allScripts[idx] = script.copyWith(
          enabled: value, status: value ? 'IDLE' : 'DISABLED');
      _applyFilter();
    });
    try {
      await _svc!.setEnabled(script.uid, value);
      _showSnack(value ? 'Script diaktifkan' : 'Script dinonaktifkan',
          isError: false);
    } catch (e) {
      if (mounted) setState(() { _allScripts[idx] = script; _applyFilter(); });
      _showSnack('Gagal mengubah status: $e', isError: true);
    }
  }

  Future<void> _runNow(OHScript script) async {
    if (_runningUids.contains(script.uid)) return;
    setState(() => _runningUids.add(script.uid));
    try {
      await _svc!.runNow(script.uid);
      _showSnack('Script "${script.label}" dijalankan', isError: false);
    } catch (e) {
      _showSnack('Gagal menjalankan: $e', isError: true);
    } finally {
      if (mounted) {
        await Future.delayed(const Duration(seconds: 2));
        setState(() => _runningUids.remove(script.uid));
      }
    }
  }

  Future<void> _confirmDelete(OHScript script) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF27272A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Hapus Script',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: isDark ? Colors.white : const Color(0xFF18181B))),
        content: Text(
          'Yakin ingin menghapus "${script.label}"?\nTindakan ini tidak dapat dibatalkan.',
          style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: isDark ? Colors.white60 : const Color(0xFF71717A)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Batal',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      color: isDark ? Colors.white54 : const Color(0xFF71717A)))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hapus',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _svc!.delete(script.uid);
        if (!mounted) return;
        setState(() {
          _allScripts.removeWhere((s) => s.uid == script.uid);
          _applyFilter();
        });
        _showSnack('Script dihapus', isError: false);
      } catch (e) {
        _showSnack('Gagal menghapus: $e', isError: true);
      }
    }
  }

  Future<void> _openAddScript() async {
    if (_svc == null) return;
    final result = await Navigator.push<OHScript>(
      context,
      MaterialPageRoute(builder: (_) => AddScriptPage(service: _svc!)),
    );
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _allScripts.insert(0, result);
        _applyFilter();
      });
      _showSnack('Script "${result.label}" berhasil dibuat!', isError: false);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'Inter', fontSize: 13)),
      backgroundColor: isError
          ? const Color(0xFFEF4444)
          : const Color(0xFF22C55E),
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
      return const AccessDeniedView(featureName: 'Scripts Management');
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      appBar: _buildAppBar(),
      body: _isLoading
          ? _buildLoading()
          : _errorMsg != null
              ? _buildError()
              : _buildContent(),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddScript,
        backgroundColor: AppColors.primary,
        elevation: 4,
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
      ),
    );
  }

  AppBar _buildAppBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;

    return AppBar(
      backgroundColor: cs.surface,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new, size: 18, color: cs.onSurface),
        onPressed: () => Navigator.pop(context),
      ),
      title: _showSearch
          ? TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: (v) { _searchQuery = v; _applyFilter(); },
              style: TextStyle(
                  fontFamily: 'Inter', fontSize: 15, color: cs.onSurface),
              decoration: InputDecoration(
                hintText: 'Cari script...',
                hintStyle: TextStyle(
                    fontFamily: 'Inter',
                    color: isDark ? Colors.white38 : Colors.grey.shade400,
                    fontSize: 15),
                border: InputBorder.none,
              ),
            )
          : Text('Scripts',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: cs.onSurface)),
      actions: [
        IconButton(
          icon: Icon(
            _showSearch ? Icons.close_rounded : Icons.search_rounded,
            size: 22, color: cs.onSurface,
          ),
          onPressed: () {
            setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchCtrl.clear();
                _searchQuery = '';
                _applyFilter();
              }
            });
          },
        ),
        IconButton(
          icon: Icon(Icons.refresh_rounded, size: 22, color: cs.onSurface),
          onPressed: _loadScripts,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildLoading() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: 14),
        Text('Memuat Scripts...',
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
          Text('Gagal memuat Scripts',
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
        ]),
      ),
    );
  }

  Widget _buildContent() {
    return RefreshIndicator(
      onRefresh: _loadScripts,
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
                  _buildSummaryCards(),
                  const SizedBox(height: 16),
                  _buildLangChips(),
                  const SizedBox(height: 16),
                  _buildFilterChips(),
                  const SizedBox(height: 16),
                  _buildListHeader(),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          _filteredScripts.isEmpty
              ? SliverFillRemaining(child: _buildEmpty())
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final script = _filteredScripts[i];
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
                          child: _ScriptCard(
                            script: script,
                            isRunning: _runningUids.contains(script.uid),
                            onToggle: (v) => _toggleEnabled(script, v),
                            onRunNow: () => _runNow(script),
                            onTap: () => _showDetail(script),
                            onDelete: () => _confirmDelete(script),
                          ),
                        );
                      },
                      childCount: _filteredScripts.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Row(children: [
      Expanded(child: _SummaryCard(
          label: 'Total', count: _allScripts.length,
          color: const Color(0xFF8B5CF6), icon: FontAwesomeIcons.code)),
      const SizedBox(width: 10),
      Expanded(child: _SummaryCard(
          label: 'Aktif', count: _enabledCount,
          color: const Color(0xFF22C55E), icon: FontAwesomeIcons.circleCheck)),
      const SizedBox(width: 10),
      Expanded(child: _SummaryCard(
          label: 'Nonaktif', count: _disabledCount,
          color: const Color(0xFF94A3B8), icon: FontAwesomeIcons.circlePause)),
    ]);
  }

  Widget _buildLangChips() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final langs  = [
      {'key': 'all',    'label': 'Semua Bahasa'},
      {'key': 'dsl',    'label': 'DSL'},
      {'key': 'js',     'label': 'JS'},
      {'key': 'jython', 'label': 'Jython'},
      {'key': 'groovy', 'label': 'Groovy'},
      {'key': 'ruby',   'label': 'Ruby'},
      {'key': 'rules',  'label': 'Rules'},
    ];
    final presentLangs = _allScripts.map((s) => s.language).toSet();
    final filtered     = langs.where((l) =>
        l['key'] == 'all' || presentLangs.contains(l['key'])).toList();
    if (filtered.length <= 1) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filtered.map((lang) {
          final isSelected = _selectedLang == lang['key'];
          final color      = langColor(lang['key']!);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedLang = lang['key']!);
                _applyFilter();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color
                      : (isDark ? const Color(0xFF27272A) : Colors.white),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? color
                        : (isDark
                            ? const Color(0xFF3F3F46)
                            : const Color(0xFFE4E4E7)),
                    width: 1.5,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (lang['key'] != 'all') ...[
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(lang['label']!,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: isSelected
                              ? Colors.white
                              : (isDark
                                  ? Colors.white70
                                  : const Color(0xFF52525B)))),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFilterChips() {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final filters = [
      {'key': 'all',      'label': 'Semua',    'count': _allScripts.length},
      {'key': 'enabled',  'label': 'Aktif',    'count': _enabledCount},
      {'key': 'disabled', 'label': 'Nonaktif', 'count': _disabledCount},
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

  Widget _buildListHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(children: [
      Text(
          '${_filteredScripts.length} Script${_filteredScripts.length != 1 ? 's' : ''}',
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

  Widget _buildEmpty() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.code_off_rounded,
            size: 56,
            color: isDark ? Colors.white24 : Colors.grey.shade300),
        const SizedBox(height: 12),
        Text('Tidak ada Script',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: isDark ? Colors.white54 : Colors.grey.shade500)),
        const SizedBox(height: 4),
        Text(
          _filterStatus == 'all'
              ? 'Tekan tombol + untuk membuat script baru.'
              : 'Tidak ada script dengan status ini.',
          style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: isDark ? Colors.white38 : Colors.grey.shade400),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }

  void _showDetail(OHScript script) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ScriptDetailSheet(script: script),
    );
  }
}

class AddScriptPage extends StatefulWidget {
  final ScriptsService service;
  const AddScriptPage({super.key, required this.service});

  @override
  State<AddScriptPage> createState() => _AddScriptPageState();
}

class _AddScriptPageState extends State<AddScriptPage> {
  final _labelCtrl  = TextEditingController();
  final _descCtrl   = TextEditingController();
  final _scriptCtrl = TextEditingController();
  final _tagCtrl    = TextEditingController();

  String _selectedLang = 'dsl';
  final List<String> _tags   = [];
  bool _isSaving       = false;
  String? _errorMsg;

  static const Map<String, String> _templates = {
    'dsl': '''rule "My Script"
when
    System started
then
    logInfo("MyScript", "Hello from DSL!")
end''',
    'js': '''// JavaScript (GraalVM / Nashorn)
var logger = Java.type("org.slf4j.LoggerFactory")
    .getLogger("org.openhab.rule.MyScript");

logger.info("Hello from JavaScript!");''',
    'jython': '''# Jython (Python 2.7)
from core.log import logging, LOG_PREFIX
log = logging.getLogger("{}.MyScript".format(LOG_PREFIX))

log.info("Hello from Jython!")''',
    'groovy': '''// Groovy
import org.slf4j.LoggerFactory
def log = LoggerFactory.getLogger("org.openhab.rule.MyScript")

log.info("Hello from Groovy!")''',
    'ruby': '''# Ruby (JRuby)
logger = Java::OrgSlf4j::LoggerFactory.getLogger(
  "org.openhab.rule.MyScript")

logger.info("Hello from Ruby!")''',
    'rules': '''rule "My Rules DSL Script"
when
    Item MyItem changed
then
    logInfo("MyScript", "Item changed to: " + MyItem.state)
end''',
  };

  static const Map<String, Map<String, dynamic>> _langConfig = {
    'dsl':    {'label': 'DSL',        'hint': 'openHAB DSL (default)'},
    'js':     {'label': 'JavaScript', 'hint': 'GraalVM / Nashorn JS'},
    'jython': {'label': 'Jython',     'hint': 'Python 2.7 via JRuby'},
    'groovy': {'label': 'Groovy',     'hint': 'Apache Groovy'},
    'ruby':   {'label': 'Ruby',       'hint': 'JRuby scripting'},
    'rules':  {'label': 'Rules DSL',  'hint': 'openHAB Rules DSL'},
  };

  @override
  void initState() {
    super.initState();
    _scriptCtrl.text = _templates[_selectedLang] ?? '';
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _descCtrl.dispose();
    _scriptCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  void _addTag() {
    final tag = _tagCtrl.text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() { _tags.add(tag); _tagCtrl.clear(); });
    }
  }

  void _removeTag(String tag) => setState(() => _tags.remove(tag));

  Future<void> _save() async {
    final label  = _labelCtrl.text.trim();
    final script = _scriptCtrl.text.trim();

    if (label.isEmpty) {
      setState(() => _errorMsg = 'Nama script tidak boleh kosong');
      return;
    }
    if (script.isEmpty) {
      setState(() => _errorMsg = 'Konten script tidak boleh kosong');
      return;
    }

    setState(() { _isSaving = true; _errorMsg = null; });

    try {
      final result = await widget.service.createScript(
        label: label,
        description: _descCtrl.text.trim(),
        language: _selectedLang,
        scriptContent: script,
        tags: _tags,
      );
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() { _isSaving = false; _errorMsg = 'Gagal menyimpan: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      appBar: _buildAppBar(isDark, cs),
      body: _buildBody(isDark, cs),
    );
  }

  AppBar _buildAppBar(bool isDark, ColorScheme cs) {
    return AppBar(
      backgroundColor: cs.surface,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.close_rounded, size: 22, color: cs.onSurface),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text('Tambah Script',
          style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: cs.onSurface)),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: GestureDetector(
            onTap: _isSaving ? null : _save,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: _isSaving
                    ? AppColors.primary.withValues(alpha: 0.5)
                    : AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Simpan',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Colors.white)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(bool isDark, ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_errorMsg != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF3B1218)
                    : const Color(0xFFFFF0F0),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const FaIcon(FontAwesomeIcons.circleExclamation,
                    size: 14, color: Color(0xFFEF4444)),
                const SizedBox(width: 10),
                Expanded(child: Text(_errorMsg!,
                    style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: Color(0xFFEF4444)))),
                GestureDetector(
                  onTap: () => setState(() => _errorMsg = null),
                  child: const Icon(Icons.close_rounded,
                      size: 16, color: Color(0xFFEF4444)),
                ),
              ]),
            ),
          ],
          _sectionLabel('INFORMASI SCRIPT', isDark),
          const SizedBox(height: 10),
          _buildCard(isDark, children: [
            _fieldLabel('Nama Script *', isDark),
            const SizedBox(height: 8),
            _buildTextField(
              isDark: isDark,
              controller: _labelCtrl,
              hint: 'contoh: Matikan semua lampu jam 10 malam',
              prefixIcon: FontAwesomeIcons.tag,
            ),
            const SizedBox(height: 16),
            _fieldLabel('Deskripsi (opsional)', isDark),
            const SizedBox(height: 8),
            _buildTextField(
              isDark: isDark,
              controller: _descCtrl,
              hint: 'Jelaskan fungsi script ini...',
              prefixIcon: FontAwesomeIcons.alignLeft,
              maxLines: 2,
            ),
          ]),

          const SizedBox(height: 20),
          _sectionLabel('BAHASA SCRIPTING', isDark),
          const SizedBox(height: 10),
          _buildCard(isDark, children: [
            ...(_langConfig.entries.map((entry) {
              final lang       = entry.key;
              final config     = entry.value;
              final isSelected = _selectedLang == lang;
              final color      = langColor(lang);

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedLang = lang;
                    if (_templates.values.any((t) =>
                        _scriptCtrl.text.trim() == t.trim() ||
                        _scriptCtrl.text.trim().isEmpty)) {
                      _scriptCtrl.text = _templates[lang] ?? '';
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.08)
                        : (isDark
                            ? const Color(0xFF3F3F46)
                            : const Color(0xFFF8F8FA)),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? color
                          : (isDark
                              ? const Color(0xFF52525B)
                              : const Color(0xFFE4E4E7)),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: isSelected ? 0.15 : 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                          child: FaIcon(langIcon(lang), size: 16, color: color)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(config['label'] as String,
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: isSelected
                                    ? color
                                    : (isDark
                                        ? Colors.white
                                        : const Color(0xFF18181B)))),
                        Text(config['hint'] as String,
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white54
                                    : const Color(0xFF71717A))),
                      ],
                    )),
                    if (isSelected)
                      Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                            color: color, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded,
                            size: 13, color: Colors.white),
                      ),
                  ]),
                ),
              );
            })),
          ]),

          const SizedBox(height: 20),
          _sectionLabel('TAGS (opsional)', isDark),
          const SizedBox(height: 10),
          _buildCard(isDark, children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _tagCtrl,
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      color: isDark ? Colors.white : const Color(0xFF18181B)),
                  onSubmitted: (_) => _addTag(),
                  decoration: InputDecoration(
                    hintText: 'Tambah tag lalu tekan Enter...',
                    hintStyle: TextStyle(
                        fontFamily: 'Inter',
                        color: isDark ? Colors.white38 : Colors.grey.shade400,
                        fontSize: 13),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF3F3F46)
                        : const Color(0xFFF5F5F7),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: FaIcon(FontAwesomeIcons.hashtag,
                          size: 13,
                          color: isDark
                              ? Colors.white54
                              : const Color(0xFF71717A)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _addTag,
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ]),
            if (_tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: _tags.map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('#$tag',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: AppColors.primary)),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _removeTag(tag),
                      child: Icon(Icons.close_rounded,
                          size: 14, color: AppColors.primary),
                    ),
                  ]),
                );
              }).toList()),
            ],
          ]),

          const SizedBox(height: 20),
          Row(children: [
            _sectionLabel('KODE SCRIPT', isDark),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(
                  () => _scriptCtrl.text = _templates[_selectedLang] ?? ''),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF27272A) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: isDark
                            ? const Color(0xFF3F3F46)
                            : const Color(0xFFE4E4E7))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  FaIcon(FontAwesomeIcons.rotate,
                      size: 10,
                      color: isDark
                          ? Colors.white54
                          : const Color(0xFF71717A)),
                  const SizedBox(width: 6),
                  Text('Reset Template',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          color: isDark
                              ? Colors.white54
                              : const Color(0xFF71717A),
                          fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(children: [
                  _dot(const Color(0xFFFF5F57)),
                  const SizedBox(width: 6),
                  _dot(const Color(0xFFFFBD2E)),
                  const SizedBox(width: 6),
                  _dot(const Color(0xFF28C840)),
                  const SizedBox(width: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: langColor(_selectedLang).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      FaIcon(langIcon(_selectedLang),
                          size: 10, color: langColor(_selectedLang)),
                      const SizedBox(width: 6),
                      Text(langLabel(_selectedLang),
                          style: TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 11,
                              color: langColor(_selectedLang),
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _scriptCtrl.clear(),
                    child: const Text('Clear',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            color: Color(0xFF6C7086))),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFF313244)),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LineNumbers(controller: _scriptCtrl),
                      Expanded(
                        child: TextField(
                          controller: _scriptCtrl,
                          maxLines: null,
                          minLines: 12,
                          keyboardType: TextInputType.multiline,
                          style: const TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 13,
                            color: Color(0xFFCDD6F4),
                            height: 1.6,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding:
                                EdgeInsets.fromLTRB(4, 12, 16, 20),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF27272A) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: isDark
                      ? const Color(0xFF3F3F46)
                      : const Color(0xFFE4E4E7)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FaIcon(FontAwesomeIcons.circleInfo,
                  size: 14, color: Color(0xFF6366F1)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Script akan disimpan sebagai Rule di openHAB dengan satu '
                  'action tipe "${langLabel(_selectedLang)}". Script bisa '
                  'dijalankan manual atau ditambahkan trigger nanti melalui UI openHAB.',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: isDark ? Colors.white54 : const Color(0xFF71717A),
                      height: 1.5),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const FaIcon(FontAwesomeIcons.floppyDisk,
                            size: 16, color: Colors.white),
                        const SizedBox(width: 10),
                        const Text('Simpan Script ke openHAB',
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: Colors.white)),
                      ]),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
              fontSize: 11,
              letterSpacing: 0.8,
              color: isDark ? Colors.white38 : const Color(0xFF9E9E9E))),
    );
  }

  Widget _fieldLabel(String label, bool isDark) {
    return Text(label,
        style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: isDark ? Colors.white60 : const Color(0xFF71717A)));
  }

  Widget _buildCard(bool isDark, {required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _buildTextField({
    required bool isDark,
    required TextEditingController controller,
    required String hint,
    required FaIconData prefixIcon,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: isDark ? Colors.white : const Color(0xFF18181B)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            fontFamily: 'Inter',
            color: isDark ? Colors.white38 : Colors.grey.shade400,
            fontSize: 13),
        filled: true,
        fillColor:
            isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        prefixIcon: Center(
          widthFactor: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: FaIcon(prefixIcon,
                size: 14,
                color: isDark ? Colors.white54 : const Color(0xFF71717A)),
          ),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _dot(Color color) => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class _LineNumbers extends StatefulWidget {
  final TextEditingController controller;
  const _LineNumbers({required this.controller});

  @override
  State<_LineNumbers> createState() => _LineNumbersState();
}

class _LineNumbersState extends State<_LineNumbers> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() { if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    final lines = (widget.controller.text.split('\n').length).clamp(12, 200);
    return Container(
      width: 40,
      padding: const EdgeInsets.only(top: 12, bottom: 20, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(
          lines,
          (i) => Text(
            '${i + 1}',
            style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 13,
                color: Color(0xFF585B70),
                height: 1.6),
          ),
        ),
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
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Center(child: FaIcon(icon, size: 14, color: color))),
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

class _ScriptCard extends StatelessWidget {
  final OHScript script;
  final bool isRunning;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRunNow;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ScriptCard({
    required this.script,
    required this.isRunning,
    required this.onToggle,
    required this.onRunNow,
    required this.onTap,
    required this.onDelete,
  });

  Color get _statusColor {
    if (!script.enabled) return const Color(0xFF94A3B8);
    switch (script.status) {
      case 'RUNNING': return const Color(0xFF3B82F6);
      case 'IDLE':    return const Color(0xFF22C55E);
      default:        return const Color(0xFFEF4444);
    }
  }

  String get _statusLabel {
    if (!script.enabled) return 'Nonaktif';
    switch (script.status) {
      case 'RUNNING':       return 'Berjalan';
      case 'IDLE':          return 'Idle';
      case 'UNINITIALIZED': return 'Uninitialized';
      default:              return script.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lc     = langColor(script.language);

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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              Row(children: [
                Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: lc.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14)),
                    child: Center(
                        child: FaIcon(langIcon(script.language),
                            size: 20, color: lc))),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(script.label,
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: isDark
                                ? Colors.white
                                : const Color(0xCC18181B)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (script.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(script.description,
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
                      _badge(label: _statusLabel, color: _statusColor),
                      const SizedBox(width: 6),
                      _badge(label: langLabel(script.language), color: lc),
                      if (script.type == 'blockly') ...[
                        const SizedBox(width: 6),
                        _badge(
                            label: 'Blockly',
                            color: const Color(0xFF0ea5e9)),
                      ],
                    ]),
                  ],
                )),
                Switch(
                    value: script.enabled,
                    onChanged: onToggle,
                    activeThumbColor: AppColors.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ]),
              if (script.script.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E2E),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    script.script.length > 120
                        ? '${script.script.substring(0, 120)}...'
                        : script.script,
                    style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 11,
                        color: Color(0xFFCDD6F4),
                        height: 1.5),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],

              const SizedBox(height: 12),
              Divider(
                  height: 1,
                  color: isDark
                      ? const Color(0xFF3F3F46)
                      : const Color(0xFFF0F0F0)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: Text(script.uid,
                        style: TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 10,
                            color: isDark
                                ? Colors.white38
                                : const Color(0xFF94A3B8)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10)),
                    child: const FaIcon(FontAwesomeIcons.trash,
                        size: 11, color: Color(0xFFEF4444)),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: script.enabled ? onRunNow : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: script.enabled
                          ? (isRunning
                              ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
                              : AppColors.primary.withValues(alpha: 0.08))
                          : (isDark
                              ? const Color(0xFF3F3F46)
                              : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      isRunning
                          ? SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: script.enabled
                                      ? AppColors.primary
                                      : Colors.grey))
                          : FaIcon(FontAwesomeIcons.play,
                              size: 10,
                              color: script.enabled
                                  ? AppColors.primary
                                  : Colors.grey.shade400),
                      const SizedBox(width: 6),
                      Text(
                          isRunning ? 'Berjalan...' : 'Jalankan',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: script.enabled
                                  ? (isRunning
                                      ? const Color(0xFF3B82F6)
                                      : AppColors.primary)
                                  : Colors.grey.shade400)),
                    ]),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _badge({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              fontSize: 10,
              color: color)),
    );
  }
}


class _ScriptDetailSheet extends StatelessWidget {
  final OHScript script;
  const _ScriptDetailSheet({required this.script});

  Color get _statusColor {
    if (!script.enabled) return const Color(0xFF94A3B8);
    switch (script.status) {
      case 'RUNNING': return const Color(0xFF3B82F6);
      case 'IDLE':    return const Color(0xFF22C55E);
      default:        return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lc     = langColor(script.language);

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.95,
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
            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                        color: lc.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16)),
                    child: Center(
                        child: FaIcon(langIcon(script.language),
                            size: 22, color: lc))),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(script.label,
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                            color: isDark
                                ? Colors.white
                                : const Color(0xCC18181B))),
                    const SizedBox(height: 6),
                    Row(children: [
                      _pill(script.enabled ? script.status : 'DISABLED',
                          _statusColor),
                      const SizedBox(width: 8),
                      _pill(langLabel(script.language), lc),
                    ]),
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
                _InfoRow(label: 'UID', value: script.uid),
                if (script.description.isNotEmpty)
                  _InfoRow(label: 'Deskripsi', value: script.description),
                _InfoRow(
                    label: 'Status',
                    value: script.enabled ? 'Aktif' : 'Nonaktif'),
                _InfoRow(label: 'Bahasa', value: langLabel(script.language)),
                _InfoRow(
                    label: 'Tipe',
                    value: script.type == 'blockly' ? 'Blockly' : 'Script'),
                _InfoRow(
                    label: 'Tags',
                    value: script.tags.isEmpty
                        ? '-'
                        : script.tags.join(', ')),
              ]),
            ),

            if (script.script.isNotEmpty) ...[
              const SizedBox(height: 4),
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
                      FaIcon(FontAwesomeIcons.code, size: 13, color: lc),
                      const SizedBox(width: 6),
                      Text('Script Content',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: lc)),
                      const Spacer(),
                      Text('${script.script.split('\n').length} baris',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white54
                                  : const Color(0xFF71717A))),
                    ]),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E2E),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(script.script,
                            style: const TextStyle(
                                fontFamily: 'Courier',
                                fontSize: 12,
                                color: Color(0xFFCDD6F4),
                                height: 1.6)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (script.triggers.isNotEmpty) ...[
              Divider(
                  height: 1,
                  color: isDark
                      ? const Color(0xFF3F3F46)
                      : const Color(0xFFE4E4E7)),
              const SizedBox(height: 16),
              _buildSection(context,
                  icon: FontAwesomeIcons.boltLightning,
                  title: 'Triggers (${script.triggers.length})',
                  color: const Color(0xFFF59E0B),
                  items: script.triggers,
                  isDark: isDark),
            ],

            if (script.actions.isNotEmpty) ...[
              Divider(
                  height: 1,
                  color: isDark
                      ? const Color(0xFF3F3F46)
                      : const Color(0xFFE4E4E7)),
              const SizedBox(height: 16),
              _buildSection(context,
                  icon: FontAwesomeIcons.gears,
                  title: 'Actions (${script.actions.length})',
                  color: const Color(0xFF22C55E),
                  items: script.actions,
                  isDark: isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color: color)),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required FaIconData icon,
    required String title,
    required Color color,
    required List<Map<String, dynamic>> items,
    required bool isDark,
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
          final id         = item['id'] as String? ?? '';
          final cfg        = item['configuration'] as Map<String, dynamic>? ?? {};
          final cfgPreview = cfg.entries
              .take(2)
              .map((e) => '${e.key}: ${e.value}')
              .join(', ');
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.08 : 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: color.withValues(alpha: isDark ? 0.2 : 0.12))),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 90,
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