import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/pages/energy_page.dart';
import 'package:mobile/pages/floor_plan_page.dart';
import 'package:mobile/pages/settings_page.dart';
import 'package:mobile/core/services/app_notification_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/providers/installation_provider.dart';
import '../../../../core/controllers/openhab_controller.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  final _ctrl = OpenHABController.instance;
  final _svc  = AppNotificationService.instance;

  List<AppNotif> get _notifs => _svc.items;

  bool _isSelectionMode = false;
  final _selectedIds    = <String>{};

  late bool _isLoading = !_svc.ready;
  bool      _isDeleting = false;
  String?   _error;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onSvcChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _svc.removeListener(_onSvcChanged);
    super.dispose();
  }

  void _onSvcChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    if (!_ctrl.isConnected) {
      setState(() {
        _isLoading = false;
        _error     = 'Server openHAB tidak terhubung.\nPeriksa konfigurasi di Settings.';
      });
      return;
    }
    await _svc.startFromContext(context);
    if (mounted) setState(() { _isLoading = false; _error = null; });
  }

  Future<Map<String, String>> _headers() async => AppNotificationService
      .buildHeaders(context.read<InstallationProvider>().config);

  Future<bool> _ignoreInboxItem(String thingUID) async {
    if (thingUID.isEmpty) return false;
    try {
      final h   = await _headers();
      final uri = Uri.parse(
          '${_ctrl.serverUrl}/rest/inbox/${Uri.encodeComponent(thingUID)}/ignore');
      final res = await http
          .post(uri, headers: h)
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200 || res.statusCode == 204) return true;

      final delUri = Uri.parse(
          '${_ctrl.serverUrl}/rest/inbox/${Uri.encodeComponent(thingUID)}');
      final delRes = await http
          .delete(delUri, headers: h)
          .timeout(const Duration(seconds: 8));
      return delRes.statusCode == 200 || delRes.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  void _enterSelectionMode() {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == _notifs.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(_notifs.map((n) => n.id));
      }
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    if (count == 0) return;

    final confirm = await _showDeleteConfirm(count);
    if (confirm != true) return;

    setState(() => _isDeleting = true);

    final toDelete = _notifs.where((n) => _selectedIds.contains(n.id)).toList();

    final inboxItems    = toDelete.where((n) => n.type == AppNotifType.inbox).toList();
    final nonInboxItems = toDelete.where((n) => n.type != AppNotifType.inbox).toList();

    int ohSuccess = 0;
    int ohFailed  = 0;
    if (inboxItems.isNotEmpty) {
      final results = await Future.wait(
        inboxItems.map((n) => _ignoreInboxItem(n.thingUID ?? '')),
      );
      for (final ok in results) {
        if (ok) {
          ohSuccess++;
        } else {
          ohFailed++;
        }
      }
    }

    setState(() {
      _svc.removeByIds(Set<String>.of(_selectedIds));
      _selectedIds.clear();
      _isSelectionMode = false;
      _isDeleting      = false;
    });

    if (!mounted) return;
    if (inboxItems.isNotEmpty) {
      if (ohFailed > 0) {
        _showSnackbar(
          '${nonInboxItems.length + ohSuccess} notifikasi dihapus · '
          '$ohFailed inbox gagal dihapus dari openHAB',
          isError: true,
        );
      } else {
        _showSnackbar(
          '${toDelete.length} notifikasi dihapus'
          '${ohSuccess > 0 ? ' · $ohSuccess inbox dihapus dari openHAB' : ''}',
        );
      }
    } else {
      _showSnackbar('${toDelete.length} notifikasi dihapus');
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          FaIcon(
            isError
                ? FontAwesomeIcons.triangleExclamation
                : FontAwesomeIcons.circleCheck,
            size: 16,
            color: Colors.white,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    fontFamily: 'Inter', fontSize: 13)),
          ),
        ]),
        backgroundColor:
            isError ? const Color(0xFFEF4444) : const Color(0xFF34C759),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<bool?> _showDeleteConfirm(int count) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedItems =
        _notifs.where((n) => _selectedIds.contains(n.id)).toList();
    final hasInbox =
        selectedItems.any((n) => n.type == AppNotifType.inbox);

    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor:
            isDark ? const Color(0xFF27272A) : Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: FaIcon(FontAwesomeIcons.trash,
                      size: 22, color: Color(0xFFEF4444)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Hapus Notifikasi',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: isDark ? Colors.white : const Color(0xFF18181B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                count == _notifs.length
                    ? 'Semua notifikasi akan dihapus.'
                    : '$count notifikasi akan dihapus.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: isDark
                      ? Colors.white54
                      : const Color(0xFF71717A),
                ),
              ),
              if (hasInbox) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FaIcon(FontAwesomeIcons.circleInfo,
                          size: 13, color: Color(0xFF3B82F6)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Notifikasi inbox akan di-ignore di openHAB '
                          'dan tidak muncul kembali.',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            height: 1.4,
                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF3B82F6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF3F3F46)
                            : const Color(0xFFF5F5F7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text('Batal',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF18181B),
                            )),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text('Hapus',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.white,
                            )),
                      ),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptionsMenu(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF27272A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _buildMenuTile(
              icon: FontAwesomeIcons.squareCheck,
              iconColor: const Color(0xFF3B82F6),
              label: 'Pilih Notifikasi',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                _enterSelectionMode();
              },
            ),
            Divider(height: 1, thickness: 1,
                color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF0F0F0),
                indent: 56),
            _buildMenuTile(
              icon: FontAwesomeIcons.checkDouble,
              iconColor: const Color(0xFFFFA500),
              label: 'Tandai Semua Dibaca',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                _markAllRead();
              },
            ),
            Divider(height: 1, thickness: 1,
                color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF0F0F0),
                indent: 56),
            _buildMenuTile(
              icon: FontAwesomeIcons.trashCan,
              iconColor: const Color(0xFFEF4444),
              label: 'Hapus Semua Notifikasi',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _selectedIds
                    ..clear()
                    ..addAll(_notifs.map((n) => n.id));
                  _isSelectionMode = true;
                });
                _deleteSelected();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTile({
    required FaIconData icon,
    required Color iconColor,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          FaIcon(icon, size: 18, color: iconColor),
          const SizedBox(width: 16),
          Text(label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : const Color(0xFF18181B),
              )),
        ]),
      ),
    );
  }

  Map<String, List<AppNotif>> _grouped() {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final week  = today.subtract(const Duration(days: 7));

    final groups = <String, List<AppNotif>>{
      'BARU': [], 'HARI INI': [], 'MINGGU INI': [], 'LEBIH LAMA': [],
    };

    for (final n in _notifs) {
      final d = DateTime(n.time.year, n.time.month, n.time.day);
      if (d == today && now.difference(n.time).inMinutes < 60) {
        groups['BARU']!.add(n);
      } else if (d == today) {
        groups['HARI INI']!.add(n);
      } else if (d.isAfter(week)) {
        groups['MINGGU INI']!.add(n);
      } else {
        groups['LEBIH LAMA']!.add(n);
      }
    }

    groups.removeWhere((_, v) => v.isEmpty);
    return groups;
  }

  void _markAllRead() => _svc.markAllRead();

  int get _unreadCount => _notifs.where((n) => !n.isRead).length;

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24)   return '${diff.inHours} jam lalu';
    if (diff.inDays < 7)     return '${diff.inDays} hari lalu';
    return '${t.day}/${t.month}/${t.year}';
  }
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Stack(
          children: [
            Column(children: [
              Expanded(
                child: _isLoading
                    ? _buildLoading(isDark)
                    : _error != null
                        ? _buildError(isDark)
                        : _notifs.isEmpty
                            ? _buildEmpty(isDark)
                            : _buildList(isDark),
              ),
              if (_isSelectionMode)
                _buildSelectionBar(isDark)
              else
                _buildBottomNav(context, isDark),
            ]),
            if (_isDeleting)
              Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(
                        color: Color(0xFFFFA500), strokeWidth: 2.5),
                    SizedBox(height: 14),
                    Text('Menghapus dari openHAB...',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none,
                        )),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionBar(bool isDark) {
    final hasSelection = _selectedIds.isNotEmpty;
    final selectedItems =
        _notifs.where((n) => _selectedIds.contains(n.id)).toList();
    final inboxCount =
        selectedItems.where((n) => n.type == AppNotifType.inbox).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasSelection && inboxCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const FaIcon(FontAwesomeIcons.circleInfo,
                      size: 11, color: Color(0xFF3B82F6)),
                  const SizedBox(width: 6),
                  Text(
                    '$inboxCount inbox akan di-ignore di openHAB',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: Color(0xFF3B82F6),
                    ),
                  ),
                ],
              ),
            ),
          GestureDetector(
            onTap: hasSelection ? _deleteSelected : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                color: hasSelection
                    ? const Color(0xFFEF4444)
                    : const Color(0xFFEF4444).withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const FaIcon(FontAwesomeIcons.trash,
                      size: 16, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    hasSelection
                        ? 'Hapus ${_selectedIds.length} Notifikasi'
                        : 'Pilih notifikasi untuk dihapus',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(bool isDark) {
    if (!_isSelectionMode) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: SizedBox(
              width: 28, height: 28,
              child: Center(
                child: FaIcon(FontAwesomeIcons.arrowLeft,
                    size: 18,
                    color: isDark ? Colors.white : const Color(0xCC18181B)),
              ),
            ),
          ),
          Expanded(
            child: Text('Notifications',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                  color: isDark ? Colors.white : const Color(0xCC18181B),
                )),
          ),
          GestureDetector(
            onTap: () => _showOptionsMenu(context, isDark),
            child: SizedBox(
              width: 28, height: 28,
              child: Center(
                child: FaIcon(FontAwesomeIcons.ellipsisVertical,
                    size: 16,
                    color: isDark ? Colors.white : const Color(0xCC18181B)),
              ),
            ),
          ),
        ]),
      );
    }

    final allSelected = _selectedIds.length == _notifs.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        GestureDetector(
          onTap: _exitSelectionMode,
          child: SizedBox(
            width: 28, height: 28,
            child: Center(
              child: FaIcon(FontAwesomeIcons.xmark,
                  size: 18,
                  color: isDark ? Colors.white : const Color(0xCC18181B)),
            ),
          ),
        ),
        Expanded(
          child: Text(
            _selectedIds.isEmpty
                ? 'Pilih Notifikasi'
                : '${_selectedIds.length} dipilih',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: isDark ? Colors.white : const Color(0xCC18181B),
            ),
          ),
        ),
        GestureDetector(
          onTap: _toggleSelectAll,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: allSelected
                  ? const Color(0xFFFFA500)
                  : (isDark
                      ? const Color(0xFF3F3F46)
                      : const Color(0xFFF0F0F0)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              allSelected ? 'Batal Semua' : 'Semua',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: allSelected
                    ? Colors.white
                    : (isDark
                        ? Colors.white70
                        : const Color(0xFF18181B)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildLoading(bool isDark) {
    return Column(children: [
      const SizedBox(height: 16),
      _buildAppBar(isDark),
      const Expanded(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(
                color: Color(0xFFFFA500), strokeWidth: 2.5),
            SizedBox(height: 16),
            Text('Memuat notifikasi...',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: Color(0xFF71717A))),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildError(bool isDark) {
    return Column(children: [
      const SizedBox(height: 16),
      _buildAppBar(isDark),
      Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: FaIcon(FontAwesomeIcons.plugCircleExclamation,
                      size: 28, color: Color(0xFFEF4444)),
                ),
              ),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: isDark
                        ? Colors.white54
                        : const Color(0xFF71717A),
                    height: 1.5,
                  )),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isLoading = true;
                    _error     = null;
                  });
                  _bootstrap();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFA500),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Coba Lagi',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.white,
                      )),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _buildEmpty(bool isDark) {
    return Column(children: [
      const SizedBox(height: 16),
      _buildAppBar(isDark),
      Expanded(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFFFA500).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: FaIcon(FontAwesomeIcons.bellSlash,
                    size: 28, color: Color(0xFFFFA500)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Belum Ada Notifikasi',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: isDark ? Colors.white : const Color(0xFF18181B),
                )),
            const SizedBox(height: 6),
            Text(
              'Notifikasi dari server openHAB\nakan muncul di sini secara realtime.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: isDark
                    ? Colors.white54
                    : const Color(0xFF71717A),
                height: 1.5,
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildList(bool isDark) {
    final groups = _grouped();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(children: [
            const SizedBox(height: 16),
            _buildAppBar(isDark),
            if (!_isSelectionMode && _unreadCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFA500).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const FaIcon(FontAwesomeIcons.circleDot,
                        size: 12, color: Color(0xFFFFA500)),
                    const SizedBox(width: 8),
                    Text('$_unreadCount notifikasi belum dibaca',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: Color(0xFFFFA500),
                          fontWeight: FontWeight.w500,
                        )),
                    const Spacer(),
                    GestureDetector(
                      onTap: _markAllRead,
                      child: const Text('Tandai semua',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: Color(0xFFFFA500),
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFFFFA500),
                          )),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
          ]),
        ),
        for (final entry in groups.entries)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 10),
                    child: Text(entry.key,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                          letterSpacing: 0.8,
                          color: isDark
                              ? Colors.white38
                              : const Color(0xFF9E9E9E),
                        )),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF27272A)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: isDark ? 0.2 : 0.055),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: List.generate(entry.value.length, (i) {
                        final item = entry.value[i];
                        return Column(children: [
                          _buildNotifRow(item, isDark),
                          if (i < entry.value.length - 1)
                            Divider(
                              height: 1, thickness: 1,
                              color: isDark
                                  ? const Color(0xFF3F3F46)
                                  : const Color(0xFFF0F0F0),
                              indent: 74,
                            ),
                        ]);
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_isSelectionMode)
          const SliverToBoxAdapter(child: SizedBox(height: 110)),
      ],
    );
  }

  Widget _buildNotifRow(AppNotif item, bool isDark) {
    final isSelected = _selectedIds.contains(item.id);

    return GestureDetector(
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelect(item.id);
        } else {
          _svc.markRead(item);
        }
      },
      onLongPress: () {
        if (!_isSelectionMode) {
          _enterSelectionMode();
          _toggleSelect(item.id);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFEF4444).withValues(alpha: 0.08)
              : item.isRead
                  ? Colors.transparent
                  : (isDark
                      ? const Color(0xFFFFA500).withValues(alpha: 0.06)
                      : const Color(0xFFFFFBF2)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFEF4444)
                          : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFEF4444)
                            : (isDark
                                ? Colors.white38
                                : const Color(0xFFD1D1D1)),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check,
                            size: 16, color: Colors.white)
                        : null,
                  ),
                )
              else
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                      color: item.iconBg, shape: BoxShape.circle),
                  child: Center(
                      child:
                          Icon(item.icon, size: 20, color: Colors.white)),
                ),
              SizedBox(width: _isSelectionMode ? 12 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      if (_isSelectionMode)
                        Container(
                          width: 28, height: 28,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                              color: item.iconBg,
                              shape: BoxShape.circle),
                          child: Center(
                              child: Icon(item.icon,
                                  size: 14, color: Colors.white)),
                        ),
                      Expanded(
                        child: Text(item.title,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xCC18181B),
                            )),
                      ),
                      if (!_isSelectionMode && !item.isRead)
                        Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(
                              color: Color(0xFFFFA500),
                              shape: BoxShape.circle),
                        ),
                      if (!_isSelectionMode &&
                          item.type == AppNotifType.inbox)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('openHAB',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF3B82F6),
                              )),
                        ),
                    ]),
                    const SizedBox(height: 3),
                    Text(item.subtitle,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                          fontSize: 12,
                          color: isDark
                              ? Colors.white54
                              : const Color(0xFF71717A),
                          height: 1.4,
                        )),
                    const SizedBox(height: 4),
                    Text(_timeAgo(item.time),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          color: isDark
                              ? Colors.white38
                              : const Color(0xFFB0B0B0),
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context, bool isDark) {
    const navItems = [
      _NavItem(icon: FontAwesomeIcons.house,         label: 'Home'),
      _NavItem(icon: FontAwesomeIcons.bolt,          label: 'Energy'),
      _NavItem(icon: FontAwesomeIcons.mapLocationDot, label: 'Floorplan'),
      _NavItem(icon: FontAwesomeIcons.gear,          label: 'Settings'),
    ];
    const selectedIndex = 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(navItems.length, (i) {
          final isSelected = i == selectedIndex;
          return GestureDetector(
            onTap: () {
              if (i == 0) { Navigator.pop(context); return; }
              if (i == 1) { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const EnergyPage())); return; }
              if (i == 2) { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const FloorPlanPage())); return; }
              if (i == 3) { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SettingsPage())); return; }
            },
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FaIcon(navItems[i].icon,
                  size: 20,
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? Colors.white38 : Colors.black38)),
              const SizedBox(height: 4),
              Text(navItems[i].label,
                  style: AppTypography.bodySmall.copyWith(
                    fontSize: 11,
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? Colors.white38 : Colors.black38),
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  )),
            ]),
          );
        }),
      ),
    );
  }
}


class _NavItem {
  final FaIconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}