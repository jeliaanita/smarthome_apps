import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:mobile/core/controllers/openhab_controller.dart';
import 'package:mobile/core/providers/installation_provider.dart';

/// Ringkasan Item untuk kebutuhan pemetaan (bukan model utama aplikasi).
class MappingItem {
  final String name;
  final String label;
  final String type;
  final List<String> tags;
  final List<String> groupNames;

  const MappingItem({
    required this.name,
    required this.label,
    required this.type,
    required this.tags,
    required this.groupNames,
  });

  bool get isGroup => type == 'Group';

  factory MappingItem.fromJson(Map<String, dynamic> j) => MappingItem(
        name: j['name'] as String? ?? '',
        label: j['label'] as String? ?? '',
        type: j['type'] as String? ?? '',
        tags: List<String>.from(j['tags'] as List? ?? const []),
        groupNames: List<String>.from(j['groupNames'] as List? ?? const []),
      );
}

/// Service kecil khusus pemetaan Thing -> Channel -> Item -> Location/Equipment.
///
/// Sengaja berdiri sendiri (tidak mengubah OpenHABManagementService) supaya
/// aman ditambahkan. Auth memakai pola yang sama dengan FloorPlanPage.
class OpenHABMappingService {
  final String baseUrl;
  final Map<String, String> _headers;

  OpenHABMappingService._(this.baseUrl, this._headers);

  factory OpenHABMappingService.fromContext(BuildContext context) {
    final config = context.read<InstallationProvider>().config;
    var url = config?.openhabUrl ?? OpenHABController.instance.serverUrl;
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);

    final headers = <String, String>{'Accept': 'application/json'};
    if (config?.apiToken != null && config!.apiToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.apiToken}';
    } else if (config?.username != null && config?.password != null) {
      final enc =
          base64Encode(utf8.encode('${config!.username}:${config.password}'));
      headers['Authorization'] = 'Basic $enc';
    }
    return OpenHABMappingService._(url, headers);
  }

  static const _timeout = Duration(seconds: 15);

  Map<String, String> get _jsonHeaders =>
      {..._headers, 'Content-Type': 'application/json'};

  void _check(http.Response r, String what) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    final body = r.body.isNotEmpty ? ' - ${r.body}' : '';
    throw Exception('$what gagal (HTTP ${r.statusCode})$body');
  }

  /// Semua Item (ringkas) — dipakai untuk cek nama bentrok, daftar Equipment,
  /// dan pilihan "pakai Item yang sudah ada".
  Future<List<MappingItem>> fetchItems() async {
    final r = await http
        .get(
          Uri.parse(
              '$baseUrl/rest/items?fields=name,label,type,tags,groupNames'),
          headers: _headers,
        )
        .timeout(_timeout);
    _check(r, 'Memuat Item');
    return (jsonDecode(r.body) as List)
        .map((e) => MappingItem.fromJson(e as Map<String, dynamic>))
        .where((i) => i.name.isNotEmpty)
        .toList();
  }

  /// Buat / timpa Item. Dipakai untuk Group (Location/Equipment) maupun Point.
  Future<void> putItem({
    required String name,
    required String type,
    required String label,
    List<String> tags = const [],
    List<String> groupNames = const [],
    String? category,
  }) async {
    final body = {
      'type': type,
      'name': name,
      'label': label,
      'tags': tags,
      'groupNames': groupNames,
      if (category != null) 'category': category,
    };
    final r = await http
        .put(Uri.parse('$baseUrl/rest/items/${Uri.encodeComponent(name)}'),
            headers: _jsonHeaders, body: jsonEncode(body))
        .timeout(_timeout);
    _check(r, 'Membuat Item "$name"');
  }

  /// Masukkan Item yang SUDAH ada ke sebuah Group (Equipment/Location).
  Future<void> addMember(String groupName, String itemName) async {
    final r = await http
        .put(
          Uri.parse('$baseUrl/rest/items/${Uri.encodeComponent(groupName)}'
              '/members/${Uri.encodeComponent(itemName)}'),
          headers: _headers,
        )
        .timeout(_timeout);
    _check(r, 'Memasukkan "$itemName" ke "$groupName"');
  }

  /// Tautkan Channel Thing ke Item.
  Future<void> linkItem(String itemName, String channelUid) async {
    final body = {
      'itemName': itemName,
      'channelUID': channelUid,
      'configuration': <String, dynamic>{},
    };
    final r = await http
        .put(
          Uri.parse('$baseUrl/rest/links/${Uri.encodeComponent(itemName)}'
              '/${Uri.encodeComponent(channelUid)}'),
          headers: _jsonHeaders,
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    _check(r, 'Menautkan "$itemName"');
  }

  Future<void> unlinkItem(String itemName, String channelUid) async {
    final r = await http
        .delete(
          Uri.parse('$baseUrl/rest/links/${Uri.encodeComponent(itemName)}'
              '/${Uri.encodeComponent(channelUid)}'),
          headers: _headers,
        )
        .timeout(_timeout);
    _check(r, 'Melepas link "$itemName"');
  }
}
