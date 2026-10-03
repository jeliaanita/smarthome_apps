import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mobile/core/services/openhab_management_service.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:mobile/core/utils/responsive_utils.dart';

/// Halaman Discovery: scan binding yang mendukung auto-discovery (WiZ, Hue,
/// mDNS, dsb), lalu tampilkan hasil temuan dari Inbox openHAB untuk
/// di-approve jadi Thing, diabaikan, atau dihapus.
class DiscoveryPage extends StatefulWidget {
  /// Kalau diisi, halaman langsung memicu Scan untuk binding ini begitu
  /// dibuka — dipakai saat Add Thing menemukan 0 thing type manual dan
  /// mengarahkan user langsung ke Discovery untuk binding yang sama.
  final String? initialBindingId;
  const DiscoveryPage({super.key, this.initialBindingId});

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage> {
  final _mgmt = OpenHABManagementService();

  List<String> _bindings = [];
  List<OHInboxEntry> _inbox = [];
  bool _loadingBindings = true;
  bool _loadingInbox = true;
  String? _scanningBinding;
  Timer? _pollTimer;
  String? _errorMsg;

  bool _didApprove = false;
  Timer? _backgroundPollTimer;

  @override
  void initState() {
    super.initState();
    _loadBindings();
    _loadInbox();
    // openHAB sendiri sudah auto-discover di background untuk binding
    // yang mendukungnya (mis. LG webOS via SSDP, Sony via UPnP) — TV
    // bisa nongol di Inbox kapan saja begitu nyala, bukan cuma pas
    // tombol Scan ditekan. Makanya kita polling ringan di sini selama
    // halaman ini terbuka, supaya hasilnya kelihatan tanpa perlu aksi
    // manual user.
    _backgroundPollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadInbox(silent: true),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _backgroundPollTimer?.cancel();
    super.dispose();
  }

  /// Bersihkan pesan error dari prefix teknis ("Exception: ", dsb)
  /// supaya pesan yang tampil ke user lebih akurat & mudah dibaca.
  String _cleanError(Object e) {
    return e.toString().replaceFirst(
        RegExp(r'^(OpenHABException|Exception):\s*'), '');
  }

  Future<void> _loadBindings() async {
    setState(() { _loadingBindings = true; _errorMsg = null; });
    try {
      final bindings = await _mgmt.getDiscoveryBindings();
      if (mounted) setState(() => _bindings = bindings);

      // Kalau dibuka dari Add Thing dengan binding tertentu (0 thing type
      // manual), langsung picu scan untuk binding itu tanpa user harus
      // cari & tap lagi.
      final initial = widget.initialBindingId;
      if (initial != null && mounted) {
        if (bindings.contains(initial)) {
          _scan(initial);
        } else {
          // Dead-end sungguhan: binding tidak punya thing type manual
          // MAUPUN Discovery. Ini kemungkinan besar masalah di sisi
          // binding/server, bukan sesuatu yang bisa diperbaiki dari app.
          setState(() => _errorMsg =
              'Binding "$initial" tidak memiliki thing type manual maupun '
              'dukungan Discovery. Kemungkinan binding gagal load penuh di '
              'server, atau versi openHAB tidak cocok — cek log server openHAB.');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _errorMsg = _cleanError(e));
    } finally {
      if (mounted) setState(() => _loadingBindings = false);
    }
  }

  Future<void> _loadInbox({bool silent = false}) async {
    if (!silent) setState(() => _loadingInbox = true);
    try {
      final entries = await _mgmt.getInboxEntries();
      if (mounted) {
        setState(() =>
            _inbox = entries.where((e) => e.flag != 'IGNORED').toList());
      }
    } catch (e) {
      // Polling background diam-diam kalau gagal (mis. koneksi sempat
      // putus) — jangan timpa pesan error yang lagi ditampilkan ke user
      // hanya karena satu siklus polling gagal.
      if (mounted && !silent) setState(() => _errorMsg = _cleanError(e));
    } finally {
      if (mounted && !silent) setState(() => _loadingInbox = false);
    }
  }

  Future<void> _scan(String bindingId) async {
    setState(() { _scanningBinding = bindingId; _errorMsg = null; });
    try {
      await _mgmt.startScan(bindingId);
    } catch (e) {
      if (mounted) {
        setState(() { _errorMsg = _cleanError(e); _scanningBinding = null; });
      }
      return;
    }

    // Scan berjalan async di server (biasanya perangkat butuh beberapa
    // detik untuk merespons broadcast/mDNS). Poll Inbox beberapa kali
    // selama proses scan, bukan cuma sekali langsung setelah trigger.
    _pollTimer?.cancel();
    var attempts = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      attempts++;
      await _loadInbox();
      if (attempts >= 6 || !mounted) {
        timer.cancel();
        if (mounted) setState(() => _scanningBinding = null);
      }
    });
  }

  Future<void> _approve(OHInboxEntry entry) async {
    final labelCtrl = TextEditingController(text: entry.label);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tambahkan sebagai Thing',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
        content: TextField(
          controller: labelCtrl,
          style: const TextStyle(fontFamily: 'Inter'),
          decoration: const InputDecoration(labelText: 'Label'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Tambahkan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _mgmt.approveInboxEntry(entry.thingUID, label: labelCtrl.text.trim());
      _didApprove = true;

      // Thing baru dibuat, tapi Channel-nya belum otomatis kelihatan di
      // Home/Floor Plan — Channel harus di-link ke Item dulu. Kita
      // buatkan & link otomatis di sini, supaya user tidak perlu buka
      // Items Management dan link satu-satu secara manual.
      final linkedCount = await _autoLinkChannels(entry.thingUID);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(linkedCount > 0
              ? '"${entry.label}" ditambahkan, $linkedCount channel siap dipakai di Home'
              : '"${entry.label}" berhasil ditambahkan sebagai Thing'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        await _loadInbox();
      }
    } catch (e) {
      if (mounted) setState(() => _errorMsg = _cleanError(e));
    }
  }

  /// Auto-buat & link Item untuk tiap Channel milik Thing yang baru
  /// di-approve, supaya langsung terkontrol di Home/Floor Plan tanpa
  /// harus buka Items Management manual.
  ///
  /// Nama Item yang dihasilkan bersifat teknis (dari UID Thing +
  /// Channel), bukan nama yang cantik — kamu bisa ganti Label-nya
  /// belakangan lewat Edit Item kalau mau nama yang lebih rapi.
  Future<int> _autoLinkChannels(String thingUID) async {
    OHThing? thing;
    // Server butuh sedikit waktu menginstansiasi Thing setelah approve,
    // jadi coba beberapa kali dengan jeda alih-alih langsung menyerah.
    for (var attempt = 0; attempt < 4 && thing == null; attempt++) {
      if (attempt > 0) await Future.delayed(const Duration(seconds: 1));
      try {
        final things = await _mgmt.getThings();
        thing = things.where((t) => t.uid == thingUID).isNotEmpty
            ? things.firstWhere((t) => t.uid == thingUID)
            : null;
      } catch (_) {}
    }
    if (thing == null) return 0;

    var linked = 0;
    for (final channel in thing.channels) {
      if (channel.linkedItems.isNotEmpty) continue; // sudah ada, skip
      final itemName = _sanitizeItemName('${thing.uid}_${channel.id}');
      final itemType = channel.itemType.isNotEmpty ? channel.itemType : 'String';
      try {
        await _mgmt.addOrUpdateItem(
          name: itemName,
          type: itemType,
          label: channel.label.isNotEmpty ? channel.label : channel.id,
        );
        await _mgmt.linkChannelToItem(channelUID: channel.uid, itemName: itemName);
        linked++;
      } catch (_) {
        // Best-effort per channel — satu channel gagal tidak
        // menghentikan channel lainnya. Yang gagal masih bisa di-link
        // manual lewat Items Management.
      }
    }
    return linked;
  }

  /// openHAB Item name cuma boleh huruf/angka/underscore — UID Thing
  /// biasanya mengandung ":" (mis. "lgwebos:WebOSTV:xxxx").
  String _sanitizeItemName(String raw) =>
      raw.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');

  Future<void> _ignore(OHInboxEntry entry) async {
    try {
      await _mgmt.ignoreInboxEntry(entry.thingUID);
      await _loadInbox();
    } catch (e) {
      if (mounted) setState(() => _errorMsg = _cleanError(e));
    }
  }

  Future<void> _remove(OHInboxEntry entry) async {
    try {
      await _mgmt.removeInboxEntry(entry.thingUID);
      await _loadInbox();
    } catch (e) {
      if (mounted) setState(() => _errorMsg = _cleanError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      appBar: _buildAppBar(context),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([_loadBindings(), _loadInbox()]),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              ResponsiveUtils.horizontalPadding(context), 16,
              ResponsiveUtils.horizontalPadding(context), 40),
          children: [
            if (_errorMsg != null) _buildErrorBanner(),
            _buildSectionTitle('Binding Mendukung Discovery', context),
            const SizedBox(height: 4),
            Text('Tap Scan untuk mencari perangkat baru di jaringan.',
                style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.grey.shade500)),
            const SizedBox(height: 10),
            _buildBindingsSection(context),

            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: _buildSectionTitle('Hasil Ditemukan', context)),
              const SizedBox(width: 8),
              Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(
                    color: AppColors.success, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text('memantau otomatis',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 10,
                      color: isDark ? Colors.white38 : Colors.grey.shade500)),
            ]),
            const SizedBox(height: 4),
            Text(
              'Perangkat yang mendukung Discovery (mis. TV, WiZ) muncul '
              'otomatis di sini begitu nyala di jaringan yang sama — '
              'tidak perlu tekan Scan berulang. Setujui untuk menambahkan '
              'sebagai Thing.',
              style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.grey.shade500),
            ),
            const SizedBox(height: 10),
            _buildInboxSection(context),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: cs.surface,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new, size: 18, color: cs.onSurface),
        onPressed: () => Navigator.pop(context, _didApprove),
      ),
      title: Text('Discovery',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
              fontSize: 18, color: cs.onSurface)),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(children: [
        Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(_errorMsg!,
            style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.red.shade700))),
      ]),
    );
  }

  Widget _buildSectionTitle(String title, BuildContext context) {
    return Text(title,
        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
            fontSize: 14, color: Theme.of(context).colorScheme.onSurface));
  }

  Widget _buildBindingsSection(BuildContext context) {
    if (_loadingBindings) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_bindings.isEmpty) {
      return _buildEmptyState(
        context,
        icon: FontAwesomeIcons.magnifyingGlass,
        title: 'Tidak ada binding dengan Discovery',
        subtitle: 'Install binding yang mendukung auto-discovery lewat Addon Store.',
      );
    }

    return Wrap(
      spacing: 10, runSpacing: 10,
      children: _bindings.map((bindingId) {
        final isScanning = _scanningBinding == bindingId;
        return _buildDetailCard(context, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            FaIcon(FontAwesomeIcons.puzzlePiece, size: 14, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(bindingId,
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
                    fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: (_scanningBinding == null) ? () => _scan(bindingId) : null,
              child: isScanning
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Scan',
                          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                              fontSize: 12, color: AppColors.primary)),
                    ),
            ),
          ]),
        ));
      }).toList(),
    );
  }

  Widget _buildInboxSection(BuildContext context) {
    if (_loadingInbox) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_inbox.isEmpty) {
      return _buildEmptyState(
        context,
        icon: FontAwesomeIcons.inbox,
        title: 'Belum ada perangkat ditemukan',
        subtitle: 'Jalankan Scan pada binding di atas untuk mencari perangkat baru.',
      );
    }

    return Column(
      children: _inbox.map((entry) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _buildDetailCard(context, child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(child: FaIcon(FontAwesomeIcons.microchip,
                  size: 16, color: AppColors.primary)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.label,
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                      fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(entry.thingUID,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 11,
                      color: AppColors.textMuted),
                  overflow: TextOverflow.ellipsis),
            ])),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _approve(entry),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.check, size: 18, color: AppColors.success),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showEntryMenu(entry),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.more_vert, size: 18, color: AppColors.textMuted),
              ),
            ),
          ]),
        )),
      )).toList(),
    );
  }

  void _showEntryMenu(OHInboxEntry entry) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF27272A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.visibility_off, color: AppColors.textMuted),
              title: const Text('Abaikan', style: TextStyle(fontFamily: 'Inter')),
              onTap: () { Navigator.pop(sheetContext); _ignore(entry); },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Hapus dari Inbox',
                  style: TextStyle(fontFamily: 'Inter', color: Colors.red)),
              onTap: () { Navigator.pop(sheetContext); _remove(entry); },
            ),
          ]),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context,
      {required FaIconData icon, required String title, required String subtitle}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _buildDetailCard(context, child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(children: [
        FaIcon(icon, size: 28, color: AppColors.textMuted),
        const SizedBox(height: 12),
        Text(title,
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 4),
        Text(subtitle, textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                color: isDark ? Colors.white38 : Colors.grey.shade500)),
      ]),
    ));
  }

  Widget _buildDetailCard(BuildContext context, {required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }
}