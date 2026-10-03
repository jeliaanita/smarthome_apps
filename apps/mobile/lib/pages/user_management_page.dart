import 'package:flutter/material.dart';
import '../core/services/user_management_service.dart';
class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  List<String> _installationIds = [];
  final _newInstallationCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadInstallationIds();
  }

  @override
  void dispose() {
    _newInstallationCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInstallationIds() async {
    final ids = await UserManagementService.listInstallationIds();
    if (mounted) setState(() => _installationIds = ids);
  }

  void _showEditSheet(AppUser user) {
    String selectedRole = user.role;
    String? selectedInstallation = user.installationId;
    bool isCreatingNew = false;
    bool isSaving = false;
    _newInstallationCtrl.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.email,
                  style:
                      const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),

              const Text('Role', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'user', label: Text('User')),
                  ButtonSegment(value: 'admin', label: Text('Admin')),
                ],
                selected: {selectedRole},
                onSelectionChanged: (val) {
                  setSheetState(() => selectedRole = val.first);
                },
              ),
              const SizedBox(height: 20),

              const Text('Instalasi (Server openHAB)',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),

              if (!isCreatingNew) ...[
                if (_installationIds.isEmpty)
                  const Text(
                    'Belum ada instalasi terdaftar.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: selectedInstallation,
                    hint: const Text('Pilih instalasi yang sudah ada'),
                    items: _installationIds
                        .map((id) =>
                            DropdownMenuItem(value: id, child: Text(id)))
                        .toList(),
                    onChanged: (val) {
                      setSheetState(() => selectedInstallation = val);
                    },
                  ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => setSheetState(() => isCreatingNew = true),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Buat instalasi baru'),
                ),
              ] else ...[
                TextField(
                  controller: _newInstallationCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ID Instalasi Baru',
                    hintText: 'contoh: rumah_002',
                    helperText:
                        'Huruf kecil, angka, underscore saja. Server openHAB '
                        'diisi belakangan lewat Hub & Connectivity.',
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => setSheetState(() => isCreatingNew = false),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Pilih dari yang sudah ada'),
                ),
              ],
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final targetInstallation = isCreatingNew
                              ? _newInstallationCtrl.text.trim()
                              : selectedInstallation;

                          if (isCreatingNew &&
                              (targetInstallation == null ||
                                  targetInstallation.isEmpty)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('ID instalasi tidak boleh kosong')),
                            );
                            return;
                          }

                          setSheetState(() => isSaving = true);
                          try {
                            await UserManagementService.updateUser(
                              uid: user.uid,
                              role: selectedRole,
                              installationId: targetInstallation,
                            );
                            if (mounted) {
                              Navigator.pop(ctx);
                              await _loadInstallationIds(); // refresh dropdown
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(isCreatingNew
                                      ? 'Instalasi "$targetInstallation" dibuat. '
                                        'Isi server URL lewat Hub & Connectivity.'
                                      : 'User berhasil diupdate'),
                                ),
                              );
                            }
                          } catch (e) {
                            setSheetState(() => isSaving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Gagal: $e')),
                              );
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Simpan'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kelola User')),
      body: StreamBuilder<List<AppUser>>(
        stream: UserManagementService.watchAllUsers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final users = snapshot.data ?? [];
          if (users.isEmpty) {
            return const Center(child: Text('Belum ada user terdaftar'));
          }

          return ListView.separated(
            itemCount: users.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final user = users[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      user.isAdmin ? Colors.orange : Colors.grey.shade300,
                  child: Icon(
                    user.isAdmin ? Icons.shield : Icons.person,
                    color: user.isAdmin ? Colors.white : Colors.black54,
                    size: 18,
                  ),
                ),
                title: Text(user.email),
                subtitle: Text(
                  '${user.isAdmin ? "Admin" : "User"} • '
                  '${user.installationId ?? "Belum ada instalasi"}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showEditSheet(user),
              );
            },
          );
        },
      ),
    );
  }
}