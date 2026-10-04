// Kamera ringan seperti openHAB: thumbnail snapshot di kartu, tap langsung
// live (MJPEG) tanpa tombol play & tanpa menunggu HLS. Kalau MJPEG gagal,
// otomatis turun ke snapshot yang diperbarui terus (±1 fps).
// Taruh di: lib/core/widgets/camera_widgets.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/controllers/openhab_controller.dart';
import 'package:mobile/core/services/openhab_management_service.dart' show OHThing;

String _thingLabel(OHThing t) => t.label.isNotEmpty ? t.label : t.uid;

// ─────────────────────────────────────────────────────────────────────
// Kartu kamera: thumbnail snapshot (diperbarui tiap beberapa detik)
// ─────────────────────────────────────────────────────────────────────

class CameraThingCard extends StatefulWidget {
  final OHThing thing;
  final OpenHABController ctrl;
  const CameraThingCard({super.key, required this.thing, required this.ctrl});

  @override
  State<CameraThingCard> createState() => _CameraThingCardState();
}

class _CameraThingCardState extends State<CameraThingCard> {
  Uint8List? _bytes;
  bool _failed = false;
  bool _busy = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      final res = await http
          .get(Uri.parse(widget.ctrl.cameraSnapshotUrl(widget.thing)),
              headers: widget.ctrl.authHeaders)
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (res.statusCode == 200 && res.bodyBytes.length > 500) {
        setState(() { _bytes = res.bodyBytes; _failed = false; });
      } else if (_bytes == null) {
        setState(() => _failed = true);
      }
    } catch (_) {
      if (mounted && _bytes == null) setState(() => _failed = true);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _thingLabel(widget.thing);
    final online = widget.thing.isOnline;
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => CameraLiveDialog(thing: widget.thing, ctrl: widget.ctrl),
      ),
      child: Container(
        width: double.infinity,
        height: 170,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(fit: StackFit.expand, children: [
          if (_bytes != null)
            Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true)
          else
            Center(
              child: _failed
                  ? const Icon(Icons.videocam_off_outlined,
                      color: Colors.white24, size: 34)
                  : const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white38)),
            ),
          // gradien agar judul terbaca
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [Color(0xCC000000), Color(0x00000000)],
              ),
            ),
          ),
          Positioned(
            left: 14, top: 12, right: 80,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: 'Inter', fontWeight: FontWeight.w700,
                    fontSize: 15, color: Colors.white)),
          ),
          if (!online)
            Positioned(
              right: 12, top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Offline',
                    style: TextStyle(
                        fontFamily: 'Inter', fontSize: 10,
                        fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          Center(
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 26),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Dialog live: langsung jalan. MJPEG → fallback snapshot.
// ─────────────────────────────────────────────────────────────────────

enum _CamState { connecting, liveMjpeg, liveSnapshot, error }

class CameraLiveDialog extends StatefulWidget {
  final OHThing thing;
  final OpenHABController ctrl;
  const CameraLiveDialog({super.key, required this.thing, required this.ctrl});

  @override
  State<CameraLiveDialog> createState() => _CameraLiveDialogState();
}

class _CameraLiveDialogState extends State<CameraLiveDialog> {
  final _frame = ValueNotifier<Uint8List?>(null);
  _CamState _state = _CamState.connecting;
  String? _error;
  http.Client? _client;
  Timer? _watchdog;
  Timer? _snapTimer;
  DateTime _lastFrame = DateTime.now();
  int _attempt = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    _frame.dispose();
    super.dispose();
  }

  void _stop() {
    _watchdog?.cancel();
    _snapTimer?.cancel();
    _client?.close();
    _client = null;
  }

  void _set(_CamState s, {String? error}) {
    if (_disposed) return;
    setState(() { _state = s; _error = error; });
  }

  Future<void> _start() async {
    _stop();
    _attempt = 0;
    _frame.value = null;
    _set(_CamState.connecting);

    // Picu server (aman kalau channel tidak ada); jangan ditunggu lama.
    widget.ctrl.startCameraStream(widget.thing).timeout(
        const Duration(seconds: 3), onTimeout: () => false).catchError((_) => false);

    await _connectMjpeg();
  }

  Future<void> _connectMjpeg() async {
    if (_disposed) return;
    _attempt++;
    final client = http.Client();
    _client = client;
    _lastFrame = DateTime.now();
    var gotFrame = false;

    // Tidak ada frame dalam 8 detik → anggap gagal.
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 2), (t) {
      if (DateTime.now().difference(_lastFrame) > const Duration(seconds: 8)) {
        t.cancel();
        client.close();
      }
    });

    try {
      final req = http.Request('GET', Uri.parse(widget.ctrl.cameraMjpegUrl(widget.thing)))
        ..headers.addAll(widget.ctrl.authHeaders);
      final resp = await client.send(req).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }

      // Parser MJPEG: cari penanda JPEG awal (FFD8) dan akhir (FFD9).
      var data = Uint8List(0);
      await for (final chunk in resp.stream) {
        if (_disposed) return;
        data = data.isEmpty ? Uint8List.fromList(chunk) : Uint8List.fromList([...data, ...chunk]);
        while (true) {
          final s = _find(data, 0xFF, 0xD8, 0);
          if (s < 0) { if (data.length > 1) data = data.sublist(data.length - 1); break; }
          final e = _find(data, 0xFF, 0xD9, s + 2);
          if (e < 0) { if (s > 0) data = data.sublist(s); break; }
          final jpg = Uint8List.sublistView(data, s, e + 2);
          _frame.value = Uint8List.fromList(jpg);
          _lastFrame = DateTime.now();
          if (!gotFrame) { gotFrame = true; _set(_CamState.liveMjpeg); }
          data = data.sublist(e + 2);
        }
        if (data.length > 3 * 1024 * 1024) data = Uint8List(0); // jaga memori
      }
      throw Exception('stream berhenti');
    } catch (e) {
      _watchdog?.cancel();
      if (_disposed) return;
      if (gotFrame && _attempt < 3) {
        // sempat jalan lalu putus → sambung ulang
        await Future.delayed(const Duration(seconds: 1));
        return _connectMjpeg();
      }
      _startSnapshotFallback();
    }
  }

  int _find(Uint8List d, int a, int b, int from) {
    for (var i = from; i < d.length - 1; i++) {
      if (d[i] == a && d[i + 1] == b) return i;
    }
    return -1;
  }

  // Fallback: snapshot berulang (±1 fps) — tetap "hidup" walau MJPEG tak ada.
  Future<void> _startSnapshotFallback() async {
    _stop();
    if (_disposed) return;
    var fails = 0;
    var busy = false;

    Future<void> tick() async {
      if (busy || _disposed) return;
      busy = true;
      try {
        final res = await http
            .get(Uri.parse(widget.ctrl.cameraSnapshotUrl(widget.thing)),
                headers: widget.ctrl.authHeaders)
            .timeout(const Duration(seconds: 5));
        if (_disposed) return;
        if (res.statusCode == 200 && res.bodyBytes.length > 500) {
          fails = 0;
          _frame.value = res.bodyBytes;
          if (_state != _CamState.liveSnapshot) _set(_CamState.liveSnapshot);
        } else {
          fails++;
        }
      } catch (_) {
        fails++;
      } finally {
        busy = false;
      }
      if (fails >= 4 && _frame.value == null) {
        _snapTimer?.cancel();
        _set(_CamState.error,
            error: widget.thing.isOnline
                ? 'Stream & snapshot tidak bisa diakses dari aplikasi.\n'
                    'Cek URL/autentikasi kamera di openHAB dan pastikan HP '
                    'satu jaringan dengan server.'
                : 'Kamera offline di openHAB. Periksa daya/jaringan kamera.');
      } else if (fails >= 4) {
        _set(_CamState.connecting); // sempat tampil, lalu putus
      }
    }

    await tick();
    _snapTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) => tick());
  }

  @override
  Widget build(BuildContext context) {
    final label = _thingLabel(widget.thing);
    final live = _state == _CamState.liveMjpeg || _state == _CamState.liveSnapshot;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: const Color(0xFF0A0A0A),
            child: Stack(fit: StackFit.expand, children: [
              ValueListenableBuilder<Uint8List?>(
                valueListenable: _frame,
                builder: (_, bytes, __) => bytes == null
                    ? const SizedBox.shrink()
                    : Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
              ),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [Color(0xAA000000), Color(0x00000000)],
                  ),
                ),
              ),
              Positioned(
                left: 16, top: 14, right: 56,
                child: Row(children: [
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'Inter', fontWeight: FontWeight.w700,
                            fontSize: 16, color: Colors.white)),
                  ),
                  if (live) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _state == _CamState.liveMjpeg
                            ? Colors.red.withValues(alpha: 0.9)
                            : Colors.orange.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                          _state == _CamState.liveMjpeg ? 'LIVE' : 'SNAPSHOT',
                          style: const TextStyle(
                              fontFamily: 'Inter', fontSize: 9,
                              fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ],
                ]),
              ),
              Positioned(
                right: 8, top: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              if (_state == _CamState.connecting)
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: const [
                    CircularProgressIndicator(color: Colors.white70, strokeWidth: 2),
                    SizedBox(height: 10),
                    Text('Menghubungkan kamera…',
                        style: TextStyle(
                            fontFamily: 'Inter', fontSize: 12, color: Colors.white54)),
                  ]),
                ),
              if (_state == _CamState.error)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.videocam_off_outlined,
                            color: Colors.white38, size: 34),
                        const SizedBox(height: 8),
                        Text(_error ?? 'Gagal memuat kamera.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontFamily: 'Inter', fontSize: 12, color: Colors.white54)),
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: _start,
                          child: const Text('Coba lagi',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
