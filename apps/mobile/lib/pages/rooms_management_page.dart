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

class OHRoom {
  final String name;
  final String label;
  final String type;
  final List<String> tags;
  final List<String> groupNames;
  final List<OHRoomMember> members;
  final String category;

  const OHRoom({
    required this.name,
    required this.label,
    required this.type,
    required this.tags,
    required this.groupNames,
    required this.members,
    required this.category,
  });

  factory OHRoom.fromJson(Map<String, dynamic> json) {
    final members = (json['members'] as List? ?? [])
        .map((m) => OHRoomMember.fromJson(m as Map<String, dynamic>))
        .toList();

    final tags = List<String>.from(json['tags'] as List? ?? []);
    final category = json['category'] as String? ?? '';

    return OHRoom(
      name: json['name'] as String? ?? '',
      label: json['label'] as String? ?? json['name'] as String? ?? '-',
      type: json['type'] as String? ?? 'Group',
      tags: tags,
      groupNames: List<String>.from(json['groupNames'] as List? ?? []),
      members: members,
      category: category,
    );
  }
  String get locationType {
    for (final tag in tags) {
      final t = tag.toLowerCase();
      if (t.contains('livingroom'))    return 'livingroom';
      if (t.contains('bedroom'))       return 'bedroom';
      if (t.contains('kitchen'))       return 'kitchen';
      if (t.contains('bathroom'))      return 'bathroom';
      if (t.contains('garage'))        return 'garage';
      if (t.contains('garden'))        return 'garden';
      if (t.contains('corridor'))      return 'corridor';
      if (t.contains('office'))        return 'office';
      if (t.contains('cellar') || t.contains('basement')) return 'cellar';
      if (t.contains('terrace') || t.contains('balcony')) return 'terrace';
      if (t.contains('groundfloor') || t.contains('floor')) return 'floor';
      if (t.contains('indoor'))        return 'indoor';
      if (t.contains('outdoor'))       return 'outdoor';
      if (t.contains('building'))      return 'building';
    }
    return 'room';
  }

  List<OHRoomMember> get equipmentMembers =>
      members.where((m) => m.isEquipment).toList();

  List<OHRoomMember> get pointMembers =>
      members.where((m) => m.isPoint).toList();

  List<OHRoomMember> get allPoints {
    final result = <OHRoomMember>[...pointMembers];
    for (final e in equipmentMembers) {
      result.addAll(e.allPoints);
    }
    return result;
  }

  int get itemCount => allPoints.length;
  int get equipmentCount => equipmentMembers.length;
  String? get parentLocation =>
      groupNames.isNotEmpty ? groupNames.first : null;
}

class OHRoomMember {
  final String name;
  final String label;
  final String type;
  final String state;
  final List<String> tags;
  final String category;
  final List<String> groupNames;
  final List<OHRoomMember> members;

  const OHRoomMember({
    required this.name,
    required this.label,
    required this.type,
    required this.state,
    required this.tags,
    required this.category,
    this.groupNames = const [],
    this.members = const [],
  });

  factory OHRoomMember.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'] as List? ?? [];
    return OHRoomMember(
      name: json['name'] as String? ?? '',
      label: json['label'] as String? ?? json['name'] as String? ?? '-',
      type: json['type'] as String? ?? '',
      state: json['state'] as String? ?? 'NULL',
      tags: List<String>.from(json['tags'] as List? ?? []),
      category: json['category'] as String? ?? '',
      groupNames: List<String>.from(json['groupNames'] as List? ?? []),
      members: rawMembers
          .map((m) => OHRoomMember.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }

  bool get isControllable =>
      type == 'Switch' || type == 'Dimmer' || type == 'Color' ||
      type == 'Rollershutter' || type == 'Player';

  bool get isOn => state == 'ON';

  bool get isEquipment => type == 'Group';

  bool get isPoint => !isEquipment;

  String get equipmentTypeLabel {
    for (final tag in tags) {
      final t = tag.toLowerCase();
      if (tag.isNotEmpty && !t.contains('location') && !t.contains('point')) {
        return tag;
      }
    }
    return type;
  }

  List<OHRoomMember> get allPoints {
    final result = <OHRoomMember>[];
    for (final m in members) {
      if (m.isEquipment) {
        result.addAll(m.allPoints);
      } else {
        result.add(m);
      }
    }
    return result;
  }

  String? get semanticPointType {
    for (final t in tags) {
      if (_pointTypeTags.contains(t)) return t;
    }
    return null;
  }

  String? get semanticProperty {
    for (final t in tags) {
      if (_propertyTags.contains(t)) return t;
    }
    return null;
  }

  List<String> get nonSemanticTags => tags
      .where((t) => !_pointTypeTags.contains(t) && !_propertyTags.contains(t))
      .toList();

  static const _pointTypeTags = {
    'Alarm', 'Control', 'Measurement', 'Setpoint', 'Status', 'Switch', 'Tilt',
  };

  static const _propertyTags = {
    'Energy', 'Power', 'Voltage', 'Current', 'Frequency', 'PowerFactor',
    'Temperature', 'Humidity', 'Light', 'Illuminance', 'Presence', 'Smoke',
    'Water', 'Gas', 'CO2', 'CO', 'Noise', 'Rain', 'Wind', 'Pressure',
    'Brightness', 'Color', 'ColorTemperature', 'Duration', 'Level',
    'Opening', 'Timestamp', 'Ultraviolet', 'Vibration', 'Airflow',
    'App', 'Enthalpy', 'Heating', 'InfraredIntensity', 'Neighborhood',
    'Ozone', 'Precipitation', 'RadonConcentration', 'SmokeConcentration',
    'SoundVolume', 'Speed', 'Ultrasound',
  };
}

class RoomsService {
  final String baseUrl;
  final Map<String, String> headers;

  RoomsService({required this.baseUrl, required this.headers});

  Uri _uri(String path) => Uri.parse('$baseUrl/rest$path');

  Future<List<OHRoom>> getRooms() async {
    final res = await http.get(
      _uri('/items?type=Group&metadata=semantics&recursive=true&fields=name,label,type,tags,groupNames,category,members,state'),
      headers: headers,
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final list = jsonDecode(res.body) as List;

    return list
        .map((e) => OHRoom.fromJson(e as Map<String, dynamic>))
        .where(_isLocationGroup)
        .toList();
  }

  bool _isLocationGroup(OHRoom room) {
    return room.tags.any((tag) {
      final t = tag.toLowerCase();
      return t.contains('location') || t.contains('room') ||
          t.contains('floor') || t.contains('building') ||
          t.contains('indoor') || t.contains('outdoor') ||
          t.contains('corridor') || t.contains('garage') ||
          t.contains('garden') || t.contains('terrace') ||
          t.contains('office') || t.contains('cellar') ||
          t.contains('bedroom') || t.contains('kitchen') ||
          t.contains('bathroom') || t.contains('livingroom');
    });
  }
  Future<OHRoom> createRoom({
    required String name,
    required String label,
    required String locationType,
    required String? parentGroup,
    required String category,
  }) async {
    final tag = _semanticTag(locationType);
    final payload = <String, dynamic>{
      'name': name,
      'label': label,
      'type': 'Group',
      'category': category.isNotEmpty ? category : _defaultCategory(locationType),
      'tags': [tag],
      if (parentGroup != null && parentGroup.isNotEmpty)
        'groupNames': [parentGroup],
    };

    final res = await http.put(
        _uri('/items/$name'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode != 200 && res.statusCode != 201 && res.statusCode != 204) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    return OHRoom(
      name: name, label: label, type: 'Group',
      tags: [tag], groupNames: parentGroup != null ? [parentGroup] : [],
      members: [], category: category,
    );
  }

  Future<void> updateRoom({
    required String name,
    required String label,
    required String locationType,
    required String? parentGroup,
    required String category,
    required List<String> existingTags,
  }) async {
    final tag = _semanticTag(locationType);
    final tags = [
      tag,
      ...existingTags.where((t) => !t.toLowerCase().contains('location') &&
          !_locationKeywords.any((k) => t.toLowerCase().contains(k))),
    ];

    final payload = <String, dynamic>{
      'name': name,
      'label': label,
      'type': 'Group',
      'category': category.isNotEmpty ? category : _defaultCategory(locationType),
      'tags': tags,
      if (parentGroup != null && parentGroup.isNotEmpty)
        'groupNames': [parentGroup],
    };

    final res = await http.put(
      _uri('/items/$name'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode != 200 && res.statusCode != 202 && res.statusCode != 404) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<void> deleteRoom(String name) async {
    final res = await http.delete(
      _uri('/items/$name'),
      headers: headers,
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }

  Future<void> addItemToRoom(String roomName, String itemName) async {
    final res = await http.put(
      _uri('/items/$roomName/members/$itemName'),
      headers: headers,
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }

  Future<void> removeItemFromRoom(String roomName, String itemName) async {
    final res = await http.delete(
      _uri('/items/$roomName/members/$itemName'),
      headers: headers,
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }

  Future<void> updateItemMetadata({
    required String name,
    required String type,
    required String label,
    required String category,
    required List<String> tags,
    required List<String> groupNames,
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      'type': type,
      'label': label,
      'category': category,
      'tags': tags,
      'groupNames': groupNames,
    };

    final res = await http.put(
      _uri('/items/$name'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode != 200 && res.statusCode != 201 &&
        res.statusCode != 202 && res.statusCode != 204) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<void> sendCommand(String itemName, String command) async {
    await http.post(
      _uri('/items/$itemName'),
      headers: {...headers, 'Content-Type': 'text/plain'},
      body: command,
    ).timeout(const Duration(seconds: 6));
  }

  Future<List<Map<String, dynamic>>> getAllItems() async {
    final res = await http.get(
      _uri('/items?fields=name,label,type,tags,groupNames'),
      headers: headers,
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return List<Map<String, dynamic>>.from(jsonDecode(res.body) as List);
  }

  static const _locationKeywords = [
    'room', 'floor', 'building', 'indoor', 'outdoor',
    'corridor', 'garage', 'garden', 'terrace', 'office',
    'cellar', 'bedroom', 'kitchen', 'bathroom', 'livingroom',
  ];

  static String _semanticTag(String type) {
    switch (type) {
      case 'livingroom':  return 'Location_Indoor_Room_LivingRoom';
      case 'bedroom':     return 'Location_Indoor_Room_Bedroom';
      case 'kitchen':     return 'Location_Indoor_Room_Kitchen';
      case 'bathroom':    return 'Location_Indoor_Room_Bathroom';
      case 'garage':      return 'Location_Indoor_Garage';
      case 'garden':      return 'Location_Outdoor_Garden';
      case 'corridor':    return 'Location_Indoor_Corridor';
      case 'office':      return 'Location_Indoor_Room_Office';
      case 'cellar':      return 'Location_Indoor_Cellar';
      case 'terrace':     return 'Location_Outdoor_Terrace';
      case 'floor':       return 'Location_Indoor_Floor';
      case 'building':    return 'Location_Building';
      case 'outdoor':     return 'Location_Outdoor';
      default:            return 'Location_Indoor_Room';
    }
  }

  static String _defaultCategory(String type) {
    switch (type) {
      case 'livingroom':  return 'sofa';
      case 'bedroom':     return 'bedroom';
      case 'kitchen':     return 'kitchen';
      case 'bathroom':    return 'bath';
      case 'garage':      return 'garage';
      case 'garden':      return 'garden';
      case 'office':      return 'office';
      default:            return 'house';
    }
  }
}

Color roomColor(String type) {
  switch (type) {
    case 'livingroom':  return const Color(0xFF6366F1);
    case 'bedroom':     return const Color(0xFF8B5CF6);
    case 'kitchen':     return const Color(0xFFF59E0B);
    case 'bathroom':    return const Color(0xFF3B82F6);
    case 'garage':      return const Color(0xFF94A3B8);
    case 'garden':      return const Color(0xFF22C55E);
    case 'corridor':    return const Color(0xFF06B6D4);
    case 'office':      return const Color(0xFFEC4899);
    case 'cellar':      return const Color(0xFF78716C);
    case 'terrace':     return const Color(0xFF10B981);
    case 'floor':       return const Color(0xFF64748B);
    case 'building':    return const Color(0xFF475569);
    case 'outdoor':     return const Color(0xFF16A34A);
    default:            return const Color(0xFF6366F1);
  }
}

IconData roomIcon(String type) {
  switch (type) {
    case 'livingroom':  return Icons.weekend_rounded;
    case 'bedroom':     return Icons.bed_rounded;
    case 'kitchen':     return Icons.soup_kitchen_rounded;
    case 'bathroom':    return Icons.bathtub_rounded;
    case 'garage':      return Icons.garage_rounded;
    case 'garden':      return Icons.yard_rounded;
    case 'corridor':    return Icons.meeting_room_rounded;
    case 'office':      return Icons.work_rounded;
    case 'cellar':      return Icons.foundation_rounded;
    case 'terrace':     return Icons.deck_rounded;
    case 'floor':       return Icons.layers_rounded;
    case 'building':    return Icons.apartment_rounded;
    case 'outdoor':     return Icons.park_rounded;
    default:            return Icons.room_rounded;
  }
}

String roomTypeLabel(String type) {
  switch (type) {
    case 'livingroom':  return 'Ruang Tamu';
    case 'bedroom':     return 'Kamar Tidur';
    case 'kitchen':     return 'Dapur';
    case 'bathroom':    return 'Kamar Mandi';
    case 'garage':      return 'Garasi';
    case 'garden':      return 'Taman';
    case 'corridor':    return 'Koridor';
    case 'office':      return 'Kantor';
    case 'cellar':      return 'Ruang Bawah';
    case 'terrace':     return 'Teras';
    case 'floor':       return 'Lantai';
    case 'building':    return 'Bangunan';
    case 'outdoor':     return 'Luar Ruangan';
    default:            return 'Ruangan';
  }
}

IconData equipmentIcon(String tag) {
  final t = tag.toLowerCase();
  if (t.contains('lightbulb') || t.contains('light'))          return Icons.lightbulb_rounded;
  if (t.contains('poweroutlet') || t.contains('outlet') || t.contains('plug')) {
    return Icons.power_rounded;
  }
  if (t.contains('powermeter') || t.contains('meter'))          return Icons.speed_rounded;
  if (t.contains('sensor'))                                     return Icons.sensors_rounded;
  if (t.contains('camera'))                                     return Icons.videocam_rounded;
  if (t.contains('lock'))                                       return Icons.lock_rounded;
  if (t.contains('thermostat') || t.contains('hvac'))           return Icons.thermostat_rounded;
  if (t.contains('blind') || t.contains('shutter') || t.contains('curtain') || t.contains('awning')) {
    return Icons.blinds_rounded;
  }
  if (t.contains('fan'))                                        return Icons.mode_fan_off_rounded;
  if (t.contains('tv') || t.contains('television') || t.contains('player')) {
    return Icons.tv_rounded;
  }
  if (t.contains('speaker'))                                    return Icons.speaker_rounded;
  if (t.contains('valve'))                                      return Icons.water_drop_rounded;
  if (t.contains('alarm') || t.contains('siren'))                return Icons.notifications_active_rounded;
  if (t.contains('door') || t.contains('window'))               return Icons.sensor_door_rounded;
  return Icons.widgets_rounded;
}


class RoomsManagementPage extends StatefulWidget {
  const RoomsManagementPage({super.key});

  @override
  State<RoomsManagementPage> createState() => _RoomsManagementPageState();
}

class _RoomsManagementPageState extends State<RoomsManagementPage>
    with SingleTickerProviderStateMixin {
  final _ctrl = OpenHABController.instance;

  RoomsService? _svc;
  List<OHRoom> _allRooms      = [];
  List<OHRoom> _filteredRooms = [];
  bool    _isLoading  = false;
  String? _errorMsg;

  String _filterType   = 'all';
  String _searchQuery  = '';
  bool   _showSearch   = false;
  final  _searchCtrl   = TextEditingController();

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
    _svc = RoomsService(baseUrl: _ctrl.serverUrl, headers: headers);
    await _loadRooms();
  }

  Future<void> _loadRooms() async {
    if (_svc == null) return;
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      final rooms = await _svc!.getRooms();
      rooms.sort((a, b) => a.label.compareTo(b.label));
      if (!mounted) return;
      setState(() { _allRooms = rooms; _applyFilter(); });
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
      List<OHRoom> base = List.from(_allRooms);
      if (_filterType != 'all') {
        base = base.where((r) => r.locationType == _filterType).toList();
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        base = base.where((r) =>
            r.label.toLowerCase().contains(q) ||
            r.name.toLowerCase().contains(q) ||
            roomTypeLabel(r.locationType).toLowerCase().contains(q)).toList();
      }
      _filteredRooms = base;
    });
  }

  Future<void> _confirmDelete(OHRoom room) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF27272A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Hapus Room',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: isDark ? Colors.white : const Color(0xFF18181B))),
        content: Text(
          'Yakin ingin menghapus "${room.label}"?\n'
          'Item di dalam room tidak akan ikut terhapus.',
          style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: isDark ? Colors.white54 : const Color(0xFF71717A)),
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
    if (!mounted) return;
    if (confirm == true) {
      try {
        await _svc!.deleteRoom(room.name);
        if (!mounted) return;
        setState(() {
          _allRooms.removeWhere((r) => r.name == room.name);
          _applyFilter();
        });
        _showSnack('Room dihapus', isError: false);
      } catch (e) {
        if (!mounted) return;
        _showSnack('Gagal menghapus: $e', isError: true);
      }
    }
  }

  Future<void> _openAddRoom() async {
    if (_svc == null) return;
    final result = await Navigator.push<OHRoom>(
      context,
      MaterialPageRoute(
          builder: (_) => AddEditRoomPage(service: _svc!, rooms: _allRooms)),
    );
    if (!mounted) return;
    if (result != null) {
      setState(() { _allRooms.insert(0, result); _applyFilter(); });
      _showSnack('Room "${result.label}" berhasil dibuat!', isError: false);
    }
  }

  Future<void> _openEditRoom(OHRoom room) async {
    if (_svc == null) return;
    final result = await Navigator.push<OHRoom>(
      context,
      MaterialPageRoute(
          builder: (_) => AddEditRoomPage(
              service: _svc!, rooms: _allRooms, editRoom: room)),
    );
    if (!mounted) return;
    if (result != null) {
      final idx = _allRooms.indexWhere((r) => r.name == room.name);
      if (idx >= 0) setState(() { _allRooms[idx] = result; _applyFilter(); });
      _showSnack('Room diperbarui', isError: false);
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
      return const AccessDeniedView(featureName: 'Rooms Management');
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
        onPressed: _openAddRoom,
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
                hintText: 'Cari room...',
                hintStyle: TextStyle(
                    fontFamily: 'Inter',
                    color: isDark ? Colors.white38 : Colors.grey.shade400,
                    fontSize: 15),
                border: InputBorder.none,
              ),
            )
          : Text('Rooms',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: cs.onSurface)),
      actions: [
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
          onPressed: _loadRooms,
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
        Text('Memuat Rooms...',
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
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
          Icon(Icons.wifi_off_rounded, size: 56,
              color: isDark ? Colors.red.shade300 : Colors.red.shade300),
          const SizedBox(height: 14),
          Text('Gagal memuat Rooms',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                  fontSize: 16, color: Colors.red.shade700)),
          const SizedBox(height: 6),
          Text(_errorMsg!, textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                  color: isDark ? Colors.red.shade300 : Colors.red.shade400)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadRooms,
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
    final presentTypes = _allRooms.map((r) => r.locationType).toSet();
    return RefreshIndicator(
      onRefresh: _loadRooms,
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
                  if (presentTypes.length > 1) ...[
                    _buildTypeChips(presentTypes),
                    const SizedBox(height: 16),
                  ],
                  _buildListHeader(),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          _filteredRooms.isEmpty
              ? SliverFillRemaining(child: _buildEmpty())
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final room = _filteredRooms[i];
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
                          child: _RoomCard(
                            room: room,
                            onTap: () => _showDetail(room),
                            onEdit: () => _openEditRoom(room),
                            onDelete: () => _confirmDelete(room),
                          ),
                        );
                      },
                      childCount: _filteredRooms.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final indoorCount  = _allRooms.where((r) =>
        !['garden', 'outdoor', 'terrace'].contains(r.locationType)).length;
    final itemsTotal   = _allRooms.fold(0, (sum, r) => sum + r.itemCount);
    return Row(children: [
      Expanded(child: _SummaryCard(
          label: 'Total Rooms', count: _allRooms.length,
          color: const Color(0xFF6366F1), icon: Icons.home_rounded)),
      const SizedBox(width: 10),
      Expanded(child: _SummaryCard(
          label: 'Indoor', count: indoorCount,
          color: const Color(0xFF3B82F6), icon: Icons.house_rounded)),
      const SizedBox(width: 10),
      Expanded(child: _SummaryCard(
          label: 'Total Items', count: itemsTotal,
          color: const Color(0xFF22C55E), icon: Icons.devices_rounded)),
    ]);
  }

  Widget _buildTypeChips(Set<String> presentTypes) {
    final allTypes = [
      'livingroom', 'bedroom', 'kitchen', 'bathroom',
      'garage', 'garden', 'corridor', 'office',
      'cellar', 'terrace', 'floor', 'building', 'outdoor',
    ].where((t) => presentTypes.contains(t)).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _typeChip('all', Icons.grid_view_rounded, 'Semua'),
          ...allTypes.map((t) => _typeChip(t, roomIcon(t), roomTypeLabel(t))),
        ],
      ),
    );
  }

  Widget _typeChip(String type, IconData icon, String label) {
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _filterType == type;
    final color      = type == 'all' ? AppColors.primary : roomColor(type);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () { setState(() => _filterType = type); _applyFilter(); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? color
                : (isDark ? const Color(0xFF3F3F46) : Colors.white),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: isSelected
                    ? color
                    : (isDark ? const Color(0xFF52525B) : const Color(0xFFE4E4E7)),
                width: 1.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 13,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : color)),
            const SizedBox(width: 6),
            Text(label,
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
  }

  Widget _buildListHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(children: [
      Text('${_filteredRooms.length} Room${_filteredRooms.length != 1 ? 's' : ''}',
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
        Icon(Icons.meeting_room_rounded,
            size: 56,
            color: isDark ? Colors.white24 : Colors.grey.shade300),
        const SizedBox(height: 12),
        Text('Tidak ada Room',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: isDark ? Colors.white38 : Colors.grey.shade500)),
        const SizedBox(height: 4),
        Text('Tekan + untuk menambah room baru.',
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: isDark ? Colors.white24 : Colors.grey.shade400)),
      ]),
    );
  }

  void _showDetail(OHRoom room) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RoomDetailSheet(
          room: room,
          service: _svc!,
          onRefresh: _loadRooms),
    );
  }
}

class AddEditRoomPage extends StatefulWidget {
  final RoomsService service;
  final List<OHRoom> rooms;
  final OHRoom? editRoom;

  const AddEditRoomPage({
    super.key,
    required this.service,
    required this.rooms,
    this.editRoom,
  });

  @override
  State<AddEditRoomPage> createState() => _AddEditRoomPageState();
}

class _AddEditRoomPageState extends State<AddEditRoomPage> {
  final _labelCtrl    = TextEditingController();
  final _nameCtrl     = TextEditingController();
  final _categoryCtrl = TextEditingController();

  String  _selectedType    = 'livingroom';
  String? _selectedParent;
  bool    _isSaving        = false;
  String? _errorMsg;
  bool    _nameManuallySet = false;

  bool get _isEdit => widget.editRoom != null;

  static const _locationTypes = [
    {'key': 'livingroom', 'label': 'Ruang Tamu'},
    {'key': 'bedroom',    'label': 'Kamar Tidur'},
    {'key': 'kitchen',    'label': 'Dapur'},
    {'key': 'bathroom',   'label': 'Kamar Mandi'},
    {'key': 'garage',     'label': 'Garasi'},
    {'key': 'garden',     'label': 'Taman'},
    {'key': 'corridor',   'label': 'Koridor'},
    {'key': 'office',     'label': 'Kantor'},
    {'key': 'cellar',     'label': 'Ruang Bawah'},
    {'key': 'terrace',    'label': 'Teras'},
    {'key': 'floor',      'label': 'Lantai'},
    {'key': 'building',   'label': 'Bangunan'},
    {'key': 'outdoor',    'label': 'Luar Ruangan'},
    {'key': 'room',       'label': 'Ruangan Lain'},
  ];

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final r = widget.editRoom!;
      _labelCtrl.text    = r.label;
      _nameCtrl.text     = r.name;
      _selectedType      = r.locationType;
      _selectedParent    = r.parentLocation;
      _categoryCtrl.text = r.category;
      _nameManuallySet   = true;
    }
    _labelCtrl.addListener(_onLabelChanged);
  }

  void _onLabelChanged() {
    if (!_nameManuallySet && !_isEdit) {
      final generated = _labelCtrl.text
          .trim()
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      _nameCtrl.text = generated;
    }
  }

  @override
  void dispose() {
    _labelCtrl.removeListener(_onLabelChanged);
    _labelCtrl.dispose();
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  List<OHRoom> get _parentCandidates => widget.rooms
      .where((r) =>
          r.name != widget.editRoom?.name &&
          ['floor', 'building', 'indoor', 'outdoor'].contains(r.locationType))
      .toList();

  Future<void> _save() async {
    final label = _labelCtrl.text.trim();
    final name  = _nameCtrl.text.trim();

    if (label.isEmpty) {
      setState(() => _errorMsg = 'Nama room tidak boleh kosong'); return;
    }
    if (name.isEmpty) {
      setState(() => _errorMsg = 'Item name tidak boleh kosong'); return;
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(name)) {
      setState(() => _errorMsg = 'Item name hanya boleh huruf, angka, dan underscore');
      return;
    }

    setState(() { _isSaving = true; _errorMsg = null; });
    try {
      OHRoom result;
      if (_isEdit) {
        await widget.service.updateRoom(
          name: name,
          label: label,
          locationType: _selectedType,
          parentGroup: _selectedParent,
          category: _categoryCtrl.text.trim(),
          existingTags: widget.editRoom!.tags,
        );
        result = OHRoom(
          name: name, label: label, type: 'Group',
          tags: widget.editRoom!.tags,
          groupNames: _selectedParent != null ? [_selectedParent!] : [],
          members: widget.editRoom!.members,
          category: _categoryCtrl.text.trim(),
        );
      } else {
        result = await widget.service.createRoom(
          name: name,
          label: label,
          locationType: _selectedType,
          parentGroup: _selectedParent,
          category: _categoryCtrl.text.trim(),
        );
      }
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
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF27272A) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, size: 22, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_isEdit ? 'Edit Room' : 'Tambah Room',
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
      ),
      body: SingleChildScrollView(
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
                      ? const Color(0xFF3B1515)
                      : const Color(0xFFFFF0F0),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
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

            _sectionLabel('TIPE LOKASI', isDark),
            const SizedBox(height: 10),
            _card(isDark: isDark, children: [
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.85,
                children: _locationTypes.map((type) {
                  final key        = type['key']!;
                  final isSelected = _selectedType == key;
                  final color      = roomColor(key);
                  return GestureDetector(
                    onTap: () => setState(() => _selectedType = key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? color.withValues(alpha: 0.12)
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
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(roomIcon(key),
                              size: 24,
                              color: isSelected
                                  ? color
                                  : (isDark
                                      ? Colors.white38
                                      : const Color(0xFF94A3B8))),
                          const SizedBox(height: 6),
                          Text(type['label']!, textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                  color: isSelected
                                      ? color
                                      : (isDark
                                          ? Colors.white54
                                          : const Color(0xFF52525B)))),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ]),

            const SizedBox(height: 20),
            _sectionLabel('INFORMASI ROOM', isDark),
            const SizedBox(height: 10),
            _card(isDark: isDark, children: [
              _fieldLabel('Nama Tampilan *', isDark),
              const SizedBox(height: 8),
              _textField(
                  controller: _labelCtrl,
                  hint: 'contoh: Ruang Tamu Utama',
                  icon: Icons.label_rounded,
                  isDark: isDark),
              const SizedBox(height: 16),
              _fieldLabel('Item Name (openHAB) *', isDark),
              const SizedBox(height: 4),
              Text(
                'Hanya huruf, angka, underscore. Tidak bisa diubah setelah dibuat.',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: isDark ? Colors.white38 : const Color(0xFF9E9E9E)),
              ),
              const SizedBox(height: 8),
              _textField(
                controller: _nameCtrl,
                hint: 'contoh: LivingRoom_Main',
                icon: Icons.code_rounded,
                isDark: isDark,
                enabled: !_isEdit,
                onChanged: (_) => _nameManuallySet = true,
              ),
              const SizedBox(height: 16),
              _fieldLabel('Category (opsional)', isDark),
              const SizedBox(height: 4),
              Text(
                'Icon kategori openHAB, contoh: sofa, bedroom, kitchen',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: isDark ? Colors.white38 : const Color(0xFF9E9E9E)),
              ),
              const SizedBox(height: 8),
              _textField(
                  controller: _categoryCtrl,
                  hint: 'contoh: sofa',
                  icon: Icons.category_rounded,
                  isDark: isDark),
            ]),

            const SizedBox(height: 20),
            _sectionLabel('LOKASI INDUK (OPSIONAL)', isDark),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                'Tempatkan room ini di dalam lantai atau bangunan tertentu.',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: isDark ? Colors.white38 : const Color(0xFF9E9E9E)),
              ),
            ),
            _card(isDark: isDark, children: [
              if (_parentCandidates.isEmpty)
                Text(
                  'Tidak ada lokasi induk tersedia. Tambah Lantai atau Bangunan terlebih dahulu.',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: isDark ? Colors.white54 : const Color(0xFF71717A)),
                )
              else ...[
                _parentOption(null, isDark: isDark),
                ..._parentCandidates.map((r) => _parentOption(r.name, room: r, isDark: isDark)),
              ],
            ]),

            const SizedBox(height: 20),

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
                    'Room dibuat sebagai Group Item openHAB dengan semantic '
                    'Location tag. Items dan perangkat bisa ditambahkan ke '
                    'room ini setelah disimpan.',
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
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(_isEdit ? Icons.save_rounded : Icons.add_rounded,
                            size: 18, color: Colors.white),
                        const SizedBox(width: 10),
                        Text(_isEdit ? 'Simpan Perubahan' : 'Buat Room di openHAB',
                            style: const TextStyle(
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
      ),
    );
  }

  Widget _parentOption(String? value, {OHRoom? room, required bool isDark}) {
    final isSelected = _selectedParent == value;
    final color = value == null
        ? const Color(0xFF94A3B8)
        : roomColor(room!.locationType);
    return GestureDetector(
      onTap: () => setState(() => _selectedParent = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.1)
              : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFF8F8FA)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected
                  ? color
                  : (isDark
                      ? const Color(0xFF52525B)
                      : const Color(0xFFE4E4E7)),
              width: isSelected ? 1.5 : 1),
        ),
        child: Row(children: [
          Icon(value == null ? Icons.block_rounded : roomIcon(room!.locationType),
              size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(
            value == null ? 'Tanpa induk (root location)' : room!.label,
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: isSelected
                    ? color
                    : (isDark ? Colors.white70 : const Color(0xFF52525B))),
          )),
          if (isSelected)
            Icon(Icons.check_circle_rounded, size: 18, color: color),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String label, bool isDark) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(label,
        style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w500,
            fontSize: 11,
            letterSpacing: 0.8,
            color: isDark ? Colors.white38 : const Color(0xFF9E9E9E))),
  );

  Widget _fieldLabel(String label, bool isDark) => Text(label,
      style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: isDark ? Colors.white54 : const Color(0xFF71717A)));

  Widget _card({required List<Widget> children, required bool isDark}) =>
      Container(
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
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isDark,
    bool enabled = true,
    ValueChanged<String>? onChanged,
  }) =>
      TextField(
        controller: controller,
        enabled: enabled,
        onChanged: onChanged,
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
          fillColor: enabled
              ? (isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7))
              : (isDark ? const Color(0xFF2D2D30) : const Color(0xFFEEEEEE)),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          prefixIcon: Center(
              widthFactor: 1,
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Icon(icon,
                      size: 16,
                      color: isDark ? Colors.white38 : const Color(0xFF71717A)))),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
}

class _RoomCard extends StatelessWidget {
  final OHRoom room;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RoomCard({required this.room, required this.onTap,
      required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rc     = roomColor(room.locationType);
    final previewPoints = room.allPoints;
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
              Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                      color: rc.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16)),
                  child: Center(child: Icon(roomIcon(room.locationType),
                      size: 24, color: rc))),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: isDark ? Colors.white : const Color(0xCC18181B))),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    _badge(roomTypeLabel(room.locationType), rc),
                    if (room.equipmentCount > 0)
                      _badge('${room.equipmentCount} equipment',
                          const Color(0xFF6366F1)),
                    if (room.parentLocation != null)
                      _badge(room.parentLocation!, const Color(0xFF94A3B8)),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.devices_rounded,
                            size: 12,
                            color: isDark ? Colors.white38 : Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text('${room.itemCount} channel${room.itemCount != 1 ? 's' : ''}',
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                color: isDark ? Colors.white38 : Colors.grey.shade500)),
                      ]),
                      ...previewPoints.take(4).map((m) => Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF3F3F46)
                                : const Color(0xFFF5F5F7),
                            borderRadius: BorderRadius.circular(6)),
                        child: Center(child: Icon(
                            _memberIcon(m.type), size: 11,
                            color: isDark ? Colors.white38 : const Color(0xFF94A3B8))),
                      )),
                      if (previewPoints.length > 4)
                        Text('+${previewPoints.length - 4}',
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                color: isDark ? Colors.white38 : const Color(0xFF94A3B8))),
                    ],
                  ),
                ],
              )),
              Column(children: [
                GestureDetector(
                  onTap: onEdit,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.edit_rounded,
                        size: 14, color: AppColors.primary),
                  ),
                ),
                const SizedBox(height: 8),
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
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  IconData _memberIcon(String type) {
    switch (type) {
      case 'Switch':        return Icons.toggle_on_rounded;
      case 'Dimmer':        return Icons.light_mode_rounded;
      case 'Color':         return Icons.palette_rounded;
      case 'Rollershutter': return Icons.blinds_rounded;
      case 'Number':        return Icons.numbers_rounded;
      case 'String':        return Icons.text_fields_rounded;
      case 'Contact':       return Icons.sensor_door_rounded;
      default:              return Icons.device_unknown_rounded;
    }
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20)),
    child: Text(label,
        style: TextStyle(fontFamily: 'Inter',
            fontWeight: FontWeight.w600, fontSize: 10, color: color)),
  );
}
class _RoomDetailSheet extends StatefulWidget {
  final OHRoom room;
  final RoomsService service;
  final VoidCallback onRefresh;

  const _RoomDetailSheet(
      {required this.room, required this.service, required this.onRefresh});

  @override
  State<_RoomDetailSheet> createState() => _RoomDetailSheetState();
}

class _RoomDetailSheetState extends State<_RoomDetailSheet> {
  late OHRoom _room;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
  }

  Future<void> _sendCommand(OHRoomMember member, String command) async {
    try {
      await widget.service.sendCommand(member.name, command);
      widget.onRefresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal: $e'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
      }
    }
  }

  List<OHRoomMember> _removeMemberByName(
      List<OHRoomMember> members, String name) {
    return members
        .where((m) => m.name != name)
        .map((m) => m.members.isEmpty
            ? m
            : OHRoomMember(
                name: m.name,
                label: m.label,
                type: m.type,
                state: m.state,
                tags: m.tags,
                category: m.category,
                members: _removeMemberByName(m.members, name),
              ))
        .toList();
  }

  List<OHRoomMember> _updateMemberByName(
      List<OHRoomMember> members, String name, OHRoomMember updated) {
    return members.map((m) {
      if (m.name == name) return updated;
      if (m.members.isEmpty) return m;
      return OHRoomMember(
        name: m.name,
        label: m.label,
        type: m.type,
        state: m.state,
        tags: m.tags,
        category: m.category,
        groupNames: m.groupNames,
        members: _updateMemberByName(m.members, name, updated),
      );
    }).toList();
  }

  void _applyMemberUpdate(OHRoomMember updated) {
    setState(() {
      _room = OHRoom(
        name: _room.name, label: _room.label, type: _room.type,
        tags: _room.tags, groupNames: _room.groupNames,
        members: _updateMemberByName(_room.members, updated.name, updated),
        category: _room.category,
      );
    });
    widget.onRefresh();
  }

  Future<void> _removeItem(OHRoomMember member) async {
    try {
      await widget.service.removeItemFromRoom(_room.name, member.name);
      if (!mounted) return;
      setState(() {
        _room = OHRoom(
          name: _room.name, label: _room.label, type: _room.type,
          tags: _room.tags, groupNames: _room.groupNames,
          members: _removeMemberByName(_room.members, member.name),
          category: _room.category,
        );
      });
      widget.onRefresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menghapus item: $e'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rc     = roomColor(_room.locationType);
    final equipment = _room.equipmentMembers;
    final directPoints = _room.pointMembers;
    return DraggableScrollableSheet(
      initialChildSize: 0.75, minChildSize: 0.5, maxChildSize: 0.95,
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
            Center(child: Container(
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
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                        color: rc.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18)),
                    child: Center(child: Icon(
                        roomIcon(_room.locationType), size: 26, color: rc))),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_room.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: isDark ? Colors.white : const Color(0xCC18181B))),
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _pill(roomTypeLabel(_room.locationType), rc),
                      _pill('${equipment.length} Equipment', const Color(0xFF6366F1)),
                      _pill('${_room.itemCount} Channels', const Color(0xFF22C55E)),
                    ]),
                  ],
                )),
              ]),
            ),

            const SizedBox(height: 16),
            Divider(height: 1,
                color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7)),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(children: [
                _InfoRow(label: 'Item Name', value: _room.name, isDark: isDark),
                _InfoRow(label: 'Tipe', value: roomTypeLabel(_room.locationType), isDark: isDark),
                if (_room.parentLocation != null)
                  _InfoRow(label: 'Induk', value: _room.parentLocation!, isDark: isDark),
                _InfoRow(label: 'Tags',
                    value: _room.tags.isEmpty ? '-' : _room.tags.join(', '),
                    isDark: isDark),
              ]),
            ),

            Divider(height: 1,
                color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7)),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                Icon(Icons.widgets_rounded, size: 16, color: rc),
                const SizedBox(width: 8),
                Text('Equipment & Channels (${_room.itemCount})',
                    style: TextStyle(fontFamily: 'Inter',
                        fontWeight: FontWeight.w700, fontSize: 14, color: rc)),
              ]),
            ),
            const SizedBox(height: 12),

            if (equipment.isEmpty && directPoints.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text('Belum ada equipment atau item di room ini.',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 13,
                        color: isDark ? Colors.white38 : const Color(0xFF71717A))),
              )
            else ...[
              ...equipment.map((eq) => _EquipmentTile(
                    equipment: eq,
                    color: rc,
                    isDark: isDark,
                    service: widget.service,
                    onSaved: _applyMemberUpdate,
                    onTogglePoint: (m) =>
                        _sendCommand(m, m.isOn ? 'OFF' : 'ON'),
                    onRemoveEquipment: () => _removeItem(eq),
                  )),
              ...directPoints.map((member) => _MemberTile(
                    member: member,
                    isDark: isDark,
                    service: widget.service,
                    onSaved: _applyMemberUpdate,
                    onToggle: member.type == 'Switch'
                        ? () => _sendCommand(member, member.isOn ? 'OFF' : 'ON')
                        : null,
                    onRemove: () => _removeItem(member),
                  )),
            ],

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20)),
    child: Text(label,
        style: TextStyle(fontFamily: 'Inter',
            fontWeight: FontWeight.w700, fontSize: 11, color: color)),
  );
}

class _EquipmentTile extends StatefulWidget {
  final OHRoomMember equipment;
  final Color color;
  final bool isDark;
  final void Function(OHRoomMember point) onTogglePoint;
  final VoidCallback onRemoveEquipment;
  final RoomsService? service;
  final ValueChanged<OHRoomMember>? onSaved;

  const _EquipmentTile({
    required this.equipment,
    required this.color,
    required this.isDark,
    required this.onTogglePoint,
    required this.onRemoveEquipment,
    this.service,
    this.onSaved,
  });

  @override
  State<_EquipmentTile> createState() => _EquipmentTileState();
}

class _EquipmentTileState extends State<_EquipmentTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final eq       = widget.equipment;
    final points   = eq.allPoints;
    final isDark   = widget.isDark;
    final color    = widget.color;
    final icon     = equipmentIcon(eq.equipmentTypeLabel);

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? const Color(0xFF52525B) : const Color(0xFFE4E4E7)),
      ),
      child: Column(children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => showPointDetail(context, eq, isDark,
                service: widget.service, onSaved: widget.onSaved),
            onLongPress: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Center(child: Icon(icon, size: 16, color: color)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(eq.label,
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: isDark ? Colors.white : const Color(0xCC18181B))),
                    Text(
                      'Equipment · ${eq.equipmentTypeLabel} · '
                      '${points.length} channel${points.length != 1 ? 's' : ''}',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          color: isDark ? Colors.white38 : const Color(0xFF71717A)),
                    ),
                  ],
                )),
                GestureDetector(
                  onTap: widget.onRemoveEquipment,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.remove_circle_outline_rounded,
                        size: 14, color: Color(0xFFEF4444)),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Icon(
                      _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 18,
                      color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                ),
              ]),
            ),
          ),
        ),
        if (_expanded && points.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: points
                  .map((p) => _MemberTile(
                        member: p,
                        isDark: isDark,
                        service: widget.service,
                        onSaved: widget.onSaved,
                        onToggle: p.type == 'Switch'
                            ? () => widget.onTogglePoint(p)
                            : null,
                        onRemove: null,
                        compact: true,
                      ))
                  .toList(),
            ),
          ),
      ]),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final OHRoomMember member;
  final VoidCallback? onToggle;
  final VoidCallback? onRemove;
  final bool isDark;
  final bool compact;
  final RoomsService? service;
  final ValueChanged<OHRoomMember>? onSaved;

  const _MemberTile({
    required this.member,
    required this.onToggle,
    this.onRemove,
    required this.isDark,
    this.compact = false,
    this.service,
    this.onSaved,
  });

  Color get _typeColor {
    switch (member.type) {
      case 'Switch':        return const Color(0xFF22C55E);
      case 'Dimmer':        return const Color(0xFFF59E0B);
      case 'Color':         return const Color(0xFFEC4899);
      case 'Rollershutter': return const Color(0xFF6366F1);
      case 'Number':        return const Color(0xFF3B82F6);
      default:              return const Color(0xFF94A3B8);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _typeColor;
    return Container(
      margin: compact
          ? const EdgeInsets.only(bottom: 6)
          : const EdgeInsets.fromLTRB(24, 0, 24, 8),
      decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF8F8FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isDark
                  ? const Color(0xFF52525B)
                  : const Color(0xFFE4E4E7))),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showPointDetail(context, member, isDark,
              service: service, onSaved: onSaved),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Center(child: Icon(_itemIcon(member.type),
                      size: 16, color: color))),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.label,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: isDark ? Colors.white : const Color(0xCC18181B))),
                  Text('${member.type} · ${member.state}',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          color: isDark ? Colors.white38 : const Color(0xFF71717A))),
                ],
              )),
              if (member.type == 'Switch' && onToggle != null)
                Switch(
                  value: member.isOn,
                  onChanged: (_) => onToggle!(),
                  activeThumbColor: AppColors.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(member.state,
                      style: TextStyle(fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 11, color: color)),
                ),
              if (onRemove != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.remove_circle_outline_rounded,
                        size: 14, color: Color(0xFFEF4444)),
                  ),
                ),
              ] else ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 16,
                    color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  IconData _itemIcon(String type) {
    switch (type) {
      case 'Switch':        return Icons.toggle_on_rounded;
      case 'Dimmer':        return Icons.light_mode_rounded;
      case 'Color':         return Icons.palette_rounded;
      case 'Rollershutter': return Icons.blinds_rounded;
      case 'Number':        return Icons.numbers_rounded;
      case 'String':        return Icons.text_fields_rounded;
      case 'Contact':       return Icons.sensor_door_rounded;
      case 'Group':         return Icons.folder_rounded;
      default:              return Icons.device_unknown_rounded;
    }
  }
}

void showPointDetail(
  BuildContext context,
  OHRoomMember point,
  bool isDark, {
  RoomsService? service,
  ValueChanged<OHRoomMember>? onSaved,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _PointDetailSheet(
      point: point,
      isDark: isDark,
      service: service,
      onSaved: onSaved,
    ),
  );
}

class _PointDetailSheet extends StatefulWidget {
  final OHRoomMember point;
  final bool isDark;
  final RoomsService? service;
  final ValueChanged<OHRoomMember>? onSaved;

  const _PointDetailSheet({
    required this.point,
    required this.isDark,
    this.service,
    this.onSaved,
  });

  @override
  State<_PointDetailSheet> createState() => _PointDetailSheetState();
}

class _PointDetailSheetState extends State<_PointDetailSheet> {
  late TextEditingController _labelCtrl;
  late TextEditingController _iconCtrl;
  late TextEditingController _addTagCtrl;
  late List<String> _tags;
  late List<String> _groupNames;
  String? _semanticPoint;
  String? _semanticProperty;
  bool _isSaving = false;
  bool _dirty = false;

  bool get isDark => widget.isDark;
  bool get _canEdit => widget.service != null;

  @override
  void initState() {
    super.initState();
    final p = widget.point;
    _labelCtrl = TextEditingController(text: p.label);
    _iconCtrl = TextEditingController(text: p.category);
    _addTagCtrl = TextEditingController();
    _tags = List<String>.from(p.tags);
    _groupNames = List<String>.from(p.groupNames);
    _semanticPoint = p.semanticPointType;
    _semanticProperty = p.semanticProperty;
    _labelCtrl.addListener(_markDirty);
    _iconCtrl.addListener(_markDirty);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _iconCtrl.dispose();
    _addTagCtrl.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) {
      setState(() => _dirty = true);
    } else {
      setState(() {});
    }
  }

  List<String> get _nonSemanticTags => _tags
      .where((t) =>
          !OHRoomMember._pointTypeTags.contains(t) &&
          !OHRoomMember._propertyTags.contains(t))
      .toList();

  void _setSemanticPoint(String? value) {
    setState(() {
      _tags.removeWhere((t) => OHRoomMember._pointTypeTags.contains(t));
      if (value != null) _tags.add(value);
      _semanticPoint = value;
      _dirty = true;
    });
  }

  void _setSemanticProperty(String? value) {
    setState(() {
      _tags.removeWhere((t) => OHRoomMember._propertyTags.contains(t));
      if (value != null) _tags.add(value);
      _semanticProperty = value;
      _dirty = true;
    });
  }

  void _addTag() {
    final v = _addTagCtrl.text.trim();
    if (v.isEmpty) return;
    if (OHRoomMember._pointTypeTags.contains(v) ||
        OHRoomMember._propertyTags.contains(v)) {
      _showSnack('Gunakan Semantic Point/Property untuk tag ini', isError: true);
      return;
    }
    setState(() {
      if (!_tags.contains(v)) _tags.add(v);
      _addTagCtrl.clear();
      _dirty = true;
    });
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
      if (OHRoomMember._pointTypeTags.contains(tag)) _semanticPoint = null;
      if (OHRoomMember._propertyTags.contains(tag)) _semanticProperty = null;
      _dirty = true;
    });
  }

  Future<void> _removeParentGroup(String group) async {
    if (widget.service == null) return;
    try {
      await widget.service!.removeItemFromRoom(group, widget.point.name);
      if (!mounted) return;
      setState(() {
        _groupNames.remove(group);
      });
      _showSnack('Dihapus dari $group', isError: false);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Gagal menghapus dari group: $e', isError: true);
    }
  }

  Future<void> _pickSemantic({
    required String title,
    required Set<String> options,
    required String? current,
    required ValueChanged<String?> onPicked,
  }) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SemanticPickerSheet(
        title: title,
        options: options,
        current: current,
        isDark: isDark,
      ),
    );
    if (!mounted) return;
    if (result == null) return;
    onPicked(result.isEmpty ? null : result);
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Inter', fontSize: 13)),
      backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  Future<void> _save() async {
    if (widget.service == null) return;
    setState(() => _isSaving = true);
    try {
      await widget.service!.updateItemMetadata(
        name: widget.point.name,
        type: widget.point.type,
        label: _labelCtrl.text.trim(),
        category: _iconCtrl.text.trim(),
        tags: _tags,
        groupNames: _groupNames,
      );
      final updated = OHRoomMember(
        name: widget.point.name,
        label: _labelCtrl.text.trim(),
        type: widget.point.type,
        state: widget.point.state,
        tags: _tags,
        category: _iconCtrl.text.trim(),
        groupNames: _groupNames,
        members: widget.point.members,
      );
      widget.onSaved?.call(updated);
      if (!mounted) return;
      _showSnack('Item diperbarui', isError: false);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showSnack('Gagal menyimpan: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.point;
    final color = p.isEquipment ? const Color(0xFF6366F1) : const Color(0xFF3B82F6);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF27272A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7),
                    borderRadius: BorderRadius.circular(2)))),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
              child: Row(children: [
                Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14)),
                    child: Center(child: Icon(
                        p.isEquipment
                            ? equipmentIcon(_iconCtrl.text.isNotEmpty
                                ? _iconCtrl.text : p.equipmentTypeLabel)
                            : Icons.bolt_rounded,
                        size: 22, color: color))),
                const SizedBox(width: 12),
                Expanded(child: Text(
                    _labelCtrl.text.isEmpty ? p.name : _labelCtrl.text,
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: isDark ? Colors.white : const Color(0xCC18181B)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
                if (_canEdit)
                  GestureDetector(
                    onTap: (_dirty && !_isSaving) ? _save : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: (_dirty && !_isSaving)
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: _isSaving
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Simpan',
                              style: TextStyle(fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13, color: Colors.white)),
                    ),
                  ),
              ]),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(children: [
                      Text('State',
                          style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                              color: isDark ? Colors.white54 : const Color(0xFF71717A))),
                      const Spacer(),
                      Text(p.state,
                          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                              fontSize: 15, color: color)),
                    ]),
                  ),
                  const SizedBox(height: 20),

                  _fieldLabel('Name'),
                  const SizedBox(height: 6),
                  _readOnlyBox(p.name),
                  const SizedBox(height: 16),

                  _fieldLabel('Label'),
                  const SizedBox(height: 6),
                  _editTextField(_labelCtrl, hint: 'Label item', enabled: _canEdit),
                  const SizedBox(height: 16),

                  _fieldLabel('Icon'),
                  const SizedBox(height: 6),
                  _editTextField(_iconCtrl,
                      hint: 'contoh: ColorLight, Light, Fan', enabled: _canEdit),
                  const SizedBox(height: 20),

                  if (!p.isEquipment) ...[
                    _fieldLabel('Semantic Point'),
                    const SizedBox(height: 6),
                    _pickerRow(
                      value: _semanticPoint ?? '-',
                      enabled: _canEdit,
                      onTap: () => _pickSemantic(
                        title: 'Pilih Semantic Point',
                        options: OHRoomMember._pointTypeTags,
                        current: _semanticPoint,
                        onPicked: _setSemanticPoint,
                      ),
                    ),
                    const SizedBox(height: 16),

                    _fieldLabel('Semantic Property'),
                    const SizedBox(height: 6),
                    _pickerRow(
                      value: _semanticProperty ?? 'None',
                      enabled: _canEdit,
                      onTap: () => _pickSemantic(
                        title: 'Pilih Semantic Property',
                        options: OHRoomMember._propertyTags,
                        current: _semanticProperty,
                        onPicked: _setSemanticProperty,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  Row(children: [
                    _fieldLabel('Non-Semantic Tags'),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF0F0F2),
                          borderRadius: BorderRadius.circular(10)),
                      child: Text('${_nonSemanticTags.length}',
                          style: TextStyle(fontFamily: 'Inter', fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white54 : const Color(0xFF71717A))),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    ..._nonSemanticTags.map((t) => _removableTagChip(
                        t, const Color(0xFF94A3B8),
                        onRemove: _canEdit ? () => _removeTag(t) : null)),
                    if (_nonSemanticTags.isEmpty)
                      Text('-', style: TextStyle(fontFamily: 'Inter', fontSize: 13,
                          color: isDark ? Colors.white38 : const Color(0xFF71717A))),
                  ]),
                  if (_canEdit) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: _editTextField(_addTagCtrl,
                          hint: 'Tambah tag...', enabled: true,
                          onSubmitted: (_) => _addTag())),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _addTag,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                        ),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 20),

                  _fieldLabel('Parent Groups'),
                  const SizedBox(height: 8),
                  _groupNames.isEmpty
                      ? Text('-', style: TextStyle(fontFamily: 'Inter', fontSize: 13,
                          color: isDark ? Colors.white38 : const Color(0xFF71717A)))
                      : Wrap(spacing: 6, runSpacing: 6, children: _groupNames
                          .map((g) => _removableTagChip(g, const Color(0xFF94A3B8),
                              onRemove: _canEdit ? () => _removeParentGroup(g) : null))
                          .toList()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) => Text(label,
      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12,
          color: isDark ? Colors.white54 : const Color(0xFF71717A)));

  Widget _readOnlyBox(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D30) : const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(12)),
    child: Text(text, style: TextStyle(fontFamily: 'Inter', fontSize: 13,
        color: isDark ? Colors.white54 : const Color(0xFF71717A))),
  );

  Widget _editTextField(TextEditingController ctrl,
      {required String hint, required bool enabled, ValueChanged<String>? onSubmitted}) {
    return TextField(
      controller: ctrl,
      enabled: enabled,
      onSubmitted: onSubmitted,
      style: TextStyle(fontFamily: 'Inter', fontSize: 14,
          color: isDark ? Colors.white : const Color(0xFF18181B)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontFamily: 'Inter', fontSize: 13,
            color: isDark ? Colors.white38 : Colors.grey.shade400),
        filled: true,
        fillColor: enabled
            ? (isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7))
            : (isDark ? const Color(0xFF2D2D30) : const Color(0xFFEEEEEE)),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        suffixIcon: (ctrl.text.isNotEmpty && enabled)
            ? GestureDetector(
                onTap: () { ctrl.clear(); _markDirty(); },
                child: Icon(Icons.cancel_rounded, size: 16,
                    color: isDark ? Colors.white38 : const Color(0xFF9E9E9E)))
            : null,
      ),
    );
  }

  Widget _pickerRow({required String value, required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
            color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7),
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(child: Text(value, style: TextStyle(fontFamily: 'Inter', fontSize: 14,
              color: isDark ? Colors.white : const Color(0xFF18181B)))),
          if (enabled)
            Icon(Icons.chevron_right_rounded, size: 18,
                color: isDark ? Colors.white38 : const Color(0xFF9E9E9E)),
        ]),
      ),
    );
  }

  Widget _removableTagChip(String label, Color color, {VoidCallback? onRemove}) => Container(
    padding: EdgeInsets.only(left: 10, right: onRemove != null ? 6 : 10, top: 5, bottom: 5),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
          fontSize: 11, color: color)),
      if (onRemove != null) ...[
        const SizedBox(width: 4),
        GestureDetector(onTap: onRemove, child: Icon(Icons.close_rounded, size: 13, color: color)),
      ],
    ]),
  );
}

class _SemanticPickerSheet extends StatelessWidget {
  final String title;
  final Set<String> options;
  final String? current;
  final bool isDark;

  const _SemanticPickerSheet({
    required this.title,
    required this.options,
    required this.current,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = options.toList()..sort();
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF27272A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7),
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                fontSize: 16, color: isDark ? Colors.white : const Color(0xCC18181B))),
            const SizedBox(height: 12),
            ListTile(
              title: Text('None', style: TextStyle(fontFamily: 'Inter',
                  color: isDark ? Colors.white70 : const Color(0xFF52525B))),
              trailing: current == null
                  ? const Icon(Icons.check_rounded, color: AppColors.primary)
                  : null,
              onTap: () => Navigator.pop(context, ''),
            ),
            ...sorted.map((o) => ListTile(
                  title: Text(o, style: TextStyle(fontFamily: 'Inter',
                      color: isDark ? Colors.white : const Color(0xCC18181B))),
                  trailing: current == o
                      ? const Icon(Icons.check_rounded, color: AppColors.primary)
                      : null,
                  onTap: () => Navigator.pop(context, o),
                )),
          ],
        ),
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
            blurRadius: 8,
            offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Center(child: Icon(icon, size: 16, color: color))),
        const SizedBox(height: 10),
        Text('$count',
            style: TextStyle(fontFamily: 'Inter',
                fontWeight: FontWeight.w800, fontSize: 22, color: color)),
        Text(label,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: isDark ? Colors.white38 : const Color(0xFF71717A),
                fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
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
        SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: isDark ? Colors.white38 : const Color(0xFF71717A),
                    fontWeight: FontWeight.w500))),
        Expanded(
            child: Text(value,
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: isDark ? Colors.white70 : const Color(0xCC18181B),
                    fontWeight: FontWeight.w500))),
      ]),
    );
  }
}