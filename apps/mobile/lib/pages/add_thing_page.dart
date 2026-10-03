import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mobile/core/services/openhab_management_service.dart';
import 'package:mobile/core/controllers/openhab_controller.dart';
import 'package:mobile/pages/discovery_page.dart';
import 'package:mobile/core/utils/responsive_utils.dart';
import '../../../../core/providers/installation_provider.dart';
import '../../../../core/providers/role_provider.dart';
import 'package:mobile/core/widget/access_denied_view.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

class AddThingPage extends StatefulWidget {
  const AddThingPage({super.key});

  @override
  State<AddThingPage> createState() => _AddThingPageState();
}

class _AddThingPageState extends State<AddThingPage> {
  final _formKey = GlobalKey<FormState>();
  final _mgmt = OpenHABManagementService();
  final _ctrl = OpenHABController.instance;

  int _step = 0;

  List<OHBinding> _bindings = [];
  List<OHBinding> _filteredBindings = [];
  List<OHThingType> _thingTypes = [];
  List<OHThingType> _filteredThingTypes = [];
  OHBinding? _selectedBinding;
  OHThingType? _selectedThingType;

  final _labelCtrl  = TextEditingController();
  final _uidCtrl    = TextEditingController();
  final _bridgeCtrl = TextEditingController();
  final Map<String, _ConfigField> _configFields = {};

  // ── Search (Binding & Thing Type step) ──────────────────────────────────
  final _bindingSearchCtrl   = TextEditingController();
  final _thingTypeSearchCtrl = TextEditingController();
  String _bindingSearchQuery   = '';
  String _thingTypeSearchQuery = '';

  bool _loadingBindings = false;
  bool _loadingTypes    = false;
  bool _submitting      = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _mgmt.setBaseUrl(_ctrl.serverUrl);
    _initAndLoad();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _uidCtrl.dispose();
    _bridgeCtrl.dispose();
    _bindingSearchCtrl.dispose();
    _thingTypeSearchCtrl.dispose();
    for (final f in _configFields.values) {
      f.controller?.dispose();
    }
    super.dispose();
  }

  Future<void> _initAndLoad() async {
    // ⚠️ FIX: sebelumnya cek ini berdasarkan ada-tidaknya token/username,
    // padahal openHAB DEFAULTNYA TIDAK BUTUH AUTH SAMA SEKALI kecuali
    // authentication sengaja diaktifkan di server-nya. Banyak instalasi
    // openHAB lokal/rumahan jalan tanpa token & tanpa username/password —
    // itu kondisi VALID, bukan berarti "belum dikonfigurasi". Indikator
    // yang benar untuk "sudah dikonfigurasi" adalah server URL-nya terisi,
    // bukan kredensialnya.
    if (_ctrl.serverUrl.isEmpty) {
      if (mounted) {
        setState(() => _errorMsg =
          'openHAB belum dikonfigurasi. Silakan atur di Settings → openHAB Server.');
      }
      return;
    }

    final config = context.read<InstallationProvider>().config;
    final token    = config?.apiToken;
    final username = config?.username;
    final password = config?.password;

    if (token != null && token.isNotEmpty) {
      _mgmt.setApiToken(token);
    } else if (username != null && password != null) {
      _mgmt.setBasicAuth(username, password);
    }
    // Kalau tidak ada token maupun username/password, itu OK — lanjut tanpa
    // auth (banyak instalasi openHAB memang begini).

    await _loadBindings();
  }

  Future<void> _loadBindings() async {
    setState(() { _loadingBindings = true; _errorMsg = null; });
    try {
      final bindings = await _mgmt.getBindings();
      setState(() {
        _bindings = bindings;
        _applyBindingFilter();
      });
    } catch (e) {
      setState(() => _errorMsg = 'Gagal memuat bindings: ${_cleanError(e)}');
    } finally {
      setState(() => _loadingBindings = false);
    }
  }

  void _applyBindingFilter() {
    setState(() {
      if (_bindingSearchQuery.isEmpty) {
        _filteredBindings = List.from(_bindings);
      } else {
        final q = _bindingSearchQuery.toLowerCase();
        _filteredBindings = _bindings.where((b) =>
            b.name.toLowerCase().contains(q) ||
            b.id.toLowerCase().contains(q) ||
            b.description.toLowerCase().contains(q)).toList();
      }
    });
  }

  Future<void> _loadThingTypes(String bindingId) async {
    setState(() {
      _loadingTypes = true;
      _errorMsg = null;
      _thingTypes = [];
      _filteredThingTypes = [];
      _thingTypeSearchCtrl.clear();
      _thingTypeSearchQuery = '';
    });
    try {
      final types = await _mgmt.getThingTypes(bindingId: bindingId);
      setState(() {
        _thingTypes = types;
        _applyThingTypeFilter();
      });
    } catch (e) {
      setState(() => _errorMsg = 'Gagal memuat thing types: ${_cleanError(e)}');
    } finally {
      setState(() => _loadingTypes = false);
    }
  }

  void _applyThingTypeFilter() {
    setState(() {
      if (_thingTypeSearchQuery.isEmpty) {
        _filteredThingTypes = List.from(_thingTypes);
      } else {
        final q = _thingTypeSearchQuery.toLowerCase();
        _filteredThingTypes = _thingTypes.where((t) =>
            t.label.toLowerCase().contains(q) ||
            t.uid.toLowerCase().contains(q) ||
            t.description.toLowerCase().contains(q)).toList();
      }
    });
  }

  void _selectBinding(OHBinding binding) {
    setState(() { _selectedBinding = binding; _step = 1; });
    _loadThingTypes(binding.id);
  }

  void _selectThingType(OHThingType type) async {
    setState(() => _loadingTypes = true);
    try {
      final detail   = await _mgmt.getThingType(type.uid);
      final fullType = detail ?? type;

      for (final f in _configFields.values) {
        f.controller?.dispose();
      }
      _configFields.clear();

      for (final param in fullType.configParameters) {
        final name = param['name'] as String? ?? '';
        if (name.isEmpty) continue;

        final paramType    = (param['type'] as String? ?? 'TEXT').toUpperCase();
        final defaultValue = param['defaultValue'];
        final options      = param['options'] as List<dynamic>? ?? const [];

        if (paramType == 'BOOLEAN') {
          final boolDefault = defaultValue is bool
              ? defaultValue
              : (defaultValue?.toString().toLowerCase() == 'true');
          _configFields[name] = _ConfigField(meta: param, boolValue: boolDefault);
        } else if (options.isNotEmpty) {
          _configFields[name] = _ConfigField(
            meta: param,
            dropdownValue: defaultValue?.toString(),
          );
        } else {
          _configFields[name] = _ConfigField(
            meta: param,
            controller: TextEditingController(text: defaultValue?.toString() ?? ''),
          );
        }
      }

      setState(() { _selectedThingType = fullType; _step = 2; });
    } catch (e) {
      setState(() => _errorMsg = 'Gagal memuat detail: ${_cleanError(e)}');
    } finally {
      setState(() => _loadingTypes = false);
    }
  }

  /// Bersihkan pesan error dari prefix teknis ("Exception: ", dsb)
  /// supaya pesan yang tampil ke user lebih akurat & mudah dibaca.
  String _cleanError(Object e) {
    return e.toString().replaceFirst(
        RegExp(r'^(OpenHABException|Exception):\s*'), '');
  }

  void _goBack() {
    if (_step > 0) {
      setState(() {
        _step--;
        _errorMsg = null;
        if (_step == 0) {
          _selectedBinding = null;
          _thingTypes = [];
          _filteredThingTypes = [];
        }
        if (_step == 1) { _selectedThingType = null; }
      });
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _submitting = true; _errorMsg = null; });
    try {
      final config = <String, dynamic>{};
      _configFields.forEach((key, field) {
        if (field.type == 'BOOLEAN') {
          config[key] = field.boolValue;
        } else if (field.options.isNotEmpty) {
          final v = field.dropdownValue;
          if (v != null && v.trim().isNotEmpty) config[key] = v;
        } else if (field.controller != null) {
          final val = field.controller!.text.trim();
          if (val.isNotEmpty) {
            if (field.type == 'INTEGER') {
              config[key] = int.tryParse(val) ?? val;
            } else if (field.type == 'DECIMAL') {
              config[key] = double.tryParse(val) ?? val;
            } else {
              config[key] = val;
            }
          }
        }
      });

      await _mgmt.addThing(
        thingTypeUID:  _selectedThingType!.uid,
        label:         _labelCtrl.text.trim(),
        uid:           _uidCtrl.text.trim().isNotEmpty ? _uidCtrl.text.trim() : null,
        configuration: config,
        bridgeUID:     _bridgeCtrl.text.trim().isNotEmpty ? _bridgeCtrl.text.trim() : null,
      );

      if (mounted) {
        _showSuccessSnack();
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _errorMsg = _cleanError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSuccessSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text('Thing "${_labelCtrl.text.trim()}" berhasil ditambahkan!',
              style: const TextStyle(fontFamily: 'Inter', fontSize: 13)),
        ]),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Guard app-level: openHAB tidak tahu konsep role di app ini,
    // jadi ini satu-satunya lapisan proteksi untuk halaman admin-only.
    if (!context.watch<RoleProvider>().isAdmin) {
      return const AccessDeniedView(featureName: 'Add Thing');
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: () async { _goBack(); return false; },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
        appBar: _buildAppBar(context),
        body: Column(children: [
          _buildStepIndicator(context),
          Expanded(child: _buildBody(context)),
        ]),
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
        onPressed: _goBack,
      ),
      title: Text(
        _step == 0 ? 'Pilih Binding' : _step == 1 ? 'Pilih Thing Type' : 'Konfigurasi Thing',
        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
            fontSize: 18, color: cs.onSurface),
      ),
    );
  }

  Widget _buildStepIndicator(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const steps = ['Binding', 'Thing Type', 'Detail'];

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.fromLTRB(
          ResponsiveUtils.horizontalPadding(context), 8,
          ResponsiveUtils.horizontalPadding(context), 16),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            final stepIdx = i ~/ 2;
            return Expanded(
              child: Container(
                height: 2,
                color: _step > stepIdx
                    ? AppColors.primary
                    : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7)),
              ),
            );
          }
          final stepIdx  = i ~/ 2;
          final isDone   = _step > stepIdx;
          final isCurrent = _step == stepIdx;
          return Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: isDone || isCurrent
                    ? AppColors.primary
                    : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5)),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : Text('${stepIdx + 1}',
                        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: isCurrent ? Colors.white : AppColors.textMuted)),
              ),
            ),
            const SizedBox(height: 4),
            Text(steps[stepIdx],
                style: TextStyle(fontFamily: 'Inter', fontSize: 10,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                    color: isCurrent ? AppColors.primary : AppColors.textMuted)),
          ]);
        }),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_errorMsg != null) return _buildErrorState(context);
    switch (_step) {
      case 0:  return _buildBindingStep(context);
      case 1:  return _buildThingTypeStep(context);
      case 2:  return _buildDetailStep(context);
      default: return const SizedBox();
    }
  }

  // ── Search box helper (dipakai di step Binding & Thing Type) ────────────
  Widget _buildSearchBox({
    required BuildContext context,
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
    required VoidCallback onClear,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          ResponsiveUtils.horizontalPadding(context), 12,
          ResponsiveUtils.horizontalPadding(context), 4),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF27272A) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: isDark ? Colors.white : const Color(0xFF18181B),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: isDark ? Colors.white38 : Colors.grey.shade400,
            ),
            border: InputBorder.none,
            prefixIcon: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Icon(Icons.search_rounded, size: 18,
                  color: isDark ? Colors.white38 : const Color(0xFF71717A)),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            suffixIcon: controller.text.isNotEmpty
                ? GestureDetector(
                    onTap: onClear,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Icon(Icons.close_rounded, size: 16,
                          color: isDark ? Colors.white38 : const Color(0xFF71717A)),
                    ),
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildBindingStep(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loadingBindings) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(),
        SizedBox(height: 12),
        Text('Memuat bindings...', style: TextStyle(fontFamily: 'Inter',
            fontSize: 13, color: AppColors.textMuted)),
      ]));
    }

    if (_bindings.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.extension_off, size: 48,
              color: isDark ? Colors.white24 : Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('Tidak ada binding tersedia',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                  fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 6),
          Text('Install binding terlebih dahulu di openHAB dashboard.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Inter', fontSize: 13,
                  color: isDark ? Colors.white38 : Colors.grey.shade500)),
          const SizedBox(height: 16),
          _retryButton(_loadBindings),
        ]),
      ));
    }

    return Column(children: [
      _buildSearchBox(
        context: context,
        controller: _bindingSearchCtrl,
        hint: 'Cari binding...',
        onChanged: (v) { _bindingSearchQuery = v; _applyBindingFilter(); },
        onClear: () {
          _bindingSearchCtrl.clear();
          _bindingSearchQuery = '';
          _applyBindingFilter();
        },
      ),
      Expanded(
        child: _filteredBindings.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.search_off_rounded, size: 48,
                        color: isDark ? Colors.white24 : Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('Tidak ditemukan',
                        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                            fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
                    const SizedBox(height: 6),
                    Text('Tidak ada binding yang cocok dengan "$_bindingSearchQuery".',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Inter', fontSize: 13,
                            color: isDark ? Colors.white38 : Colors.grey.shade500)),
                  ]),
                ),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                    ResponsiveUtils.horizontalPadding(context), 12,
                    ResponsiveUtils.horizontalPadding(context), 40),
                children: _buildGroupedBindingList(context),
              ),
      ),
    ]);
  }

  /// Kelompokkan binding per kategori (heuristik, lihat
  /// OHBindingCategory) supaya daftar panjang tidak perlu scroll banyak
  /// untuk mencari satu binding tertentu.
  List<Widget> _buildGroupedBindingList(BuildContext context) {
    final grouped = <String, List<OHBinding>>{};
    for (final b in _filteredBindings) {
      grouped.putIfAbsent(b.category, () => []).add(b);
    }

    const order = [
      'Lighting', 'Kamera & Keamanan', 'Media & TV', 'Energi & Daya',
      'Sensor', 'Smart Hub', 'Jaringan & Protokol', 'Lainnya',
    ];
    final categories = grouped.keys.toList()
      ..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final widgets = <Widget>[];
    for (final cat in categories) {
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
        child: Row(children: [
          Text(cat,
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                  fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(width: 8),
          Expanded(child: Container(
            height: 1,
            color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7),
          )),
          const SizedBox(width: 8),
          Text('${grouped[cat]!.length}',
              style: const TextStyle(fontFamily: 'Inter', fontSize: 12,
                  color: AppColors.textMuted)),
        ]),
      ));
      for (final b in grouped[cat]!) {
        widgets.add(_BindingCard(binding: b, onTap: () => _selectBinding(b)));
      }
    }
    return widgets;
  }

  Widget _buildThingTypeStep(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loadingTypes) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(),
        SizedBox(height: 12),
        Text('Memuat thing types...', style: TextStyle(fontFamily: 'Inter',
            fontSize: 13, color: AppColors.textMuted)),
      ]));
    }

    if (_thingTypes.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.device_unknown, size: 48,
              color: isDark ? Colors.white24 : Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('Tidak ada thing type',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                  fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 4),
          Text('Binding "${_selectedBinding?.name}" tidak memiliki thing type manual.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Inter', fontSize: 13,
                  color: isDark ? Colors.white38 : Colors.grey.shade500)),
          const SizedBox(height: 10),
          Text(
            'Ini wajar — sebagian binding openHAB memang hanya bisa '
            'ditemukan lewat Discovery (auto-scan), bukan dipilih manual.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                color: isDark ? Colors.white30 : Colors.grey.shade400),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () async {
              final bindingId = _selectedBinding?.id;
              if (bindingId == null) return;
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DiscoveryPage(initialBindingId: bindingId)),
              );
              if (result == true && mounted) {
                // Thing sudah dibuat lewat Discovery → tutup alur Add Thing manual.
                Navigator.pop(context, true);
              }
            },
            icon: const Icon(Icons.radar, size: 18, color: Colors.white),
            label: const Text('Coba Discovery',
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                    color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ]),
      ));
    }

    return Column(children: [
      _buildSearchBox(
        context: context,
        controller: _thingTypeSearchCtrl,
        hint: 'Cari thing type...',
        onChanged: (v) { _thingTypeSearchQuery = v; _applyThingTypeFilter(); },
        onClear: () {
          _thingTypeSearchCtrl.clear();
          _thingTypeSearchQuery = '';
          _applyThingTypeFilter();
        },
      ),
      Expanded(
        child: _filteredThingTypes.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.search_off_rounded, size: 48,
                        color: isDark ? Colors.white24 : Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('Tidak ditemukan',
                        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                            fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
                    const SizedBox(height: 6),
                    Text('Tidak ada thing type yang cocok dengan "$_thingTypeSearchQuery".',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Inter', fontSize: 13,
                            color: isDark ? Colors.white38 : Colors.grey.shade500)),
                  ]),
                ),
              )
            : ListView.builder(
                padding: EdgeInsets.fromLTRB(
                    ResponsiveUtils.horizontalPadding(context), 12,
                    ResponsiveUtils.horizontalPadding(context), 40),
                itemCount: _filteredThingTypes.length,
                itemBuilder: (ctx, i) => _ThingTypeCard(
                    type: _filteredThingTypes[i],
                    onTap: () => _selectThingType(_filteredThingTypes[i])),
              ),
      ),
    ]);
  }

  Widget _buildDetailStep(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;

    return Form(
      key: _formKey,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            ResponsiveUtils.horizontalPadding(context), 16,
            ResponsiveUtils.horizontalPadding(context), 40),
        children: [
          _buildSummaryCard(context),
          const SizedBox(height: 20),

          _buildSectionTitle('Label (Nama Tampilan)', context),
          const SizedBox(height: 10),
          _buildDetailCard(context, child: TextFormField(
            controller: _labelCtrl,
            style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: cs.onSurface),
            decoration: _inputDecoration('Label', 'Contoh: MQTT Broker Rumah',
                FontAwesomeIcons.penToSquare, context),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Label tidak boleh kosong' : null,
          )),
          const SizedBox(height: 16),

          _buildSectionTitle('UID (opsional)', context),
          const SizedBox(height: 4),
          Text('Kosongkan jika ingin openHAB generate otomatis.',
              style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.grey.shade500)),
          const SizedBox(height: 8),
          _buildDetailCard(context, child: TextFormField(
            controller: _uidCtrl,
            style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: cs.onSurface),
            decoration: _inputDecoration('UID', 'Contoh: mqtt:broker:myBroker',
                FontAwesomeIcons.fingerprint, context),
          )),
          const SizedBox(height: 16),

          _buildSectionTitle('Bridge UID (opsional)', context),
          const SizedBox(height: 8),
          _buildDetailCard(context, child: TextFormField(
            controller: _bridgeCtrl,
            style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: cs.onSurface),
            decoration: _inputDecoration('Bridge UID', 'Contoh: mqtt:broker:myBroker',
                FontAwesomeIcons.networkWired, context),
          )),

          if (_configFields.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildSectionTitle('Konfigurasi', context),
            const SizedBox(height: 4),
            Text('Parameter sesuai jenis thing yang dipilih.',
                style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.grey.shade500)),
            const SizedBox(height: 10),
            ..._buildConfigFields(context),
          ],

          const SizedBox(height: 32),
          if (_errorMsg != null) _buildInlineError(),
          _buildSubmitButton(context),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: isDark ? 0.1 : 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(child: FaIcon(FontAwesomeIcons.microchip,
              size: 20, color: AppColors.primary)),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_selectedThingType?.label ?? '',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                  fontSize: 15, color: cs.onSurface)),
          Text('${_selectedBinding?.name ?? ''} · ${_selectedThingType?.uid ?? ''}',
              style: const TextStyle(fontFamily: 'Inter', fontSize: 11,
                  color: AppColors.textMuted),
              overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }

  List<Widget> _buildConfigFields(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return _configFields.values.map((field) {
      final labelText = field.required ? '${field.label} *' : field.label;
      final hintText  = field.description.isNotEmpty ? field.description : field.label;

      Widget input;

      if (field.type == 'BOOLEAN') {
        // Parameter boolean → toggle switch, bukan kotak teks "true"/"false".
        input = _buildDetailCard(context, child: SwitchListTile(
          value: field.boolValue,
          onChanged: (v) => setState(() => field.boolValue = v),
          activeThumbColor: AppColors.primary,
          title: Text(labelText,
              style: TextStyle(fontFamily: 'Inter', fontSize: 14,
                  fontWeight: FontWeight.w600, color: cs.onSurface)),
          subtitle: field.description.isNotEmpty
              ? Text(field.description,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 12,
                      color: AppColors.textMuted))
              : null,
        ));
      } else if (field.options.isNotEmpty) {
        // Parameter dengan daftar pilihan tetap → dropdown, bukan free text.
        final validOptionValues =
            field.options.map((o) => o['value']?.toString()).toSet();
        final currentValue =
            validOptionValues.contains(field.dropdownValue) ? field.dropdownValue : null;

        input = _buildDetailCard(context, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: DropdownButtonFormField<String>(
            initialValue: currentValue,
            isExpanded: true,
            decoration: _inputDecoration(
                labelText, hintText, FontAwesomeIcons.sliders, context),
            style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: cs.onSurface),
            items: field.options.map((o) {
              final value    = o['value']?.toString() ?? '';
              final optLabel = o['label']?.toString() ?? value;
              return DropdownMenuItem(
                value: value,
                child: Text(optLabel, overflow: TextOverflow.ellipsis, maxLines: 1),
              );
            }).toList(),
            onChanged: (v) => setState(() => field.dropdownValue = v),
            validator: field.required
                ? (v) => (v == null || v.isEmpty) ? '${field.label} wajib dipilih' : null
                : null,
          ),
        ));
      } else {
        // TEXT / INTEGER / DECIMAL, termasuk field password (context: "password").
        final isNumeric = field.type == 'INTEGER' || field.type == 'DECIMAL';
        input = _buildDetailCard(context, child: TextFormField(
          controller: field.controller,
          obscureText: field.isPassword,
          keyboardType: isNumeric
              ? TextInputType.numberWithOptions(decimal: field.type == 'DECIMAL')
              : TextInputType.text,
          style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: cs.onSurface),
          decoration: _inputDecoration(
            labelText, hintText,
            field.isPassword ? FontAwesomeIcons.lock : FontAwesomeIcons.sliders,
            context,
          ),
          validator: (v) {
            final trimmed = v?.trim() ?? '';
            if (field.required && trimmed.isEmpty) {
              return '${field.label} wajib diisi';
            }
            if (trimmed.isNotEmpty && isNumeric) {
              final parsed = field.type == 'INTEGER'
                  ? int.tryParse(trimmed)
                  : double.tryParse(trimmed);
              if (parsed == null) return '${field.label} harus berupa angka';
            }
            return null;
          },
        ));
      }

      return Padding(padding: const EdgeInsets.only(bottom: 12), child: input);
    }).toList();
  }

  Widget _buildInlineError() {
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
            style: TextStyle(fontFamily: 'Inter', fontSize: 13,
                color: Colors.red.shade700))),
      ]),
    );
  }

  Widget _buildSubmitButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: double.infinity, height: 52,
      child: ElevatedButton(
        onPressed: _submitting ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B),
          disabledBackgroundColor: isDark
              ? const Color(0xFFF4F4F5).withValues(alpha: 0.3)
              : const Color(0xFF18181B).withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusXl)),
          elevation: 0,
        ),
        child: _submitting
            ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                FaIcon(FontAwesomeIcons.microchip, size: 16,
                    color: isDark ? const Color(0xFF18181B) : Colors.white),
                const SizedBox(width: 10),
                Text('Tambah Thing',
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: isDark ? const Color(0xFF18181B) : Colors.white)),
              ]),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off, color: Colors.red, size: 48),
        const SizedBox(height: 12),
        Text(_errorMsg!, textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.red)),
        const SizedBox(height: 16),
        _retryButton(() {
          setState(() => _errorMsg = null);
          if (_step == 0) _loadBindings();
          if (_step == 1 && _selectedBinding != null) _loadThingTypes(_selectedBinding!.id);
        }),
      ]),
    ));
  }

  Widget _retryButton(VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
      ),
      child: const Text('Coba Lagi',
          style: TextStyle(fontFamily: 'Inter', color: Colors.white,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildSectionTitle(String title, BuildContext context) {
    return Text(title,
        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
            fontSize: 14, color: Theme.of(context).colorScheme.onSurface));
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

  InputDecoration _inputDecoration(
      String label, String hint, FaIconData icon, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13,
          color: AppColors.textMuted),
      hintStyle: TextStyle(fontFamily: 'Inter', fontSize: 13,
          color: isDark ? Colors.white38 : Colors.grey.shade400),
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 16, right: 10),
        child: FaIcon(icon, size: 15, color: AppColors.textMuted),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}

/// Menyimpan metadata parameter konfigurasi (dari configParameters openHAB)
/// beserta nilainya saat ini, agar tiap parameter bisa dirender dengan
/// widget input yang sesuai tipenya (BOOLEAN/options/INTEGER/DECIMAL/TEXT)
/// alih-alih disamaratakan jadi satu kotak teks untuk semua binding.
class _ConfigField {
  final Map<String, dynamic> meta;
  TextEditingController? controller; // dipakai untuk TEXT / INTEGER / DECIMAL
  bool boolValue;                    // dipakai untuk BOOLEAN
  String? dropdownValue;             // dipakai kalau meta punya `options`

  _ConfigField({
    required this.meta,
    this.controller,
    this.boolValue = false,
    this.dropdownValue,
  });

  String get name => meta['name'] as String? ?? '';
  String get type => (meta['type'] as String? ?? 'TEXT').toUpperCase();
  String get label => meta['label'] as String? ?? name;
  String get description => meta['description'] as String? ?? '';
  bool get required => meta['required'] as bool? ?? false;
  String get _context => (meta['context'] as String? ?? '').toLowerCase();
  List<dynamic> get options => meta['options'] as List<dynamic>? ?? const [];
  bool get isPassword => _context == 'password';
}

class _BindingCard extends StatelessWidget {
  final OHBinding binding;
  final VoidCallback onTap;
  const _BindingCard({required this.binding, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
              blurRadius: 10, offset: const Offset(0, 3)),
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
            child: Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(child: FaIcon(FontAwesomeIcons.plug,
                    size: 20, color: AppColors.primary)),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(binding.name,
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
                        fontSize: 15, color: cs.onSurface)),
                if (binding.description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(binding.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12,
                          color: AppColors.textMuted)),
                ],
                const SizedBox(height: 4),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(binding.id,
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 10,
                            fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (binding.installed ? AppColors.success : AppColors.textMuted)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(binding.installed ? 'Terpasang' : 'Tersedia',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: binding.installed ? AppColors.success : AppColors.textMuted)),
                  ),
                ]),
              ])),
              Icon(Icons.chevron_right,
                  color: isDark ? Colors.white24 : const Color(0xFFD4D4D8), size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ThingTypeCard extends StatelessWidget {
  final OHThingType type;
  final VoidCallback onTap;
  const _ThingTypeCard({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
              blurRadius: 10, offset: const Offset(0, 3)),
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
            child: Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.07)
                      : const Color(0xFF18181B).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(child: FaIcon(FontAwesomeIcons.microchip,
                    size: 20, color: isDark ? Colors.white70 : const Color(0xFF18181B))),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(type.label,
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
                        fontSize: 15, color: cs.onSurface)),
                if (type.description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(type.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12,
                          color: AppColors.textMuted)),
                ],
                const SizedBox(height: 4),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(type.uid,
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 10,
                            fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                  ),
                  if (type.channelDefinitions.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text('${type.channelDefinitions.length} channels',
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 11,
                            color: AppColors.textMuted)),
                  ],
                ]),
              ])),
              Icon(Icons.chevron_right,
                  color: isDark ? Colors.white24 : const Color(0xFFD4D4D8), size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}