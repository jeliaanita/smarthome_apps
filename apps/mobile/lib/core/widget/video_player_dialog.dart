import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

/// Dialog video player HLS sungguhan (video_player + hlsUrl dari binding
/// IP Camera). Mulai dari tampilan poster (gelap + tombol play, mirip
/// widget Video openHAB) — begitu ditekan, baru mulai inisialisasi &
/// memutar stream. Kalau gagal (URL invalid/stream mati), tampilkan
/// pesan error yang jelas, bukan pura-pura berhasil.
class VideoPlayerDialog extends StatefulWidget {
  final String label;
  final String videoUrl;
  /// Dijalankan sebelum mulai memutar (mis. nyalain channel startStream
  /// binding IP Camera). Return false kalau channel/Item startStream-nya
  /// tidak ditemukan — dipakai untuk kasih pesan error yang lebih spesifik
  /// ketimbang "gagal memutar video" generik. Opsional — biar widget ini
  /// tetap reusable buat kasus tanpa Thing (item Camera biasa yang
  /// state-nya langsung URL).
  final Future<bool> Function()? onBeforePlay;
  /// Header Authorization yang sama dipakai request REST openHAB lain —
  /// tanpa ini, request stream ke server openHAB yang butuh autentikasi
  /// akan selalu kena 401 walau URL dan stream-nya sendiri sudah benar.
  final Map<String, String> httpHeaders;
 const VideoPlayerDialog({
  super.key,
  required this.label,
  required this.videoUrl,
  this.onBeforePlay,
  this.httpHeaders = const {},
});

  @override
  State<VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<VideoPlayerDialog> {
  VideoPlayerController? _controller;
  bool _started = false;
  bool _loading = false;
  String? _error;
  bool _muted = false;

  Future<void> _startPlayback() async {
    setState(() { _started = true; _loading = true; _error = null; });
    try {
      if (widget.onBeforePlay != null) {
        final triggered = await widget.onBeforePlay!();
        if (!triggered) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = 'Channel "startStream" belum di-link ke Item — server '
                'tidak pernah dipicu untuk mulai membuat file stream. '
                'Cek konfigurasi Thing kamera ini di openHAB.';
          });
          return;
        }
        // FFmpeg butuh waktu buka koneksi RTSP + probe stream + generate
        // manifest .m3u8/.mjpeg pertama kali dipicu — durasinya beda-beda
        // tiap kamera/jaringan (bisa 2 detik, bisa >10 detik), jadi delay
        // TETAP tidak reliable. Sebagai gantinya, poll URL manifestnya
        // sampai server benar-benar siap (HTTP 200) atau timeout.
        final ready = await _waitUntilStreamReady(widget.videoUrl, widget.httpHeaders);
        if (!mounted) return;
        if (!ready) {
          setState(() {
            _loading = false;
            _error = 'Stream belum siap setelah menunggu — server openHAB '
                'mungkin gagal generate file (cek log FFmpeg/RTSP di server) '
                'atau kamera tidak reachable.';
          });
          return;
        }
      }
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
        formatHint: VideoFormat.hls,
        httpHeaders: widget.httpHeaders,
      );
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) { controller.dispose(); return; }
      setState(() { _controller = controller; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Gagal memutar video.\nPastikan stream aktif & URL benar.';
      });
    }
  }

  /// Poll URL manifest/stream sampai server balas 200 (artinya FFmpeg
  /// sudah selesai generate file), dicoba tiap 1.5 detik sampai
  /// [maxWait] tercapai. HEAD request dulu kalau server tidak izinkan
  /// HEAD (405/501), fallback ke GET biasa.
  Future<bool> _waitUntilStreamReady(
    String url,
    Map<String, String> headers, {
    Duration maxWait = const Duration(seconds: 15),
    Duration interval = const Duration(milliseconds: 1500),
  }) async {
    final deadline = DateTime.now().add(maxWait);
    while (DateTime.now().isBefore(deadline)) {
      if (!mounted) return false;
      try {
        var res = await http
            .head(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 3));
        if (res.statusCode == 405 || res.statusCode == 501) {
          res = await http
              .get(Uri.parse(url), headers: headers)
              .timeout(const Duration(seconds: 3));
        }
        if (res.statusCode == 200) return true;
      } catch (_) {
        // belum siap / server belum reachable, coba lagi
      }
      await Future.delayed(interval);
    }
    return false;
  }

  void _toggleMute() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      _muted = !_muted;
      c.setVolume(_muted ? 0 : 1);
    });
  }

  void _togglePlayPause() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      c.value.isPlaying ? c.pause() : c.play();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final hasVideo = controller != null && controller.value.isInitialized;
    final aspectRatio = hasVideo ? controller.value.aspectRatio : 16 / 9;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Container(
            color: const Color(0xFF0A0A0A),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasVideo)
                  GestureDetector(
                    onTap: _togglePlayPause,
                    child: VideoPlayer(controller),
                  ),
                Positioned(
                  left: 16, top: 14,
                  child: Text(widget.label,
                      style: const TextStyle(
                          fontFamily: 'Inter', fontWeight: FontWeight.w700,
                          fontSize: 16, color: Colors.white)),
                ),
                Positioned(
                  right: 8, top: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                if (hasVideo)
                  Positioned(
                    right: 8, bottom: 8,
                    child: IconButton(
                      icon: Icon(_muted ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white70),
                      onPressed: _toggleMute,
                    ),
                  ),
                if (!_started)
                  Center(
                    child: GestureDetector(
                      onTap: _startPlayback,
                      child: Container(
                        width: 56, height: 56,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE4E4E7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.black, size: 30),
                      ),
                    ),
                  )
                else if (_loading)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white70),
                  )
                else if (_error != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: SingleChildScrollView(
                        child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.white38, size: 36),
                          const SizedBox(height: 8),
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontFamily: 'Inter', fontSize: 12,
                                  color: Colors.white54)),
                          const SizedBox(height: 10),
                          // URL yang beneran dicoba — biar bisa di-copy dan
                          // dites manual di browser/VLC buat mastiin ini
                          // masalah di app atau di server/binding kamera.
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: widget.videoUrl));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('URL disalin ke clipboard'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(widget.videoUrl,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        style: const TextStyle(
                                            fontFamily: 'monospace', fontSize: 10,
                                            color: Colors.white38)),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.copy, size: 12, color: Colors.white38),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _startPlayback,
                            child: const Text('Coba lagi',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
