import 'package:flutter/material.dart';
import '../services/installation_service.dart';

class InstallationProvider extends ChangeNotifier {
  String? _installationId;
  InstallationConfig? _config;
  bool _isLoading = true;

  String? get installationId => _installationId;
  InstallationConfig? get config => _config;
  bool get isLoading => _isLoading;
  bool get hasConfig => _config != null && _config!.openhabUrl.isNotEmpty;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    try {
      _installationId = await InstallationService.getMyInstallationId();
      if (_installationId != null) {
        _config = await InstallationService.getConfig(_installationId!);
      } else {
        _config = null;
      }
    } catch (e) {
      debugPrint('❌ InstallationProvider ERROR: $e');
      _config = null;
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Dipanggil admin setelah simpan config baru — refresh in-memory state
  Future<void> saveConfig({
    required String openhabUrl,
    String? apiToken,
    String? username,
    String? password,
  }) async {
    if (_installationId == null) {
      throw Exception('installationId belum ada — hubungi developer.');
    }
    await InstallationService.updateConfig(
      installationId: _installationId!,
      openhabUrl: openhabUrl,
      apiToken: apiToken,
      username: username,
      password: password,
    );
    await load(); // refresh
  }

  void reset() {
    _installationId = null;
    _config = null;
    notifyListeners();
  }
}
