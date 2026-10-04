import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/controllers/openhab_controller.dart';
import 'package:mobile/core/providers/installation_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppNotifType { inbox, thingIssue, alarm, stateChange, info }

class AppNotif {
  final String id;
  final AppNotifType type;
  final String title;
  final String subtitle;
  final DateTime time;
  final String? thingUID;
  bool isRead;

  AppNotif({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.time,
    this.thingUID,
    this.isRead = false,
  });

  bool get isCritical =>
      type == AppNotifType.thingIssue || type == AppNotifType.alarm;

  IconData get icon {
    switch (type) {
      case AppNotifType.inbox:       return Icons.add_circle_outline_rounded;
      case AppNotifType.thingIssue:  return Icons.warning_amber_rounded;
      case AppNotifType.alarm:       return Icons.notifications_active_rounded;
      case AppNotifType.stateChange: return Icons.bolt_rounded;
      case AppNotifType.info:        return Icons.info_outline_rounded;
    }
  }

  Color get iconBg {
    switch (type) {
      case AppNotifType.inbox:       return const Color(0xFF3B82F6);
      case AppNotifType.thingIssue:  return const Color(0xFFEF4444);
      case AppNotifType.alarm:       return const Color(0xFFDC2626);
      case AppNotifType.stateChange: return const Color(0xFFFFA500);
      case AppNotifType.info:        return const Color(0xFF34A853);
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'subtitle': subtitle,
        'time': time.toIso8601String(),
        'thingUID': thingUID,
        'isRead': isRead,
      };

  factory AppNotif.fromJson(Map<String, dynamic> j) => AppNotif(
        id: j['id'] as String,
        type: AppNotifType.values.byName(j['type'] as String),
        title: j['title'] as String,
        subtitle: j['subtitle'] as String,
        time: DateTime.parse(j['time'] as String),
        thingUID: j['thingUID'] as String?,
        isRead: j['isRead'] as bool? ?? false,
      );
}

class _ThingInfo {
  final String label;
  final String? location;
  const _ThingInfo(this.label, this.location);
}

/// Service notifikasi global. Panggil [startFromContext] sekali setelah
/// login/terhubung ke openHAB (mis. di initState HomePage).
class AppNotificationService extends ChangeNotifier
    with WidgetsBindingObserver {
  AppNotificationService._();
  static final AppNotificationService instance = AppNotificationService._();

  /// Pasang di MaterialApp: scaffoldMessengerKey: AppNotificationService.messengerKey
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// Dipanggil saat banner "Lihat" atau notifikasi sistem diketuk.
  VoidCallback? onOpen;

  // ── Pengaturan (tersimpan) ────────────────────────────────────────────────
  bool enabled = true;
  bool notifyOffline = true;
  bool notifyAlarm = true;
  bool notifyInbox = true;
  bool notifyStateChange = false; // default mati: terlalu berisik

  /// Nama item → batas maksimum. Notifikasi sekali saat nilai melewati batas.
  final Map<String, double> maxThresholds = {};

  /// Item yang namanya cocok + bernilai ON/OPEN/ALARM dianggap alarm aktif.
  RegExp alarmPattern = RegExp(
    r'(alarm|smoke|fire|gas|leak|flood|intrusion|siren)',
    caseSensitive: false,
  );

  // ── State ─────────────────────────────────────────────────────────────────
  final List<AppNotif> items = [];
  final Set<String> _seen = {};
  final Set<String> _active = {}; // kondisi bermasalah yang sudah diberitahukan
  final Map<String, _ThingInfo> _things = {};
  final Map<String, DateTime> _lastStateNotif = {};
  final List<AppNotif> _pendingAlerts = [];

  bool _started = false;
  bool ready = false;
  bool _firstRun = false;

  String? Function() _serverUrl = () => null;
  Future<Map<String, String>> Function() _headers = () async => {};

  final _plugin = FlutterLocalNotificationsPlugin();
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  Timer? _pollTimer;
  Timer? _saveTimer;
  Timer? _reconnectTimer;
  http.Client? _sseClient;
  StreamSubscription<String>? _sseSub;
  int _retry = 0;
  String _dataBuf = '';

  int get unreadCount => items.where((n) => !n.isRead).length;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  static Map<String, String> buildHeaders(dynamic config) {
    final token = config?.apiToken as String?;
    final user = config?.username as String?;
    final pass = config?.password as String?;
    final h = <String, String>{'Accept': 'application/json'};
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    } else if (user != null && pass != null) {
      h['Authorization'] =
          'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
    }
    return h;
  }

  Future<void> startFromContext(BuildContext context) async {
    final provider = context.read<InstallationProvider>();
    final ctrl = OpenHABController.instance;
    if (!ctrl.isConnected) return;
    await start(
      serverUrl: () => ctrl.serverUrl,
      headers: () async => buildHeaders(provider.config),
    );
  }

  Future<void> start({
    required String? Function() serverUrl,
    required Future<Map<String, String>> Function() headers,
  }) async {
    _serverUrl = serverUrl;
    _headers = headers;
    if (_started) return;
    _started = true;

    WidgetsBinding.instance.addObserver(this);
    await _loadPrefs();
    await _initLocalNotifications();
    await _poll();
    _firstRun = false;
    _connectSSE();
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) => _poll());
    ready = true;
    notifyListeners();
  }

  /// Panggil saat logout.
  Future<void> stop({bool clearHistory = false}) async {
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    await _closeSSE();
    WidgetsBinding.instance.removeObserver(this);
    _started = false;
    ready = false;
    if (clearHistory) {
      items.clear();
      _seen.clear();
      _active.clear();
      await _savePrefsNow();
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
     _log('lifecycle -> $state');   
    if (state == AppLifecycleState.resumed && _started) {
      // Kejar kejadian yang terlewat saat app di latar belakang.
      _poll();
      _connectSSE();
    }
  }

  Future<void> refresh() => _poll();

  // ── Aksi dari UI ──────────────────────────────────────────────────────────
  void markRead(AppNotif n) {
    if (n.isRead) return;
    n.isRead = true;
    _changed();
  }

  void markAllRead() {
    for (final n in items) {
      n.isRead = true;
    }
    _changed();
  }

  void removeByIds(Set<String> ids) {
    items.removeWhere((n) => ids.contains(n.id));
    _changed();
  }

  Future<void> saveSettings() => _savePrefsNow();

  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _savePrefsNow);
  }

  // ── Persistensi ───────────────────────────────────────────────────────────
  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('notif_items');
      if (raw != null) {
        items
          ..clear()
          ..addAll((jsonDecode(raw) as List)
              .map((e) => AppNotif.fromJson(e as Map<String, dynamic>)));
      }
      _seen.addAll(p.getStringList('notif_seen') ?? const []);
      _active.addAll(p.getStringList('notif_active') ?? const []);
      _firstRun = _seen.isEmpty && items.isEmpty;

      final s = p.getString('notif_settings');
      if (s != null) {
        final m = jsonDecode(s) as Map<String, dynamic>;
        enabled = m['enabled'] as bool? ?? enabled;
        notifyOffline = m['offline'] as bool? ?? notifyOffline;
        notifyAlarm = m['alarm'] as bool? ?? notifyAlarm;
        notifyInbox = m['inbox'] as bool? ?? notifyInbox;
        notifyStateChange = m['state'] as bool? ?? notifyStateChange;
        final t = m['thresholds'] as Map<String, dynamic>?;
        if (t != null) {
          maxThresholds
            ..clear()
            ..addAll(t.map((k, v) => MapEntry(k, (v as num).toDouble())));
        }
      }
    } catch (e) {
      _log('load prefs gagal: $e');
    }
  }

  Future<void> _savePrefsNow() async {
    try {
      final p = await SharedPreferences.getInstance();
      while (_seen.length > 500) {
        _seen.remove(_seen.first);
      }
      await p.setString(
          'notif_items', jsonEncode(items.map((e) => e.toJson()).toList()));
      await p.setStringList('notif_seen', _seen.toList());
      await p.setStringList('notif_active', _active.toList());
      await p.setString(
        'notif_settings',
        jsonEncode({
          'enabled': enabled,
          'offline': notifyOffline,
          'alarm': notifyAlarm,
          'inbox': notifyInbox,
          'state': notifyStateChange,
          'thresholds': maxThresholds,
        }),
      );
    } catch (e) {
      _log('save prefs gagal: $e');
    }
  }

  // ── Polling ───────────────────────────────────────────────────────────────
  Future<http.Response?> _get(String path) async {
    final base = _serverUrl();
    if (base == null || base.isEmpty) return null;
    try {
      final res = await http
          .get(Uri.parse('$base$path'), headers: await _headers())
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200 ? res : null;
    } catch (e) {
      _log('GET $path gagal: $e');
      return null;
    }
  }

  Future<void> _poll() async {
    await _pollThings();
    await _pollInbox();
    _flushAlerts();
    _changed();
  }

  Future<void> _pollThings() async {
    final res = await _get('/rest/things?summary=true');
    if (res == null) return;
    try {
      final list = jsonDecode(res.body) as List;
      final problemUids = <String>{};
      for (final e in list) {
        final uid = e['UID'] as String? ?? '';
        if (uid.isEmpty) continue;
        final label = e['label'] as String? ?? uid;
        _things[uid] = _ThingInfo(label, e['location'] as String?);

        final status =
            (e['statusInfo']?['status'] as String? ?? '').toUpperCase();
        if (status == 'OFFLINE' || status == 'ERROR') {
          problemUids.add(uid);
          _raiseThingIssue(
              uid, status, e['statusInfo']?['description'] as String?);
        }
      }
      // Perangkat yang sudah pulih: izinkan notifikasi lagi jika bermasalah.
      _active.removeWhere((k) =>
          k.startsWith('thing|') && !problemUids.contains(k.split('|')[1]));
    } catch (e) {
      _log('parse things gagal: $e');
    }
  }

  Future<void> _pollInbox() async {
    final res = await _get('/rest/inbox');
    if (res == null) return;
    try {
      for (final e in jsonDecode(res.body) as List) {
        final uid = e['thingUID'] as String? ?? '';
        _raiseInbox(uid, e['label'] as String? ?? uid,
            e['flag'] as String? ?? '');
      }
    } catch (e) {
      _log('parse inbox gagal: $e');
    }
  }

  // ── Pemicu notifikasi ─────────────────────────────────────────────────────
  void _raiseThingIssue(String uid, String status, String? detail) {
    if (!_active.add('thing|$uid|$status')) return; // sudah diberitahu
    final info = _things[uid];
    final label = info?.label ?? uid;
    final loc = (info?.location?.isNotEmpty ?? false) ? ' · ${info!.location}' : '';
    final desc = (detail == null || detail.isEmpty) ? status : detail;
    _add(
      AppNotif(
        id: 'thing|$uid|$status|${DateTime.now().millisecondsSinceEpoch}',
        type: AppNotifType.thingIssue,
        title: status == 'OFFLINE' ? 'Perangkat Offline' : 'Error Perangkat',
        subtitle: '$label$loc — $desc',
        time: DateTime.now(),
        thingUID: uid,
      ),
      alert: notifyOffline,
    );
  }

  void _raiseInbox(String uid, String label, String flag) {
    final key = 'inbox|$uid';
    if (uid.isEmpty || !_seen.add(key)) return;
    _add(
      AppNotif(
        id: '$key|${DateTime.now().millisecondsSinceEpoch}',
        type: AppNotifType.inbox,
        title: 'Perangkat Baru Terdeteksi',
        subtitle: '$label${flag.isNotEmpty ? ' · $flag' : ''}',
        time: DateTime.now(),
        thingUID: uid,
      ),
      // Saat pertama kali dipasang, jangan banjiri pengguna dengan inbox lama.
      alert: notifyInbox && !_firstRun,
    );
  }

  void _raiseItemState(String name, String value) {
    final v = value.toUpperCase();
    final label = _labelFromItemName(name);
    final isOn = v == 'ON' || v == 'OPEN' || v == 'ALARM' || v == 'TRUE';
    final isOff = v == 'OFF' || v == 'CLOSED' || v == 'NULL' || v == 'FALSE';
    final num = double.tryParse(
        RegExp(r'^-?\d+(\.\d+)?').stringMatch(value) ?? '');

    // 1) Alarm aktif
    if (alarmPattern.hasMatch(name)) {
      final key = 'alarm|$name';
      if (isOn) {
        if (_active.add(key)) {
          _add(
            AppNotif(
              id: '$key|${DateTime.now().millisecondsSinceEpoch}',
              type: AppNotifType.alarm,
              title: 'Alarm Aktif',
              subtitle: '$label — status $value',
              time: DateTime.now(),
            ),
            alert: notifyAlarm,
          );
        }
      } else if (isOff) {
        _active.remove(key);
      }
    }

    // 2) Nilai melewati batas
    final max = maxThresholds[name];
    if (max != null && num != null) {
      final key = 'thr|$name';
      if (num > max) {
        if (_active.add(key)) {
          _add(
            AppNotif(
              id: '$key|${DateTime.now().millisecondsSinceEpoch}',
              type: AppNotifType.alarm,
              title: 'Melewati Batas',
              subtitle: '$label bernilai $value (batas $max)',
              time: DateTime.now(),
            ),
            alert: notifyAlarm,
          );
        }
      } else {
        _active.remove(key);
      }
    }

    // 3) Perubahan status biasa (opsional, dibatasi 1x / 30 detik per item)
    if (notifyStateChange && (isOn || isOff)) {
      final last = _lastStateNotif[name];
      if (last == null ||
          DateTime.now().difference(last) > const Duration(seconds: 30)) {
        _lastStateNotif[name] = DateTime.now();
        _add(
          AppNotif(
            id: 'state|$name|${DateTime.now().millisecondsSinceEpoch}',
            type: AppNotifType.stateChange,
            title: label,
            subtitle: '$label berubah ke $value.',
            time: DateTime.now(),
          ),
          alert: false,
        );
      }
    }
  }

  String _labelFromItemName(String name) => name
      .replaceAll('_', ' ')
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .trim();

  void _add(AppNotif n, {required bool alert}) {
    items.insert(0, n);
    if (items.length > 100) items.removeLast();
    if (alert && enabled) _pendingAlerts.add(n);
  }

  // ── SSE ───────────────────────────────────────────────────────────────────
  Future<void> _closeSSE() async {
    await _sseSub?.cancel();
    _sseSub = null;
    _sseClient?.close();
    _sseClient = null;
    _dataBuf = '';
  }

  Future<void> _connectSSE() async {
    _reconnectTimer?.cancel();
    await _closeSSE();
    final base = _serverUrl();
    if (base == null || base.isEmpty) return;

    final client = http.Client();
    _sseClient = client;
    try {
      final uri = Uri.parse(
        '$base/rest/events'
        '?topics=openhab/items/*/statechanged'
        ',openhab/things/*/statuschanged'
        ',openhab/inbox/*',
      );
      final req = http.Request('GET', uri)..headers.addAll(await _headers());
      final resp = await client.send(req);
      _retry = 0;
      _sseSub = resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onSSELine,
            onError: (_) => _scheduleReconnect(),
            onDone: _scheduleReconnect,
            cancelOnError: true,
          );
    } catch (e) {
      _log('SSE gagal: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_started) return;
    _reconnectTimer?.cancel();
    final secs = (5 * (1 << _retry.clamp(0, 4))).clamp(5, 60); // 5..60 dtk
    _retry++;
    _reconnectTimer = Timer(Duration(seconds: secs), _connectSSE);
  }

  void _onSSELine(String line) {
    if (line.startsWith('data:')) {
      _dataBuf += line.substring(5).trim();
    } else if (line.isEmpty && _dataBuf.isNotEmpty) {
      final raw = _dataBuf;
      _dataBuf = '';
      _onSSEEvent(raw);
    }
  }

  void _onSSEEvent(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final topic = json['topic'] as String? ?? '';
      final type = json['type'] as String? ?? '';
      final parts = topic.split('/');

      if (type == 'ItemStateChangedEvent') {
        final payload = jsonDecode(json['payload'] as String) as Map;
        final name = parts.length > 2 ? parts[2] : '';
        if (name.isEmpty) return;
        _raiseItemState(name, payload['value']?.toString() ?? '');
      } else if (type == 'ThingStatusInfoChangedEvent') {
        final payload = jsonDecode(json['payload'] as String) as List;
        final uid = parts.length > 2 ? parts[2] : '';
        final info = payload.isNotEmpty ? payload[0] as Map : const {};
        final status = (info['status'] as String? ?? '').toUpperCase();
        if (status == 'OFFLINE' || status == 'ERROR') {
          _raiseThingIssue(uid, status, info['description'] as String?);
        } else if (status == 'ONLINE') {
          _active.removeWhere((k) => k.startsWith('thing|$uid|'));
        }
      } else if (type == 'InboxAddedEvent') {
        final payload = jsonDecode(json['payload'] as String) as Map;
        final uid = payload['thingUID'] as String? ?? '';
        _raiseInbox(uid, payload['label'] as String? ?? uid, '');
      } else {
        return;
      }
      _flushAlerts();
      _changed();
    } catch (e) {
      _log('parse event gagal: $e');
    }
  }

  // ── Tampilan: banner (foreground) / notifikasi sistem (background) ───────
  Future<void> _initLocalNotifications() async {
    try {
      // initialize (sekitar baris 585)
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (_) => onOpen?.call(),
    );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      _log('init notifikasi lokal gagal: $e');
    }
  }

  void _flushAlerts() {
    if (_pendingAlerts.isEmpty) return;
    final list = List<AppNotif>.of(_pendingAlerts);
    _pendingAlerts.clear();

    if (list.length > 3) {
      // Ringkas agar tidak membanjiri pengguna.
      _surface(
        AppNotif(
          id: 'summary|${DateTime.now().millisecondsSinceEpoch}',
          type: list.any((n) => n.isCritical)
              ? AppNotifType.thingIssue
              : AppNotifType.info,
          title: '${list.length} notifikasi baru',
          subtitle: list.take(3).map((n) => n.title).toSet().join(', '),
          time: DateTime.now(),
        ),
      );
    } else {
      for (final n in list) {
        _surface(n);
      }
    }
  }

  void _surface(AppNotif n) {
     _log('surface: lifecycle=$_lifecycle started=$_started');
    if (_lifecycle == AppLifecycleState.resumed) {
      _showBanner(n);
    } else {
      _showSystem(n);
    }
  }

  void _showBanner(AppNotif n) {
    final m = messengerKey.currentState;
    if (m == null) return;
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: n.iconBg,
          duration: const Duration(seconds: 6),
          content: Row(
            children: [
              Icon(n.icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.title,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                    Text(n.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
          action: onOpen == null
              ? null
              : SnackBarAction(
                  label: 'Lihat',
                  textColor: Colors.white,
                  onPressed: onOpen!,
                ),
        ),
      );
  }

  Future<void> _showSystem(AppNotif n) async {
    final t = n.time;
    final hhmm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final body = '${n.subtitle}\n$hhmm';
    final critical = n.isCritical;
    try {
      await _plugin.show(
      id: n.id.hashCode & 0x7fffffff,
      title: n.title,
      body: body,
      notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            critical ? 'critical' : 'info',
            critical ? 'Peringatan penting' : 'Informasi',
            importance: critical ? Importance.high : Importance.defaultImportance,
            priority: critical ? Priority.high : Priority.defaultPriority,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
        payload: 'notifications',
      );
    } catch (e) {
      _log('tampilkan notifikasi sistem gagal: $e');
    }
  }

  void _log(String m) {
    if (kDebugMode) debugPrint('[Notif] $m');
  }
}
