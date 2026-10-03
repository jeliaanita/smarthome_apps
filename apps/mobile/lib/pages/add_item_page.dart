import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mobile/core/services/openhab_management_service.dart';
import 'package:mobile/core/controllers/openhab_controller.dart';
import '../../../../core/providers/installation_provider.dart';
import '../../../../core/providers/role_provider.dart';
import 'package:mobile/core/widget/access_denied_view.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import 'package:mobile/core/utils/responsive_utils.dart';

class AddItemPage extends StatefulWidget {
  const AddItemPage({super.key});

  @override
  State<AddItemPage> createState() => _AddItemPageState();
}

class _AddItemPageState extends State<AddItemPage> {
  final _formKey = GlobalKey<FormState>();
  final _mgmt = OpenHABManagementService();
  final _ctrl = OpenHABController.instance;

  final _nameCtrl  = TextEditingController();
  final _labelCtrl = TextEditingController();
  final _groupCtrl = TextEditingController();

  String _selectedType = 'Switch';
  String? _selectedCategory;
  final List<String> _selectedTags   = [];
  final List<String> _selectedGroups = [];
  List<String> _availableGroups      = [];
  List<String> _existingItemNames    = [];
  bool _isLoading    = false;
  bool _groupsLoading = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _mgmt.setBaseUrl(_ctrl.serverUrl);
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    await _initAuth();
    await _loadGroups();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _labelCtrl.dispose();
    _groupCtrl.dispose();
    super.dispose();
  }

  Future<void> _initAuth() async {
    final config = context.read<InstallationProvider>().config;
    final token    = config?.apiToken;
    final username = config?.username;
    final password = config?.password;
    if (token != null && token.isNotEmpty) {
      _mgmt.setApiToken(token);
    } else if (username != null && password != null) {
      _mgmt.setBasicAuth(username, password);
    }
  }

  Future<void> _loadGroups() async {
    setState(() => _groupsLoading = true);
    try {
      final items  = await _mgmt.getItems();
      final groups = items.where((i) => i.isGroup).map((i) => i.name).toList();
      final names  = items.map((i) => i.name).toList();
      if (mounted) {
        setState(() {
        _availableGroups   = groups;
        _existingItemNames = names;
      });
      }
    } catch (_) {}
    finally {
      if (mounted) setState(() => _groupsLoading = false);
    }
  }

  /// Bersihkan pesan error dari prefix teknis ("Exception: ", dsb)
  /// supaya pesan yang tampil ke user lebih akurat & mudah dibaca.
  String _cleanError(Object e) {
    return e.toString().replaceFirst(
        RegExp(r'^(OpenHABException|Exception):\s*'), '');
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Guard tambahan: cegah PUT diam-diam menimpa item lama kalau daftar
    // nama sempat berubah setelah form pertama kali divalidasi.
    final trimmedName = _nameCtrl.text.trim();
    if (_existingItemNames.contains(trimmedName)) {
      setState(() => _errorMsg =
          'Item "$trimmedName" sudah ada. Gunakan nama lain atau edit item tersebut.');
      return;
    }

    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      final manualGroups = _groupCtrl.text.trim().isNotEmpty
          ? _groupCtrl.text.trim().split(',')
              .map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
          : <String>[];
      final allGroups = {..._selectedGroups, ...manualGroups}.toList();
      final success = await _mgmt.addOrUpdateItem(
        name:       _nameCtrl.text.trim(),
        type:       _selectedType,
        label:      _labelCtrl.text.trim(),
        category:   _selectedCategory,
        groupNames: allGroups,
        tags:       _selectedTags,
      );
      if (success && mounted) {
        _showSuccessSnack();
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() => _errorMsg = 'Gagal menambahkan item. Coba lagi.');
      }
    } catch (e) {
      setState(() => _errorMsg = _cleanError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text('Item "${_labelCtrl.text.trim()}" berhasil ditambahkan!',
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
      return const AccessDeniedView(featureName: 'Add Item');
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      appBar: _buildAppBar(context),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              ResponsiveUtils.horizontalPadding(context), 16,
              ResponsiveUtils.horizontalPadding(context), 40),
          children: [
            if (_errorMsg != null) _buildErrorBanner(),
            _buildSectionTitle('Identitas Item', context),
            const SizedBox(height: 10),
            _buildNameField(context),
            const SizedBox(height: 12),
            _buildLabelField(context),
            const SizedBox(height: 20),
            _buildSectionTitle('Tipe Item', context),
            const SizedBox(height: 10),
            _buildTypeSelector(context),
            const SizedBox(height: 20),
            _buildSectionTitle('Kategori (Ikon)', context),
            const SizedBox(height: 10),
            _buildCategorySelector(context),
            const SizedBox(height: 20),
            _buildSectionTitle('Semantic Tags', context),
            const SizedBox(height: 10),
            _buildTagsSelector(context),
            const SizedBox(height: 20),
            _buildSectionTitle('Group (opsional)', context),
            const SizedBox(height: 10),
            _buildGroupField(context),
            const SizedBox(height: 32),
            _buildSubmitButton(),
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
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Tambah Item',
        style: TextStyle(
          fontFamily: 'Inter', fontWeight: FontWeight.w700,
          fontSize: 18, color: cs.onSurface,
        ),
      ),
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
            style: TextStyle(fontFamily: 'Inter', fontSize: 13,
                color: Colors.red.shade700))),
      ]),
    );
  }

  Widget _buildSectionTitle(String title, BuildContext context) {
    return Text(title,
        style: TextStyle(
          fontFamily: 'Inter', fontWeight: FontWeight.w700,
          fontSize: 14, color: Theme.of(context).colorScheme.onSurface,
        ));
  }

  Widget _buildNameField(BuildContext context) {
    return _InputCard(
      child: TextFormField(
        controller: _nameCtrl,
        style: TextStyle(fontFamily: 'Inter', fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface),
        decoration: _inputDecoration('Nama Item', 'Contoh: LivingRoom_Light1',
            FontAwesomeIcons.tag, context),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Nama tidak boleh kosong';
          final trimmed = v.trim();
          if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(trimmed)) {
            return 'Hanya huruf, angka, dan underscore';
          }
          if (_existingItemNames.contains(trimmed)) {
            return 'Item dengan nama ini sudah ada';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildLabelField(BuildContext context) {
    return _InputCard(
      child: TextFormField(
        controller: _labelCtrl,
        style: TextStyle(fontFamily: 'Inter', fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface),
        decoration: _inputDecoration('Label (Nama Tampilan)',
            'Contoh: Lampu Ruang Tamu', FontAwesomeIcons.penToSquare, context),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Label tidak boleh kosong' : null,
      ),
    );
  }

  Widget _buildTypeSelector(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;

    return _InputCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            FaIcon(FontAwesomeIcons.cubes, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Text('Tipe: $_selectedType',
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
                    fontSize: 14, color: cs.onSurface)),
          ]),
        ),
        Divider(height: 1, color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF0F0F0)),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8, runSpacing: 8,
            children: OpenHABManagementService.itemTypes.map((type) {
              final isSelected = _selectedType == type;
              return GestureDetector(
                onTap: () => setState(() => _selectedType = type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(type,
                      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500,
                          fontSize: 12,
                          color: isSelected ? Colors.white
                              : (isDark ? Colors.white70 : const Color(0xFF71717A)))),
                ),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }

  Widget _buildCategorySelector(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;

    return _InputCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            FaIcon(FontAwesomeIcons.icons, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Text(
              _selectedCategory ?? 'Pilih Kategori (opsional)',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: _selectedCategory != null ? cs.onSurface : AppColors.textMuted),
            ),
          ]),
        ),
        Divider(height: 1, color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF0F0F0)),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8, runSpacing: 8,
            children: OpenHABManagementService.itemCategories.map((cat) {
              final isSelected = _selectedCategory == cat;
              return GestureDetector(
                onTap: () => setState(() => _selectedCategory = isSelected ? null : cat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5)),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Text(cat,
                      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500,
                          fontSize: 12,
                          color: isSelected ? AppColors.primary
                              : (isDark ? Colors.white70 : const Color(0xFF71717A)))),
                ),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }

  Widget _buildTagsSelector(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;

    return _InputCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            FaIcon(FontAwesomeIcons.hashtag, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Text(
              _selectedTags.isEmpty ? 'Pilih Tags (opsional)' : '${_selectedTags.length} tag dipilih',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: _selectedTags.isEmpty ? AppColors.textMuted : cs.onSurface),
            ),
          ]),
        ),
        Divider(height: 1, color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF0F0F0)),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8, runSpacing: 8,
            children: OpenHABManagementService.semanticTags.map((tag) {
              final isSelected = _selectedTags.contains(tag);
              return GestureDetector(
                onTap: () => setState(() {
                  isSelected ? _selectedTags.remove(tag) : _selectedTags.add(tag);
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF6366F1).withValues(alpha: 0.12)
                        : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5)),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (isSelected) ...[
                      const Icon(Icons.check, size: 10, color: Color(0xFF6366F1)),
                      const SizedBox(width: 4),
                    ],
                    Text(tag,
                        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500,
                            fontSize: 11,
                            color: isSelected ? const Color(0xFF6366F1)
                                : (isDark ? Colors.white70 : const Color(0xFF71717A)))),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }
  Widget _buildGroupField(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;

    return _InputCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            FaIcon(FontAwesomeIcons.layerGroup, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Text(
              _selectedGroups.isEmpty ? 'Pilih Group (opsional)' : '${_selectedGroups.length} group dipilih',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: _selectedGroups.isEmpty ? AppColors.textMuted : cs.onSurface),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _loadGroups,
              child: _groupsLoading
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF71717A)))
                  : const FaIcon(FontAwesomeIcons.arrowsRotate, size: 12, color: Color(0xFF71717A)),
            ),
          ]),
        ),
        Divider(height: 1, color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF0F0F0)),
        Padding(
          padding: const EdgeInsets.all(12),
          child: _groupsLoading
              ? const Center(child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: CircularProgressIndicator(strokeWidth: 2)))
              : _availableGroups.isEmpty
                  ? _buildManualGroupInput(context)
                  : Wrap(
                      spacing: 8, runSpacing: 8,
                      children: _availableGroups.map((group) {
                        final isSelected = _selectedGroups.contains(group);
                        return GestureDetector(
                          onTap: () => setState(() {
                            isSelected ? _selectedGroups.remove(group) : _selectedGroups.add(group);
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF6366F1).withValues(alpha: 0.12)
                                  : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5)),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              if (isSelected) ...[
                                const Icon(Icons.check, size: 10, color: Color(0xFF6366F1)),
                                const SizedBox(width: 4),
                              ],
                              FaIcon(FontAwesomeIcons.layerGroup, size: 10,
                                  color: isSelected ? const Color(0xFF6366F1)
                                      : (isDark ? Colors.white70 : const Color(0xFF71717A))),
                              const SizedBox(width: 5),
                              Text(group,
                                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                      color: isSelected ? const Color(0xFF6366F1)
                                          : (isDark ? Colors.white70 : const Color(0xFF71717A)))),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
        ),
        if (_selectedGroups.isNotEmpty) ...[
          Divider(height: 1, color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF0F0F0)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dipilih:', style: TextStyle(fontFamily: 'Inter', fontSize: 11,
                  color: isDark ? Colors.white54 : const Color(0xFF71717A))),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: _selectedGroups.map((g) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: const Color(0xFF6366F1),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(g, style: const TextStyle(fontFamily: 'Inter', fontSize: 11,
                        fontWeight: FontWeight.w600, color: Colors.white)),
                    const SizedBox(width: 5),
                    GestureDetector(
                      onTap: () => setState(() => _selectedGroups.remove(g)),
                      child: const Icon(Icons.close, size: 12, color: Colors.white),
                    ),
                  ]),
                )).toList(),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _buildManualGroupInput(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Tidak ada group ditemukan.',
          style: TextStyle(fontFamily: 'Inter', fontSize: 12,
              color: isDark ? Colors.white38 : Colors.grey.shade400)),
      const SizedBox(height: 8),
      TextFormField(
        controller: _groupCtrl,
        style: TextStyle(fontFamily: 'Inter', fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: 'Ketik manual: LivingRoom, Ground_Floor',
          hintStyle: TextStyle(fontFamily: 'Inter', fontSize: 12,
              color: isDark ? Colors.white38 : Colors.grey.shade400),
          filled: true,
          fillColor: isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    ]);
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity, height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusXl)),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : const Text('Tambah Item',
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                    fontSize: 16, color: Colors.white)),
      ),
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

class _InputCard extends StatelessWidget {
  final Widget child;
  const _InputCard({required this.child});

  @override
  Widget build(BuildContext context) {
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
      child: child,
    );
  }
}