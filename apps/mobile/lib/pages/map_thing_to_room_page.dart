import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/core/controllers/openhab_controller.dart';
import 'package:mobile/core/providers/installation_provider.dart';
import 'package:mobile/core/providers/role_provider.dart';
import 'package:mobile/core/services/openhab_management_service.dart';
import 'package:mobile/core/services/openhab_mapping_service.dart';
import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/core/utils/responsive_utils.dart';
import 'package:mobile/core/widget/access_denied_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Konstanta semantic model
// ─────────────────────────────────────────────────────────────────────────────

/// Kelas Equipment openHAB -> label Indonesia.
const Map<String, String> kEquipmentTags = {
  'Lightbulb': 'Lampu',
  'WallSwitch': 'Saklar',
  'PowerOutlet': 'Stop Kontak',
  'Blinds': 'Tirai / Rolling',
  'Fan': 'Kipas',
  'AirConditioner': 'AC',
  'Camera': 'Kamera',
  'Television': 'TV',
  'Speaker': 'Speaker',
  'Sensor': 'Sensor',
};

/// Tag Point (Control / Measurement / Status) berdasarkan tipe Item.
List<String> _pointTags(String itemType) {
  final base = itemType.split(':').first;
  switch (base) {
    case 'Switch':
    case 'Dimmer':
    case 'Color':
    case 'Rollershutter':
    case 'Player':
      return ['Control'];
    case 'Number':
      return ['Measurement'];
    case 'Contact':
    case 'String':
    case 'DateTime':
      return ['Status'];
    default:
      return const [];
  }
}

String _suggestEquipmentTag(OHThing t) {
  final types = t.channels.map((c) => c.itemType.split(':').first).toSet();
  if (t.thingTypeUID.toLowerCase().contains('camera')) return 'Camera';
  if (types.contains('Rollershutter')) return 'Blinds';
  if (types.contains('Dimmer') || types.contains('Color')) return 'Lightbulb';
  return '';
}

String _sanitize(String s) {
  var r = s
      .replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (r.isEmpty) r = 'X';
  if (RegExp(r'^[0-9]').hasMatch(r)) r = '_$r';
  return r;
}

String _unique(String base, Set<String> taken) {
  if (!taken.contains(base)) return base;
  var i = 2;
  while (taken.contains('${base}_$i')) {
    i++;
  }
  return '${base}_$i';
}

// ─────────────────────────────────────────────────────────────────────────────
// Model lokal
// ─────────────────────────────────────────────────────────────────────────────

class _Room {
  final String name;
  final String label;
  const _Room(this.name, this.label);
}

class _ChannelRow {
  final String uid; // thingUID:channelId
  final String shortId;
  final String label;
  final String itemType;
  final bool mappable; // trigger channel (tanpa itemType) tidak bisa di-link
  bool alreadyLinked;
  bool selected;
  String? existingItem; // null = buat Item baru
  final TextEditingController nameCtrl = TextEditingController();

  _ChannelRow({
    required this.uid,
    required this.shortId,
    required this.label,
    required this.itemType,
    required this.mappable,
    required this.alreadyLinked,
    required this.selected,
  });
}

enum _EquipMode { create, existing, none }

// ─────────────────────────────────────────────────────────────────────────────
// Halaman wizard
// ─────────────────────────────────────────────────────────────────────────────

/// Alur: pilih Channel -> pilih Ruangan (Location) -> pilih/buat Equipment
/// -> simpan (buat Item + link Channel + masukkan ke semantic model).
/// Hasilnya langsung muncul di Floorplan karena Floorplan membaca semantic
/// model yang sama. `Navigator.pop(context, true)` kalau ada yang tersimpan.
class MapThingToRoomPage extends StatefulWidget {
  final OHThing thing;

  /// Nama (name, bukan label) Location yang dipilih awal — dipakai saat
  /// dibuka dari Floorplan supaya ruangan langsung terpilih.
  final String? initialLocationName;

  const MapThingToRoomPage({
    super.key,
    required this.thing,
    this.initialLocationName,
  });

  @override
  State<MapThingToRoomPage> createState() => _MapThingToRoomPageState();
}

class _MapThingToRoomPageState extends State<MapThingToRoomPage> {
  late final OpenHABMappingService _svc;
  final _ctrl = OpenHABController.instance;
  final _equipNameCtrl = TextEditingController();

  late final List<_ChannelRow> _rows;
  final List<_Room> _rooms = [];
  List<MappingItem> _items = [];

  String? _roomName;
  _EquipMode _equipMode = _EquipMode.create;
  String _equipTag = '';
  String? _existingEquip;

  bool _loading = true;
  bool _submitting = false;
  bool _savedAny = false;
  String? _error;

  String get _thingTitle =>
      widget.thing.label.isNotEmpty ? widget.thing.label : widget.thing.uid;

  @override
  void initState() {
    super.initState();
    _svc = OpenHABMappingService.fromContext(context);
    _equipNameCtrl.text = _thingTitle;
    _equipTag = _suggestEquipmentTag(widget.thing);

    _rows = widget.thing.channels.map((ch) {
      final uid = ch.id.contains(':') ? ch.id : '${widget.thing.uid}:${ch.id}';
      final mappable = ch.itemType.isNotEmpty;
      final linked = ch.linkedItems.isNotEmpty;
      return _ChannelRow(
        uid: uid,
        shortId: ch.id.split(':').last.replaceAll('#', '_'),
        label: ch.label.isNotEmpty ? ch.label : ch.id,
        itemType: ch.itemType,
        mappable: mappable,
        alreadyLinked: linked,
        selected: mappable && !linked,
      );
    }).toList();

    _load();
  }

  @override
  void dispose() {
    _equipNameCtrl.dispose();
    for (final r in _rows) {
      r.nameCtrl.dispose();
    }
    super.dispose();
  }

  String _clean(Object e) => e
      .toString()
      .replaceFirst(RegExp(r'^(OpenHABException|Exception):\s*'), '');

  Future<void> _load() async {
    try {
      final items = await _svc.fetchItems();
      final rooms = <_Room>[];
      for (final l in _ctrl.locations) {
        final m = Map<String, dynamic>.from(l as Map);
        final n = m['name'] as String? ?? '';
        if (n.isEmpty) continue;
        final lbl = m['label'] as String?;
        rooms.add(_Room(n, (lbl != null && lbl.isNotEmpty) ? lbl : n));
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _rooms
          ..clear()
          ..addAll(rooms);
        final init = widget.initialLocationName;
        if (init != null && rooms.any((r) => r.name == init)) {
          _roomName = init;
        }
        _syncEquipmentMode();
      });
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Helper data ────────────────────────────────────────────────────────────

  Set<String> get _takenNames => _items.map((e) => e.name).toSet();

  List<MappingItem> get _roomEquipment => _items
      .where((i) =>
          i.isGroup &&
          _roomName != null &&
          i.groupNames.contains(_roomName) &&
          i.tags.any(kEquipmentTags.containsKey))
      .toList();

  /// Jika ruangan sudah punya Equipment, default ke "pilih yang ada".
  void _syncEquipmentMode() {
    if (_equipMode == _EquipMode.existing &&
        !_roomEquipment.any((e) => e.name == _existingEquip)) {
      _existingEquip = null;
    }
  }

  List<MappingItem> _compatibleItems(_ChannelRow r) {
    final base = r.itemType.split(':').first;
    return _items
        .where((i) => !i.isGroup && i.type.split(':').first == base)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Nama Item final per baris (otomatis, atau ketikan user).
  Map<_ChannelRow, String> _plannedNames() {
    final out = <_ChannelRow, String>{};
    if (_roomName == null) return out;
    final taken = _takenNames.toSet();
    for (final r in _rows.where((r) => r.selected && r.existingItem == null)) {
      final custom = r.nameCtrl.text.trim();
      final name = custom.isNotEmpty
          ? custom
          : _unique(
              '${_roomName}_${_sanitize(_thingTitle)}_${_sanitize(r.shortId)}',
              taken);
      taken.add(name);
      out[r] = name;
    }
    return out;
  }

  // ── Aksi ───────────────────────────────────────────────────────────────────

  Future<void> _createRoom() async {
    final c = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ruangan baru'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Contoh: Ruang Tamu'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Buat')),
        ],
      ),
    );
    c.dispose();
    if (label == null || label.isEmpty) return;

    try {
      final name = _unique(_sanitize(label), _takenNames);
      await _svc.putItem(
          name: name, type: 'Group', label: label, tags: const ['Room']);
      final items = await _svc.fetchItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _rooms.add(_Room(name, label));
        _roomName = name;
        _savedAny = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    }
  }

  Future<void> _submit() async {
    final sel =
        _rows.where((r) => r.selected && r.mappable && !r.alreadyLinked).toList();

    String? problem;
    if (_roomName == null) {
      problem = 'Pilih ruangan terlebih dahulu.';
    } else if (sel.isEmpty) {
      problem = 'Pilih minimal satu channel.';
    } else if (_equipMode == _EquipMode.create &&
        (_equipTag.isEmpty || _equipNameCtrl.text.trim().isEmpty)) {
      problem = 'Isi nama dan jenis Equipment, atau pilih "Tanpa Equipment".';
    } else if (_equipMode == _EquipMode.existing && _existingEquip == null) {
      problem = 'Pilih Equipment yang sudah ada.';
    } else {
      final taken = _takenNames;
      final seen = <String>{};
      for (final r in sel.where((r) => r.existingItem == null)) {
        final custom = r.nameCtrl.text.trim();
        if (custom.isEmpty) continue;
        if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(custom)) {
          problem = 'Nama Item "$custom" tidak valid (huruf, angka, underscore).';
        } else if (taken.contains(custom) || !seen.add(custom)) {
          problem = 'Nama Item "$custom" sudah dipakai.';
        }
      }
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final failures = <String>[];
    try {
      var parent = _roomName!;

      if (_equipMode == _EquipMode.create) {
        final label = _equipNameCtrl.text.trim();
        final eqName =
            _unique('${_roomName}_${_sanitize(label)}', _takenNames.toSet());
        await _svc.putItem(
          name: eqName,
          type: 'Group',
          label: label,
          tags: [_equipTag],
          groupNames: [_roomName!],
        );
        parent = eqName;
        // Kalau ada channel yang gagal lalu user coba lagi, pakai Equipment ini
        // (jangan membuat duplikat).
        _equipMode = _EquipMode.existing;
        _existingEquip = eqName;
        _items = [
          ..._items,
          MappingItem(
              name: eqName,
              label: label,
              type: 'Group',
              tags: [_equipTag],
              groupNames: [_roomName!]),
        ];
        _savedAny = true;
      } else if (_equipMode == _EquipMode.existing) {
        parent = _existingEquip!;
      }

      final names = _plannedNames();
      for (final r in sel) {
        try {
          late final String itemName;
          if (r.existingItem != null) {
            itemName = r.existingItem!;
            await _svc.addMember(parent, itemName);
          } else {
            itemName = names[r]!;
            await _svc.putItem(
              name: itemName,
              type: r.itemType,
              label: '$_thingTitle ${r.label}',
              tags: _pointTags(r.itemType),
              groupNames: [parent],
            );
          }
          await _svc.linkItem(itemName, r.uid);
          r.alreadyLinked = true;
          r.selected = false;
          _savedAny = true;
        } catch (e) {
          failures.add('${r.label}: ${_clean(e)}');
        }
      }
    } catch (e) {
      failures.add(_clean(e));
    }

    try {
      final fresh = await _svc.fetchItems();
      if (mounted) setState(() => _items = fresh);
    } catch (_) {}
    try {
      await _ctrl.loadItems(); // supaya Floorplan langsung memuat Item baru
    } catch (_) {}

    if (!mounted) return;
    setState(() => _submitting = false);

    if (failures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Perangkat berhasil dipasang ke ruangan.',
            style: TextStyle(fontFamily: 'Inter', fontSize: 13)),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) Navigator.pop(context, true);
    } else {
      setState(() => _error = 'Sebagian gagal:\n${failures.join('\n')}');
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!context.watch<RoleProvider>().isAdmin) {
      return const AccessDeniedView(featureName: 'Pasang ke Ruangan');
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _savedAny);
      },
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
        appBar: AppBar(
          backgroundColor: cs.surface,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, size: 18, color: cs.onSurface),
            onPressed: () => Navigator.pop(context, _savedAny),
          ),
          title: Text('Pasang ke Ruangan',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: cs.onSurface)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: EdgeInsets.fromLTRB(
                    ResponsiveUtils.horizontalPadding(context), 16,
                    ResponsiveUtils.horizontalPadding(context), 40),
                children: [
                  if (_error != null) _errorBanner(),
                  _thingHeader(isDark, cs),
                  const SizedBox(height: 20),
                  _title('1. Pilih Channel', cs),
                  const SizedBox(height: 4),
                  _hint('Tiap channel yang dipilih menjadi satu Item yang '
                      'bisa dikontrol.', isDark),
                  const SizedBox(height: 10),
                  ..._rows.map((r) => _channelCard(r, isDark, cs)),
                  const SizedBox(height: 20),
                  _title('2. Pilih Ruangan', cs),
                  const SizedBox(height: 10),
                  _roomPicker(isDark),
                  const SizedBox(height: 20),
                  _title('3. Equipment', cs),
                  const SizedBox(height: 4),
                  _hint('Equipment = perangkat fisik di ruangan (mis. Lampu). '
                      'Item channel dikelompokkan di bawahnya.', isDark),
                  const SizedBox(height: 10),
                  _equipmentSection(isDark, cs),
                  const SizedBox(height: 28),
                  _submitButton(),
                ],
              ),
      ),
    );
  }

  Widget _card(bool isDark, Widget child, {EdgeInsets? padding}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: padding ?? const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF27272A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: child,
      );

  Widget _title(String t, ColorScheme cs) => Text(t,
      style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: cs.onSurface));

  Widget _hint(String t, bool isDark) => Text(t,
      style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          height: 1.4,
          color: isDark ? Colors.white54 : AppColors.textMuted));

  Widget _errorBanner() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(_error!,
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: Colors.red.shade700))),
        ]),
      );

  Widget _thingHeader(bool isDark, ColorScheme cs) => _card(
        isDark,
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.memory_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_thingTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: cs.onSurface)),
              const SizedBox(height: 2),
              Text(widget.thing.thingTypeUID,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: isDark ? Colors.white54 : AppColors.textMuted)),
            ]),
          ),
        ]),
      );

  Widget _channelCard(_ChannelRow r, bool isDark, ColorScheme cs) {
    final planned = _plannedNames();
    final compat = _compatibleItems(r);
    final disabled = !r.mappable || r.alreadyLinked;

    return _card(
      isDark,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(
            width: 28,
            child: Checkbox(
              value: r.selected,
              onChanged: disabled
                  ? null
                  : (v) => setState(() => r.selected = v ?? false),
              activeColor: AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.label,
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: disabled
                          ? (isDark ? Colors.white38 : Colors.grey)
                          : cs.onSurface)),
              Text(
                r.alreadyLinked
                    ? 'Sudah terhubung ke Item'
                    : (!r.mappable
                        ? 'Channel trigger (tidak bisa di-link)'
                        : r.itemType),
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: r.alreadyLinked
                        ? const Color(0xFF22C55E)
                        : (isDark ? Colors.white54 : AppColors.textMuted)),
              ),
            ]),
          ),
        ]),
        if (r.selected && !disabled) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: r.existingItem,
                style: TextStyle(
                    fontFamily: 'Inter', fontSize: 12, color: cs.onSurface),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Buat Item baru (otomatis)')),
                  ...compat.map((i) => DropdownMenuItem<String?>(
                      value: i.name,
                      child: Text('Pakai: ${i.name}',
                          overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setState(() => r.existingItem = v),
              ),
            ),
          ),
          if (r.existingItem == null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: r.nameCtrl,
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                  fontFamily: 'Inter', fontSize: 12, color: cs.onSurface),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Nama Item (opsional)',
                hintText: planned[r] ?? 'Pilih ruangan dulu',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ],
      ]),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, bool isDark,
      {IconData? icon}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon,
                size: 14,
                color: selected
                    ? Colors.white
                    : (isDark ? Colors.white70 : const Color(0xFF71717A))),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  color: selected
                      ? Colors.white
                      : (isDark ? Colors.white70 : const Color(0xFF71717A)))),
        ]),
      ),
    );
  }

  Widget _roomPicker(bool isDark) => _card(
        isDark,
        Wrap(spacing: 8, runSpacing: 8, children: [
          ..._rooms.map((r) => _chip(r.label, _roomName == r.name, () {
                setState(() {
                  _roomName = r.name;
                  _syncEquipmentMode();
                });
              }, isDark, icon: Icons.meeting_room_outlined)),
          _chip('Ruangan baru', false, _createRoom, isDark, icon: Icons.add),
        ]),
      );

  Widget _equipmentSection(bool isDark, ColorScheme cs) {
    final existing = _roomEquipment;
    return _card(
      isDark,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          _chip('Buat baru', _equipMode == _EquipMode.create,
              () => setState(() => _equipMode = _EquipMode.create), isDark),
          if (existing.isNotEmpty)
            _chip('Pilih yang ada', _equipMode == _EquipMode.existing,
                () => setState(() => _equipMode = _EquipMode.existing), isDark),
          _chip('Tanpa Equipment', _equipMode == _EquipMode.none,
              () => setState(() => _equipMode = _EquipMode.none), isDark),
        ]),
        const SizedBox(height: 12),
        if (_equipMode == _EquipMode.create) ...[
          TextField(
            controller: _equipNameCtrl,
            style: TextStyle(
                fontFamily: 'Inter', fontSize: 13, color: cs.onSurface),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Nama Equipment',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kEquipmentTags.entries
                .map((e) => _chip(e.value, _equipTag == e.key,
                    () => setState(() => _equipTag = e.key), isDark))
                .toList(),
          ),
        ] else if (_equipMode == _EquipMode.existing) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: existing
                .map((e) => _chip(
                    e.label.isNotEmpty ? e.label : e.name,
                    _existingEquip == e.name,
                    () => setState(() => _existingEquip = e.name),
                    isDark))
                .toList(),
          ),
        ] else
          _hint('Item akan langsung menjadi anggota ruangan.', isDark),
      ]),
    );
  }

  Widget _submitButton() => SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0,
          ),
          child: _submitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white))
              : const Text('Simpan & Tampilkan di Floorplan',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Colors.white)),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Entry point dari Floorplan: pilih Thing dulu, baru buka wizard.
// ─────────────────────────────────────────────────────────────────────────────

Future<bool?> openThingMapper(BuildContext context,
    {String? locationName}) async {
  final mgmt = OpenHABManagementService();
  final config = context.read<InstallationProvider>().config;
  if (config != null) {
    if (config.apiToken != null && config.apiToken!.isNotEmpty) {
      mgmt.setApiToken(config.apiToken!);
    } else if (config.username != null && config.password != null) {
      mgmt.setBasicAuth(config.username!, config.password!);
    }
    mgmt.setBaseUrl(config.openhabUrl);
  } else {
    mgmt.setBaseUrl(OpenHABController.instance.serverUrl);
  }

  List<OHThing> things;
  try {
    things = await mgmt.getThings();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat Things: $e')));
    }
    return null;
  }
  if (!context.mounted) return null;

  final candidates = things
      .where((t) => t.channels.any((c) => c.itemType.isNotEmpty))
      .toList();

  final picked = await showModalBottomSheet<OHThing>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, sc) => Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF27272A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Pilih perangkat (Thing)',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: isDark ? Colors.white : const Color(0xCC18181B))),
            const SizedBox(height: 12),
            Expanded(
              child: candidates.isEmpty
                  ? const Center(
                      child: Text('Belum ada Thing. Tambahkan dulu di '
                          'Settings > Things.'))
                  : ListView.builder(
                      controller: sc,
                      itemCount: candidates.length,
                      itemBuilder: (_, i) {
                        final t = candidates[i];
                        final free = t.channels
                            .where((c) =>
                                c.itemType.isNotEmpty && c.linkedItems.isEmpty)
                            .length;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.memory_rounded,
                              color: t.status == 'ONLINE'
                                  ? const Color(0xFF22C55E)
                                  : Colors.grey),
                          title: Text(t.label.isNotEmpty ? t.label : t.uid,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('$free channel belum terhubung'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(ctx, t),
                        );
                      },
                    ),
            ),
          ]),
        ),
      );
    },
  );
  if (picked == null || !context.mounted) return null;

  return Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) =>
          MapThingToRoomPage(thing: picked, initialLocationName: locationName),
    ),
  );
}
