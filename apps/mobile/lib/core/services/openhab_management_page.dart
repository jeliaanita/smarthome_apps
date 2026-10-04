import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mobile/core/controllers/openhab_controller.dart';
import 'package:mobile/core/models/openhab_item.dart';
import 'package:mobile/core/services/openhab_management_service.dart';
import 'package:mobile/pages/add_item_page.dart';
import 'package:mobile/pages/add_thing_page.dart';


class OpenHABManagementPage extends StatefulWidget {
  const OpenHABManagementPage({super.key});

  @override
  State<OpenHABManagementPage> createState() => _OpenHABManagementPageState();
}

class _OpenHABManagementPageState extends State<OpenHABManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _ctrl = OpenHABController.instance;
  final _mgmt = OpenHABManagementService();

  List<OHThing> _things = [];
  bool _loadingThings = false;
  String? _thingsError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _ctrl.addListener(_onCtrlUpdate);
    _mgmt.setBaseUrl(_ctrl.serverUrl);
    _loadThings();
  }

  void _onCtrlUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ctrl.removeListener(_onCtrlUpdate);
    super.dispose();
  }

  Future<void> _loadThings() async {
    setState(() {
      _loadingThings = true;
      _thingsError = null;
    });
    try {
      final things = await _mgmt.getThings();
      setState(() => _things = things);
    } catch (e) {
      setState(() => _thingsError = e.toString());
    } finally {
      setState(() => _loadingThings = false);
    }
  }

  Future<void> _deleteThing(OHThing thing) async {
    final confirm = await _showDeleteDialog(
      title: 'Hapus Thing?',
      content: '"${thing.label}" akan dihapus dari openHAB.',
    );
    if (!confirm) return;
    try {
      await _mgmt.deleteThing(thing.uid);
      _showSnack('Thing "${thing.label}" berhasil dihapus', isError: false);
      await _loadThings();
    } catch (e) {
      _showSnack('Gagal hapus: $e');
    }
  }

  Future<void> _deleteItem(OpenHABItem item) async {
    final confirm = await _showDeleteDialog(
      title: 'Hapus Item?',
      content: '"${item.label}" akan dihapus dari openHAB.',
    );
    if (!confirm) return;
    try {
      await _mgmt.deleteItem(item.name);
      _showSnack('Item "${item.label}" berhasil dihapus', isError: false);
      await _ctrl.loadItems();
    } catch (e) {
      _showSnack('Gagal hapus: $e');
    }
  }

  Future<bool> _showDeleteDialog(
      {required String title, required String content}) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: Text(title,
                style: const TextStyle(
                    fontFamily: 'Inter', fontWeight: FontWeight.w700)),
            content: Text(content,
                style: const TextStyle(fontFamily: 'Inter', fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal',
                    style: TextStyle(
                        fontFamily: 'Inter', color: Color(0xFF71717A))),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Hapus',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.red,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showSnack(String msg, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 13)),
        backgroundColor: isError ? Colors.red.shade700 : const Color(0xFF34C759),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showThingDetail(OHThing thing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ThingDetailSheet(thing: thing, mgmt: _mgmt),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildThingsTab(),
                _buildItemsTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new,
            size: 18, color: Color(0xFF18181B)),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'openHAB Manager',
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: Color(0xCC18181B),
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _ctrl.isConnected
                ? const Color(0xFFDCFCE7)
                : const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _ctrl.isConnected
                      ? const Color(0xFF16A34A)
                      : Colors.red,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                _ctrl.isConnected ? 'Online' : 'Offline',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _ctrl.isConnected
                      ? const Color(0xFF16A34A)
                      : Colors.red,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: const Color(0xFF6366F1),
        unselectedLabelColor: const Color(0xFF71717A),
        indicatorColor: const Color(0xFF6366F1),
        indicatorWeight: 3,
        labelStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 14),
        unselectedLabelStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w500,
            fontSize: 14),
        tabs: [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FaIcon(FontAwesomeIcons.microchip, size: 14),
                const SizedBox(width: 6),
                Text('Things (${_things.length})'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FaIcon(FontAwesomeIcons.toggleOn, size: 14),
                const SizedBox(width: 6),
                Text('Items (${_ctrl.items.length})'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // FAB tambah Item
        FloatingActionButton.extended(
          heroTag: 'fab_item',
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AddItemPage()),
            );
            await _ctrl.loadItems();
          },
          backgroundColor: const Color(0xFF6366F1),
          icon: const FaIcon(FontAwesomeIcons.plus,
              size: 16, color: Colors.white),
          label: const Text('Item',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontSize: 14)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'fab_thing',
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AddThingPage()),
            );
            await _loadThings();
          },
          backgroundColor: const Color(0xFF18181B),
          icon: const FaIcon(FontAwesomeIcons.microchip,
              size: 16, color: Colors.white),
          label: const Text('Thing',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontSize: 14)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
      ],
    );
  }

  Widget _buildThingsTab() {
    if (_loadingThings) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_thingsError != null) {
      return _buildErrorState(_thingsError!, _loadThings);
    }
    if (_things.isEmpty) {
      return _buildEmptyState(
        icon: FontAwesomeIcons.microchip,
        title: 'Belum ada Things',
        subtitle:
            'Things adalah perangkat fisik yang terhubung.\nTap tombol "+ Thing" untuk menambahkan.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadThings,
      color: const Color(0xFF6366F1),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        itemCount: _things.length,
        itemBuilder: (ctx, i) => _ThingCard(
          thing: _things[i],
          onTap: () => _showThingDetail(_things[i]),
          onDelete: () => _deleteThing(_things[i]),
        ),
      ),
    );
  }

  Widget _buildItemsTab() {
    if (_ctrl.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_ctrl.items.isEmpty) {
      return _buildEmptyState(
        icon: FontAwesomeIcons.toggleOn,
        title: 'Belum ada Items',
        subtitle:
            'Items adalah kontrol virtual perangkat.\nTap tombol "+ Item" untuk menambahkan.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _ctrl.loadItems(),
      color: const Color(0xFF6366F1),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        itemCount: _ctrl.items.length,
        itemBuilder: (ctx, i) {
          final item = _ctrl.items[i];
          return _ItemCard(
            item: item,
            onDelete: () => _deleteItem(item),
          );
        },
      ),
    );
  }

  Widget _buildErrorState(String error, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Coba Lagi',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required FaIconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(icon, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: Color(0xCC18181B))),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}

class _ThingCard extends StatelessWidget {
  final OHThing thing;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ThingCard({
    required this.thing,
    required this.onTap,
    required this.onDelete,
  });

  Color get _statusColor {
    switch (thing.status) {
      case 'ONLINE':
        return const Color(0xFF16A34A);
      case 'OFFLINE':
        return Colors.red;
      case 'INITIALIZING':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3)),
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
            child: Row(
              children: [
                // Status indicator + icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: FaIcon(
                      FontAwesomeIcons.microchip,
                      size: 20,
                      color: _statusColor,
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        thing.label.isNotEmpty
                            ? thing.label
                            : thing.uid,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Color(0xCC18181B),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        thing.thingTypeUID,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: Color(0xFF71717A),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _statusColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            thing.status,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: _statusColor,
                            ),
                          ),
                          if (thing.channels.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${thing.channels.length} channel(s)',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                color: Color(0xFF71717A),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 20),
                  onPressed: onDelete,
                ),
                const Icon(Icons.chevron_right,
                    color: Color(0xFFD4D4D8), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final OpenHABItem item;
  final VoidCallback onDelete;

  const _ItemCard({required this.item, required this.onDelete});

  FaIconData get _icon {
    switch (item.iconKey) {
      case 'lightbulb':
        return FontAwesomeIcons.lightbulb;
      case 'temperature':
        return FontAwesomeIcons.temperatureHalf;
      case 'tv':
        return FontAwesomeIcons.tv;
      case 'speaker':
        return FontAwesomeIcons.volumeHigh;
      case 'fan':
        return FontAwesomeIcons.fan;
      case 'dimmer':
        return FontAwesomeIcons.sliders;
      default:
        return FontAwesomeIcons.toggleOn;
    }
  }

  Color get _typeColor {
    switch (item.type) {
      case 'Switch':
        return const Color(0xFF6366F1);
      case 'Dimmer':
        return const Color(0xFFF59E0B);
      case 'Number':
        return const Color(0xFF0EA5E9);
      case 'Color':
        return const Color(0xFFEC4899);
      case 'Player':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF71717A);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _typeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: FaIcon(_icon, size: 20, color: _typeColor),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Color(0xCC18181B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: Color(0xFF71717A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _typeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.type,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _typeColor,
                          ),
                        ),
                      ),
                      if (item.state != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          'State: ${item.state}',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            color: Color(0xFF71717A),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.red, size: 20),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _ThingDetailSheet extends StatefulWidget {
  final OHThing thing;
  final OpenHABManagementService mgmt;

  const _ThingDetailSheet({required this.thing, required this.mgmt});

  @override
  State<_ThingDetailSheet> createState() => _ThingDetailSheetState();
}

class _ThingDetailSheetState extends State<_ThingDetailSheet> {
  final Map<String, TextEditingController> _itemNameCtrls = {};
  final Map<String, bool> _linking = {};

  @override
  void initState() {
    super.initState();
    for (final ch in widget.thing.channels) {
      _itemNameCtrls[ch.uid] = TextEditingController(
        text: ch.linkedItems.isNotEmpty ? ch.linkedItems.first : '',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _itemNameCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _linkChannel(OHChannel channel) async {
    final itemName = _itemNameCtrls[channel.uid]?.text.trim() ?? '';
    if (itemName.isEmpty) return;

    // Ambil sebelum await (hindari BuildContext lintas async gap).
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _linking[channel.uid] = true);
    try {
      await widget.mgmt.linkChannelToItem(
          channelUID: channel.uid, itemName: itemName);
      messenger.showSnackBar(SnackBar(
        content: Text('Channel di-link ke item "$itemName"'),
        backgroundColor: const Color(0xFF34C759),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Gagal: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } finally {
      if (mounted) setState(() => _linking[channel.uid] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Handle
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: widget.thing.isOnline
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: FaIcon(
                          FontAwesomeIcons.microchip,
                          size: 20,
                          color: widget.thing.isOnline
                              ? const Color(0xFF16A34A)
                              : Colors.red,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.thing.label.isNotEmpty
                                ? widget.thing.label
                                : widget.thing.uid,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              color: Color(0xCC18181B),
                            ),
                          ),
                          Text(
                            widget.thing.uid,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: Color(0xFF71717A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),

              // Channels
              Expanded(
                child: widget.thing.channels.isEmpty
                    ? Center(
                        child: Text(
                          'Tidak ada channels',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              color: Colors.grey.shade400),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(
                            16, 12, 16, 40),
                        itemCount: widget.thing.channels.length,
                        itemBuilder: (_, i) {
                          final ch = widget.thing.channels[i];
                          return _ChannelLinkCard(
                            channel: ch,
                            itemNameCtrl:
                                _itemNameCtrls[ch.uid]!,
                            isLinking:
                                _linking[ch.uid] ?? false,
                            onLink: () => _linkChannel(ch),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}


class _ChannelLinkCard extends StatelessWidget {
  final OHChannel channel;
  final TextEditingController itemNameCtrl;
  final bool isLinking;
  final VoidCallback onLink;

  const _ChannelLinkCard({
    required this.channel,
    required this.itemNameCtrl,
    required this.isLinking,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const FaIcon(FontAwesomeIcons.link,
                  size: 14, color: Color(0xFF6366F1)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  channel.label.isNotEmpty ? channel.label : channel.id,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xCC18181B),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  channel.itemType,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            channel.uid,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: Color(0xFF71717A),
            ),
          ),
          if (channel.linkedItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.check_circle,
                    size: 12, color: Color(0xFF16A34A)),
                const SizedBox(width: 4),
                Text(
                  'Linked: ${channel.linkedItems.join(', ')}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: itemNameCtrl,
                  style: const TextStyle(
                      fontFamily: 'Inter', fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Nama item (contoh: MyLight)',
                    hintStyle: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Color(0xFFE4E4E7)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Color(0xFFE4E4E7)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Color(0xFF6366F1), width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: isLinking ? null : onLink,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isLinking
                        ? Colors.grey.shade200
                        : const Color(0xFF6366F1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: isLinking
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white),
                        )
                      : const Text(
                          'Link',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}