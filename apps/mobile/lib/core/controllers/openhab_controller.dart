import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mobile/core/services/installation_service.dart';
import '../models/openhab_item.dart';
import '../services/openhab_service.dart';
import '../services/openhab_management_service.dart' show OHThing, OpenHABManagementService;
import '../config/openhab_config.dart';

class OpenHABController extends ChangeNotifier {
  OpenHABController._();
  static final instance = OpenHABController._();
  final _service = OpenHABService();
  final _mgmt    = OpenHABManagementService();

  List<OpenHABItem>            _items     = [];
  List<Map<String, dynamic>>   _locations = [];
  List<Map<String, dynamic>>   _allGroups = [];
  List<OHThing>                _things    = [];
  bool    _isLoading                      = false;
  bool    _isConnected                    = false;
  String? _error;
  String  _serverUrl                      = OpenHABConfig.defaultUrl;
  StreamSubscription<Map<String, dynamic>>? _eventSub;

  List<OpenHABItem>          get items       => _items;
  List<Map<String, dynamic>> get locations   => _locations;
  bool                       get isLoading   => _isLoading;
  bool                       get isConnected => _isConnected;
  String?                    get error       => _error;
  String                     get serverUrl   => _serverUrl;
  bool                       get hasItems    => _items.isNotEmpty;

  /// Header Authorization yang sama dipakai semua request REST openHAB —
  /// diteruskan ke video player supaya request stream HLS/MJPEG kamera
  /// juga bawa kredensial yang sama, bukan request "polos" tanpa auth.
  Map<String, String> get authHeaders => _service.authHeaders;
  bool                       get hasLocations => _locations.isNotEmpty;

  List<OHThing> get things => _things;

  /// Thing dianggap "kamera" kalau bindingnya "ipcamera" (binding IP Camera
  /// paling umum dipakai di openHAB), ATAU punya minimal 1 channel bertipe
  /// Image (snapshot) — supaya tetap kedeteksi walau pakai binding kamera
  /// lain yang formatnya beda.
  bool _isCameraThing(OHThing t) =>
      t.thingTypeUID.startsWith('ipcamera:') ||
      t.channels.any((c) => c.itemType == 'Image');

  List<OHThing> get cameraThings =>
      _things.where(_isCameraThing).toList();

  bool get hasCameraThings => cameraThings.isNotEmpty;

  /// Grup AC hasil auto-discovery lewat pola penamaan Item openHAB — Item
  /// generator openHAB otomatis menamai Point sebagai "NamaGroup + label
  /// channel dg spasi->underscore", jadi tiap unit AC (Group Equipment
  /// apapun namanya) selalu punya pola akhiran yang sama persis karena
  /// semua unit AC pakai Thing template MQTT yang sama (lihat channel
  /// POWER_AC/MODE_AC/FAN_AC/dst di file .things). Deteksi generik ini
  /// dipicu dari Item "_AC_Power" (Switch) — begitu unit AC baru
  /// ditambahkan di openHAB dengan pola sama, otomatis kebaca di app
  /// tanpa perlu ubah kode.
  List<OHAcUnit> get acUnits {
    final powerItems =
        _items.where((i) => i.isSwitch && i.name.endsWith('_AC_Power'));
    final units = <OHAcUnit>[];

    for (final p in powerItems) {
      final prefix = p.name.substring(0, p.name.length - '_AC_Power'.length);

      String? find(String suffix) {
        final name = '$prefix$suffix';
        return getItem(name) != null ? name : null;
      }

      final group = _allGroups.firstWhere(
        (g) => g['name'] == prefix,
        orElse: () => <String, dynamic>{},
      );
      final groupLabel = group['label'] as String?;
      final label = (groupLabel != null && groupLabel.isNotEmpty)
          ? groupLabel
          : prefix.replaceAll('_', ' ');

      units.add(OHAcUnit(
        id: prefix,
        label: label,
        powerItem: p.name,
        modeItem: find('_AC_Mode'),
        fanItem: find('_AC_Fan'),
        setTempItem: find('_AC_Set_Temperature'),
        stateModeItem: find('_AC_State_Mode'),
        stateFanItem: find('_AC_State_Fan'),
        roomTempItem: find('_Room_Temperature'),
        roomHumidityItem: find('_Room_Humidity'),
        statusItem: find('_Status_Device'),
      ));
    }
    return units;
  }

  bool get hasAcUnits => acUnits.isNotEmpty;

  /// Cari label lokasi (Room) sebuah Thing lewat Semantic Model — Thing
  /// hasil auto-discovery biasanya nggak punya field "location" mentah
  /// terisi, tapi Item yang di-link ke channel-nya biasanya jadi anggota
  /// sebuah Group yang di-tag Location. Ditelusuri dengan pola yang sama
  /// kayak getItemsForLocation: dari nama Item, naik ke Group leluhurnya,
  /// dicocokkan ke salah satu _locations. Return null kalau nggak ketemu.
  String? locationForThing(OHThing thing) {
    final linkedNames = <String>{
      for (final ch in thing.channels) ...ch.linkedItems,
    };
    if (linkedNames.isEmpty) return null;

    for (final loc in _locations) {
      final locName = loc['name'] as String?;
      if (locName == null || locName.isEmpty) continue;
      final descendantGroups = getDescendantGroupNames(locName);

      for (final itemName in linkedNames) {
        // Item point biasa (Switch/Image/dll) ada di _items; kalau
        // channel di-link ke Group (Equipment), ceknya di _allGroups.
        final item = getItem(itemName);
        final itemGroupNames = item?.groupNames ??
            (_allGroups.firstWhere(
                  (g) => g['name'] == itemName,
                  orElse: () => <String, dynamic>{},
                )['groupNames'] as List<dynamic>? ??
                [])
                .cast<String>();

        if (itemGroupNames.any((g) => descendantGroups.contains(g))) {
          final label = loc['label'] as String?;
          return (label != null && label.isNotEmpty) ? label : locName;
        }
      }
    }
    return null;
  }

  /// ID kamera yang dipakai binding IP Camera di path URL-nya sendiri —
  /// TERBUKTI lewat tes manual di browser: UID Thing PENUH
  /// ("ipcamera:onvif:xxxx") menghasilkan 404 "Not Found", sedangkan ID
  /// pendek (cuma segmen terakhir setelah titik dua) berhasil dikenali
  /// sebagai file video oleh browser. Jangan diubah balik ke thing.uid
  /// tanpa tes ulang manual dulu.
  String _cameraId(OHThing thing) => thing.uid.split(':').last;

  /// URL stream MJPEG dari binding IP Camera openHAB — binding ini
  /// menyediakan proxy servlet bawaan di path ini, dikonstruksi langsung
  /// dari server URL + ID kamera (bukan dari state Item manapun).
  String cameraMjpegUrl(OHThing thing) =>
      '$_serverUrl/ipcamera/${_cameraId(thing)}/ipcamera.mjpeg';

  /// URL live stream HLS (.m3u8) — path sama seperti cameraMjpegUrl, cuma
  /// ekstensi beda, sesuai dokumentasi resmi binding IP Camera openHAB.
  String cameraHlsUrl(OHThing thing) =>
      '$_serverUrl/ipcamera/${_cameraId(thing)}/ipcamera.m3u8';

  /// URL snapshot statis (.jpg) — dipakai kalau live stream belum/tidak
  /// tersedia tapi snapshot masih bisa diambil.
  String cameraSnapshotUrl(OHThing thing) =>
      '$_serverUrl/ipcamera/${_cameraId(thing)}/ipcamera.jpg';

  /// Cari nama Item yang di-link ke channel tertentu pada sebuah Thing.
  /// Dipakai untuk nemuin Item di balik channel "startStream" dkk tanpa
  /// perlu tau namanya di muka (bisa beda-beda tiap instalasi openHAB).
  String? _linkedItemForChannel(OHThing thing, String channelId) {
    for (final ch in thing.channels) {
      if (ch.id == channelId && ch.linkedItems.isNotEmpty) {
        return ch.linkedItems.first;
      }
    }
    return null;
  }

  /// Nyalakan channel "startStream" binding IP Camera sebelum mencoba
  /// memutar HLS/MJPEG — binding ini baru mulai generate file .m3u8/.mjpeg
  /// via FFmpeg SETELAH channel ini di-ON-kan, jadi request ke URL stream
  /// sebelum ini dipicu akan selalu gagal (file belum ada di server).
  /// Return true kalau berhasil kirim command (channel+item ketemu), false
  /// kalau channel/Item-nya tidak ditemukan — dipakai UI untuk kasih pesan
  /// error yang lebih spesifik ("channel belum di-link") ketimbang cuma
  /// "gagal memutar video" generik yang menyesatkan (seolah masalah di
  /// video player, padahal FFmpeg-nya belum pernah dipicu jalan).
  Future<bool> startCameraStream(OHThing thing) async {
    final itemName = _linkedItemForChannel(thing, 'startStream');
    if (itemName == null) return false;
    try {
      await sendCommand(itemName, 'ON');
      return true;
    } catch (e) {
      debugPrint('startCameraStream warning: $e');
      return false;
    }
  }

  String get primaryLocationName {
    if (_locations.isEmpty) return 'My Home';
    final label = _locations.first['label'] as String?;
    final name  = _locations.first['name']  as String?;
    if (label != null && label.isNotEmpty) return label;
    return _formatLocationName(name ?? 'My Home');
  }

  String get primaryLocationShortName {
    if (_locations.isEmpty) return 'Home';
    final name = _locations.first['name'] as String?;
    return name ?? 'Home';
  }

  List<String> get locationNames {
    return _locations.map((loc) {
      final label = loc['label'] as String?;
      final name  = loc['name']  as String?;
      if (label != null && label.isNotEmpty) return label;
      return _formatLocationName(name ?? 'Unknown');
    }).toList();
  }

  String _formatLocationName(String name) {
    return name.replaceAllMapped(
      RegExp(r'(?<=[a-z])([A-Z])'),
      (m) => ' ${m[0]}',
    );
  }

  Set<String> getDescendantGroupNames(String locationName) {
    final result  = <String>{locationName};
    bool  changed = true;

    while (changed) {
      changed = false;
      for (final group in _allGroups) {
        final name       = group['name']       as String? ?? '';
        final groupNames = List<String>.from(group['groupNames'] ?? []);
        if (groupNames.any((g) => result.contains(g)) &&
            !result.contains(name)) {
          result.add(name);
          changed = true;
        }
      }
    }

    return result;
  }
  List<OpenHABItem> getItemsForLocation(String locationName) {
    final groupNames = getDescendantGroupNames(locationName);
    return _items.where((item) {
      if (item.type == 'Group') return false;
      return item.groupNames.any((g) => groupNames.contains(g));
    }).toList();
  }

  List<OpenHABItem> get switchItems  => _items.where((i) => i.isSwitch).toList();
  List<OpenHABItem> get dimmerItems  => _items.where((i) => i.isDimmer).toList();
  List<OpenHABItem> get numberItems  => _items.where((i) => i.isNumber).toList();
  List<OpenHABItem> get colorItems   => _items.where((i) => i.isColor).toList();
  List<OpenHABItem> get stringItems  => _items.where((i) => i.isString).toList();
  List<OpenHABItem> get playerItems  => _items.where((i) => i.type == 'Player').toList();

  List<OpenHABItem> switchItemsForLocation(String locationName) =>
      getItemsForLocation(locationName).where((i) => i.isSwitch).toList();

  List<OpenHABItem> dimmerItemsForLocation(String locationName) =>
      getItemsForLocation(locationName).where((i) => i.isDimmer).toList();

  List<OpenHABItem> playerItemsForLocation(String locationName) =>
      getItemsForLocation(locationName).where((i) => i.type == 'Player').toList();

  List<OpenHABItem> lampItemsForLocation(String locationName) =>
      getItemsForLocation(locationName).where((i) {
        final combined = '${i.name} ${i.label}'.toLowerCase();
        return combined.contains('light') || combined.contains('lamp');
      }).toList();

  OpenHABItem? getItem(String name) {
    try {
      return _items.firstWhere((i) => i.name == name);
    } catch (_) {
      return null;
    }
  }

  OpenHABItem? findItem(String keyword) {
    final kw = keyword.toLowerCase();
    try {
      return _items.firstWhere(
        (i) => i.name.toLowerCase().contains(kw) ||
               i.label.toLowerCase().contains(kw),
      );
    } catch (_) {
      return null;
    }
  }

  /// Fallback kalau dipanggil tanpa InstallationConfig (jarang terjadi —
  /// lihat pemanggil di hub_connectivity_page.dart yang selalu prioritaskan
  /// initializeWithConfig() dulu kalau config tersedia). Karena kredensial
  /// tidak lagi disimpan di OpenHABConfig (lihat catatan keamanan di
  /// openhab_config.dart), fallback ini connect tanpa auth. Kalau server
  /// butuh login, pemanggil harus pakai initializeWithConfig(config).
  Future<void> initialize() async {
    _serverUrl = await OpenHABConfig.getBaseUrl();
    _service.setBaseUrl(_serverUrl);
    _mgmt.setBaseUrl(_serverUrl);

    _isConnected = await _service.isServerReachable();
    notifyListeners();

    if (_isConnected) {
      await Future.wait([
        loadItems(),
        loadLocations(),
        loadThings(),
      ]);
      _startRealTimeUpdates();
    } else {
      _error = 'Tidak dapat terhubung ke openHAB server.\nPastikan server menyala dan URL benar.';
      notifyListeners();
    }
  }

  Future<void> initializeWithConfig(InstallationConfig config) async {
  _serverUrl = config.openhabUrl;
  _service.setBaseUrl(_serverUrl);
  _mgmt.setBaseUrl(_serverUrl);
 
  if (config.apiToken != null && config.apiToken!.isNotEmpty) {
    _service.setApiToken(config.apiToken!);
    _mgmt.setApiToken(config.apiToken!);
  } else if (config.username != null && config.password != null) {
    _service.setBasicAuth(config.username!, config.password!);
    _mgmt.setBasicAuth(config.username!, config.password!);
    // pastikan OpenHABService.setBasicAuth ada; kalau belum ada,
    // tambahkan method serupa yang dipakai di OpenHABManagementService
  }
 
  _isConnected = await _service.isServerReachable();
  notifyListeners();
 
  if (_isConnected) {
    await Future.wait([
      loadItems(),
      loadLocations(),
      loadThings(),
    ]);
    _startRealTimeUpdates();
  } else {
    _error = 'Tidak dapat terhubung ke openHAB server.\nPastikan server menyala dan URL benar.';
    notifyListeners();
  }
}

void resetConnection() {
  _eventSub?.cancel();
  _isConnected = false;
  _items = [];
  _locations = [];
  _allGroups = [];
  _things = [];
  _error = 'Akun ini belum terhubung ke server openHAB manapun.';
  _serverUrl = '';
  notifyListeners();
}

  /// Muat ulang SEMUA data (Items, Groups, Locations, Things) lalu sambungkan
  /// ulang stream real-time. Dipakai refresh manual, app kembali aktif,
  /// setelah simpan Thing/Item/Room, dan saat koneksi pulih — tanpa perlu
  /// sign out / force close (QC 08). Berurutan: loadItems dulu karena
  /// loadLocations menambahkan ke _allGroups yang ditimpa loadItems.
  Future<void> refresh() async {
    if (_serverUrl.isEmpty) return;
    _isConnected = await _service.isServerReachable();
    notifyListeners();
    if (!_isConnected) {
      _error = 'Tidak dapat terhubung ke openHAB server.\nPastikan server menyala dan URL benar.';
      notifyListeners();
      return;
    }
    await loadItems();
    await Future.wait([loadLocations(), loadThings()]);
    _startRealTimeUpdates();
  }

  /// Hubungkan ulang dengan konfigurasi baru (URL + token/user/password).
  /// updateServerUrl() hanya mengganti URL — kredensial baru TIDAK ikut
  /// terpasang di service, jadi login ke server berkredensial baru gagal
  /// sampai sign out / force close. Pakai ini saat konfigurasi disimpan.
  Future<bool> reconnectWithConfig(InstallationConfig config) async {
    await _eventSub?.cancel();
    _isConnected = false;
    _items = [];
    _locations = [];
    _allGroups = [];
    _things = [];
    _error = null;
    notifyListeners();
    await initializeWithConfig(config);
    return _isConnected;
  }

  Timer? _reloadDebounce;

  /// Item ditambah/dihapus/diubah di server → muat ulang (debounce 1,5 dtk
  /// karena openHAB mengirim banyak event beruntun saat import/generate).
  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 1500), () async {
      await loadItems();
      await loadLocations();
    });
  }

  Future<void> loadItems() async {
    // Spinner hanya saat pertama kali (belum ada data). Refresh berikutnya
    // diam-diam, supaya grid tidak berkedip jadi loading tiap 15 detik.
    _isLoading = _items.isEmpty;
    _error = null;
    notifyListeners();

    try {
      final all = await _service.getItems();
      _allGroups = all
          .where((i) => i.type == 'Group')
          .map((i) => <String, dynamic>{
                'name':       i.name,
                'label':      i.label,
                'type':       i.type,
                'groupNames': i.groupNames,
                'tags':       i.tags,
              })
          .toList();
      _items = all.where((i) => i.type != 'Group').toList();

    } on OpenHABException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Terjadi kesalahan: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fitur kamera bersifat opsional/bonus — kalau gagal (mis. server tidak
  /// expose /rest/things, atau user tidak punya izin), JANGAN sampai
  /// menggagalkan koneksi utama (items/locations tetap harus jalan).
  Future<void> loadThings() async {
    try {
      _things = await _mgmt.getThings();
      notifyListeners();
    } catch (e) {
      debugPrint('loadThings warning (non-fatal): $e');
    }
  }

  Future<void> loadLocations() async {
    try {
      final raw = await _service.getLocations();

      _locations = raw.where((loc) {
        final tags = List<String>.from(loc['tags'] ?? []);
        final type = loc['type'] as String? ?? '';

        return type == 'Group' && tags.any((t) =>
            t.toLowerCase().contains('location') ||
            t.toLowerCase().contains('room') ||
            t.toLowerCase().contains('floor') ||
            t.toLowerCase().contains('building') ||
            t.toLowerCase().contains('indoor') ||
            t.toLowerCase().contains('outdoor') ||
            t.toLowerCase().contains('corridor') ||
            t.toLowerCase().contains('garage') ||
            t.toLowerCase().contains('garden') ||
            t.toLowerCase().contains('terrace') ||
            t.toLowerCase().contains('office') ||
            t.toLowerCase().contains('cellar') ||
            t.toLowerCase().contains('bedroom') ||
            t.toLowerCase().contains('kitchen') ||
            t.toLowerCase().contains('bathroom') ||
            t.toLowerCase().contains('livingroom')
        );
      }).toList();

      _locations = _locations.map((loc) {
        final label = loc['label'] as String?;
        final name  = loc['name']  as String? ?? '';
        if (label == null || label.isEmpty) {
          return {
            ...loc,
            'label': _formatLocationName(name),
          };
        }
        return loc;
      }).toList();
      for (final loc in _locations) {
        final name = loc['name'] as String?;
        if (name != null && !_allGroups.any((g) => g['name'] == name)) {
          _allGroups.add(loc);
        }
      }

      notifyListeners();
    } catch (e) {
      if (_items.isNotEmpty) {
        _locations = _inferLocationsFromItems();
        notifyListeners();
      }
      debugPrint('loadLocations warning: $e');
    }
  }

  List<Map<String, dynamic>> _inferLocationsFromItems() {
    final groupSet = <String>{};
    for (final item in _items) {
      for (final g in item.groupNames) {
        groupSet.add(g);
      }
    }

    return groupSet.map((name) {
      return <String, dynamic>{
        'name': name,
        'label': _formatLocationName(name),
        'type': 'Group',
        'tags': ['Location'],
      };
    }).toList();
  }

  /// Command transport (bukan representasi state target) untuk tipe
  /// tertentu — mengirim command ini TIDAK boleh langsung menimpa state
  /// lokal, karena command-nya bukan nilai state akhir yang valid.
  /// Contoh: Player "NEXT" tidak membuat state item jadi "NEXT"; itu cuma
  /// aksi transport. State sebenarnya datang lewat event real-time.
  bool _isTransportCommand(OpenHABItem item, String command) {
    final cmd = command.toUpperCase();
    if (item.isPlayer) {
      return ['NEXT', 'PREVIOUS', 'REWIND', 'FASTFORWARD'].contains(cmd);
    }
    if (item.isRollershutter) {
      return ['UP', 'DOWN', 'STOP', 'MOVE'].contains(cmd);
    }
    return false;
  }

  Future<void> sendCommand(String itemName, String command) async {
    final idx  = _items.indexWhere((i) => i.name == itemName);
    String? prev;
    final canOptimisticUpdate =
        idx != -1 && !_isTransportCommand(_items[idx], command);

    if (canOptimisticUpdate) {
      prev = _items[idx].state;
      _items[idx] = _items[idx].copyWith(state: command);
      notifyListeners();
    }

    try {
      final ok = await _service.sendCommand(itemName, command);
      if (!ok) throw Exception('Command tidak diterima server');
    } catch (_) {
      if (canOptimisticUpdate && prev != null) {
        _items[idx] = _items[idx].copyWith(state: prev);
        notifyListeners();
      }
    }
  }

  Future<void> toggleItem(String itemName) async {
    final item = getItem(itemName);
    if (item == null) return;
    // Cegah kirim command ON/OFF ke tipe yang bukan Switch (mis. Contact
    // sensor pintu/jendela yang read-only) — mencegah command salah kirim
    // ke sensor yang seharusnya cuma dibaca statusnya.
    if (!item.isSwitch) return;
    await sendCommand(itemName, item.isOn ? 'OFF' : 'ON');
  }

  Future<void> setBrightness(String itemName, int value) async {
    await sendCommand(itemName, value.clamp(0, 100).toString());
  }

  Future<void> setTemperature(String itemName, double temp) async {
    await sendCommand(itemName, temp.toString());
  }

  Future<bool> updateServerUrl(String newUrl) async {
    if (!OpenHABConfig.isValidUrl(newUrl)) return false;

    await OpenHABConfig.setBaseUrl(newUrl);
    _serverUrl = newUrl;
    _service.setBaseUrl(newUrl);
    _mgmt.setBaseUrl(newUrl);

    await _eventSub?.cancel();
    _isConnected = false;
    _items       = [];
    _locations   = [];
    _allGroups   = [];
    _things      = [];
    _error       = null;
    notifyListeners();

    await initialize();
    return _isConnected;
  }

  void _startRealTimeUpdates() {
    _eventSub?.cancel();
    void reconnect() {
      Future.delayed(const Duration(seconds: 5), () {
        if (_isConnected) _startRealTimeUpdates();
      });
    }

    _eventSub = _service.streamEvents().listen(
      _handleEvent,
      onError: (e) => reconnect(),
      // Stream yang ditutup diam-diam (mis. iOS memutus koneksi saat app
      // di background) sebelumnya tidak pernah tersambung lagi.
      onDone: reconnect,
      cancelOnError: true,
    );
  }

  void _handleEvent(Map<String, dynamic> event) {
    final topic = event['topic'] as String? ?? '';
    final parts = topic.split('/');
    if (parts.length < 4) return;

    // Perubahan struktur Item (tambah/hapus/ubah) → sinkronkan ulang.
    if (parts[1] == 'items' &&
        (parts[3] == 'added' || parts[3] == 'removed' || parts[3] == 'updated')) {
      _scheduleReload();
      return;
    }

    final itemName   = parts[2];
    final rawPayload = event['payload'];

    String? newState;
    try {
      final payload = rawPayload is String
          ? jsonDecode(rawPayload) as Map<String, dynamic>
          : rawPayload as Map<String, dynamic>;
      newState = payload['value']?.toString();
    } catch (_) {
      return;
    }

    if (newState == null) return;

    final idx = _items.indexWhere((i) => i.name == itemName);
    if (idx != -1) {
      _items[idx] = _items[idx].copyWith(state: newState);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }
}

extension OpenHABItemIcon on OpenHABItem {
  String get iconKey {
    final n = name.toLowerCase();
    final l = label.toLowerCase();
    final c = (category ?? '').toLowerCase();
    final combined = '$n $l $c';

    if (combined.contains('light') || combined.contains('lamp') || combined.contains('bulb')) {
      return 'lightbulb';
    }
    if (combined.contains('ac') || combined.contains('aircond') || combined.contains('air_cond')) {
      return 'ac';
    }
    if (combined.contains('temp') || combined.contains('thermostat')) {
      return 'temperature';
    }
    if (combined.contains('tv') || combined.contains('television')) {
      return 'tv';
    }
    if (combined.contains('speaker') || combined.contains('audio') || combined.contains('homepod')) {
      return 'speaker';
    }
    if (combined.contains('door') || combined.contains('window') || combined.contains('lock')) {
      return 'door';
    }
    if (combined.contains('fan') || combined.contains('ventilation')) {
      return 'fan';
    }
    if (combined.contains('camera') || combined.contains('cctv')) {
      return 'camera';
    }
    if (combined.contains('sensor') || combined.contains('motion')) {
      return 'sensor';
    }
    if (combined.contains('media') || combined.contains('player')) {
      return 'player';
    }
    if (isSwitch) return 'switch';
    if (isDimmer) return 'dimmer';
    if (isColor) return 'color';
    if (isString) return looksLikeRemoteButton ? 'remote' : 'command';
    if (isNumber) return 'number';
    return 'device';
  }

  String get roomGuess {
    if (groupNames.isEmpty) return 'Home';
    final g = groupNames.first;
    return g.replaceAllMapped(
      RegExp(r'(?<=[a-z])([A-Z])'),
      (m) => ' ${m[0]}',
    );
  }
}

/// Satu unit AC hasil auto-discovery (lihat OpenHABController.acUnits).
/// Field selain [id]/[label]/[powerItem] bisa null kalau Item-nya belum
/// di-link ke channel yang bersangkutan di openHAB.
class OHAcUnit {
  final String id;
  final String label;
  final String powerItem;
  final String? modeItem;
  final String? fanItem;
  final String? setTempItem;
  final String? stateModeItem;
  final String? stateFanItem;
  final String? roomTempItem;
  final String? roomHumidityItem;
  final String? statusItem;

  const OHAcUnit({
    required this.id,
    required this.label,
    required this.powerItem,
    this.modeItem,
    this.fanItem,
    this.setTempItem,
    this.stateModeItem,
    this.stateFanItem,
    this.roomTempItem,
    this.roomHumidityItem,
    this.statusItem,
  });
}