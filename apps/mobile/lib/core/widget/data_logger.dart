// lib/core/widgets/data_logger.dart
//
// Data Logger reusable berbasis openHAB Persistence API.
// Dipakai di halaman Energy 1 Phase, 3 Phase, dan bisa dipasang di sensor lain
// (suhu, kelembapan, asap, dst) cukup dengan mendefinisikan daftar LoggerSeries.
//
// Tipe data yang didukung (LoggerKind):
//   gauge      -> nilai numerik sesaat (daya, tegangan, suhu, kelembapan)  => grafik garis
//   cumulative -> meter kumulatif (kWh)                                    => grafik batang pemakaian
//   binary     -> status ON/OFF, alarm asap, pintu                         => linimasa kejadian
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_colors.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model & konfigurasi
// ─────────────────────────────────────────────────────────────────────────────

enum LoggerKind { gauge, cumulative, binary }

class LoggerSeries {
  /// ID unik di dalam satu logger (boleh sama dengan channelId / nama item).
  final String id;
  final String label;
  final String unit;
  final LoggerKind kind;
  final Color color;
  final IconData icon;

  /// Pengali nilai mentah -> nilai tampil (mis. Watt -> kW = 0.001, PF 0.97 -> % = 100).
  final double scale;
  final int decimals;

  /// Jeda rekam yang diharapkan. Kalau diisi, jeda data yang lebih lama dari
  /// 3x nilai ini ditandai di grafik. Biarkan null untuk persistence
  /// "everyChange" (jeda panjang di sana normal).
  final Duration? expectedInterval;

  /// Setelah berapa lama tanpa data baru dianggap "data berhenti masuk".
  final Duration staleAfter;

  // Khusus binary
  final String activeLabel;
  final String inactiveLabel;

  /// true = kondisi aktif itu berbahaya (mis. alarm asap) -> ditampilkan merah.
  final bool activeIsAlarm;

  const LoggerSeries({
    required this.id,
    required this.label,
    this.unit = '',
    this.kind = LoggerKind.gauge,
    this.color = const Color(0xFFFFA500),
    this.icon = Icons.show_chart_rounded,
    this.scale = 1,
    this.decimals = 2,
    this.expectedInterval,
    this.staleAfter = const Duration(hours: 2),
    this.activeLabel = 'ON',
    this.inactiveLabel = 'OFF',
    this.activeIsAlarm = false,
  });
}

/// Mengembalikan list mentah `[{time: epochMs, state: "..."}]` dari persistence.
/// Return null = Item belum ditemukan / persistence belum aktif.
/// Boleh throw [LoggerException] dengan pesan yang ramah pengguna.
typedef LoggerFetcher = Future<List<Map<String, dynamic>>?> Function(
    LoggerSeries series, DateTime start, DateTime end);

class LoggerException implements Exception {
  final String message;
  const LoggerException(this.message);
  @override
  String toString() => message;
}

/// Fetcher siap pakai untuk openHAB REST. [itemNameOf] memetakan series ke nama Item.
LoggerFetcher openHabLoggerFetcher({
  required String Function() baseUrl,
  required Map<String, String> Function() headers,
  required String? Function(LoggerSeries series) itemNameOf,
}) {
  return (series, start, end) async {
    final item = itemNameOf(series);
    if (item == null || item.isEmpty) return null;
    final uri = Uri.parse('${baseUrl()}/rest/persistence/items/$item').replace(
      queryParameters: {
        'starttime': start.toUtc().toIso8601String(),
        'endtime': end.toUtc().toIso8601String(),
      },
    );
    final res = await http.get(uri, headers: headers()).timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) {
      throw LoggerException('Item "$item" tidak ditemukan di openHAB.');
    }
    if (res.statusCode != 200) {
      throw LoggerException('Server menjawab HTTP ${res.statusCode}. '
          'Pastikan persistence sudah diaktifkan untuk Item "$item".');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return (json['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  };
}

class _Sample {
  final DateTime t;
  final double v;
  const _Sample(this.t, this.v);
}

class _Bucket {
  final DateTime t;
  final double v;
  const _Bucket(this.t, this.v);
}

class _Segment {
  final DateTime start;
  final DateTime end;
  final bool active;
  const _Segment(this.start, this.end, this.active);
  Duration get duration => end.difference(start);
}

enum LoggerRange { h1, h24, d7, d30, custom }

// ─────────────────────────────────────────────────────────────────────────────
// Halaman penuh (untuk dipakai dari kartu sensor suhu / kelembapan / asap)
// ─────────────────────────────────────────────────────────────────────────────

class DataLoggerPage extends StatelessWidget {
  final String title;
  final List<LoggerSeries> series;
  final LoggerFetcher fetcher;
  const DataLoggerPage({super.key, required this.title, required this.series, required this.fetcher});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Text(title,
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 18,
                color: isDark ? Colors.white : const Color(0xCC18181B))),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : const Color(0xCC18181B)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: DataLoggerCard(title: 'Data Logger', series: series, fetcher: fetcher),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Kartu Data Logger
// ─────────────────────────────────────────────────────────────────────────────

class DataLoggerCard extends StatefulWidget {
  final String title;
  final List<LoggerSeries> series;
  final LoggerFetcher fetcher;
  final LoggerRange initialRange;

  const DataLoggerCard({
    super.key,
    required this.series,
    required this.fetcher,
    this.title = 'Data Logger',
    this.initialRange = LoggerRange.h24,
  });

  @override
  State<DataLoggerCard> createState() => _DataLoggerCardState();
}

class _DataLoggerCardState extends State<DataLoggerCard> {
  late LoggerSeries _series = widget.series.first;
  late LoggerRange _range = widget.initialRange;
  DateTimeRange? _custom;

  bool _loading = false;
  String? _error;
  List<_Sample> _samples = [];
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  int _reqId = 0;

  double? _touch; // 0..1 posisi sentuhan di grafik
  bool _showRaw = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  (DateTime, DateTime) _resolveRange() {
    final now = DateTime.now();
    switch (_range) {
      case LoggerRange.h1:
        return (now.subtract(const Duration(hours: 1)), now);
      case LoggerRange.h24:
        return (now.subtract(const Duration(hours: 24)), now);
      case LoggerRange.d7:
        return (now.subtract(const Duration(days: 7)), now);
      case LoggerRange.d30:
        return (now.subtract(const Duration(days: 30)), now);
      case LoggerRange.custom:
        final c = _custom!;
        final end = DateTime(c.end.year, c.end.month, c.end.day, 23, 59, 59);
        return (c.start, end.isAfter(now) ? now : end);
    }
  }

  Future<void> _load() async {
    final id = ++_reqId;
    final (from, to) = _resolveRange();
    final series = _series;
    setState(() {
      _loading = true;
      _error = null;
      _touch = null;
      _from = from;
      _to = to;
    });
    try {
      final raw = await widget.fetcher(series, from, to);
      if (!mounted || id != _reqId) return;
      if (raw == null) {
        throw const LoggerException(
            'Item untuk data ini belum terhubung, atau persistence belum diaktifkan di openHAB.');
      }
      final parsed = _parse(raw, series);
      setState(() {
        _samples = parsed;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _reqId) return;
      setState(() {
        _samples = [];
        _loading = false;
        _error = e is LoggerException
            ? e.message
            : e is TimeoutException
                ? 'Server terlalu lama menjawab. Periksa koneksi lalu coba lagi.'
                : 'Gagal memuat riwayat: $e';
      });
    }
  }

  static final _numRe = RegExp(r'-?\d+(?:[.,]\d+)?(?:[eE][-+]?\d+)?');

  /// Mendukung "12.5", "12.5 kW" (QuantityType), ON/OFF/OPEN/CLOSED/ALARM, dan 0/1.
  List<_Sample> _parse(List<Map<String, dynamic>> raw, LoggerSeries s) {
    final out = <_Sample>[];
    for (final m in raw) {
      final t = m['time'];
      final st = '${m['state'] ?? ''}'.trim();
      if (t is! num || st.isEmpty) continue;
      final up = st.toUpperCase();
      if (up == 'NULL' || up == 'UNDEF' || up == 'NAN') continue;
      double? v;
      if (s.kind == LoggerKind.binary) {
        const on = {'ON', 'OPEN', 'OPENED', 'ALARM', 'TRUE', 'DETECTED', 'ACTIVE'};
        const off = {'OFF', 'CLOSED', 'FALSE', 'NORMAL', 'CLEAR', 'INACTIVE'};
        if (on.contains(up)) {
          v = 1;
        } else if (off.contains(up)) {
          v = 0;
        } else {
          final n = double.tryParse(st.replaceAll(',', '.'));
          if (n != null) v = n != 0 ? 1 : 0;
        }
      } else {
        final mt = _numRe.firstMatch(st);
        final n = mt == null ? null : double.tryParse(mt.group(0)!.replaceAll(',', '.'));
        if (n != null && n.isFinite) v = n * s.scale;
      }
      if (v == null) continue;
      out.add(_Sample(DateTime.fromMillisecondsSinceEpoch(t.toInt()), v));
    }
    out.sort((a, b) => a.t.compareTo(b.t));
    return out;
  }

  // ── Format ────────────────────────────────────────────────────────────────

  String _two(int n) => n.toString().padLeft(2, '0');
  String _fmtTime(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
  String _fmtDate(DateTime t) => '${_two(t.day)}/${_two(t.month)}';
  String _fmtFull(DateTime t) => '${_fmtDate(t)}/${t.year} ${_fmtTime(t)}:${_two(t.second)}';
  String _fmtShort(DateTime t) => '${_fmtDate(t)} ${_fmtTime(t)}';
  String _num(double v) => v.toStringAsFixed(_series.decimals);
  String _val(double v) => _series.unit.isEmpty ? _num(v) : '${_num(v)} ${_series.unit}';

  String _fmtDur(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds} dtk';
    if (d.inMinutes < 60) return '${d.inMinutes} mnt';
    if (d.inHours < 24) {
      final m = d.inMinutes % 60;
      return m == 0 ? '${d.inHours} j' : '${d.inHours} j $m mnt';
    }
    final h = d.inHours % 24;
    return h == 0 ? '${d.inDays} hr' : '${d.inDays} hr $h j';
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    return d.inSeconds < 60 ? 'baru saja' : '${_fmtDur(d)} lalu';
  }

  String get _rangeLabel {
    switch (_range) {
      case LoggerRange.h1:
        return '1 jam terakhir';
      case LoggerRange.h24:
        return '24 jam terakhir';
      case LoggerRange.d7:
        return '7 hari terakhir';
      case LoggerRange.d30:
        return '30 hari terakhir';
      case LoggerRange.custom:
        return '${_fmtDate(_from)} – ${_fmtDate(_to)}';
    }
  }

  // ── Olah data ─────────────────────────────────────────────────────────────

  /// Min/max decimation: lonjakan nilai tetap terlihat walau data ribuan.
  List<_Bucket> _downsample(List<_Sample> src, {int target = 240}) {
    if (src.length <= target * 2) return src.map((s) => _Bucket(s.t, s.v)).toList();
    final span = _to.difference(_from).inMilliseconds;
    final width = math.max(1, span ~/ target);
    final out = <_Bucket>[];
    var i = 0;
    while (i < src.length) {
      final idx = (src[i].t.millisecondsSinceEpoch - _from.millisecondsSinceEpoch) ~/ width;
      var lo = src[i], hi = src[i];
      var j = i;
      while (j < src.length &&
          (src[j].t.millisecondsSinceEpoch - _from.millisecondsSinceEpoch) ~/ width == idx) {
        if (src[j].v < lo.v) lo = src[j];
        if (src[j].v > hi.v) hi = src[j];
        j++;
      }
      final pair = [lo, hi]..sort((a, b) => a.t.compareTo(b.t));
      out.add(_Bucket(pair.first.t, pair.first.v));
      if (!identical(pair.first, pair.last)) out.add(_Bucket(pair.last.t, pair.last.v));
      i = j;
    }
    return out;
  }

  /// Pemakaian per jam (rentang <= 36 jam) atau per hari, dari meter kumulatif.
  List<_Bucket> _consumption(List<_Sample> src) {
    if (src.length < 2) return [];
    final hourly = _to.difference(_from) <= const Duration(hours: 36);
    DateTime key(DateTime t) =>
        hourly ? DateTime(t.year, t.month, t.day, t.hour) : DateTime(t.year, t.month, t.day);
    final last = <DateTime, double>{};
    for (final s in src) {
      last[key(s.t)] = s.v;
    }
    final keys = last.keys.toList()..sort();
    var prev = src.first.v;
    final out = <_Bucket>[];
    for (final k in keys) {
      final cur = last[k]!;
      out.add(_Bucket(k, math.max(0, cur - prev))); // reset meter -> 0, bukan negatif
      prev = cur;
    }
    return out;
  }

  List<_Segment> _segments(List<_Sample> src) {
    if (src.isEmpty) return [];
    final out = <_Segment>[];
    for (var i = 0; i < src.length; i++) {
      final next = i + 1 < src.length ? src[i + 1].t : _to;
      // minimal 1 detik supaya tiap sampel selalu punya segmen
      final end = next.isAfter(src[i].t) ? next : src[i].t.add(const Duration(seconds: 1));
      out.add(_Segment(src[i].t, end, src[i].v > 0.5));
    }
    // gabungkan segmen berurutan yang statusnya sama
    final merged = <_Segment>[];
    for (final s in out) {
      if (merged.isNotEmpty && merged.last.active == s.active) {
        merged[merged.length - 1] = _Segment(merged.last.start, s.end, s.active);
      } else {
        merged.add(s);
      }
    }
    return merged;
  }

  List<Duration> _gaps(List<_Sample> src, Duration expected) {
    final thr = expected * 3;
    final g = <Duration>[];
    for (var i = 1; i < src.length; i++) {
      final d = src[i].t.difference(src[i - 1].t);
      if (d > thr) g.add(d);
    }
    return g;
  }

  // ── Aksi ──────────────────────────────────────────────────────────────────

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 730)),
      lastDate: now,
      initialDateRange: _custom ??
          DateTimeRange(start: now.subtract(const Duration(days: 3)), end: now),
      helpText: 'Pilih rentang tanggal',
      saveText: 'Terapkan',
    );
    if (picked == null) return;
    setState(() {
      _custom = picked;
      _range = LoggerRange.custom;
    });
    _load();
  }

  bool _sharing = false;

  /// Buat file .csv di folder sementara lalu buka share sheet
  /// (WhatsApp, email, AirDrop, simpan ke Files, dst).
  Future<void> _shareCsv() async {
    if (_sharing || _samples.isEmpty) return;
    setState(() => _sharing = true);

    // iPad butuh titik asal popover share; di iPhone/Android diabaikan.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;

    try {
      final unit = _series.unit;
      final b = StringBuffer('\uFEFF'); // BOM supaya simbol seperti °C terbaca benar di Excel
      b.writeln('waktu,nilai,satuan');
      for (final s in _samples) {
        final t = s.t;
        final waktu = '${t.year}-${_two(t.month)}-${_two(t.day)} '
            '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
        final v = _series.kind == LoggerKind.binary
            ? (s.v > 0.5 ? _series.activeLabel : _series.inactiveLabel)
            : s.v.toStringAsFixed(_series.decimals);
        b.writeln('$waktu,$v,$unit');
      }

      final now = DateTime.now();
      final safeName = _series.label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      final fileName = 'logger_${safeName}_${now.year}${_two(now.month)}${_two(now.day)}'
          '_${_two(now.hour)}${_two(now.minute)}.csv';

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(b.toString(), encoding: utf8);

      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv', name: fileName)],
        subject: 'Data Logger – ${_series.label}',
        text: '${_series.label} • $_rangeLabel • ${_samples.length} data',
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal membuat file CSV: $e'),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = isDark ? Colors.white54 : const Color(0xFF71717A);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(widget.title,
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 16,
                    color: isDark ? Colors.white : const Color(0xCC18181B))),
          ),
          _iconBtn(Icons.refresh_rounded, 'Muat ulang', _loading ? null : _load, isDark),
        ]),
        const SizedBox(height: 2),
        Text('Riwayat ${_series.label} • $_rangeLabel',
            style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: sub)),
        const SizedBox(height: 12),
        _buildSeriesChips(isDark),
        const SizedBox(height: 10),
        _buildRangeChips(isDark),
        const SizedBox(height: 14),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 56),
            child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
          )
        else if (_error != null)
          _buildError(isDark)
        else if (_samples.isEmpty)
          _buildEmpty(isDark)
        else
          _buildContent(isDark),
      ]),
    );
  }

  Widget _iconBtn(IconData icon, String tip, VoidCallback? onTap, bool isDark) => IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
        icon: Icon(icon, size: 20, color: isDark ? Colors.white54 : const Color(0xFF71717A)),
      );

  Widget _chip(String label, bool selected, Color accent, VoidCallback onTap, bool isDark,
      {IconData? icon}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.15)
              : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFF5F5F7)),
          borderRadius: BorderRadius.circular(12),
          border: selected ? Border.all(color: accent) : Border.all(color: Colors.transparent),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: selected ? accent : (isDark ? Colors.white38 : const Color(0xFF9E9E9E))),
            const SizedBox(width: 6),
          ],
          Text(label,
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12,
                  color: selected ? accent : (isDark ? Colors.white54 : const Color(0xFF71717A)))),
        ]),
      ),
    );
  }

  Widget _buildSeriesChips(bool isDark) {
    if (widget.series.length < 2) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: widget.series
            .map((s) => _chip(s.label, s.id == _series.id, s.color, () {
                  if (s.id == _series.id) return;
                  setState(() {
                    _series = s;
                    _showRaw = false;
                  });
                  _load();
                }, isDark, icon: s.icon))
            .toList(),
      ),
    );
  }

  Widget _buildRangeChips(bool isDark) {
    const items = <(LoggerRange, String)>[
      (LoggerRange.h1, '1 Jam'),
      (LoggerRange.h24, '24 Jam'),
      (LoggerRange.d7, '7 Hari'),
      (LoggerRange.d30, '30 Hari'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final it in items)
          _chip(it.$2, _range == it.$1, AppColors.primary, () {
            if (_range == it.$1) return;
            setState(() => _range = it.$1);
            _load();
          }, isDark),
        _chip(
          _range == LoggerRange.custom ? _rangeLabel : 'Pilih tanggal',
          _range == LoggerRange.custom,
          AppColors.primary,
          _pickCustom,
          isDark,
          icon: Icons.calendar_month_rounded,
        ),
      ]),
    );
  }

  // ── State kosong / error ──────────────────────────────────────────────────

  Widget _buildError(bool isDark) {
    return _stateBox(
      isDark,
      icon: Icons.cloud_off_rounded,
      title: 'Riwayat belum bisa ditampilkan',
      body: _error!,
      action: 'Coba lagi',
      onAction: _load,
    );
  }

  Widget _buildEmpty(bool isDark) {
    final canExtend = _range == LoggerRange.h1 || _range == LoggerRange.h24;
    return _stateBox(
      isDark,
      icon: Icons.query_stats_rounded,
      title: 'Belum ada data pada rentang ini',
      body: 'Coba rentang waktu yang lebih panjang. Jika tetap kosong, pastikan '
          'persistence openHAB aktif dan Item "${_series.label}" ikut direkam.',
      action: canExtend ? 'Lihat 7 hari' : null,
      onAction: canExtend
          ? () {
              setState(() => _range = LoggerRange.d7);
              _load();
            }
          : null,
    );
  }

  Widget _stateBox(bool isDark,
      {required IconData icon,
      required String title,
      required String body,
      String? action,
      VoidCallback? onAction}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      child: Center(
        child: Column(children: [
          Icon(icon, size: 34, color: isDark ? Colors.white38 : Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14,
                  color: isDark ? Colors.white : const Color(0xCC18181B))),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Inter', fontSize: 12, height: 1.4,
                  color: isDark ? Colors.white54 : const Color(0xFF71717A))),
          if (action != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onAction,
              child: Text(action,
                  style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600,
                      fontSize: 13, color: Color(0xFFFFA500))),
            ),
          ],
        ]),
      ),
    );
  }

  // ── Konten ────────────────────────────────────────────────────────────────

  Widget _buildContent(bool isDark) {
    final children = <Widget>[];
    final sub = isDark ? Colors.white54 : const Color(0xFF71717A);

    // Peringatan data berhenti masuk (hanya untuk rentang yang berakhir "sekarang")
    final endsNow = _range != LoggerRange.custom;
    final lastT = _samples.last.t;
    if (endsNow && DateTime.now().difference(lastT) > _series.staleAfter) {
      children.add(_banner(
        Icons.warning_amber_rounded,
        const Color(0xFFF59E0B),
        'Data terakhir direkam ${_ago(lastT)} (${_fmtShort(lastT)}). '
        'Perangkat mungkin offline atau berhenti mengirim data.',
      ));
      children.add(const SizedBox(height: 12));
    }

    switch (_series.kind) {
      case LoggerKind.gauge:
        children.addAll(_gaugeView(isDark));
        break;
      case LoggerKind.cumulative:
        children.addAll(_cumulativeView(isDark));
        break;
      case LoggerKind.binary:
        children.addAll(_binaryView(isDark));
        break;
    }

    children.add(const SizedBox(height: 14));
    children.add(_buildRawSection(isDark));
    children.add(const SizedBox(height: 8));
    children.add(Text(
      '${_samples.length} data • zona waktu perangkat ini'
      '${_series.unit.isNotEmpty ? ' • satuan ${_series.unit}' : ''}',
      style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: sub),
    ));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _banner(IconData icon, Color color, String text) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontFamily: 'Inter', fontSize: 11, height: 1.4, color: color)),
          ),
        ]),
      );

  Widget _statTile(String label, String value, bool isDark, {String? note, Color? color}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3F3F46).withValues(alpha: 0.6) : const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Text(label,
              style: TextStyle(fontFamily: 'Inter', fontSize: 10,
                  color: isDark ? Colors.white54 : const Color(0xFF71717A))),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14,
                    color: color ?? (isDark ? Colors.white : const Color(0xCC18181B)))),
          ),
          if (note != null) ...[
            const SizedBox(height: 2),
            Text(note,
                style: TextStyle(fontFamily: 'Inter', fontSize: 9,
                    color: isDark ? Colors.white38 : const Color(0xFF9E9E9E))),
          ],
        ]),
      ),
    );
  }

  Widget _readout(String text, bool isDark, {Color? color}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12,
                color: color ?? (isDark ? Colors.white70 : const Color(0xFF52525B)))),
      );

  // ── Gauge: grafik garis ───────────────────────────────────────────────────

  List<Widget> _gaugeView(bool isDark) {
    final s = _samples;
    var minS = s.first, maxS = s.first, sum = 0.0;
    for (final x in s) {
      if (x.v < minS.v) minS = x;
      if (x.v > maxS.v) maxS = x;
      sum += x.v;
    }
    final avg = sum / s.length;
    final pts = _downsample(s);
    final gapDurations =
        _series.expectedInterval == null ? <Duration>[] : _gaps(s, _series.expectedInterval!);

    _Bucket? sel;
    if (_touch != null) {
      final target = _from.millisecondsSinceEpoch +
          (_touch! * _to.difference(_from).inMilliseconds).round();
      sel = pts.reduce((a, b) =>
          (a.t.millisecondsSinceEpoch - target).abs() < (b.t.millisecondsSinceEpoch - target).abs()
              ? a
              : b);
    }

    return [
      _readout(
        sel == null
            ? 'Ketuk atau geser grafik untuk melihat nilai tiap waktu'
            : '${_fmtFull(sel.t)}  →  ${_val(sel.v)}',
        isDark,
        color: sel == null ? (isDark ? Colors.white38 : const Color(0xFF9E9E9E)) : _series.color,
      ),
      _chartBox(
        height: 190,
        child: CustomPaint(
          size: Size.infinite,
          painter: _LinePainter(
            points: pts,
            from: _from,
            to: _to,
            color: _series.color,
            isDark: isDark,
            decimals: _series.decimals,
            touch: _touch,
            selected: sel,
            gapThreshold: _series.expectedInterval == null ? null : _series.expectedInterval! * 3,
            fmtTick: _tickLabel,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        _statTile('Terakhir', _num(s.last.v), isDark, note: _fmtTime(s.last.t), color: _series.color),
        _statTile('Rata-rata', _num(avg), isDark, note: 'periode ini'),
        _statTile('Terendah', _num(minS.v), isDark, note: _fmtShort(minS.t)),
        _statTile('Tertinggi', _num(maxS.v), isDark, note: _fmtShort(maxS.t)),
      ]),
      if (gapDurations.isNotEmpty) ...[
        const SizedBox(height: 10),
        _banner(
          Icons.timer_off_rounded,
          const Color(0xFFF59E0B),
          '${gapDurations.length} jeda data terdeteksi (terlama ${_fmtDur(gapDurations.reduce((a, b) => a > b ? a : b))}). '
          'Bagian grafik yang terputus berarti tidak ada data pada saat itu.',
        ),
      ],
    ];
  }

  // ── Kumulatif: batang pemakaian ───────────────────────────────────────────

  List<Widget> _cumulativeView(bool isDark) {
    final buckets = _consumption(_samples);
    final hourly = _to.difference(_from) <= const Duration(hours: 36);
    if (buckets.isEmpty) {
      return [
        _stateBox(isDark,
            icon: Icons.bar_chart_rounded,
            title: 'Data belum cukup',
            body: 'Perlu minimal dua pembacaan meter untuk menghitung pemakaian. '
                'Coba rentang waktu yang lebih panjang.')
      ];
    }
    final total = buckets.fold<double>(0, (a, b) => a + b.v);
    final peak = buckets.reduce((a, b) => a.v >= b.v ? a : b);
    final idx = _touch == null ? null : (_touch! * buckets.length).floor().clamp(0, buckets.length - 1);
    final sel = idx == null ? null : buckets[idx];

    String bucketLabel(_Bucket b) => hourly
        ? '${_fmtDate(b.t)} ${_two(b.t.hour)}:00–${_two((b.t.hour + 1) % 24)}:00'
        : _fmtDate(b.t);

    return [
      _readout(
        sel == null
            ? 'Ketuk batang untuk melihat pemakaian per ${hourly ? 'jam' : 'hari'}'
            : '${bucketLabel(sel)}  →  ${_val(sel.v)}',
        isDark,
        color: sel == null ? (isDark ? Colors.white38 : const Color(0xFF9E9E9E)) : _series.color,
      ),
      _chartBox(
        height: 170,
        child: CustomPaint(
          size: Size.infinite,
          painter: _BarPainter(
            buckets: buckets,
            color: _series.color,
            isDark: isDark,
            decimals: _series.decimals,
            selectedIndex: idx,
            labelOf: (b) => hourly ? _two(b.t.hour) : _fmtDate(b.t),
          ),
        ),
        bucketCount: buckets.length,
      ),
      const SizedBox(height: 12),
      Row(children: [
        _statTile('Total pemakaian', _num(total), isDark, note: _series.unit, color: _series.color),
        _statTile('Pembacaan meter', _num(_samples.last.v), isDark, note: _fmtTime(_samples.last.t)),
        _statTile('Puncak', _num(peak.v), isDark,
            note: hourly ? '${_fmtDate(peak.t)} ${_two(peak.t.hour)}:00' : _fmtDate(peak.t)),
      ]),
    ];
  }

  // ── Biner: linimasa kejadian ──────────────────────────────────────────────

  List<Widget> _binaryView(bool isDark) {
    final segs = _segments(_samples);
    final activeColor = _series.activeIsAlarm ? const Color(0xFFF31260) : const Color(0xFF34C759);
    final inactiveColor = isDark ? const Color(0xFF52525B) : const Color(0xFFD4D4D8);
    final activeSegs = segs.where((s) => s.active).toList();
    final activeTotal = activeSegs.fold<Duration>(Duration.zero, (a, b) => a + b.duration);
    final nowActive = _samples.last.v > 0.5;
    final total = _to.difference(_from).inMilliseconds;

    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (nowActive ? activeColor : inactiveColor).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(nowActive && _series.activeIsAlarm ? Icons.notifications_active_rounded : Icons.circle,
              size: nowActive && _series.activeIsAlarm ? 20 : 12,
              color: nowActive ? activeColor : (isDark ? Colors.white38 : const Color(0xFF9E9E9E))),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Status terakhir: ${nowActive ? _series.activeLabel : _series.inactiveLabel}'
              ' (sejak ${_fmtShort(segs.last.start)})',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13,
                  color: isDark ? Colors.white : const Color(0xCC18181B)),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 26,
          child: Row(
            children: segs
                .map((s) => Expanded(
                      flex: math.max(1, (s.duration.inMilliseconds * 1000 / math.max(1, total)).round()),
                      child: Container(color: s.active ? activeColor : inactiveColor),
                    ))
                .toList(),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(_fmtShort(_from),
            style: TextStyle(fontFamily: 'Inter', fontSize: 9,
                color: isDark ? Colors.white38 : const Color(0xFF9E9E9E))),
        Row(children: [
          _legendDot(activeColor, _series.activeLabel, isDark),
          const SizedBox(width: 10),
          _legendDot(inactiveColor, _series.inactiveLabel, isDark),
        ]),
        Text(_fmtShort(_to),
            style: TextStyle(fontFamily: 'Inter', fontSize: 9,
                color: isDark ? Colors.white38 : const Color(0xFF9E9E9E))),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        _statTile('Kejadian ${_series.activeLabel}', '${activeSegs.length}x', isDark,
            color: activeSegs.isEmpty ? null : activeColor),
        _statTile('Total durasi ${_series.activeLabel}', activeSegs.isEmpty ? '-' : _fmtDur(activeTotal), isDark),
        _statTile('Kejadian terakhir',
            activeSegs.isEmpty ? '-' : _fmtTime(activeSegs.last.start), isDark,
            note: activeSegs.isEmpty ? null : _fmtDate(activeSegs.last.start)),
      ]),
      if (activeSegs.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Daftar kejadian ${_series.activeLabel}',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12,
                color: isDark ? Colors.white70 : const Color(0xFF52525B))),
        const SizedBox(height: 6),
        for (final e in activeSegs.reversed.take(8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Icon(Icons.circle, size: 8, color: activeColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${_fmtShort(e.start)}  →  ${_fmtShort(e.end)}',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                        color: isDark ? Colors.white70 : const Color(0xFF52525B))),
              ),
              Text(_fmtDur(e.duration),
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12,
                      color: isDark ? Colors.white : const Color(0xCC18181B))),
            ]),
          ),
      ],
    ];
  }

  Widget _legendDot(Color c, String label, bool isDark) => Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontFamily: 'Inter', fontSize: 10,
                color: isDark ? Colors.white54 : const Color(0xFF71717A))),
      ]);

  // ── Chart box (sentuhan) ──────────────────────────────────────────────────

  Widget _chartBox({required double height, required Widget child, int? bucketCount}) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, c) {
        // Area plot = lebar total dikurangi margin kiri painter (44).
        const left = 44.0;
        void update(double dx) {
          final w = c.maxWidth - left;
          if (w <= 0) return;
          setState(() => _touch = ((dx - left) / w).clamp(0.0, 0.9999));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => update(d.localPosition.dx),
          onHorizontalDragStart: (d) => update(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => update(d.localPosition.dx),
          child: child,
        );
      }),
    );
  }

  String _tickLabel(DateTime t) {
    final span = _to.difference(_from);
    return span <= const Duration(hours: 36) ? _fmtTime(t) : _fmtDate(t);
  }

  // ── Data mentah ───────────────────────────────────────────────────────────

  Widget _buildRawSection(bool isDark) {
    final shown = _samples.reversed.take(30).toList();
    final sub = isDark ? Colors.white54 : const Color(0xFF71717A);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        GestureDetector(
          onTap: () => setState(() => _showRaw = !_showRaw),
          child: Row(children: [
            Icon(_showRaw ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 20, color: AppColors.primary),
            const SizedBox(width: 4),
            const Text('Data tercatat',
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12,
                    color: AppColors.primary)),
          ]),
        ),
        const Spacer(),
        GestureDetector(
          onTap: _sharing ? null : _shareCsv,
          child: Row(children: [
            _sharing
                ? SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: sub))
                : Icon(Icons.ios_share_rounded, size: 14, color: sub),
            const SizedBox(width: 4),
            Text('Bagikan CSV',
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12, color: sub)),
          ]),
        ),
      ]),
      if (_showRaw) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              flex: 3,
              child: Text('Waktu',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: sub))),
          Text('Nilai',
              style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: sub)),
        ]),
        Divider(height: 12, color: isDark ? Colors.white12 : Colors.black12),
        for (final s in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: Text(_fmtFull(s.t),
                    style: TextStyle(fontFamily: 'Inter', fontSize: 12,
                        color: isDark ? Colors.white70 : const Color(0xFF52525B))),
              ),
              Text(
                _series.kind == LoggerKind.binary
                    ? (s.v > 0.5 ? _series.activeLabel : _series.inactiveLabel)
                    : _val(s.v),
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12,
                    color: isDark ? Colors.white : const Color(0xCC18181B)),
              ),
            ]),
          ),
        if (_samples.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                'Menampilkan ${shown.length} data terbaru dari ${_samples.length}. '
                'Gunakan "Bagikan CSV" untuk semua data.',
                style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: sub)),
          ),
      ],
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────────────────

void _drawText(Canvas canvas, String text, Offset pos, TextStyle style,
    {TextAlign align = TextAlign.left, double? maxWidth}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: align,
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(maxWidth: maxWidth ?? double.infinity);
  var dx = pos.dx;
  if (align == TextAlign.right) dx = pos.dx - tp.width;
  if (align == TextAlign.center) dx = pos.dx - tp.width / 2;
  tp.paint(canvas, Offset(dx, pos.dy - tp.height / 2));
}

String _axisNum(double v, int decimals) {
  if (v.abs() >= 1000) return v.toStringAsFixed(0);
  if (v.abs() >= 100) return v.toStringAsFixed(decimals > 1 ? 1 : decimals);
  return v.toStringAsFixed(decimals);
}

class _LinePainter extends CustomPainter {
  final List<_Bucket> points;
  final DateTime from;
  final DateTime to;
  final Color color;
  final bool isDark;
  final int decimals;
  final double? touch;
  final _Bucket? selected;
  final Duration? gapThreshold;
  final String Function(DateTime) fmtTick;

  const _LinePainter({
    required this.points,
    required this.from,
    required this.to,
    required this.color,
    required this.isDark,
    required this.decimals,
    required this.touch,
    required this.selected,
    required this.gapThreshold,
    required this.fmtTick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0, bottom = 20.0, top = 6.0;
    final w = size.width - left;
    final h = size.height - bottom - top;
    if (w <= 0 || h <= 0 || points.isEmpty) return;

    var lo = points.first.v, hi = points.first.v;
    for (final p in points) {
      lo = math.min(lo, p.v);
      hi = math.max(hi, p.v);
    }
    if ((hi - lo).abs() < 1e-9) {
      final pad = hi.abs() < 1e-9 ? 1.0 : hi.abs() * 0.1;
      lo -= pad;
      hi += pad;
    } else {
      final pad = (hi - lo) * 0.1;
      lo -= pad;
      hi += pad;
    }

    final spanMs = math.max(1, to.difference(from).inMilliseconds);
    double xOf(DateTime t) => left + (t.difference(from).inMilliseconds / spanMs).clamp(0.0, 1.0) * w;
    double yOf(double v) => top + (1 - (v - lo) / (hi - lo)) * h;

    final labelStyle = TextStyle(fontFamily: 'Inter', fontSize: 9,
        color: isDark ? Colors.white38 : const Color(0xFF94A3B8));
    final grid = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.07)
      ..strokeWidth = 1;

    for (var i = 0; i <= 3; i++) {
      final y = top + h / 3 * i;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      final v = hi - (hi - lo) / 3 * i;
      _drawText(canvas, _axisNum(v, decimals), Offset(left - 6, y), labelStyle, align: TextAlign.right);
    }
    for (var i = 0; i <= 4; i++) {
      final t = from.add(Duration(milliseconds: (spanMs * i / 4).round()));
      final x = left + w * i / 4;
      _drawText(canvas, fmtTick(t), Offset(x, size.height - 6), labelStyle,
          align: i == 0 ? TextAlign.left : (i == 4 ? TextAlign.right : TextAlign.center));
    }

    // Pecah garis di tempat ada jeda data
    final runs = <List<_Bucket>>[];
    var cur = <_Bucket>[];
    for (final p in points) {
      if (cur.isNotEmpty && gapThreshold != null && p.t.difference(cur.last.t) > gapThreshold!) {
        runs.add(cur);
        cur = <_Bucket>[];
      }
      cur.add(p);
    }
    if (cur.isNotEmpty) runs.add(cur);

    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    for (final run in runs) {
      if (run.length == 1) {
        canvas.drawCircle(Offset(xOf(run.first.t), yOf(run.first.v)), 3, Paint()..color = color);
        continue;
      }
      final path = Path()..moveTo(xOf(run.first.t), yOf(run.first.v));
      for (final p in run.skip(1)) {
        path.lineTo(xOf(p.t), yOf(p.v));
      }
      final area = Path.from(path)
        ..lineTo(xOf(run.last.t), top + h)
        ..lineTo(xOf(run.first.t), top + h)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
          ).createShader(Rect.fromLTWH(left, top, w, h)),
      );
      canvas.drawPath(path, line);
    }

    if (points.length <= 40) {
      for (final p in points) {
        canvas.drawCircle(Offset(xOf(p.t), yOf(p.v)), 2.5, Paint()..color = color);
      }
    }

    if (selected != null) {
      final x = xOf(selected!.t), y = yOf(selected!.v);
      canvas.drawLine(Offset(x, top), Offset(x, top + h),
          Paint()..color = color.withValues(alpha: 0.5)..strokeWidth = 1);
      canvas.drawCircle(Offset(x, y), 6, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = color);
      canvas.drawCircle(Offset(x, y), 3.5,
          Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.points != points || old.isDark != isDark || old.touch != touch || old.color != color;
}

class _BarPainter extends CustomPainter {
  final List<_Bucket> buckets;
  final Color color;
  final bool isDark;
  final int decimals;
  final int? selectedIndex;
  final String Function(_Bucket) labelOf;

  const _BarPainter({
    required this.buckets,
    required this.color,
    required this.isDark,
    required this.decimals,
    required this.selectedIndex,
    required this.labelOf,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0, bottom = 20.0, top = 6.0;
    final w = size.width - left;
    final h = size.height - bottom - top;
    if (w <= 0 || h <= 0 || buckets.isEmpty) return;

    final maxV = buckets.fold<double>(0, (a, b) => math.max(a, b.v));
    final hi = maxV <= 0 ? 1.0 : maxV * 1.1;

    final labelStyle = TextStyle(fontFamily: 'Inter', fontSize: 9,
        color: isDark ? Colors.white38 : const Color(0xFF94A3B8));
    final grid = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = top + h / 3 * i;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      _drawText(canvas, _axisNum(hi - hi / 3 * i, decimals), Offset(left - 6, y), labelStyle,
          align: TextAlign.right);
    }

    final n = buckets.length;
    final slot = w / n;
    final step = n <= 8 ? 1 : (n / 8).ceil();
    for (var i = 0; i < n; i++) {
      final bh = (buckets[i].v / hi) * h;
      final x0 = left + i * slot + slot * 0.18;
      final x1 = left + (i + 1) * slot - slot * 0.18;
      final isSel = selectedIndex == i;
      final paint = Paint()
        ..color = selectedIndex == null || isSel ? color : color.withValues(alpha: 0.35);
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTRB(x0, top + h - bh, x1, top + h),
            topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
        paint,
      );
      if (i % step == 0 || i == n - 1) {
        _drawText(canvas, labelOf(buckets[i]), Offset(left + i * slot + slot / 2, size.height - 6),
            labelStyle, align: TextAlign.center);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.buckets != buckets || old.isDark != isDark || old.selectedIndex != selectedIndex;
}