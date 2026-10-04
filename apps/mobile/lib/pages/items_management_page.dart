import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mobile/core/services/openhab_management_service.dart';
import 'package:mobile/core/controllers/openhab_controller.dart';
import 'package:mobile/core/providers/installation_provider.dart';
import 'package:mobile/core/providers/role_provider.dart';
import 'package:mobile/pages/add_item_page.dart';
import 'package:mobile/pages/edit_item_page.dart';
import 'package:mobile/core/utils/responsive_utils.dart';
import 'package:mobile/core/widget/video_player_dialog.dart';
import '../../../../core/theme/app_colors.dart';


class OHItem {
  final String name;
  final String type;
  final String label;
  final String state;
  final String category;
  final List<String> tags;
  final List<String> groupNames;
  /// Daftar command yang benar-benar didukung item ini, dari
  /// `commandDescription.commandOptions` REST API openHAB. KOSONG berarti
  /// server tidak melaporkan batasan apa pun (bukan berarti "tidak ada
  /// command yang didukung") — jadi default aman-nya adalah anggap semua
  /// command diperbolehkan kalau list ini kosong, dan baru membatasi kalau
  /// list ini terisi.
  final List<String> commandOptions;

  const OHItem({
    required this.name,
    required this.type,
    required this.label,
    required this.state,
    this.category = '',
    this.tags = const [],
    this.groupNames = const [],
    this.commandOptions = const [],
  });

  factory OHItem.fromJson(Map<String, dynamic> json) => OHItem(
        name: json['name'] ?? '',
        type: json['type'] ?? '',
        label: json['label'] ?? json['name'] ?? '',
        state: json['state'] ?? 'NULL',
        category: json['category'] ?? '',
        tags: List<String>.from(json['tags'] ?? []),
        groupNames: List<String>.from(json['groupNames'] ?? []),
        commandOptions: (json['commandDescription']?['commandOptions']
                as List<dynamic>? ??
            [])
            .map((o) => (o['command'] ?? '').toString().toUpperCase())
            .where((c) => c.isNotEmpty)
            .toList(),
      );

  /// True kalau command ini boleh dikirim ke item — dipakai untuk
  /// menyembunyikan tombol kontrol yang tidak didukung channel/binding
  /// (mis. tombol Next/Previous di Player yang cuma support Play/Pause).
  /// List kosong = server tidak melaporkan batasan → izinkan semua,
  /// supaya tidak salah sembunyikan tombol untuk item yang memang tidak
  /// mengisi commandDescription (banyak binding tidak mengisi field ini).
  bool supportsCommand(String command) =>
      commandOptions.isEmpty || commandOptions.contains(command.toUpperCase());

  bool get isSwitch => type == 'Switch';
  bool get isDimmer => type == 'Dimmer';
  bool get isNumber => type == 'Number';
  bool get isString => type == 'String';
  bool get isColor => type == 'Color';
  bool get isPlayer => type == 'Player';
  bool get isGroup => type == 'Group';
  bool get isContact => type == 'Contact';
  bool get isRollershutter => type == 'Rollershutter';
  bool get isImage => type == 'Image';

  /// Deteksi berbasis kata kunci di nama/label/category — konsisten
  /// dengan OpenHABItem.isCamera di openhab_item.dart. Item kamera tidak
  /// selalu bertipe Image (kadang cuma channel pendukung yang di-link),
  /// jadi dicek terpisah dari isImage, bukan pengganti.
  bool get isCamera {
    final combined = '$name $label $category'.toLowerCase();
    return combined.contains('camera') || combined.contains('cctv');
  }

  bool get isOn => state == 'ON';
  double get dimmerValue {
    final v = double.tryParse(state) ?? 0;
    return v.clamp(0, 100);
  }

  /// Item Color openHAB balikin state format "H,S,B" (Hue 0-360,
  /// Saturation 0-100, Brightness 0-100), dipisah koma.
  HSVColor? get hsbColor {
    if (!isColor) return null;
    if (state.isEmpty || state == 'NULL' || state == 'UNDEF') return null;
    final parts = state.split(',');
    if (parts.length != 3) return null;
    final h = double.tryParse(parts[0]);
    final s = double.tryParse(parts[1]);
    final b = double.tryParse(parts[2]);
    if (h == null || s == null || b == null) return null;
    return HSVColor.fromAHSV(1.0, h.clamp(0, 360).toDouble(),
        (s / 100).clamp(0, 1).toDouble(), (b / 100).clamp(0, 1).toDouble());
  }

  /// Item Image openHAB balikin state sebagai data URI
  /// "data:image/jpeg;base64,....". Null kalau belum ada snapshot/format
  /// tidak sesuai dugaan.
  Uint8List? get imageBytes {
    if (!isImage) return null;
    if (state.isEmpty || state == 'NULL' || state == 'UNDEF') return null;
    try {
      final raw = state.contains(',') ? state.split(',').last : state;
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }
}
class ItemsManagementPage extends StatefulWidget {
  const ItemsManagementPage({super.key});

  @override
  State<ItemsManagementPage> createState() => _ItemsManagementPageState();
}

class _ItemsManagementPageState extends State<ItemsManagementPage>
    with SingleTickerProviderStateMixin {
  final _mgmt = OpenHABManagementService();
  final _ctrl = OpenHABController.instance;

  List<OHItem> _allItems = [];
  List<OHItem> _filteredItems = [];
  bool _isLoading = false;
  String? _errorMsg;
  String _filterType = 'All';

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  late AnimationController _animCtrl;

  static const _filterOptions = [
    'All', 'Switch', 'Dimmer', 'Number', 'String',
    'Color', 'Image', 'Camera', 'Group', 'Contact', 'Player', 'Rollershutter',
  ];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _mgmt.setBaseUrl(_ctrl.serverUrl);
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
    if (config != null) {
      if (config.apiToken != null && config.apiToken!.isNotEmpty) {
        _mgmt.setApiToken(config.apiToken!);
      } else if (config.username != null && config.password != null) {
        _mgmt.setBasicAuth(config.username!, config.password!);
      }
      _mgmt.setBaseUrl(config.openhabUrl);
    }
    await _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      final items = await _mgmt.getItems();
      setState(() {
        _allItems = items;
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
      Iterable<OHItem> items = _filterType == 'All'
          ? _allItems
          : _filterType == 'Camera'
              ? _allItems.where((i) => i.isCamera)
              : _allItems.where((i) => i.type == _filterType);

      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        items = items.where((i) =>
            i.label.toLowerCase().contains(q) ||
            i.name.toLowerCase().contains(q));
      }

      _filteredItems = items.toList();
    });
  }

  void _onSearchChanged(String value) {
    _searchQuery = value;
    _applyFilter();
  }

  int _countOf(String type) => _allItems.where((i) => i.type == type).length;

  Future<void> _sendCommand(OHItem item, String command) async {
    try {
      await _mgmt.sendCommand(item.name, command);

      // Command transport (bukan representasi state akhir) — misal
      // NEXT/PREVIOUS untuk Player atau UP/DOWN/STOP untuk shutter —
      // tidak boleh langsung dipaksa jadi state lokal, supaya tampilan
      // tidak sempat salah sebelum data asli datang dari server.
      const transportCommands = {
        'NEXT', 'PREVIOUS', 'REWIND', 'FASTFORWARD',
        'UP', 'DOWN', 'STOP', 'MOVE',
      };
      if (transportCommands.contains(command.toUpperCase())) return;

      final idx = _allItems.indexWhere((i) => i.name == item.name);
      if (idx != -1) {
        setState(() {
          _allItems[idx] = OHItem(
            name: item.name, type: item.type, label: item.label,
            state: command, category: item.category,
            tags: item.tags, groupNames: item.groupNames,
          );
          _applyFilter();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _editItem(OHItem item) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditItemPage(item: item)),
    );
    // Selalu muat ulang dari server (bukan update state lokal) supaya
    // yang tampil adalah data yang benar-benar tersimpan.
    if (result == true) await _loadItems();
  }

  Future<void> _deleteItem(OHItem item) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF27272A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Hapus Item',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF18181B))),
        content: Text(
          'Yakin ingin menghapus "${item.label}"?',
          style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: isDark ? Colors.white70 : const Color(0xFF52525B)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Batal',
                style: TextStyle(
                    color: isDark ? Colors.white54 : const Color(0xFF71717A))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus',
                style: TextStyle(
                    color: Colors.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final ok = await _mgmt.deleteItem(item.name);
      if (ok) {
        setState(() {
          _allItems.removeWhere((i) => i.name == item.name);
          _applyFilter();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('"${item.label}" berhasil dihapus'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal hapus: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      appBar: _buildAppBar(context),
      body: _isLoading
          ? _buildLoading()
          : _errorMsg != null
              ? _buildError()
              : _buildContent(context),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAdmin = context.watch<RoleProvider>().isAdmin;

    return AppBar(
      backgroundColor: cs.surface,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new, size: 18, color: cs.onSurface),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Items',
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: cs.onSurface,
        ),
      ),
      actions: [
        if (isAdmin)
          IconButton(
            icon: Icon(Icons.add_rounded, size: 24, color: cs.onSurface),
            tooltip: 'Tambah Item',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddItemPage()),
              );
              if (result == true) await _loadItems();
            },
          ),
        IconButton(
          icon: Icon(Icons.refresh_rounded, size: 22, color: cs.onSurface),
          onPressed: _loadItems,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 14),
          const Text('Memuat Items...',
              style: TextStyle(
                  fontFamily: 'Inter', fontSize: 13, color: Color(0xFF71717A))),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 56, color: Colors.red.shade300),
            const SizedBox(height: 14),
            Text('Gagal memuat Items',
                style: TextStyle(fontFamily: 'Inter',
                    fontWeight: FontWeight.w700, fontSize: 16,
                    color: Colors.red.shade700)),
            const SizedBox(height: 6),
            Text(_errorMsg!, textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                    color: Colors.red.shade400)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadItems,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                elevation: 0,
              ),
              icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
              label: const Text('Coba Lagi',
                  style: TextStyle(fontFamily: 'Inter',
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      )),
    );
  }

  Widget _buildContent(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadItems,
      color: AppColors.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  ResponsiveUtils.horizontalPadding(context), 16,
                  ResponsiveUtils.horizontalPadding(context), 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryRow(context),
                  const SizedBox(height: 16),
                  _buildSearchBar(context),
                  const SizedBox(height: 14),
                  _buildFilterChips(context),
                  const SizedBox(height: 14),
                  _buildListHeader(context),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          _filteredItems.isEmpty
              ? SliverFillRemaining(hasScrollBody: false, child: _buildEmpty(context))
              : SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      ResponsiveUtils.horizontalPadding(context), 0,
                      ResponsiveUtils.horizontalPadding(context), 40),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final item = _filteredItems[i];
                        return AnimatedBuilder(
                          animation: _animCtrl,
                          builder: (ctx, child) {
                            final delay = (i * 0.04).clamp(0.0, 0.5);
                            final progress =
                                ((_animCtrl.value - delay) / (1.0 - delay))
                                    .clamp(0.0, 1.0);
                            return Opacity(
                              opacity: progress,
                              child: Transform.translate(
                                offset: Offset(0, 16 * (1 - progress)),
                                child: child,
                              ),
                            );
                          },
                          child: _ItemCard(
                            item: item,
                            canDelete: context.watch<RoleProvider>().isAdmin,
                            onToggle: (val) =>
                                _sendCommand(item, val ? 'ON' : 'OFF'),
                            onSlider: (val) =>
                                _sendCommand(item, val.round().toString()),
                            onPlayer: (cmd) => _sendCommand(item, cmd),
                            onEdit: () => _editItem(item),
                            onDelete: () => _deleteItem(item),
                          ),
                        );
                      },
                      childCount: _filteredItems.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final summaries = [
      {'label': 'Total',  'count': _allItems.length,    'color': const Color(0xFF6366F1)},
      {'label': 'Switch', 'count': _countOf('Switch'),  'color': const Color(0xFF22C55E)},
      {'label': 'Dimmer', 'count': _countOf('Dimmer'),  'color': const Color(0xFFF59E0B)},
      {'label': 'Number', 'count': _countOf('Number'),  'color': const Color(0xFF3B82F6)},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: summaries.map((s) {
          final color = s['color']! as Color;
          final count = s['count']! as int;
          return Container(
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  '$count ${s['label']}',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: color,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
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
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: isDark ? Colors.white : const Color(0xFF18181B),
        ),
        decoration: InputDecoration(
          hintText: 'Cari item...',
          hintStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: isDark ? Colors.white38 : Colors.grey.shade400,
          ),
          prefixIcon: Icon(Icons.search_rounded,
              size: 20,
              color: isDark ? Colors.white38 : Colors.grey.shade400),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close_rounded,
                      size: 18,
                      color: isDark ? Colors.white38 : Colors.grey.shade400),
                  onPressed: () {
                    _searchCtrl.clear();
                    _onSearchChanged('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _filterOptions.map((type) {
          final isSelected = _filterType == type;
          final count = type == 'All' ? _allItems.length : _countOf(type);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() => _filterType = type);
                _applyFilter();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? const Color(0xFF27272A) : Colors.white),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      type,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white70 : const Color(0xFF71717A)),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.25)
                            : (isDark
                                ? const Color(0xFF3F3F46)
                                : const Color(0xFFF4F4F5)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white54 : const Color(0xFF71717A)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildListHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Text(
          '${_filteredItems.length} Item${_filteredItems.length != 1 ? 's' : ''}',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: isDark ? Colors.white : const Color(0xCC18181B),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Geser untuk hapus',
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: isDark ? Colors.white38 : Colors.grey.shade400,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.layers_outlined,
              size: 56,
              color: isDark ? const Color(0xFF3F3F46) : Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'Tidak ada Item',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: isDark ? Colors.white38 : Colors.grey.shade500,
            ),
          ),
          Text(
            _searchQuery.isNotEmpty
                ? 'Tidak ada item yang cocok dengan "$_searchQuery".'
                : _filterType == 'All'
                    ? 'Belum ada item yang ditambahkan.'
                    : 'Tidak ada item bertipe "$_filterType".',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: isDark ? Colors.white30 : Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatefulWidget {
  final OHItem item;
  final bool canDelete;
  final ValueChanged<bool> onToggle;
  final ValueChanged<double> onSlider;
  final ValueChanged<String> onPlayer;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ItemCard({
    required this.item,
    required this.canDelete,
    required this.onToggle,
    required this.onSlider,
    required this.onPlayer,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  late double _sliderValue;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _sliderValue = widget.item.dimmerValue;
  }

  @override
  void didUpdateWidget(_ItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.state != widget.item.state) {
      _sliderValue = widget.item.dimmerValue;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Color get _typeColor {
    switch (widget.item.type) {
      case 'Switch':       return const Color(0xFF22C55E);
      case 'Dimmer':       return const Color(0xFFF59E0B);
      case 'Number':       return const Color(0xFF3B82F6);
      case 'String':       return const Color(0xFF8B5CF6);
      case 'Color':        return const Color(0xFFEC4899);
      case 'Player':       return const Color(0xFF06B6D4);
      case 'Group':        return const Color(0xFF6366F1);
      case 'Contact':      return const Color(0xFF14B8A6);
      case 'Rollershutter': return const Color(0xFF94A3B8);
      default:             return const Color(0xFF71717A);
    }
  }

  FaIconData get _typeIcon {
    switch (widget.item.type) {
      case 'Switch':        return FontAwesomeIcons.toggleOn;
      case 'Dimmer':        return FontAwesomeIcons.sliders;
      case 'Number':        return FontAwesomeIcons.hashtag;
      case 'String':        return FontAwesomeIcons.font;
      case 'Color':         return FontAwesomeIcons.palette;
      case 'Player':        return FontAwesomeIcons.play;
      case 'Group':         return FontAwesomeIcons.layerGroup;
      case 'Contact':       return FontAwesomeIcons.doorOpen;
      case 'Rollershutter': return FontAwesomeIcons.tableColumns;
      default:              return FontAwesomeIcons.circleQuestion;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dismissible(
      key: Key(widget.item.name),
      direction: widget.canDelete
          ? DismissDirection.endToStart
          : DismissDirection.none,
      confirmDismiss: (_) async {
        widget.onDelete();
        return false;
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const FaIcon(FontAwesomeIcons.trash, color: Colors.white, size: 18),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF27272A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LayoutBuilder: lebar kontrol di kanan dibatasi relatif terhadap
              // lebar kartu, supaya label di tengah selalu kebagian ruang dan
              // state yang panjang (String/Image/Location) tidak membuat overflow.
              LayoutBuilder(builder: (context, c) {
              // 44 ikon + 12 jarak + 39 tombol edit = 95 lebar tetap
              final maxTrailing = ((c.maxWidth - 95) * 0.5).clamp(56.0, 260.0);
              Widget cap(Widget w) => ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxTrailing),
                    child: w,
                  );
              return Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: _typeColor.withValues(alpha: isDark ? 0.15 : 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: FaIcon(_typeIcon, size: 18, color: _typeColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.label.isNotEmpty
                              ? widget.item.label
                              : widget.item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: isDark ? Colors.white : const Color(0xCC18181B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _typeColor.withValues(alpha: isDark ? 0.2 : 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                widget.item.type,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _typeColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                widget.item.name,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white38
                                      : const Color(0xFF71717A),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onEdit,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      // Padding transparan memperbesar area tap tanpa
                      // mengubah ukuran ikon yang terlihat — kartu ini
                      // padat, jadi target 48pt penuh akan merusak
                      // layout; ini kompromi paling aman.
                      padding: const EdgeInsets.all(12),
                      child: FaIcon(FontAwesomeIcons.penToSquare,
                          size: 15, color: AppColors.textMuted),
                    ),
                  ),
                  if (widget.item.isSwitch) cap(_buildSwitchControl()),
                  if (widget.item.isColor) cap(_buildColorSwatch(context, isDark)),
                  if (!widget.item.isSwitch && widget.item.isImage && !widget.item.isCamera)
                    cap(_buildImageThumb(context, isDark)),
                  if (!widget.item.isSwitch && !widget.item.isDimmer &&
                      !widget.item.isColor && !widget.item.isImage &&
                      !widget.item.isCamera)
                    cap(_buildStateBadge(isDark)),
                ],
              );
              }),
              if (!widget.item.isSwitch && widget.item.isCamera) ...[
                const SizedBox(height: 12),
                _buildCameraWidget(context, isDark),
              ],
              if (widget.item.isDimmer) ...[
                const SizedBox(height: 12),
                _buildDimmerControl(isDark),
              ],
              if (widget.item.isPlayer) ...[
                const SizedBox(height: 12),
                _buildPlayerControl(),
              ],
              if (widget.item.isRollershutter) ...[
                const SizedBox(height: 12),
                _buildRollershutterControl(isDark),
              ],
              if (widget.item.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 4,
                  children: widget.item.tags.map((tag) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF3F3F46)
                          : const Color(0xFFF4F4F5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        color: isDark
                            ? Colors.white54
                            : const Color(0xFF71717A),
                      ),
                    ),
                  )).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchControl() {
    final isOn = widget.item.isOn;
    return GestureDetector(
      onTap: () => widget.onToggle(!isOn),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52, height: 30,
        decoration: BoxDecoration(
          color: isOn ? const Color(0xFF22C55E) : const Color(0xFFE4E4E7),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              left: isOn ? 24 : 4,
              top: 4,
              child: Container(
                width: 22, height: 22,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildStateBadge(bool isDark) {
    final state = widget.item.state;
    final isNull = state == 'NULL' || state.isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isNull
            ? (isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5))
            : _typeColor.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        isNull ? '—' : state,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: isNull
              ? (isDark ? Colors.white38 : const Color(0xFF71717A))
              : _typeColor,
        ),
      ),
    );
  }

  /// Swatch bulat menampilkan warna aktual item Color (hasil parse HSB).
  /// Tap untuk membuka picker (hue/saturation/brightness) di bottom sheet.
  Widget _buildColorSwatch(BuildContext context, bool isDark) {
    final hsv = widget.item.hsbColor;
    final swatchColor = hsv?.toColor() ?? Colors.grey;
    final isNull = hsv == null;

    return GestureDetector(
      onTap: () => _openColorPicker(context, hsv),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16, height: 16,
              decoration: BoxDecoration(
                color: swatchColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? Colors.white24 : Colors.black12,
                  width: 1,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              isNull ? '—' : 'Atur',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: isDark ? Colors.white70 : const Color(0xFF52525B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openColorPicker(BuildContext context, HSVColor? initial) {
    var hsv = initial ?? HSVColor.fromAHSV(1.0, 0, 0, 1.0);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF27272A) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void sendHsb() {
              final h = hsv.hue.round();
              final s = (hsv.saturation * 100).round();
              final b = (hsv.value * 100).round();
              widget.onPlayer('$h,$s,$b');
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 20,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: hsv.toColor(),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? Colors.white24 : Colors.black12),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.item.label.isNotEmpty
                              ? widget.item.label
                              : widget.item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: isDark ? Colors.white : const Color(0xFF18181B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Warna (Hue)',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                          color: isDark ? Colors.white54 : const Color(0xFF71717A))),
                  SliderTheme(
                    data: SliderTheme.of(sheetContext).copyWith(
                      activeTrackColor: hsv.toColor(),
                      thumbColor: hsv.toColor(),
                    ),
                    child: Slider(
                      value: hsv.hue,
                      min: 0, max: 360,
                      onChanged: (v) => setSheetState(
                          () => hsv = hsv.withHue(v)),
                      onChangeEnd: (_) => sendHsb(),
                    ),
                  ),
                  Text('Saturasi',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                          color: isDark ? Colors.white54 : const Color(0xFF71717A))),
                  Slider(
                    value: hsv.saturation,
                    min: 0, max: 1,
                    onChanged: (v) => setSheetState(
                        () => hsv = hsv.withSaturation(v)),
                    onChangeEnd: (_) => sendHsb(),
                  ),
                  Text('Kecerahan',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                          color: isDark ? Colors.white54 : const Color(0xFF71717A))),
                  Slider(
                    value: hsv.value,
                    min: 0, max: 1,
                    onChanged: (v) => setSheetState(
                        () => hsv = hsv.withValue(v)),
                    onChangeEnd: (_) => sendHsb(),
                  ),
                  const SizedBox(height: 8),
                ],
              )),
            );
          },
        );
      },
    );
  }

  /// Thumbnail kecil untuk item Camera/Image — tampilkan snapshot terakhir
  /// (hasil decode base64 dari state), atau placeholder rapi kalau belum
  /// ada gambar/gagal decode. Tap untuk lihat lebih besar.
  Widget _buildImageThumb(BuildContext context, bool isDark) {
    final bytes = widget.item.imageBytes;

    return GestureDetector(
      onTap: () => _openImageViewer(context, bytes),
      child: Container(
        width: 44, height: 32,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? Colors.white24 : Colors.black12,
            width: 1,
          ),
        ),
        child: bytes != null
            ? Image.memory(
                bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.broken_image_outlined,
                  size: 16,
                  color: isDark ? Colors.white38 : const Color(0xFF71717A),
                ),
              )
            : Icon(
                Icons.videocam_outlined,
                size: 16,
                color: isDark ? Colors.white38 : const Color(0xFF71717A),
              ),
      ),
    );
  }

  void _openImageViewer(BuildContext context, Uint8List? bytes) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: isDark ? const Color(0xFF27272A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.item.label.isNotEmpty
                          ? widget.item.label
                          : widget.item.name,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: isDark ? Colors.white : const Color(0xFF18181B),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close,
                        color: isDark ? Colors.white70 : Colors.black54),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
              Flexible(child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: bytes != null
                    ? Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => _imageViewerFallback(
                            isDark, 'Gagal memuat snapshot'),
                      )
                    : _imageViewerFallback(isDark, 'Belum ada snapshot'),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageViewerFallback(bool isDark, String message) {
    return Container(
      width: double.infinity,
      height: 220,
      alignment: Alignment.center,
      color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_off_outlined,
              size: 40, color: isDark ? Colors.white38 : const Color(0xFF71717A)),
          const SizedBox(height: 8),
          Text(message,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: isDark ? Colors.white54 : const Color(0xFF71717A))),
        ],
      ),
    );
  }

  /// Widget kamera — replika tampilan widget Video openHAB: kartu gelap,
  /// label pojok kiri atas, tombol play bulat di tengah. State item
  /// (kalau berupa URL http/https) langsung dipakai sebagai sumber video;
  /// kalau bukan, tampilkan pesan jelas alih-alih pura-pura berhasil.
  Widget _buildCameraWidget(BuildContext context, bool isDark) {
    return GestureDetector(
      onTap: () => _openCameraPlayer(context),
      child: Container(
        width: double.infinity,
        height: 160,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 14, right: 14, top: 12,
              child: Text(
                widget.item.label.isNotEmpty
                    ? widget.item.label
                    : widget.item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Colors.white,
                ),
              ),
            ),
            Center(
              child: Container(
                width: 48, height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFE4E4E7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.black, size: 26),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCameraPlayer(BuildContext context) {
    final state = widget.item.state;
    final isValidUrl = state.startsWith('http://') || state.startsWith('https://');
    if (!isValidUrl) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('State item ini bukan URL video yang valid.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final item = widget.item;
    showDialog(
      context: context,
      builder: (_) => VideoPlayerDialog(
        label: item.label.isNotEmpty ? item.label : item.name,
        videoUrl: state,
        httpHeaders: OpenHABController.instance.authHeaders,
      ),
    );
  }

  Widget _buildDimmerControl(bool isDark) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => widget.onToggle(false),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: FaIcon(FontAwesomeIcons.moon,
                size: 14,
                color: isDark ? Colors.white54 : const Color(0xFF71717A)),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: _typeColor,
              inactiveTrackColor: _typeColor.withValues(alpha: 0.2),
              thumbColor: _typeColor,
              overlayColor: _typeColor.withValues(alpha: 0.15),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              trackHeight: 4,
            ),
            child: Slider(
              value: _sliderValue,
              min: 0,
              max: 100,
              onChanged: (v) {
                setState(() => _sliderValue = v);
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () {
                  widget.onSlider(v);
                });
              },
            ),
          ),
        ),
        Container(
          width: 42,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: _typeColor.withValues(alpha: isDark ? 0.2 : 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${_sliderValue.round()}%',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: _typeColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerControl() {
    final state = widget.item.state;
    final item = widget.item;
    // Tombol Previous/Next cuma ditampilkan kalau channel-nya memang
    // melaporkan dukungan command itu — banyak Player item cuma support
    // Play/Pause doang (mis. speaker sederhana tanpa playlist).
    final buttons = <Widget>[
      if (item.supportsCommand('PREVIOUS'))
        _PlayerBtn(
          icon: FontAwesomeIcons.backwardStep,
          onTap: () => widget.onPlayer('PREVIOUS'),
        ),
      _PlayerBtn(
        icon: state == 'PLAY'
            ? FontAwesomeIcons.pause
            : FontAwesomeIcons.play,
        isPrimary: true,
        color: _typeColor,
        onTap: () => widget.onPlayer(state == 'PLAY' ? 'PAUSE' : 'PLAY'),
      ),
      if (item.supportsCommand('NEXT'))
        _PlayerBtn(
          icon: FontAwesomeIcons.forwardStep,
          onTap: () => widget.onPlayer('NEXT'),
        ),
    ];

    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: buttons,
      ),
    );
  }
  Widget _buildRollershutterControl(bool isDark) {
    final item = widget.item;
    // Sama seperti Player — sembunyikan tombol yang channel-nya tidak
    // melaporkan dukungan command itu (mis. shutter tanpa fitur Stop).
    final buttons = <Widget>[
      if (item.supportsCommand('UP'))
        _RollerBtn(
          icon: FontAwesomeIcons.chevronUp,
          label: 'Up',
          isDark: isDark,
          onTap: () => widget.onPlayer('UP'),
        ),
      if (item.supportsCommand('STOP'))
        _RollerBtn(
          icon: FontAwesomeIcons.stop,
          label: 'Stop',
          isDark: isDark,
          onTap: () => widget.onPlayer('STOP'),
        ),
      if (item.supportsCommand('DOWN'))
        _RollerBtn(
          icon: FontAwesomeIcons.chevronDown,
          label: 'Down',
          isDark: isDark,
          onTap: () => widget.onPlayer('DOWN'),
        ),
    ];

    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: buttons,
      ),
    );
  }
}

class _PlayerBtn extends StatelessWidget {
  final FaIconData icon;
  final VoidCallback onTap;
  final bool isPrimary;
  final Color color;

  const _PlayerBtn({
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
    this.color = const Color(0xFF06B6D4),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isPrimary ? 48 : 38,
        height: isPrimary ? 48 : 38,
        decoration: BoxDecoration(
          color: isPrimary ? color : color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: FaIcon(
            icon,
            size: isPrimary ? 18 : 14,
            color: isPrimary ? Colors.white : color,
          ),
        ),
      ),
    );
  }
}

class _RollerBtn extends StatelessWidget {
  final FaIconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  const _RollerBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            FaIcon(icon,
                size: 14,
                color: isDark ? Colors.white54 : const Color(0xFF71717A)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : const Color(0xFF71717A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}