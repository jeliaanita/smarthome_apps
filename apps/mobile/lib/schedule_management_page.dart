import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/controllers/openhab_controller.dart';
import '../../../../core/providers/installation_provider.dart';
import '../../../../core/providers/role_provider.dart';
import 'package:mobile/core/widget/access_denied_view.dart';
import '../../../../core/theme/app_colors.dart';

/// Tag khusus yang dikenali oleh halaman "Schedule" bawaan openHAB Main UI.
/// Tanpa tag ini, rule tidak akan muncul di Settings > Schedule meskipun
/// rule tersebut punya time-based trigger (cron/timer).
const String kOpenHABScheduleTag = 'Schedule';

class OHSchedule {
  final String uid;
  final String label;
  final String description;
  final bool enabled;
  final String status;
  final List<String> tags;
  final List<Map<String, dynamic>> triggers;
  final List<Map<String, dynamic>> actions;
  final List<Map<String, dynamic>> conditions;

  const OHSchedule({
    required this.uid,
    required this.label,
    required this.description,
    required this.enabled,
    required this.status,
    required this.tags,
    required this.triggers,
    required this.actions,
    required this.conditions,
  });

  factory OHSchedule.fromJson(Map<String, dynamic> json) {
    final triggers = List<Map<String, dynamic>>.from(
        json['triggers'] as List? ?? []);

    final statusMap = json['status'] as Map<String, dynamic>?;
    final statusVal = statusMap?['status'] as String?
        ?? (json['enabled'] == false ? 'DISABLED' : 'IDLE');

    return OHSchedule(
      uid: json['uid'] as String? ?? '',
      label: json['name'] as String? ?? json['label'] as String?
          ?? json['uid'] as String? ?? '-',
      description: json['description'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      status: statusVal,
      tags: List<String>.from(json['tags'] as List? ?? []),
      triggers: triggers,
      actions: List<Map<String, dynamic>>.from(
          json['actions'] as List? ?? []),
      conditions: List<Map<String, dynamic>>.from(
          json['conditions'] as List? ?? []),
    );
  }

  /// True jika rule ini sudah punya tag "Schedule" sehingga akan muncul
  /// di halaman Settings > Schedule bawaan openHAB.
  bool get isVisibleInOpenHABScheduleUI => tags.contains(kOpenHABScheduleTag);

  OHSchedule copyWith({bool? enabled, String? status, List<String>? tags}) =>
      OHSchedule(
        uid: uid, label: label, description: description,
        enabled: enabled ?? this.enabled,
        status: status ?? this.status,
        tags: tags ?? this.tags, triggers: triggers,
        actions: actions, conditions: conditions,
      );

  Map<String, dynamic>? get primaryTrigger =>
      triggers.isNotEmpty ? triggers.first : null;

  String get triggerType {
    final t = (primaryTrigger?['type'] as String? ?? '').toLowerCase();
    if (t.contains('timer') || t.contains('cron')) return 'cron';
    if (t.contains('time')) return 'time';
    if (t.contains('item')) return 'item';
    if (t.contains('thing')) return 'thing';
    if (t.contains('system')) return 'system';
    if (t.contains('channel')) return 'channel';
    return 'other';
  }

  String get triggerDisplay {
    final cfg = primaryTrigger?['configuration'] as Map<String, dynamic>? ?? {};
    final cron = cfg['cronExpression'] as String?;
    if (cron != null) return _cronHuman(cron);
    final time = cfg['time'] as String?;
    if (time != null) return 'Setiap hari $time';
    final startTime = cfg['startTime'] as String?;
    if (startTime != null) return 'Mulai $startTime';
    final itemName = cfg['itemName'] as String?;
    if (itemName != null) {
      final state = cfg['state'] as String? ?? '';
      return '$itemName → $state';
    }
    if (cfg.isEmpty) return '-';
    return cfg.entries.take(2).map((e) => '${e.key}: ${e.value}').join(', ');
  }

  static String _cronHuman(String cron) {
    final parts = cron.trim().split(RegExp(r'\s+'));
    if (parts.length < 6) return cron;
    final ss  = parts[0];
    final mm  = parts[1];
    final hh  = parts[2];
    final day = parts[3];
    final mon = parts[4];
    final dow = parts[5];

    if (hh != '*' && mm != '*') {
      final time = '${hh.padLeft(2, '0')}:${mm.padLeft(2, '0')}';
      if (dow != '?' && dow != '*') {
        final days = _dowLabel(dow);
        return 'Setiap $days $time';
      }
      if (day != '*' && day != '?') return 'Tgl $day setiap bulan $time';
      if (mon != '*' && mon != '?') return 'Tgl $day bulan $mon $time';
      return 'Setiap hari $time';
    }
    if (mm == '0' && hh == '*') return 'Setiap jam';
    return cron;
  }

  static String _dowLabel(String dow) {
    const map = {
      '1': 'Min', '2': 'Sen', '3': 'Sel', '4': 'Rab',
      '5': 'Kam', '6': 'Jum', '7': 'Sab',
      'MON': 'Sen', 'TUE': 'Sel', 'WED': 'Rab',
      'THU': 'Kam', 'FRI': 'Jum', 'SAT': 'Sab', 'SUN': 'Min',
    };
    return dow.split(',').map((d) => map[d.trim()] ?? d).join(', ');
  }
}

class ScheduleService {
  final String baseUrl;
  final Map<String, String> headers;
  final http.Client _client = http.Client();

  ScheduleService({required this.baseUrl, required this.headers});

  Uri _uri(String path) => Uri.parse('$baseUrl/rest$path');

  Future<List<OHSchedule>> getSchedules() async {
    final res = await _client
        .get(_uri('/rules'), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final list = jsonDecode(res.body) as List;
    return list
        .map((e) => OHSchedule.fromJson(e as Map<String, dynamic>))
        .where(_isScheduleRule)
        .toList();
  }

  bool _isScheduleRule(OHSchedule s) {
    if (s.triggers.isEmpty) return false;
    final t = (s.triggers.first['type'] as String? ?? '').toLowerCase();
    return t.contains('timer') ||
        t.contains('cron') ||
        t.contains('time') ||
        t.contains('daytime') ||
        t.contains('channel.ChannelEventTrigger') == false &&
        (t.contains('time') || t.contains('timer'));
  }

  Future<OHSchedule> createSchedule({
    required String label,
    required String description,
    required String triggerType,
    required Map<String, dynamic> triggerConfig,
    required String scriptContent,
    required String scriptLanguage,
    required List<String> tags,
    required List<Map<String, dynamic>> conditions,
  }) async {
    final uid = 'schedule_${DateTime.now().millisecondsSinceEpoch}';

    String ohTriggerType;
    switch (triggerType) {
      case 'cron':  ohTriggerType = 'timer.GenericCronTrigger'; break;
      case 'time':  ohTriggerType = 'timer.TimeOfDayTrigger';   break;
      case 'item':  ohTriggerType = 'core.ItemStateChangeTrigger'; break;
      default:      ohTriggerType = 'timer.GenericCronTrigger';
    }

    final mimeType = _mimeType(scriptLanguage);

    // PENTING: paksa tambahkan tag "Schedule" agar rule ini otomatis
    // dikenali dan tampil di halaman Settings > Schedule bawaan openHAB.
    // (Halaman itu hanya menampilkan rule yang bertag "Schedule".)
    final finalTags = <String>{...tags, kOpenHABScheduleTag}.toList();

    final payload = {
      'uid': uid,
      'name': label,
      'description': description,
      'tags': finalTags,
      'visibility': 'VISIBLE',
      'triggers': [
        {'id': '1', 'type': ohTriggerType, 'configuration': triggerConfig}
      ],
      'conditions': conditions,
      'actions': [
        {
          'id': '1',
          'type': 'script.ScriptAction',
          'configuration': {'type': mimeType, 'script': scriptContent},
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
        return OHSchedule.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      } catch (_) {
        // Body tidak sesuai bentuk yang diharapkan — lanjut pakai fallback
        // di bawah, tetap dianggap sukses karena request HTTP-nya 2xx.
      }
    }

    return OHSchedule(
      uid: uid, label: label, description: description,
      enabled: true, status: 'IDLE', tags: finalTags,
      triggers: [{'id': '1', 'type': ohTriggerType, 'configuration': triggerConfig}],
      actions: [{'id': '1', 'type': 'script.ScriptAction',
        'configuration': {'type': mimeType, 'script': scriptContent}}],
      conditions: conditions,
    );
  }

  String _mimeType(String lang) {
    switch (lang) {
      case 'js':     return 'application/javascript';
      case 'jython': return 'application/x-python';
      case 'groovy': return 'application/x-groovy';
      case 'ruby':   return 'application/x-ruby';
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

  /// Ambil detail rule lengkap langsung dari openHAB (dipakai untuk retag).
  Future<Map<String, dynamic>> getRuleRaw(String uid) async {
    final res = await _client
        .get(_uri('/rules/$uid'), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Menambahkan tag "Schedule" ke rule yang sudah ada (dibuat sebelum
  /// fitur auto-tag ini ada), supaya rule lama juga muncul di halaman
  /// Settings > Schedule bawaan openHAB. Rule yang sudah bertag akan
  /// dilewati (idempotent).
  ///
  /// Mengembalikan `true` jika ada perubahan (tag ditambahkan),
  /// `false` jika rule sudah bertag sebelumnya.
  Future<bool> ensureScheduleTag(String uid) async {
    final ruleJson = await getRuleRaw(uid);
    final currentTags = List<String>.from(ruleJson['tags'] as List? ?? []);
    if (currentTags.contains(kOpenHABScheduleTag)) return false;

    currentTags.add(kOpenHABScheduleTag);
    ruleJson['tags'] = currentTags;

    final res = await _client.put(
      _uri('/rules/$uid'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode(ruleJson),
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return true;
  }
}

Color triggerColor(String type) {
  switch (type) {
    case 'cron':   return const Color(0xFF6366F1);
    case 'time':   return const Color(0xFF3B82F6);
    case 'item':   return const Color(0xFF10B981);
    case 'thing':  return const Color(0xFFF59E0B);
    case 'system': return const Color(0xFF8B5CF6);
    default:       return const Color(0xFF94A3B8);
  }
}

IconData triggerIcon(String type) {
  switch (type) {
    case 'cron':   return Icons.schedule_rounded;
    case 'time':   return Icons.access_time_rounded;
    case 'item':   return Icons.toggle_on_rounded;
    case 'thing':  return Icons.device_hub_rounded;
    case 'system': return Icons.settings_rounded;
    default:       return Icons.event_rounded;
  }
}

String triggerLabel(String type) {
  switch (type) {
    case 'cron':   return 'Cron';
    case 'time':   return 'Waktu';
    case 'item':   return 'Item';
    case 'thing':  return 'Thing';
    case 'system': return 'System';
    default:       return 'Lainnya';
  }
}

class ScheduleManagementPage extends StatefulWidget {
  const ScheduleManagementPage({super.key});

  @override
  State<ScheduleManagementPage> createState() => _ScheduleManagementPageState();
}

class _ScheduleManagementPageState extends State<ScheduleManagementPage>
    with SingleTickerProviderStateMixin {
  final _ctrl = OpenHABController.instance;

  ScheduleService? _svc;
  List<OHSchedule> _allSchedules      = [];
  List<OHSchedule> _filteredSchedules = [];
  bool    _isLoading  = false;
  bool    _isSyncing  = false;
  String? _errorMsg;

  String _filterStatus = 'all';
  String _filterType   = 'all';
  String _searchQuery  = '';
  bool   _showSearch   = false;
  final  _searchCtrl   = TextEditingController();

  final Set<String> _runningUids = {};
  late AnimationController _animCtrl;

  /// Jumlah schedule yang belum bertag "Schedule" (belum tampil di
  /// halaman Settings > Schedule bawaan openHAB).
  int get _untaggedCount =>
      _allSchedules.where((s) => !s.isVisibleInOpenHABScheduleUI).length;

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

    final headers = <String, String>{'Accept': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    } else if (username != null && password != null) {
      final encoded = base64Encode(utf8.encode('$username:$password'));
      headers['Authorization'] = 'Basic $encoded';
    }

    if (!mounted) return;
    _svc = ScheduleService(baseUrl: _ctrl.serverUrl, headers: headers);
    await _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    if (_svc == null) return;
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      final schedules = await _svc!.getSchedules();
      if (!mounted) return;
      setState(() { _allSchedules = schedules; _applyFilter(); });
      unawaited(_animCtrl.forward(from: 0));
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMsg = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    setState(() {
      List<OHSchedule> base;
      switch (_filterStatus) {
        case 'enabled':  base = _allSchedules.where((s) => s.enabled).toList();  break;
        case 'disabled': base = _allSchedules.where((s) => !s.enabled).toList(); break;
        default:         base = List.from(_allSchedules);
      }
      if (_filterType != 'all') {
        base = base.where((s) => s.triggerType == _filterType).toList();
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        base = base.where((s) =>
            s.label.toLowerCase().contains(q) ||
            s.description.toLowerCase().contains(q) ||
            s.triggerDisplay.toLowerCase().contains(q) ||
            s.uid.toLowerCase().contains(q)).toList();
      }
      _filteredSchedules = base;
    });
  }

  int get _enabledCount  => _allSchedules.where((s) => s.enabled).length;
  int get _disabledCount => _allSchedules.where((s) => !s.enabled).length;

  Future<void> _toggleEnabled(OHSchedule schedule, bool value) async {
    final idx = _allSchedules.indexWhere((s) => s.uid == schedule.uid);
    if (idx < 0) return;
    setState(() {
      _allSchedules[idx] = schedule.copyWith(
          enabled: value, status: value ? 'IDLE' : 'DISABLED');
      _applyFilter();
    });
    try {
      await _svc!.setEnabled(schedule.uid, value);
      _showSnack(value ? 'Schedule diaktifkan' : 'Schedule dinonaktifkan',
          isError: false);
    } catch (e) {
      if (!mounted) return;
      setState(() { _allSchedules[idx] = schedule; _applyFilter(); });
      _showSnack('Gagal mengubah status: $e', isError: true);
    }
  }

  Future<void> _runNow(OHSchedule schedule) async {
    if (_runningUids.contains(schedule.uid)) return;
    setState(() => _runningUids.add(schedule.uid));
    try {
      await _svc!.runNow(schedule.uid);
      _showSnack('Schedule "${schedule.label}" dijalankan', isError: false);
    } catch (e) {
      _showSnack('Gagal menjalankan: $e', isError: true);
    } finally {
      if (mounted) {
        await Future.delayed(const Duration(seconds: 2));
        setState(() => _runningUids.remove(schedule.uid));
      }
    }
  }

  Future<void> _confirmDelete(OHSchedule schedule) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF27272A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Hapus Schedule',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: isDark ? Colors.white : const Color(0xFF18181B))),
        content: Text(
          'Yakin ingin menghapus "${schedule.label}"?\nTindakan ini tidak dapat dibatalkan.',
          style: TextStyle(fontFamily: 'Inter', fontSize: 13,
              color: isDark ? Colors.white54 : const Color(0xFF71717A)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Batal',
                  style: TextStyle(fontFamily: 'Inter',
                      color: isDark ? Colors.white54 : const Color(0xFF71717A)))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hapus',
                  style: TextStyle(fontFamily: 'Inter',
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (!mounted) return;
    if (confirm == true) {
      try {
        await _svc!.delete(schedule.uid);
        if (!mounted) return;
        setState(() {
          _allSchedules.removeWhere((s) => s.uid == schedule.uid);
          _applyFilter();
        });
        _showSnack('Schedule dihapus', isError: false);
      } catch (e) {
        if (!mounted) return;
        _showSnack('Gagal menghapus: $e', isError: true);
      }
    }
  }

  Future<void> _openAddSchedule() async {
    if (_svc == null) return;
    final result = await Navigator.push<OHSchedule>(
      context,
      MaterialPageRoute(builder: (_) => AddSchedulePage(service: _svc!)),
    );
    if (!mounted) return;
    if (result != null) {
      setState(() { _allSchedules.insert(0, result); _applyFilter(); });
      _showSnack('Schedule "${result.label}" berhasil dibuat!', isError: false);
    }
  }

  /// Menambahkan tag "Schedule" ke semua rule lama yang dibuat sebelum
  /// fitur auto-tag ada, supaya semuanya tampil di halaman
  /// Settings > Schedule bawaan openHAB. Aman dijalankan berkali-kali.
  Future<void> _syncToOpenHABSchedulePage() async {
    if (_svc == null || _isSyncing) return;

    final targets =
        _allSchedules.where((s) => !s.isVisibleInOpenHABScheduleUI).toList();

    if (targets.isEmpty) {
      _showSnack('Semua schedule sudah tersinkron ke openHAB', isError: false);
      return;
    }

    setState(() => _isSyncing = true);
    int success = 0;
    int failed  = 0;

    for (final schedule in targets) {
      try {
        final changed = await _svc!.ensureScheduleTag(schedule.uid);
        if (!mounted) return;
        if (changed) {
          final idx = _allSchedules.indexWhere((s) => s.uid == schedule.uid);
          if (idx >= 0) {
            setState(() {
              _allSchedules[idx] = schedule.copyWith(
                tags: [...schedule.tags, kOpenHABScheduleTag],
              );
            });
          }
          success++;
        }
      } catch (_) {
        failed++;
      }
    }

    _applyFilter();
    if (mounted) setState(() => _isSyncing = false);

    if (failed == 0) {
      _showSnack('$success schedule berhasil disinkronkan ke openHAB',
          isError: false);
    } else {
      _showSnack('$success berhasil, $failed gagal disinkronkan',
          isError: true);
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
      return const AccessDeniedView(featureName: 'Schedule Management');
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
        onPressed: _openAddSchedule,
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
      backgroundColor: isDark ? const Color(0xFF27272A) : Colors.white,
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
              style: TextStyle(fontFamily: 'Inter', fontSize: 15, color: cs.onSurface),
              decoration: InputDecoration(
                hintText: 'Cari schedule...',
                hintStyle: TextStyle(fontFamily: 'Inter',
                    color: isDark ? Colors.white38 : Colors.grey.shade400,
                    fontSize: 15),
                border: InputBorder.none,
              ),
            )
          : Text('Schedule',
              style: TextStyle(fontFamily: 'Inter',
                  fontWeight: FontWeight.w700, fontSize: 18,
                  color: cs.onSurface)),
      actions: [
        if (!_showSearch && _untaggedCount > 0)
          IconButton(
            icon: _isSyncing
                ? SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  )
                : Badge(
                    label: Text('$_untaggedCount'),
                    backgroundColor: const Color(0xFFF59E0B),
                    child: Icon(Icons.sync_rounded, size: 22, color: cs.onSurface),
                  ),
            tooltip: 'Sinkronkan ke halaman Schedule openHAB',
            onPressed: _isSyncing ? null : _syncToOpenHABSchedulePage,
          ),
        IconButton(
          icon: Icon(_showSearch ? Icons.close_rounded : Icons.search_rounded,
              size: 22, color: cs.onSurface),
          onPressed: () {
            setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchCtrl.clear(); _searchQuery = ''; _applyFilter();
              }
            });
          },
        ),
        IconButton(
          icon: Icon(Icons.refresh_rounded, size: 22, color: cs.onSurface),
          onPressed: _loadSchedules,
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
        Text('Memuat Schedule...',
            style: TextStyle(fontFamily: 'Inter', fontSize: 13,
                color: isDark ? Colors.white54 : const Color(0xFF71717A))),
      ]),
    );
  }

  Widget _buildError() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_off_rounded, size: 56, color: Colors.red.shade300),
          const SizedBox(height: 14),
          Text('Gagal memuat Schedule',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                  fontSize: 16, color: Colors.red.shade700)),
          const SizedBox(height: 6),
          Text(_errorMsg!, textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                  color: isDark ? Colors.red.shade300 : Colors.red.shade400)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadSchedules,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                elevation: 0),
            icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
            label: const Text('Coba Lagi',
                style: TextStyle(fontFamily: 'Inter', color: Colors.white,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  Widget _buildContent() {
    final presentTypes = _allSchedules.map((s) => s.triggerType).toSet();
    return RefreshIndicator(
      onRefresh: _loadSchedules,
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
                  if (_untaggedCount > 0) ...[
                    _buildSyncBanner(),
                    const SizedBox(height: 16),
                  ],
                  _buildSummaryCards(),
                  const SizedBox(height: 16),
                  if (presentTypes.length > 1) ...[
                    _buildTypeChips(presentTypes),
                    const SizedBox(height: 16),
                  ],
                  _buildFilterChips(),
                  const SizedBox(height: 16),
                  _buildListHeader(),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          _filteredSchedules.isEmpty
              ? SliverFillRemaining(child: _buildEmpty())
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final schedule = _filteredSchedules[i];
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
                          child: _ScheduleCard(
                            schedule: schedule,
                            isRunning: _runningUids.contains(schedule.uid),
                            onToggle: (v) => _toggleEnabled(schedule, v),
                            onRunNow: () => _runNow(schedule),
                            onTap: () => _showDetail(schedule),
                            onDelete: () => _confirmDelete(schedule),
                          ),
                        );
                      },
                      childCount: _filteredSchedules.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildSyncBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline_rounded,
            size: 18, color: Color(0xFFF59E0B)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_untaggedCount schedule belum tampil di openHAB',
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: isDark ? Colors.white : const Color(0xFF92400E)),
              ),
              const SizedBox(height: 2),
              Text(
                'Halaman Settings > Schedule di openHAB hanya menampilkan '
                'rule yang bertag "Schedule". Tap tombol untuk sinkron.',
                style: TextStyle(fontFamily: 'Inter', fontSize: 11,
                    color: isDark ? Colors.white54 : const Color(0xFF92400E).withValues(alpha: 0.8)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _isSyncing ? null : _syncToOpenHABSchedulePage,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                borderRadius: BorderRadius.circular(14)),
            child: _isSyncing
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Sync',
                    style: TextStyle(fontFamily: 'Inter',
                        fontWeight: FontWeight.w700, fontSize: 12,
                        color: Colors.white)),
          ),
        ),
      ]),
    );
  }

  Widget _buildSummaryCards() {
    return Row(children: [
      Expanded(child: _SummaryCard(
          label: 'Total', count: _allSchedules.length,
          color: const Color(0xFF6366F1), icon: Icons.calendar_month_rounded)),
      const SizedBox(width: 10),
      Expanded(child: _SummaryCard(
          label: 'Aktif', count: _enabledCount,
          color: const Color(0xFF22C55E), icon: Icons.check_circle_rounded)),
      const SizedBox(width: 10),
      Expanded(child: _SummaryCard(
          label: 'Nonaktif', count: _disabledCount,
          color: const Color(0xFF94A3B8), icon: Icons.pause_circle_rounded)),
    ]);
  }

  Widget _buildTypeChips(Set<String> presentTypes) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final types = [
      {'key': 'all',    'label': 'Semua Tipe'},
      {'key': 'cron',   'label': 'Cron'},
      {'key': 'time',   'label': 'Waktu'},
      {'key': 'item',   'label': 'Item'},
      {'key': 'system', 'label': 'System'},
      {'key': 'other',  'label': 'Lainnya'},
    ].where((t) => t['key'] == 'all' || presentTypes.contains(t['key'])).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: types.map((type) {
          final isSelected = _filterType == type['key'];
          final color = triggerColor(type['key']!);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () { setState(() => _filterType = type['key']!); _applyFilter(); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color
                      : (isDark ? const Color(0xFF3F3F46) : Colors.white),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? color
                        : (isDark ? const Color(0xFF52525B) : const Color(0xFFE4E4E7)),
                    width: 1.5,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (type['key'] != 'all') ...[
                    Icon(triggerIcon(type['key']!), size: 11,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white70 : color)),
                    const SizedBox(width: 5),
                  ],
                  Text(type['label']!,
                      style: TextStyle(fontFamily: 'Inter',
                          fontWeight: FontWeight.w600, fontSize: 12,
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

  Widget _buildFilterChips() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filters = [
      {'key': 'all',      'label': 'Semua',    'count': _allSchedules.length},
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
                      : (isDark ? const Color(0xFF3F3F46) : Colors.white),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                      blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(f['label']! as String,
                      style: TextStyle(fontFamily: 'Inter',
                          fontWeight: FontWeight.w600, fontSize: 13,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white70 : const Color(0xFF71717A)))),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.25)
                          : (isDark ? const Color(0xFF52525B) : const Color(0xFFF4F4F5)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${f['count']}',
                        style: TextStyle(fontFamily: 'Inter',
                            fontWeight: FontWeight.w700, fontSize: 11,
                            color: isSelected
                                ? Colors.white
                                : (isDark ? Colors.white54 : const Color(0xFF71717A)))),
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
      Text('${_filteredSchedules.length} Schedule${_filteredSchedules.length != 1 ? 's' : ''}',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
              fontSize: 14,
              color: isDark ? Colors.white : const Color(0xCC18181B))),
      const Spacer(),
      Text('Tarik untuk refresh',
          style: TextStyle(fontFamily: 'Inter', fontSize: 11,
              color: isDark ? Colors.white38 : Colors.grey.shade400)),
    ]);
  }

  Widget _buildEmpty() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.calendar_today_rounded, size: 56,
            color: isDark ? Colors.white24 : Colors.grey.shade300),
        const SizedBox(height: 12),
        Text('Tidak ada Schedule',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                fontSize: 16,
                color: isDark ? Colors.white38 : Colors.grey.shade500)),
        const SizedBox(height: 4),
        Text(
          _filterStatus == 'all'
              ? 'Tekan tombol + untuk membuat schedule baru.'
              : 'Tidak ada schedule dengan status ini.',
          style: TextStyle(fontFamily: 'Inter', fontSize: 13,
              color: isDark ? Colors.white24 : Colors.grey.shade400),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }

  void _showDetail(OHSchedule schedule) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ScheduleDetailSheet(schedule: schedule),
    );
  }
}

class AddSchedulePage extends StatefulWidget {
  final ScheduleService service;
  const AddSchedulePage({super.key, required this.service});

  @override
  State<AddSchedulePage> createState() => _AddSchedulePageState();
}

class _AddSchedulePageState extends State<AddSchedulePage> {
  final _labelCtrl   = TextEditingController();
  final _descCtrl    = TextEditingController();
  final _scriptCtrl  = TextEditingController();
  final _tagCtrl     = TextEditingController();

  String _triggerType = 'cron';
  final String _cronPreset  = 'custom';
  final _cronCtrl     = TextEditingController(text: '0 0 8 * * ?');
  TimeOfDay _timeOfDay = const TimeOfDay(hour: 8, minute: 0);
  final Set<int> _selectedDays = {1, 2, 3, 4, 5};
  final _itemNameCtrl  = TextEditingController();
  final _itemStateCtrl = TextEditingController();
  bool _useTimeCondition = false;
  TimeOfDay _condStart   = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _condEnd     = const TimeOfDay(hour: 22, minute: 0);

  String _scriptLang = 'dsl';
  final List<String> _tags = [];
  bool _isSaving     = false;
  String? _errorMsg;

  static const Map<String, String> _cronPresets = {
    'custom':                'Custom',
    '0 0 8 * * ?':           'Setiap hari 08:00',
    '0 0 12 * * ?':          'Setiap hari 12:00',
    '0 0 18 * * ?':          'Setiap hari 18:00',
    '0 0 22 * * ?':          'Setiap hari 22:00',
    '0 0 8 * * MON-FRI':     'Setiap hari kerja 08:00',
    '0 0 8 * * SAT,SUN':     'Setiap akhir pekan 08:00',
    '0 0/30 * * * ?':        'Setiap 30 menit',
    '0 0 * * * ?':           'Setiap jam',
    '0 0 0 * * ?':           'Setiap tengah malam',
  };

  static const Map<String, String> _scriptTemplates = {
    'dsl':    'logInfo("Schedule", "Schedule triggered!")',
    'js':     'var logger = Java.type("org.slf4j.LoggerFactory").getLogger("org.openhab.rule.Schedule");\nlogger.info("Schedule triggered!");',
    'jython': 'from core.log import logging, LOG_PREFIX\nlog = logging.getLogger("{}.Schedule".format(LOG_PREFIX))\nlog.info("Schedule triggered!")',
    'groovy': 'import org.slf4j.LoggerFactory\ndef log = LoggerFactory.getLogger("org.openhab.rule.Schedule")\nlog.info("Schedule triggered!")',
  };

  @override
  void initState() {
    super.initState();
    _scriptCtrl.text = _scriptTemplates[_scriptLang] ?? '';
  }

  @override
  void dispose() {
    _labelCtrl.dispose(); _descCtrl.dispose(); _scriptCtrl.dispose();
    _tagCtrl.dispose(); _cronCtrl.dispose();
    _itemNameCtrl.dispose(); _itemStateCtrl.dispose();
    super.dispose();
  }

  void _addTag() {
    final tag = _tagCtrl.text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() { _tags.add(tag); _tagCtrl.clear(); });
    }
  }

  String _buildCronExpression() {
    if (_triggerType == 'cron') return _cronCtrl.text.trim();
    if (_triggerType == 'time') {
      final hh = _timeOfDay.hour.toString();
      final mm = _timeOfDay.minute.toString();
      if (_selectedDays.length == 7) return '0 $mm $hh * * ?';
      final dowStr = _selectedDays.map((d) {
        const map = {1:'MON',2:'TUE',3:'WED',4:'THU',5:'FRI',6:'SAT',7:'SUN'};
        return map[d]!;
      }).join(',');
      return '0 $mm $hh * * $dowStr';
    }
    return '';
  }

  Map<String, dynamic> _buildTriggerConfig() {
    switch (_triggerType) {
      case 'cron':
      case 'time':
        return {'cronExpression': _buildCronExpression()};
      case 'item':
        return {
          'itemName': _itemNameCtrl.text.trim(),
          'state': _itemStateCtrl.text.trim(),
        };
      default:
        return {'cronExpression': _cronCtrl.text.trim()};
    }
  }

  List<Map<String, dynamic>> _buildConditions() {
    if (!_useTimeCondition) return [];
    return [
      {
        'id': '1',
        'type': 'core.TimeOfDayCondition',
        'configuration': {
          'startTime': '${_condStart.hour.toString().padLeft(2,'0')}:${_condStart.minute.toString().padLeft(2,'0')}',
          'endTime':   '${_condEnd.hour.toString().padLeft(2,'0')}:${_condEnd.minute.toString().padLeft(2,'0')}',
        },
      }
    ];
  }

  Future<void> _pickTime(bool isCondStart) async {
    final picked = await showTimePicker(
        context: context,
        initialTime: isCondStart ? _condStart : _condEnd);
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        if (isCondStart) {
          _condStart = picked;
        } else {
          _condEnd   = picked;
        }
      });
    }
  }

  Future<void> _pickTriggerTime() async {
    final picked = await showTimePicker(
        context: context, initialTime: _timeOfDay);
    if (!mounted) return;
    if (picked != null) setState(() => _timeOfDay = picked);
  }

  Future<void> _save() async {
    final label  = _labelCtrl.text.trim();
    final script = _scriptCtrl.text.trim();
    if (label.isEmpty) {
      setState(() => _errorMsg = 'Nama schedule tidak boleh kosong'); return;
    }
    if (_triggerType == 'item' && _itemNameCtrl.text.trim().isEmpty) {
      setState(() => _errorMsg = 'Nama Item tidak boleh kosong'); return;
    }
    if (script.isEmpty) {
      setState(() => _errorMsg = 'Kode script tidak boleh kosong'); return;
    }

    setState(() { _isSaving = true; _errorMsg = null; });
    try {
      final result = await widget.service.createSchedule(
        label: label,
        description: _descCtrl.text.trim(),
        triggerType: _triggerType == 'time' ? 'cron' : _triggerType,
        triggerConfig: _buildTriggerConfig(),
        scriptContent: script,
        scriptLanguage: _scriptLang,
        tags: _tags,
        conditions: _buildConditions(),
      );
      if (!mounted) return;
      Navigator.pop(context, result);
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
      body: _buildBody(isDark),
    );
  }

  AppBar _buildAppBar(bool isDark, ColorScheme cs) {
    return AppBar(
      backgroundColor: isDark ? const Color(0xFF27272A) : Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.close_rounded, size: 22, color: cs.onSurface),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text('Tambah Schedule',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
              fontSize: 18, color: cs.onSurface)),
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
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Simpan',
                      style: TextStyle(fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 14, color: Colors.white)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(bool isDark) {
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
                color: isDark ? const Color(0xFF3B1515) : const Color(0xFFFFF0F0),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline_rounded,
                    size: 16, color: Color(0xFFEF4444)),
                const SizedBox(width: 10),
                Expanded(child: Text(_errorMsg!,
                    style: const TextStyle(fontFamily: 'Inter',
                        fontSize: 13, color: Color(0xFFEF4444)))),
                GestureDetector(
                  onTap: () => setState(() => _errorMsg = null),
                  child: const Icon(Icons.close_rounded,
                      size: 16, color: Color(0xFFEF4444)),
                ),
              ]),
            ),
          ],

          _sectionLabel('INFORMASI SCHEDULE', isDark),
          const SizedBox(height: 10),
          _card(isDark: isDark, children: [
            _fieldLabel('Nama Schedule *', isDark),
            const SizedBox(height: 8),
            _textField(
                controller: _labelCtrl,
                hint: 'contoh: Matikan lampu taman jam 22:00',
                icon: Icons.label_rounded,
                isDark: isDark),
            const SizedBox(height: 16),
            _fieldLabel('Deskripsi (opsional)', isDark),
            const SizedBox(height: 8),
            _textField(
                controller: _descCtrl,
                hint: 'Jelaskan fungsi schedule ini...',
                icon: Icons.notes_rounded,
                isDark: isDark,
                maxLines: 2),
          ]),

          const SizedBox(height: 20),

          _sectionLabel('TIPE TRIGGER', isDark),
          const SizedBox(height: 10),
          _card(isDark: isDark, children: [
            Row(children: [
              _triggerTypeBtn('cron',  Icons.schedule_rounded,   'Cron Expression', 'Jadwal cron fleksibel', isDark),
              const SizedBox(width: 10),
              _triggerTypeBtn('time',  Icons.access_time_rounded, 'Waktu Tertentu',  'Pilih jam & hari', isDark),
              const SizedBox(width: 10),
              _triggerTypeBtn('item',  Icons.toggle_on_rounded,   'Item State',      'Saat item berubah', isDark),
            ]),
          ]),

          const SizedBox(height: 20),

          _sectionLabel('KONFIGURASI TRIGGER', isDark),
          const SizedBox(height: 10),
          _card(isDark: isDark, children: [
            if (_triggerType == 'cron') _buildCronConfig(isDark),
            if (_triggerType == 'time') _buildTimeConfig(isDark),
            if (_triggerType == 'item') _buildItemConfig(isDark),
          ]),

          const SizedBox(height: 20),
          _sectionLabel('KONDISI (OPSIONAL)', isDark),
          const SizedBox(height: 10),
          _card(isDark: isDark, children: [
            Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Batasi Waktu Eksekusi',
                      style: TextStyle(fontFamily: 'Inter',
                          fontWeight: FontWeight.w600, fontSize: 14,
                          color: isDark ? Colors.white : const Color(0xFF18181B))),
                  Text('Hanya jalankan dalam rentang waktu tertentu',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 11,
                          color: isDark ? Colors.white54 : const Color(0xFF71717A))),
                ],
              )),
              Switch(
                value: _useTimeCondition,
                onChanged: (v) => setState(() => _useTimeCondition = v),
                activeThumbColor: AppColors.primary,
              ),
            ]),
            if (_useTimeCondition) ...[
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _timePickerBtn(
                    label: 'Mulai', time: _condStart,
                    onTap: () => _pickTime(true), isDark: isDark)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('—',
                      style: TextStyle(
                          color: isDark ? Colors.white38 : const Color(0xFF71717A))),
                ),
                Expanded(child: _timePickerBtn(
                    label: 'Selesai', time: _condEnd,
                    onTap: () => _pickTime(false), isDark: isDark)),
              ]),
            ],
          ]),

          const SizedBox(height: 20),
          _sectionLabel('TAGS (OPSIONAL)', isDark),
          const SizedBox(height: 4),
          Text(
            'Tag "Schedule" akan otomatis ditambahkan agar rule ini '
            'muncul di halaman Settings > Schedule openHAB.',
            style: TextStyle(fontFamily: 'Inter', fontSize: 11,
                color: isDark ? Colors.white38 : Colors.grey.shade500),
          ),
          const SizedBox(height: 10),
          _card(isDark: isDark, children: [
            Row(children: [
              Expanded(child: TextField(
                controller: _tagCtrl,
                style: TextStyle(fontFamily: 'Inter', fontSize: 14,
                    color: isDark ? Colors.white : const Color(0xFF18181B)),
                onSubmitted: (_) => _addTag(),
                decoration: InputDecoration(
                  hintText: 'Tambah tag lalu tekan Enter...',
                  hintStyle: TextStyle(fontFamily: 'Inter',
                      color: isDark ? Colors.white38 : Colors.grey.shade400,
                      fontSize: 13),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.tag_rounded, size: 16,
                        color: isDark ? Colors.white38 : const Color(0xFF71717A)),
                  ),
                ),
              )),
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
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              // Chip "Schedule" bawaan, non-removable, hanya sebagai indikator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.25))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_rounded, size: 11, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 5),
                  const Text('#Schedule',
                      style: TextStyle(fontFamily: 'Inter',
                          fontWeight: FontWeight.w600, fontSize: 12,
                          color: Color(0xFFF59E0B))),
                ]),
              ),
              ..._tags.map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.25))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('#$tag',
                        style: TextStyle(fontFamily: 'Inter',
                            fontWeight: FontWeight.w600, fontSize: 12,
                            color: AppColors.primary)),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => setState(() => _tags.remove(tag)),
                      child: Icon(Icons.close_rounded,
                          size: 14, color: AppColors.primary),
                    ),
                  ]),
                );
              }),
            ]),
          ]),

          const SizedBox(height: 20),
          Row(children: [
            _sectionLabel('AKSI / KODE SCRIPT', isDark),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF27272A) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: isDark
                          ? const Color(0xFF3F3F46)
                          : const Color(0xFFE4E4E7))),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _scriptLang,
                  isDense: true,
                  dropdownColor: isDark ? const Color(0xFF27272A) : Colors.white,
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                      color: isDark ? Colors.white70 : const Color(0xFF52525B)),
                  items: const [
                    DropdownMenuItem(value: 'dsl',    child: Text('DSL')),
                    DropdownMenuItem(value: 'js',     child: Text('JavaScript')),
                    DropdownMenuItem(value: 'jython', child: Text('Jython')),
                    DropdownMenuItem(value: 'groovy', child: Text('Groovy')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                      _scriptLang = v;
                      if (_scriptTemplates.values.any((t) =>
                          _scriptCtrl.text.trim() == t.trim())) {
                        _scriptCtrl.text = _scriptTemplates[v] ?? '';
                      }
                    });
                    }
                  },
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12, offset: const Offset(0, 4))],
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(_scriptLang.toUpperCase(),
                        style: const TextStyle(fontFamily: 'Courier',
                            fontSize: 11, color: Color(0xFF6366F1),
                            fontWeight: FontWeight.w600)),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(
                        () => _scriptCtrl.text = _scriptTemplates[_scriptLang] ?? ''),
                    child: const Text('Reset',
                        style: TextStyle(fontFamily: 'Inter',
                            fontSize: 11, color: Color(0xFF6C7086))),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => _scriptCtrl.clear(),
                    child: const Text('Clear',
                        style: TextStyle(fontFamily: 'Inter',
                            fontSize: 11, color: Color(0xFF6C7086))),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFF313244)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _LineNumbers(controller: _scriptCtrl),
                  Expanded(
                    child: TextField(
                      controller: _scriptCtrl,
                      maxLines: null,
                      minLines: 8,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(fontFamily: 'Courier',
                          fontSize: 13, color: Color(0xFFCDD6F4), height: 1.6),
                      decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.fromLTRB(4, 12, 16, 20)),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ]),
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
              const Icon(Icons.info_outline_rounded,
                  size: 15, color: Color(0xFF6366F1)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Schedule akan disimpan sebagai Rule openHAB dengan '
                  'time-based trigger. Anda bisa menambahkan trigger '
                  'tambahan dan kondisi melalui UI openHAB.',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12,
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
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.save_rounded, size: 18, color: Colors.white),
                      const SizedBox(width: 10),
                      const Text('Simpan Schedule ke openHAB',
                          style: TextStyle(fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 15, color: Colors.white)),
                    ]),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCronConfig(bool isDark) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _fieldLabel('Preset Jadwal', isDark),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _cronCtrl.text.isEmpty ? 'custom' :
                (_cronPresets.containsKey(_cronCtrl.text) ? _cronCtrl.text : 'custom'),
            isExpanded: true,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            dropdownColor: isDark ? const Color(0xFF27272A) : Colors.white,
            style: TextStyle(fontFamily: 'Inter', fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF18181B)),
            borderRadius: BorderRadius.circular(14),
            items: _cronPresets.entries.map((e) => DropdownMenuItem(
              value: e.key, child: Text(e.value),
            )).toList(),
            onChanged: (v) {
              if (v != null && v != 'custom') {
                setState(() => _cronCtrl.text = v);
              }
            },
          ),
        ),
      ),
      const SizedBox(height: 16),
      Row(children: [
        _fieldLabel('Cron Expression', isDark),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _showCronHelp,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.help_outline_rounded, size: 12, color: Color(0xFF6366F1)),
              SizedBox(width: 4),
              Text('Bantuan', style: TextStyle(fontFamily: 'Inter',
                  fontSize: 11, color: Color(0xFF6366F1))),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      TextField(
        controller: _cronCtrl,
        style: TextStyle(fontFamily: 'Courier', fontSize: 14,
            color: isDark ? Colors.white : const Color(0xFF18181B)),
        decoration: InputDecoration(
          hintText: '0 0 8 * * ?',
          hintStyle: TextStyle(fontFamily: 'Courier',
              color: isDark ? Colors.white38 : Colors.grey.shade400,
              fontSize: 14),
          filled: true,
          fillColor: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          prefixIcon: Center(widthFactor: 1,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Icon(Icons.schedule_rounded, size: 16,
                      color: isDark ? Colors.white38 : Colors.grey.shade500))),
        ),
        onChanged: (_) => setState(() {}),
      ),
      if (_cronCtrl.text.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, size: 13, color: Color(0xFF6366F1)),
            const SizedBox(width: 8),
            Expanded(child: Text(OHSchedule._cronHuman(_cronCtrl.text),
                style: const TextStyle(fontFamily: 'Inter',
                    fontSize: 12, color: Color(0xFF6366F1)))),
          ]),
        ),
      ],
    ]);
  }

  Widget _buildTimeConfig(bool isDark) {
    const days = [
      {'key': 1, 'label': 'Sen'}, {'key': 2, 'label': 'Sel'},
      {'key': 3, 'label': 'Rab'}, {'key': 4, 'label': 'Kam'},
      {'key': 5, 'label': 'Jum'}, {'key': 6, 'label': 'Sab'},
      {'key': 7, 'label': 'Min'},
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _fieldLabel('Jam Eksekusi', isDark),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: _pickTriggerTime,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
              color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7),
              borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(Icons.access_time_rounded, size: 18,
                color: isDark ? Colors.white38 : Colors.grey.shade500),
            const SizedBox(width: 12),
            Text(
              '${_timeOfDay.hour.toString().padLeft(2,'0')}:${_timeOfDay.minute.toString().padLeft(2,'0')}',
              style: TextStyle(fontFamily: 'Inter',
                  fontWeight: FontWeight.w600, fontSize: 22,
                  color: isDark ? Colors.white : const Color(0xFF18181B)),
            ),
            const Spacer(),
            Icon(Icons.edit_rounded, size: 16,
                color: isDark ? Colors.white38 : const Color(0xFF71717A)),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      _fieldLabel('Hari', isDark),
      const SizedBox(height: 10),
      Row(
        children: days.map((d) {
          final key = d['key']! as int;
          final isSelected = _selectedDays.contains(key);
          return Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedDays.remove(key);
                  } else {
                    _selectedDays.add(key);
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7)),
                    borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text(d['label']! as String,
                    style: TextStyle(fontFamily: 'Inter',
                        fontWeight: FontWeight.w600, fontSize: 11,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white54 : const Color(0xFF71717A))))),
              ),
            ),
          ));
        }).toList(),
      ),
    ]);
  }

  Widget _buildItemConfig(bool isDark) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _fieldLabel('Nama Item openHAB', isDark),
      const SizedBox(height: 8),
      _textField(controller: _itemNameCtrl,
          hint: 'contoh: LivingRoom_Light',
          icon: Icons.device_hub_rounded, isDark: isDark),
      const SizedBox(height: 16),
      _fieldLabel('State yang memicu (opsional)', isDark),
      const SizedBox(height: 8),
      _textField(controller: _itemStateCtrl,
          hint: 'contoh: ON, OFF, 100, ...',
          icon: Icons.compare_arrows_rounded, isDark: isDark),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.2))),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: 13, color: Color(0xFF10B981)),
          SizedBox(width: 8),
          Expanded(child: Text(
            'Trigger akan aktif ketika item berubah ke state yang ditentukan. '
            'Kosongkan state untuk trigger pada setiap perubahan.',
            style: TextStyle(fontFamily: 'Inter', fontSize: 11,
                color: Color(0xFF10B981), height: 1.4),
          )),
        ]),
      ),
    ]);
  }

  void _showCronHelp() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF27272A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7),
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text('Format Cron openHAB',
                style: TextStyle(fontFamily: 'Inter',
                    fontWeight: FontWeight.w700, fontSize: 16,
                    color: isDark ? Colors.white : const Color(0xFF18181B))),
            const SizedBox(height: 4),
            const Text('Seconds Minutes Hours Day Month DayOfWeek',
                style: TextStyle(fontFamily: 'Courier',
                    fontSize: 12, color: Color(0xFF6366F1))),
            const SizedBox(height: 16),
            ...[
              ['0 0 8 * * ?',         'Setiap hari jam 08:00'],
              ['0 30 7 * * MON-FRI',  'Senin–Jumat jam 07:30'],
              ['0 0/15 * * * ?',      'Setiap 15 menit'],
              ['0 0 * * * ?',         'Setiap jam tepat'],
              ['0 0 0 1 * ?',         'Tanggal 1 setiap bulan'],
              ['0 0 12 ? * SUN',      'Setiap Minggu jam 12:00'],
            ].map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Expanded(flex: 5, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFF1E1E2E),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(e[0], style: const TextStyle(fontFamily: 'Courier',
                      fontSize: 11, color: Color(0xFFCDD6F4))),
                )),
                const SizedBox(width: 12),
                Expanded(flex: 5, child: Text(e[1],
                    style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                        color: isDark ? Colors.white70 : const Color(0xFF52525B)))),
              ]),
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _triggerTypeBtn(String type, IconData icon, String label, String sub, bool isDark) {
    final isSelected = _triggerType == type;
    final color = triggerColor(type);
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _triggerType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.10)
              : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFF8F8FA)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isSelected
                  ? color
                  : (isDark ? const Color(0xFF52525B) : const Color(0xFFE4E4E7)),
              width: isSelected ? 1.5 : 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 22,
              color: isSelected
                  ? color
                  : (isDark ? Colors.white38 : const Color(0xFF94A3B8))),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Inter',
                  fontWeight: FontWeight.w600, fontSize: 11,
                  color: isSelected
                      ? color
                      : (isDark ? Colors.white54 : const Color(0xFF52525B)))),
        ]),
      ),
    ));
  }

  Widget _timePickerBtn({required String label, required TimeOfDay time,
      required VoidCallback onTap, required bool isDark}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7),
            borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 11,
              color: isDark ? Colors.white38 : const Color(0xFF71717A))),
          const SizedBox(height: 4),
          Text(
            '${time.hour.toString().padLeft(2,'0')}:${time.minute.toString().padLeft(2,'0')}',
            style: TextStyle(fontFamily: 'Inter',
                fontWeight: FontWeight.w700, fontSize: 18,
                color: AppColors.primary),
          ),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String label, bool isDark) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(label, style: TextStyle(fontFamily: 'Inter',
        fontWeight: FontWeight.w500, fontSize: 11,
        letterSpacing: 0.8,
        color: isDark ? Colors.white38 : const Color(0xFF9E9E9E))),
  );

  Widget _fieldLabel(String label, bool isDark) => Text(label,
      style: TextStyle(fontFamily: 'Inter',
          fontWeight: FontWeight.w600, fontSize: 13,
          color: isDark ? Colors.white54 : const Color(0xFF71717A)));

  Widget _card({required List<Widget> children, required bool isDark}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF27272A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isDark,
    int maxLines = 1,
  }) =>
      TextField(
        controller: controller,
        maxLines: maxLines,
        style: TextStyle(fontFamily: 'Inter', fontSize: 14,
            color: isDark ? Colors.white : const Color(0xFF18181B)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontFamily: 'Inter',
              color: isDark ? Colors.white38 : Colors.grey.shade400,
              fontSize: 13),
          filled: true,
          fillColor: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          prefixIcon: Center(widthFactor: 1,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Icon(icon, size: 16,
                      color: isDark ? Colors.white38 : const Color(0xFF71717A)))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );

  Widget _dot(Color color) => Container(
      width: 12, height: 12,
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
  void initState() { super.initState(); widget.controller.addListener(_rebuild); }
  @override
  void dispose() { widget.controller.removeListener(_rebuild); super.dispose(); }
  void _rebuild() { if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    final lines = (widget.controller.text.split('\n').length).clamp(8, 200);
    return Container(
      width: 40,
      padding: const EdgeInsets.only(top: 12, bottom: 20, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(lines, (i) => Text('${i + 1}',
            style: const TextStyle(fontFamily: 'Courier', fontSize: 13,
                color: Color(0xFF585B70), height: 1.6))),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _SummaryCard({required this.label, required this.count,
      required this.color, required this.icon});

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
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 32, height: 32,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Center(child: Icon(icon, size: 16, color: color))),
        const SizedBox(height: 10),
        Text('$count', style: TextStyle(fontFamily: 'Inter',
            fontWeight: FontWeight.w800, fontSize: 22, color: color)),
        Text(label,
            style: TextStyle(fontFamily: 'Inter', fontSize: 11,
                color: isDark ? Colors.white38 : const Color(0xFF71717A),
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final OHSchedule schedule;
  final bool isRunning;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRunNow;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ScheduleCard({required this.schedule, required this.isRunning,
      required this.onToggle, required this.onRunNow,
      required this.onTap, required this.onDelete});

  Color get _statusColor {
    if (!schedule.enabled) return const Color(0xFF94A3B8);
    switch (schedule.status) {
      case 'RUNNING': return const Color(0xFF3B82F6);
      case 'IDLE':    return const Color(0xFF22C55E);
      default:        return const Color(0xFFEF4444);
    }
  }

  String get _statusLabel {
    if (!schedule.enabled) return 'Nonaktif';
    switch (schedule.status) {
      case 'RUNNING': return 'Berjalan';
      case 'IDLE':    return 'Idle';
      default:        return schedule.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc     = triggerColor(schedule.triggerType);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              Row(children: [
                Container(width: 48, height: 48,
                    decoration: BoxDecoration(color: tc.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14)),
                    child: Center(child: Icon(triggerIcon(schedule.triggerType),
                        size: 22, color: tc))),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(schedule.label,
                        style: TextStyle(fontFamily: 'Inter',
                            fontWeight: FontWeight.w600, fontSize: 15,
                            color: isDark ? Colors.white : const Color(0xCC18181B)),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (schedule.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(schedule.description,
                          style: TextStyle(fontFamily: 'Inter', fontSize: 11,
                              color: isDark ? Colors.white38 : const Color(0xFF71717A)),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 6),
                    Row(children: [
                      _badge(_statusLabel, _statusColor),
                      const SizedBox(width: 6),
                      _badge(triggerLabel(schedule.triggerType), tc),
                      if (!schedule.isVisibleInOpenHABScheduleUI) ...[
                        const SizedBox(width: 6),
                        _badge('Belum sync', const Color(0xFFF59E0B)),
                      ],
                    ]),
                  ],
                )),
                Switch(value: schedule.enabled, onChanged: onToggle,
                    activeThumbColor: AppColors.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ]),

              if (schedule.triggerDisplay != '-') ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: tc.withValues(alpha: isDark ? 0.08 : 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tc.withValues(alpha: 0.18)),
                  ),
                  child: Row(children: [
                    Icon(Icons.schedule_rounded, size: 13, color: tc),
                    const SizedBox(width: 8),
                    Expanded(child: Text(schedule.triggerDisplay,
                        style: TextStyle(fontFamily: 'Inter',
                            fontWeight: FontWeight.w600, fontSize: 13,
                            color: tc))),
                  ]),
                ),
              ],

              const SizedBox(height: 12),
              Divider(height: 1,
                  color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF0F0F0)),
              const SizedBox(height: 12),

              Row(children: [
                Expanded(child: Text(schedule.uid,
                    style: TextStyle(fontFamily: 'Courier', fontSize: 10,
                        color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.delete_outline_rounded,
                        size: 14, color: Color(0xFFEF4444)),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: schedule.enabled ? onRunNow : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: schedule.enabled
                          ? (isRunning
                              ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
                              : AppColors.primary.withValues(alpha: 0.10))
                          : (isDark
                              ? const Color(0xFF3F3F46)
                              : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      isRunning
                          ? SizedBox(width: 10, height: 10,
                              child: CircularProgressIndicator(strokeWidth: 1.5,
                                  color: schedule.enabled
                                      ? AppColors.primary
                                      : (isDark ? Colors.white38 : Colors.grey)))
                          : Icon(Icons.play_arrow_rounded, size: 14,
                              color: schedule.enabled
                                  ? AppColors.primary
                                  : (isDark ? Colors.white38 : Colors.grey.shade400)),
                      const SizedBox(width: 4),
                      Text(isRunning ? 'Berjalan...' : 'Jalankan',
                          style: TextStyle(fontFamily: 'Inter',
                              fontWeight: FontWeight.w600, fontSize: 12,
                              color: schedule.enabled
                                  ? (isRunning
                                      ? const Color(0xFF3B82F6)
                                      : AppColors.primary)
                                  : (isDark ? Colors.white38 : Colors.grey.shade400))),
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

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(fontFamily: 'Inter',
        fontWeight: FontWeight.w600, fontSize: 10, color: color)),
  );
}


class _ScheduleDetailSheet extends StatelessWidget {
  final OHSchedule schedule;
  const _ScheduleDetailSheet({required this.schedule});

  Color get _statusColor {
    if (!schedule.enabled) return const Color(0xFF94A3B8);
    switch (schedule.status) {
      case 'RUNNING': return const Color(0xFF3B82F6);
      case 'IDLE':    return const Color(0xFF22C55E);
      default:        return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc     = triggerColor(schedule.triggerType);
    return DraggableScrollableSheet(
      initialChildSize: 0.72, minChildSize: 0.5, maxChildSize: 0.95,
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
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7),
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                Container(width: 52, height: 52,
                    decoration: BoxDecoration(color: tc.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16)),
                    child: Center(child: Icon(triggerIcon(schedule.triggerType),
                        size: 24, color: tc))),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(schedule.label,
                        style: TextStyle(fontFamily: 'Inter',
                            fontWeight: FontWeight.w700, fontSize: 17,
                            color: isDark ? Colors.white : const Color(0xCC18181B))),
                    const SizedBox(height: 6),
                    Row(children: [
                      _pill(schedule.enabled ? schedule.status : 'DISABLED',
                          _statusColor),
                      const SizedBox(width: 8),
                      _pill(triggerLabel(schedule.triggerType), tc),
                      if (!schedule.isVisibleInOpenHABScheduleUI) ...[
                        const SizedBox(width: 8),
                        _pill('Belum tampil di openHAB', const Color(0xFFF59E0B)),
                      ],
                    ]),
                  ],
                )),
              ]),
            ),

            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: tc.withValues(alpha: isDark ? 0.08 : 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: tc.withValues(alpha: 0.18))),
                child: Row(children: [
                  Container(width: 40, height: 40,
                      decoration: BoxDecoration(
                          color: tc.withValues(alpha: 0.14), shape: BoxShape.circle),
                      child: Center(child: Icon(Icons.schedule_rounded,
                          size: 18, color: tc))),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Jadwal Eksekusi',
                          style: TextStyle(fontFamily: 'Inter',
                              fontSize: 11, color: tc.withValues(alpha: 0.7))),
                      Text(schedule.triggerDisplay,
                          style: TextStyle(fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 15, color: tc)),
                    ],
                  )),
                ]),
              ),
            ),

            const SizedBox(height: 16),
            Divider(height: 1,
                color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7)),
            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(children: [
                _InfoRow(label: 'UID', value: schedule.uid, isDark: isDark),
                if (schedule.description.isNotEmpty)
                  _InfoRow(label: 'Deskripsi', value: schedule.description, isDark: isDark),
                _InfoRow(label: 'Status',
                    value: schedule.enabled ? 'Aktif' : 'Nonaktif', isDark: isDark),
                _InfoRow(label: 'Tipe Trigger',
                    value: triggerLabel(schedule.triggerType), isDark: isDark),
                _InfoRow(label: 'Tags',
                    value: schedule.tags.isEmpty ? '-' : schedule.tags.join(', '),
                    isDark: isDark),
                if (schedule.conditions.isNotEmpty)
                  _InfoRow(label: 'Kondisi',
                      value: '${schedule.conditions.length} kondisi aktif',
                      isDark: isDark),
              ]),
            ),

            if (schedule.triggers.isNotEmpty) ...[
              Divider(height: 1,
                  color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7)),
              const SizedBox(height: 16),
              _buildSection(context,
                  icon: Icons.bolt_rounded,
                  title: 'Triggers (${schedule.triggers.length})',
                  color: const Color(0xFFF59E0B),
                  items: schedule.triggers, isDark: isDark),
            ],

            if (schedule.actions.isNotEmpty) ...[
              Divider(height: 1,
                  color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7)),
              const SizedBox(height: 16),
              _buildSection(context,
                  icon: Icons.play_circle_rounded,
                  title: 'Actions (${schedule.actions.length})',
                  color: const Color(0xFF22C55E),
                  items: schedule.actions, isDark: isDark),
            ],

            if (schedule.conditions.isNotEmpty) ...[
              Divider(height: 1,
                  color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7)),
              const SizedBox(height: 16),
              _buildSection(context,
                  icon: Icons.filter_alt_rounded,
                  title: 'Conditions (${schedule.conditions.length})',
                  color: const Color(0xFF6366F1),
                  items: schedule.conditions, isDark: isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(fontFamily: 'Inter',
        fontWeight: FontWeight.w700, fontSize: 11, color: color)),
  );

  Widget _buildSection(BuildContext context, {
    required IconData icon, required String title,
    required Color color, required List<Map<String, dynamic>> items,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(fontFamily: 'Inter',
              fontWeight: FontWeight.w700, fontSize: 13, color: color)),
        ]),
        const SizedBox(height: 10),
        ...items.map((item) {
          final type       = item['type'] as String? ?? '-';
          final id         = item['id']   as String? ?? '';
          final cfg        = item['configuration'] as Map<String, dynamic>? ?? {};
          final cfgPreview = cfg.entries.take(2)
              .map((e) => '${e.key}: ${e.value}').join(', ');
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.08 : 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.15))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(type, style: TextStyle(fontFamily: 'Inter',
                  fontWeight: FontWeight.w600, fontSize: 12, color: color)),
              if (id.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('ID: $id', style: TextStyle(fontFamily: 'Inter',
                    fontSize: 11,
                    color: isDark ? Colors.white38 : const Color(0xFF71717A))),
              ],
              if (cfgPreview.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(cfgPreview, style: TextStyle(fontFamily: 'Inter',
                    fontSize: 11,
                    color: isDark ? Colors.white38 : const Color(0xFF71717A)),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
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

  const _InfoRow({required this.label, required this.value, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 100,
            child: Text(label,
                style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                    color: isDark ? Colors.white38 : const Color(0xFF71717A),
                    fontWeight: FontWeight.w500))),
        Expanded(child: Text(value,
            style: TextStyle(fontFamily: 'Inter', fontSize: 13,
                color: isDark ? Colors.white70 : const Color(0xCC18181B),
                fontWeight: FontWeight.w500))),
      ]),
    );
  }
}