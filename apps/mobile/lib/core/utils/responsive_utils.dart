import 'package:flutter/material.dart';

/// Kategori ukuran layar. Breakpoint mengikuti kebiasaan umum:
/// phone < 600, tablet 600–1199, wallPanel >= 1200 (logical pixels).
enum DeviceType { phone, tablet, wallPanel }

/// Utility responsive terpusat — SATU sumber breakpoint untuk seluruh
/// app, supaya phone/tablet/wall panel konsisten di semua halaman
/// (bukan angka hardcode berbeda-beda per file).
class ResponsiveUtils {
  ResponsiveUtils._();

  static const double tabletBreakpoint    = 600;
  static const double wallPanelBreakpoint = 1200;

  /// Touch target minimum sesuai standar aksesibilitas
  /// (Apple HIG 44pt / Material 48dp) — dipakai sebagai batas BAWAH
  /// ukuran tombol/ikon interaktif, supaya tidak terlalu kecil untuk
  /// disentuh di wall panel yang biasanya dilihat/disentuh dari jarak
  /// lebih jauh dibanding HP.
  static const double minTouchTarget = 48.0;

  static DeviceType deviceTypeOf(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= wallPanelBreakpoint) return DeviceType.wallPanel;
    if (width >= tabletBreakpoint) return DeviceType.tablet;
    return DeviceType.phone;
  }

  static bool isTabletOrLarger(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tabletBreakpoint;

  static bool isWallPanel(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wallPanelBreakpoint;

  /// Faktor skala berdasarkan device — dipakai untuk font, ikon, dan
  /// spacing supaya proporsinya tetap enak dilihat, bukan cuma
  /// "melebar" mengikuti layar tanpa batas.
  static double _scaleFactor(BuildContext context) {
    switch (deviceTypeOf(context)) {
      case DeviceType.wallPanel: return 1.35;
      case DeviceType.tablet:    return 1.15;
      case DeviceType.phone:     return 1.0;
    }
  }

  /// Skala ukuran font/ikon. [max] membatasi supaya tidak jadi raksasa
  /// di wall panel yang sangat besar.
  static double scale(BuildContext context, double base, {double max = 1.6}) {
    final factor = _scaleFactor(context).clamp(1.0, max);
    return base * factor;
  }

  /// Jumlah kolom grid otomatis mengikuti lebar layar.
  /// [phoneColumns] adalah baseline (jumlah kolom di HP).
  static int gridColumns(BuildContext context, {int phoneColumns = 2}) {
    switch (deviceTypeOf(context)) {
      case DeviceType.wallPanel: return phoneColumns + 3;
      case DeviceType.tablet:    return phoneColumns + 1;
      case DeviceType.phone:     return phoneColumns;
    }
  }

  /// Padding konten (horizontal/vertical) yang melebar mengikuti
  /// device, supaya di wall panel besar konten tidak menempel ke tepi.
  static EdgeInsets contentPadding(BuildContext context) {
    switch (deviceTypeOf(context)) {
      case DeviceType.wallPanel:
        return const EdgeInsets.symmetric(horizontal: 48, vertical: 20);
      case DeviceType.tablet:
        return const EdgeInsets.symmetric(horizontal: 32, vertical: 16);
      case DeviceType.phone:
        return const EdgeInsets.symmetric(horizontal: 20, vertical: 16);
    }
  }

  /// Sama seperti [contentPadding] tapi cuma nilai horizontal-nya —
  /// dipakai saat vertical padding sudah diatur terpisah oleh widget
  /// lain (mis. SizedBox spacer manual antar section).
  static double horizontalPadding(BuildContext context) {
    switch (deviceTypeOf(context)) {
      case DeviceType.wallPanel: return 48;
      case DeviceType.tablet:    return 32;
      case DeviceType.phone:     return 20;
    }
  }

  /// Lebar maksimum konten di layar sangat lebar, supaya baris
  /// teks/kartu tidak melar horizontal tak berujung — konten tetap
  /// nyaman dibaca dengan margin proporsional di kiri-kanan.
  static double maxContentWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return isWallPanel(context) ? 1000 : width;
  }

  /// Bungkus [child] supaya lebarnya dibatasi & center di layar sangat
  /// lebar (wall panel), tapi full-width apa adanya di phone/tablet.
  static Widget constrainWidth(BuildContext context, Widget child) {
    if (!isWallPanel(context)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContentWidth(context)),
        child: child,
      ),
    );
  }

  /// Pastikan ukuran interaktif (tombol/ikon tap area) tidak lebih
  /// kecil dari [minTouchTarget], sambil tetap membesar mengikuti
  /// [scale] di layar besar.
  static double touchTargetSize(BuildContext context, double base) {
    final scaled = scale(context, base);
    return scaled < minTouchTarget ? minTouchTarget : scaled;
  }
}
