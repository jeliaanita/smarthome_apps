import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart' show HSVColor;

class OpenHABItem {
  final String name;
  final String label;
  final String type;
  final String? state;
  final String? stateDescription;
  final List<String> tags;
  final String? category;
  final List<String> groupNames;
  /// Daftar command yang benar-benar didukung item ini, dari
  /// `commandDescription.commandOptions` REST API openHAB. KOSONG berarti
  /// server tidak melaporkan batasan (bukan "tidak ada yang didukung") —
  /// jadi default aman kalau kosong adalah izinkan semua command.
  final List<String> commandOptions;

  OpenHABItem({
    required this.name,
    required this.label,
    required this.type,
    this.state,
    this.stateDescription,
    this.tags = const [],
    this.category,
    this.groupNames = const [],
    this.commandOptions = const [],
  });

  /// True kalau command ini boleh dikirim ke item — dipakai untuk
  /// menyembunyikan tombol kontrol yang tidak didukung channel/binding.
  bool supportsCommand(String command) =>
      commandOptions.isEmpty || commandOptions.contains(command.toUpperCase());

  factory OpenHABItem.fromJson(Map<String, dynamic> json) {
    return OpenHABItem(
      name: json['name'] ?? '',
      label: json['label'] ?? json['name'] ?? '',
      type: json['type'] ?? '',
      state: json['state']?.toString(),
      stateDescription: json['stateDescription']?['pattern'],
      tags: List<String>.from(json['tags'] ?? []),
      category: json['category'],
      groupNames: List<String>.from(json['groupNames'] ?? []),
      commandOptions: (json['commandDescription']?['commandOptions']
                  as List<dynamic>? ??
              [])
          .map((o) => (o['command'] ?? '').toString().toUpperCase())
          .where((c) => c.isNotEmpty)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'label': label,
        'type': type,
        'state': state,
        'tags': tags,
        'category': category,
        'groupNames': groupNames,
      };
  bool get isSwitch => type == 'Switch';
  bool get isDimmer => type == 'Dimmer';
  bool get isContact => type == 'Contact';
  bool get isNumber => type == 'Number';
  bool get isString => type == 'String';
  bool get isColor => type == 'Color';
  bool get isRollershutter => type == 'Rollershutter';
  bool get isPlayer => type == 'Player';
  bool get isImage => type == 'Image';

  /// Heuristik: Item String yang namanya mengindikasikan dia adalah
  /// channel command tombol remote (mis. "rcButton" di binding LG
  /// webOS) — dipakai untuk memilih widget D-pad remote alih-alih
  /// kotak teks command generik.
  bool get looksLikeRemoteButton {
    final combined = '$name $label'.toLowerCase();
    return combined.contains('button') ||
        combined.contains('remote') ||
        combined.contains('rcbutton') ||
        combined.contains('keycode') ||
        (combined.contains('key') && !combined.contains('keyword'));
  }

  /// Deteksi berbasis kata kunci di nama/label/category — pola yang sama
  /// dipakai OpenHABItemIcon.iconKey di openhab_controller.dart. Item
  /// kamera TIDAK selalu bertipe Image (kadang cuma channel snapshot yang
  /// di-link, sisanya di-handle sebagai Thing terpisah), jadi ini dicek
  /// terpisah dari isImage, bukan pengganti.
  bool get isCamera {
    final combined = '$name $label ${category ?? ''}'.toLowerCase();
    return combined.contains('camera') || combined.contains('cctv');
  }

  /// Item Color di openHAB REST balikin state format "H,S,B"
  /// (Hue 0-360, Saturation 0-100, Brightness 0-100), dipisah koma.
  HSVColor? get hsbColor {
    if (!isColor) return null;
    if (state == null || state == 'NULL' || state == 'UNDEF') return null;
    final parts = state!.split(',');
    if (parts.length != 3) return null;
    final h = double.tryParse(parts[0]);
    final s = double.tryParse(parts[1]);
    final v = double.tryParse(parts[2]);
    if (h == null || s == null || v == null) return null;
    if (!h.isFinite || !s.isFinite || !v.isFinite) return null;
    return HSVColor.fromAHSV(
      1.0,
      h.clamp(0, 360).toDouble(),
      (s / 100).clamp(0, 1).toDouble(),
      (v / 100).clamp(0, 1).toDouble(),
    );
  }

  /// Item Image di openHAB REST balikin state sebagai data URI:
  /// "data:image/jpeg;base64,....". Null kalau belum pernah ada snapshot
  /// masuk (state NULL/UNDEF) atau formatnya tidak sesuai dugaan.
  Uint8List? get imageBytes {
    if (!isImage) return null;
    if (state == null || state == 'NULL' || state == 'UNDEF') return null;
    if (!state!.startsWith('data:')) return null;
    final commaIdx = state!.indexOf(',');
    if (commaIdx == -1) return null;
    try {
      return base64Decode(state!.substring(commaIdx + 1));
    } catch (_) {
      return null;
    }
  }

  bool get isOn => state?.toUpperCase() == 'ON';
  bool get isOff => state?.toUpperCase() == 'OFF';
  
  double? get numericValue {
    if (state == null || state == 'NULL' || state == 'UNDEF') return null;
    return double.tryParse(state!);
  }

  OpenHABItem copyWith({String? state}) {
    return OpenHABItem(
      name: name,
      label: label,
      type: type,
      state: state ?? this.state,
      stateDescription: stateDescription,
      tags: tags,
      category: category,
      groupNames: groupNames,
      commandOptions: commandOptions,
    );
  }

  @override
  String toString() => 'OpenHABItem($name, $type, state: $state)';
}