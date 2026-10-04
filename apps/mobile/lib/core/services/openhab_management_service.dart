import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/pages/items_management_page.dart';

class OHBinding {
  final String id;
  final String name;
  final String description;
  final bool installed;

  const OHBinding({
    required this.id,
    required this.name,
    required this.description,
    this.installed = false,
  });

  factory OHBinding.fromJson(Map<String, dynamic> json) => OHBinding(
        id: json['id'] ?? '',
        name: json['name'] ?? json['id'] ?? '',
        description: json['description'] ?? '',
        // Default FALSE: binding yang tidak jelas statusnya jangan dianggap terpasang.
        installed: json['installed'] as bool? ?? false,
      );
}

class OHThing {
  final String uid;
  final String label;
  final String thingTypeUID;
  final String statusDetail;
  final String status;
  final String location;
  final List<OHChannel> channels;
  final Map<String, dynamic> configuration;

  const OHThing({
    required this.uid,
    required this.label,
    required this.thingTypeUID,
    this.statusDetail = '',
    this.status = 'UNKNOWN',
    this.location = '',
    this.channels = const [],
    this.configuration = const {},
  });

  factory OHThing.fromJson(Map<String, dynamic> json) {
    final statusInfo = json['statusInfo'] as Map<String, dynamic>? ?? {};
    return OHThing(
      uid: json['UID'] ?? json['uid'] ?? '',
      label: json['label'] ?? '',
      thingTypeUID: json['thingTypeUID'] ?? '',
      status: statusInfo['status'] ?? 'UNKNOWN',
      statusDetail: statusInfo['statusDetail'] ?? '',
      location: json['location'] ?? '',
      channels: (json['channels'] as List<dynamic>? ?? [])
          .map((c) => OHChannel.fromJson(c as Map<String, dynamic>))
          .toList(),
      configuration:
          Map<String, dynamic>.from(json['configuration'] ?? {}),
    );
  }

  bool get isOnline => status == 'ONLINE';
  bool get isOffline => status == 'OFFLINE';
}


class OHChannel {
  final String uid;
  final String id;
  final String label;
  final String channelTypeUID;
  final String itemType;
  final List<String> linkedItems;

  const OHChannel({
    required this.uid,
    required this.id,
    required this.label,
    required this.channelTypeUID,
    required this.itemType,
    this.linkedItems = const [],
  });

  factory OHChannel.fromJson(Map<String, dynamic> json) => OHChannel(
        uid: json['uid'] ?? '',
        id: json['id'] ?? '',
        label: json['label'] ?? json['id'] ?? '',
        channelTypeUID: json['channelTypeUID'] ?? '',
        itemType: json['itemType'] ?? 'Switch',
        linkedItems:
            List<String>.from(json['linkedItems'] ?? []),
      );
}

class OHThingType {
  final String uid;
  final String label;
  final String description;
  final String bindingId;
  final List<Map<String, dynamic>> configParameters;
  final List<Map<String, dynamic>> channelDefinitions;

  const OHThingType({
    required this.uid,
    required this.label,
    required this.description,
    required this.bindingId,
    this.configParameters = const [],
    this.channelDefinitions = const [],
  });

  factory OHThingType.fromJson(Map<String, dynamic> json) => OHThingType(
        uid: json['UID'] ?? '',
        label: json['label'] ?? '',
        description: json['description'] ?? '',
        bindingId: json['bindingId'] ?? (json['UID'] as String? ?? '').split(':').first,
        configParameters: List<Map<String, dynamic>>.from(
          json['configParameters'] ?? [],
        ),
        channelDefinitions: List<Map<String, dynamic>>.from(
          json['channelDefinitions'] ?? [],
        ),
      );
}


/// Satu entri hasil Discovery (openHAB Inbox) — perangkat yang ditemukan
/// otomatis oleh binding tapi belum jadi Thing sampai user approve.
class OHInboxEntry {
  final String thingUID;
  final String bindingId;
  final String label;
  final String flag; // NEW, IGNORED, PENDING
  final Map<String, dynamic> properties;
  final String? representationProperty;
  final String? bridgeUID;

  const OHInboxEntry({
    required this.thingUID,
    required this.bindingId,
    required this.label,
    this.flag = 'NEW',
    this.properties = const {},
    this.representationProperty,
    this.bridgeUID,
  });

  factory OHInboxEntry.fromJson(Map<String, dynamic> json) {
    final uid = json['thingUID'] as String? ?? '';
    return OHInboxEntry(
      thingUID: uid,
      bindingId: uid.contains(':') ? uid.split(':').first : uid,
      label: json['label'] as String? ?? uid,
      flag: json['flag'] as String? ?? 'NEW',
      properties: Map<String, dynamic>.from(json['properties'] ?? {}),
      representationProperty: json['representationProperty'] as String?,
      bridgeUID: json['bridgeUID'] as String?,
    );
  }
}

class OHAddon {
  final String id;
  final String name;
  final String description;
  final String type;
  final String version;
  final bool installed;
  final String link;

  const OHAddon({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.version,
    required this.installed,
    required this.link,
  });

  factory OHAddon.fromJson(Map<String, dynamic> json) => OHAddon(
      id: json['uid'] ?? json['id'] ?? '', 
      name: json['label'] ?? json['id'] ?? '',
      description: json['description'] ?? '',
      type: json['type'] ?? '',
      version: json['version'] ?? '',
      installed: json['installed'] ?? false,
      link: json['link'] ?? '',
    );
}

class OpenHABManagementService {
  static final OpenHABManagementService _instance =
      OpenHABManagementService._internal();
  factory OpenHABManagementService() => _instance;
  OpenHABManagementService._internal();

  String _baseUrl = 'http://202.6.231.102:82';
  String? _apiToken;
  final _timeout = const Duration(seconds: 15);

  // ⚠️ FIX: sama seperti openhab_service.dart — pakai satu instance
  // http.Client() dipakai ulang (connection keep-alive), bukan fungsi
  // top-level http.get()/post() yang bikin koneksi baru tiap request.
  // Ini penyebab "loading lama tapi akhirnya jalan" yang muncul random di
  // banyak halaman management (Add Thing, Addon Store, dll).
  final http.Client _client = http.Client();

  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }


  void setApiToken(String? token) => _apiToken = token;

String? _basicAuth;        

void setBasicAuth(String username, String password) {
  final credentials = base64Encode(utf8.encode('$username:$password'));
  _basicAuth = 'Basic $credentials';
}

Map<String, String> get _headers => {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  if (_apiToken != null && _apiToken!.isNotEmpty)
    'Authorization': 'Bearer $_apiToken'
  else if (_basicAuth != null)
    'Authorization': _basicAuth!,
};

  Future<List<OHBinding>> getBindings() async {
    final res = await _client
        .get(Uri.parse('$_baseUrl/rest/addons?type=binding'), headers: _headers)
        .timeout(_timeout);
    if (res.statusCode != 200) throw _err('getBindings', res.statusCode);
    final data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => OHBinding.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Daftar binding ID yang mendukung Discovery (misal "wiz", "hue", "mqtt").
  Future<List<String>> getDiscoveryBindings() async {
    final res = await _client
        .get(Uri.parse('$_baseUrl/rest/discovery'), headers: _headers)
        .timeout(_timeout);
    if (res.statusCode != 200) throw _err('getDiscoveryBindings', res.statusCode);
    final data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => e.toString()).toList();
  }

  /// Memicu scan Discovery untuk satu binding. Scan berjalan async di
  /// server — hasil baru muncul di Inbox beberapa detik kemudian.
  Future<void> startScan(String bindingId) async {
    final res = await _client
        .post(
          Uri.parse('$_baseUrl/rest/discovery/bindings/$bindingId/scan'),
          // Endpoint scan membalas text/plain (durasi scan dalam detik), jadi
          // Accept: application/json ditolak openHAB dengan HTTP 406.
          headers: {
            'Accept': 'text/plain',
            if (_apiToken != null && _apiToken!.isNotEmpty)
              'Authorization': 'Bearer $_apiToken'
            else if (_basicAuth != null)
              'Authorization': _basicAuth!,
          },
        )
        .timeout(_timeout);
    if (res.statusCode != 200 && res.statusCode != 202 && res.statusCode != 204) {
      throw _err('startScan', res.statusCode, res.body);
    }
  }

  /// Semua entri di Inbox (hasil Discovery yang belum/sudah diproses).
  Future<List<OHInboxEntry>> getInboxEntries() async {
    final res = await _client
        .get(Uri.parse('$_baseUrl/rest/inbox'), headers: _headers)
        .timeout(_timeout);
    if (res.statusCode != 200) throw _err('getInboxEntries', res.statusCode);
    final data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => OHInboxEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Setujui satu entri Inbox → openHAB otomatis membuat Thing darinya.
  /// [label] opsional, dikirim sebagai body text/plain (nama tampilan Thing).
  Future<void> approveInboxEntry(String thingUID, {String? label}) async {
    final encoded = Uri.encodeComponent(thingUID);
    final res = await _client
        .post(
          Uri.parse('$_baseUrl/rest/inbox/$encoded/approve'),
          headers: {
            'Content-Type': 'text/plain',
            'Accept': 'application/json',
            if (_apiToken != null && _apiToken!.isNotEmpty)
              'Authorization': 'Bearer $_apiToken'
            else if (_basicAuth != null)
              'Authorization': _basicAuth!,
          },
          body: label ?? '',
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw _err('approveInboxEntry', res.statusCode, res.body);
    }
  }

  /// Tandai entri Inbox sebagai diabaikan (tidak muncul lagi di scan
  /// berikutnya, tapi tidak dihapus permanen).
  Future<void> ignoreInboxEntry(String thingUID) async {
    final encoded = Uri.encodeComponent(thingUID);
    final res = await _client
        .post(
          Uri.parse('$_baseUrl/rest/inbox/$encoded/ignore'),
          headers: _headers,
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw _err('ignoreInboxEntry', res.statusCode, res.body);
    }
  }

  /// Hapus permanen entri dari Inbox.
  Future<void> removeInboxEntry(String thingUID) async {
    final encoded = Uri.encodeComponent(thingUID);
    final res = await _client
        .delete(
          Uri.parse('$_baseUrl/rest/inbox/$encoded'),
          headers: _headers,
        )
        .timeout(_timeout);
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw _err('removeInboxEntry', res.statusCode, res.body);
    }
  }

  Future<List<OHThingType>> getThingTypes({String? bindingId}) async {
    String url = '$_baseUrl/rest/thing-types';
    if (bindingId != null && bindingId.isNotEmpty) {
      url += '?bindingId=$bindingId';
    }
    final res = await _client
        .get(Uri.parse(url), headers: _headers)
        .timeout(_timeout);
    if (res.statusCode != 200) throw _err('getThingTypes', res.statusCode);
    final data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => OHThingType.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<OHThingType?> getThingType(String uid) async {
    final encoded = Uri.encodeComponent(uid);
    final res = await _client
        .get(Uri.parse('$_baseUrl/rest/thing-types/$encoded'), headers: _headers)
        .timeout(_timeout);
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw _err('getThingType', res.statusCode);
    return OHThingType.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<OHThing>> getThings() async {
    final res = await _client
        .get(Uri.parse('$_baseUrl/rest/things'), headers: _headers)
        .timeout(_timeout);
    if (res.statusCode != 200) throw _err('getThings', res.statusCode);
    final data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => OHThing.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// [thingTypeUID]  contoh: "mqtt:broker" atau "hue:bridge"
  /// [uid]           optional — jika kosong openHAB generate otomatis
  /// [label]         nama tampilan
  /// [configuration] map parameter sesuai ThingType (misal: host, port)
  /// [bridgeUID]     optional UID bridge (untuk Things yang perlu bridge)
  Future<OHThing> addThing({
    required String thingTypeUID,
    required String label,
    String? uid,
    Map<String, dynamic> configuration = const {},
    String? bridgeUID,
  }) async {
    final body = <String, dynamic>{
      'thingTypeUID': thingTypeUID,
      'label': label,
      'configuration': configuration,
      'channels': [],
    };

    if (uid != null && uid.isNotEmpty) {
      body['UID'] = uid;
    }
    if (bridgeUID != null && bridgeUID.isNotEmpty) {
      body['bridgeUID'] = bridgeUID;
    }

    final res = await _client
        .post(
          Uri.parse('$_baseUrl/rest/things'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    if (res.statusCode == 200 || res.statusCode == 201) {
      return OHThing.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>);
    }
    throw _err('addThing', res.statusCode, res.body);
  }

  Future<OHThing> updateThing({
    required String uid,
    required String label,
    Map<String, dynamic> configuration = const {},
  }) async {
    final encoded = Uri.encodeComponent(uid);
    final body = {
      'label': label,
      'configuration': configuration,
    };

    final res = await _client
        .put(
          Uri.parse('$_baseUrl/rest/things/$encoded'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    if (res.statusCode == 200) {
      return OHThing.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>);
    }
    throw _err('updateThing', res.statusCode, res.body);
  }

  Future<bool> deleteThing(String uid) async {
    final encoded = Uri.encodeComponent(uid);
    final res = await _client
        .delete(Uri.parse('$_baseUrl/rest/things/$encoded'), headers: _headers)
        .timeout(_timeout);
    return res.statusCode == 200 || res.statusCode == 202;
  }

  Future<bool> linkChannelToItem({
    required String channelUID,
    required String itemName,
  }) async {
    final encoded = Uri.encodeComponent(channelUID);
    final res = await _client
        .put(
          Uri.parse('$_baseUrl/rest/links/$itemName/$encoded'),
          headers: _headers,
          body: jsonEncode({}),
        )
        .timeout(_timeout);
    return res.statusCode == 200;
  }

  Future<bool> unlinkChannel({
    required String channelUID,
    required String itemName,
  }) async {
    final encoded = Uri.encodeComponent(channelUID);
    final res = await _client
        .delete(
          Uri.parse('$_baseUrl/rest/links/$itemName/$encoded'),
          headers: _headers,
        )
        .timeout(_timeout);
    return res.statusCode == 200;
  }

Future<List<OHAddon>> getAddons({String? type}) async {
  String url = '$_baseUrl/rest/addons';
  if (type != null && type.isNotEmpty) url += '?type=$type';
  // ⚠️ FIX: baris ini sebelumnya nge-print SELURUH _headers (termasuk
  // "Authorization: Bearer <token>" atau "Basic <base64 user:pass>") ke
  // console log — di production ini bisa nyangkut di device log
  // (logcat/Console.app) atau crash-reporting tool. Dihapus total, bukan
  // cuma di-debugPrint, karena informasi ini memang tidak pernah boleh
  // di-log dalam bentuk apapun.
  final res = await _client
      .get(Uri.parse(url), headers: _headers)
      .timeout(_timeout);
  if (res.statusCode != 200) throw _err('getAddons', res.statusCode);
  
  final data = jsonDecode(res.body) as List<dynamic>;
  return data
      .map((e) => OHAddon.fromJson(e as Map<String, dynamic>))
      .toList();
}
Future<bool> installAddon(String addonId) async {
  final res = await _client
      .post(
        Uri.parse('$_baseUrl/rest/addons/$addonId/install'),
        headers: _headers,
      )
      .timeout(const Duration(seconds: 60));

  // debugPrint (bukan print) — otomatis di-strip di release build, dan
  // dipotong panjangnya biar log tidak berisi seluruh response body mentah.
  debugPrint('installAddon[$addonId] → ${res.statusCode}');
  return res.statusCode == 200 || res.statusCode == 202;
}

Future<bool> uninstallAddon(String addonId) async {
  final res = await _client
      .post(
        Uri.parse('$_baseUrl/rest/addons/$addonId/uninstall'),
        headers: _headers,
      )
      .timeout(const Duration(seconds: 60));

  debugPrint('uninstallAddon[$addonId] → ${res.statusCode}');
  return res.statusCode == 200 || res.statusCode == 202;
}

  /// [type]        Switch, Dimmer, Number, String, Color, Player, dll
  /// [name]        nama unik, hanya huruf/angka/underscore
  /// [label]       nama tampilan (bisa pakai format "%s" atau "%.1f °C")
  /// [category]    ikon kategori (Light, Temperature, dll)
  /// [groupNames]  list grup/lokasi tempat item ini berada
  /// [tags]        Semantic tags (Light, Sensor, dll)
  Future<bool> addOrUpdateItem({
  required String name,
  required String type,
  required String label,
  String? category,
  List<String> groupNames = const [],
  List<String> tags = const [],
  Map<String, dynamic>? stateDescription,
}) async {
  final body = <String, dynamic>{
    'name': name,
    'type': type,
    'label': label,
    if (category != null && category.isNotEmpty) 'category': category,
    'groupNames': groupNames,
    'tags': tags,
    if (stateDescription != null) 'stateDescription': stateDescription,
  };

  final res = await _client
      .put(
        Uri.parse('$_baseUrl/rest/items/$name'),
        headers: _headers,
        body: jsonEncode(body),
      )
      .timeout(_timeout);

  if (res.statusCode == 200 || res.statusCode == 201) return true;
  throw Exception(
    'Gagal membuat item (HTTP ${res.statusCode}): ${res.body}',
  );
}
  Future<bool> deleteItem(String itemName) async {
  final res = await _client
      .delete(
        Uri.parse('$_baseUrl/rest/items/$itemName'),
        headers: _headers,
      )
      .timeout(_timeout);
  return res.statusCode == 200 || res.statusCode == 202 || res.statusCode == 204;
}

  Future<List<OHItem>> getItems() async {
    final res = await _client
        .get(Uri.parse('$_baseUrl/rest/items?fields=name,type,label,state,category,tags,groupNames'),
            headers: _headers)
        .timeout(_timeout);
    if (res.statusCode != 200) throw _err('getItems', res.statusCode);
    final data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => OHItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
 
  Future<bool> sendCommand(String itemName, String command) async {
  final res = await _client
      .post(
        Uri.parse('$_baseUrl/rest/items/$itemName'),
        headers: {
          'Content-Type': 'text/plain',
          'Accept': 'application/json',
          if (_apiToken != null && _apiToken!.isNotEmpty)
            'Authorization': 'Bearer $_apiToken'
          else if (_basicAuth != null)
            'Authorization': _basicAuth!,
        },
        body: command,
      )
      .timeout(_timeout);
  return res.statusCode == 200 || res.statusCode == 201;
}

  Exception _err(String method, int code, [String? body]) {
    return Exception(
      '$method gagal (HTTP $code)${body != null && body.trim().isNotEmpty ? ': $body' : ''}',
    );
  }

  static const List<String> itemTypes = [
    'Switch',
    'Dimmer',
    'Number',
    'String',
    'Color',
    'Contact',
    'DateTime',
    'Image',
    'Location',
    'Player',
    'Rollershutter',
  ];

  static const List<String> itemCategories = [
    'Light',
    'Switch',
    'Temperature',
    'Humidity',
    'Motion',
    'Door',
    'Window',
    'Lock',
    'Fan',
    'Heating',
    'Cooling',
    'Energy',
    'Battery',
    'Sensor',
    'Camera',
    'Speaker',
    'Television',
    'Blinds',
    'Garage',
    'Garden',
  ];

  static const List<String> semanticTags = [
  'Equipment_Light',
  'Equipment_Switch', 
  'Equipment_Fan',
  'Equipment_HVAC',
  'Equipment_Lock',
  'Equipment_Television',
  'Equipment_Speaker',
  'Equipment_Camera',
  'Equipment_Door',
  'Equipment_Window',
  'Equipment_Blinds',
  'Equipment_PowerOutlet',
  'Equipment_Sensor',
  'Point_Control',
  'Point_Measurement',
  'Point_Switch',
  'Point_Setpoint',
  'Point_Alarm',
  'Point_Status',
  'Property_Temperature',
  'Property_Humidity',
  'Property_Light',
  'Property_Motion',
  'Property_Energy',
  'Property_Power',
  'Property_Voltage',
  'Property_Current',
  'Property_CO2',
  'Property_Smoke',
  'Property_Water',
  'Property_Wind',
  'Property_Rain',
  'Property_Noise',
  'Property_Pressure',
];
}

/// Kategori binding secara heuristik (client-side) berdasarkan
/// id/nama/deskripsi — openHAB sendiri tidak menyediakan field kategori
/// baku untuk binding, jadi ini best-effort supaya daftar binding yang
/// panjang bisa dikelompokkan & tidak perlu scroll banyak.
extension OHBindingCategory on OHBinding {
  String get category {
    final combined = '$id $name $description'.toLowerCase();

    bool any(List<String> keywords) => keywords.any(combined.contains);

    if (any(['light', 'hue', 'wiz', 'yeelight', 'lifx', 'nanoleaf', 'milight'])) {
      return 'Lighting';
    }
    if (any(['camera', 'onvif', 'rtsp', 'reolink', 'ipcamera', 'nest', 'ring', 'doorbird'])) {
      return 'Kamera & Keamanan';
    }
    if (any(['tv', 'sony', 'webos', 'lgwebos', 'chromecast', 'roku', 'sonos', 'spotify',
        'kodi', 'denon', 'yamaha', 'onkyo'])) {
      return 'Media & TV';
    }
    if (any(['energy', 'power', 'meter', 'solar', 'shelly', 'tasmota', 'sonoff', 'ewelink'])) {
      return 'Energi & Daya';
    }
    if (any(['mqtt', 'http', 'network', 'mdns', 'upnp', 'modbus', 'bluetooth',
        'zwave', 'zigbee', 'knx'])) {
      return 'Jaringan & Protokol';
    }
    if (any(['sensor', 'weather', 'xiaomi', 'netatmo', 'airquality', 'miio'])) {
      return 'Sensor';
    }
    if (any(['hub', 'bridge', 'gateway', 'homematic', 'deconz'])) {
      return 'Smart Hub';
    }
    return 'Lainnya';
  }
}