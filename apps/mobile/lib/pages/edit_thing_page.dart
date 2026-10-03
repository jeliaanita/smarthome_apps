import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mobile/core/services/openhab_management_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import 'package:mobile/core/utils/responsive_utils.dart';

/// Halaman Edit Thing.
///
/// Hanya label dan parameter konfigurasi yang bisa diubah. UID sengaja
/// dikunci (read-only) karena openHAB memakai UID sebagai identitas Thing —
/// mengubah UID sama saja membuat Thing baru dan meninggalkan Thing lama
/// sebagai data yatim (duplikasi).
class EditThingPage extends StatefulWidget {
  final OHThing thing;
  const EditThingPage({super.key, required this.thing});

  @override
  State<EditThingPage> createState() => _EditThingPageState();
}

class _EditThingPageState extends State<EditThingPage> {
  final _formKey = GlobalKey<FormState>();
  final _mgmt = OpenHABManagementService();

  late final TextEditingController _labelCtrl;
  final Map<String, _EditConfigField> _configFields = {};

  OHThingType? _thingType;
  bool _loading = true;
  bool _submitting = false;
  bool _deleting = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.thing.label);
    _loadThingType();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    for (final f in _configFields.values) {
      f.controller?.dispose();
    }
    super.dispose();
  }

  /// Bersihkan pesan error dari prefix teknis ("Exception: ", dsb)
  /// supaya pesan yang tampil ke user lebih akurat & mudah dibaca.
  String _cleanError(Object e) {
    return e.toString().replaceFirst(
        RegExp(r'^(OpenHABException|Exception):\s*'), '');
  }

  Future<void> _loadThingType() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final type = await _mgmt.getThingType(widget.thing.thingTypeUID);
      _thingType = type;

      final currentConfig = widget.thing.configuration;
      final params = type?.configParameters ?? const [];

      for (final f in _configFields.values) {
        f.controller?.dispose();
      }
      _configFields.clear();

      for (final param in params) {
        final name = param['name'] as String? ?? '';
        if (name.isEmpty) continue;

        final paramType = (param['type'] as String? ?? 'TEXT').toUpperCase();
        final options    = param['options'] as List<dynamic>? ?? const [];
        // Nilai saat ini diambil dari konfigurasi Thing yang tersimpan,
        // fallback ke defaultValue param kalau belum pernah di-set.
        final currentValue = currentConfig.containsKey(name)
            ? currentConfig[name]
            : param['defaultValue'];

        if (paramType == 'BOOLEAN') {
          final boolVal = currentValue is bool
              ? currentValue
              : (currentValue?.toString().toLowerCase() == 'true');
          _configFields[name] = _EditConfigField(meta: param, boolValue: boolVal);
        } else if (options.isNotEmpty) {
          _configFields[name] = _EditConfigField(
            meta: param,
            dropdownValue: currentValue?.toString(),
          );
        } else {
          _configFields[name] = _EditConfigField(
            meta: param,
            controller: TextEditingController(text: currentValue?.toString() ?? ''),
          );
        }
      }

      if (mounted) setState(() {});
    } catch (e) {
      setState(() => _errorMsg = _cleanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
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

      // UID tidak pernah diubah di sini — mencegah duplikasi Thing.
      await _mgmt.updateThing(
        uid: widget.thing.uid,
        label: _labelCtrl.text.trim(),
        configuration: config,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Perubahan pada "${_labelCtrl.text.trim()}" berhasil disimpan!',
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 13)),
              ),
            ]),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 600));
        // pop(true) → parent (ThingsManagementPage) memuat ulang dari server,
        // supaya yang ditampilkan adalah state yang benar-benar tersimpan.
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _errorMsg = _cleanError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Hapus Thing setelah konfirmasi. Relasi Item/widget yang terhubung ke
  /// Thing ini tidak dihapus otomatis oleh method ini — openHAB akan
  /// menangani unlink channel; Item itu sendiri tetap ada (tidak yatim
  /// secara struktural, hanya kehilangan link ke channel Thing yang dihapus).
  Future<void> _deleteThing() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = widget.thing.label.isNotEmpty ? widget.thing.label : widget.thing.uid;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF27272A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Hapus Thing',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF18181B))),
        content: Text(
          'Yakin ingin menghapus "$label"? Item yang terhubung ke thing ini '
          'akan kehilangan link-nya.',
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
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() { _deleting = true; _errorMsg = null; });
    try {
      final ok = await _mgmt.deleteThing(widget.thing.uid);
      if (!ok) {
        throw Exception('Gagal menghapus thing, silakan coba lagi');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('"$label" berhasil dihapus',
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 13)),
              ),
            ]),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 600));
        // pop(true) → parent (ThingsManagementPage) memuat ulang dari server.
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _errorMsg = _cleanError(e));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      appBar: _buildAppBar(context),
      body: _loading ? _buildLoading() : _buildBody(context),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: cs.surface,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new, size: 18, color: cs.onSurface),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text('Edit Thing',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
              fontSize: 18, color: cs.onSurface)),
      actions: [
        IconButton(
          tooltip: 'Hapus Thing',
          icon: _deleting
              ? SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.onSurface),
                )
              : const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: (_deleting || _submitting) ? null : _deleteThing,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildLoading() {
    return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircularProgressIndicator(),
      SizedBox(height: 12),
      Text('Memuat konfigurasi...',
          style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.textMuted)),
    ]));
  }

  Widget _buildBody(BuildContext context) {
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
          _buildSectionTitle('UID', context),
          const SizedBox(height: 4),
          Text('UID tidak dapat diubah — mencegah duplikasi Thing.',
              style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.grey.shade500)),
          const SizedBox(height: 8),
          _buildDetailCard(context, child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const FaIcon(FontAwesomeIcons.lock, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 12),
              Expanded(child: Text(widget.thing.uid,
                  style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: cs.onSurface))),
            ]),
          )),

          if (_configFields.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildSectionTitle('Konfigurasi', context),
            const SizedBox(height: 4),
            Text('Parameter sesuai jenis thing ini.',
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
          Text(
            (_thingType?.label.isNotEmpty ?? false) ? _thingType!.label : widget.thing.label,
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                fontSize: 15, color: cs.onSurface),
          ),
          Text(widget.thing.thingTypeUID,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.textMuted),
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
        final validValues = field.options.map((o) => o['value']?.toString()).toSet();
        final currentValue = validValues.contains(field.dropdownValue) ? field.dropdownValue : null;

        input = _buildDetailCard(context, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: DropdownButtonFormField<String>(
            initialValue: currentValue,
            isExpanded: true,
            decoration: _inputDecoration(labelText, hintText, FontAwesomeIcons.sliders, context),
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
            if (field.required && trimmed.isEmpty) return '${field.label} wajib diisi';
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
            style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.red.shade700))),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusXl)),
          elevation: 0,
        ),
        child: _submitting
            ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                FaIcon(FontAwesomeIcons.check, size: 16,
                    color: isDark ? const Color(0xFF18181B) : Colors.white),
                const SizedBox(width: 10),
                Text('Simpan Perubahan',
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                        fontSize: 16, color: isDark ? const Color(0xFF18181B) : Colors.white)),
              ]),
      ),
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
      labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.textMuted),
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

/// Sama seperti _ConfigField di add_thing_page.dart — dipisah di sini karena
/// privasi Dart bersifat per-file, bukan per-class.
class _EditConfigField {
  final Map<String, dynamic> meta;
  TextEditingController? controller;
  bool boolValue;
  String? dropdownValue;

  _EditConfigField({
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