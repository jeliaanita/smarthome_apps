import 'package:flutter/material.dart';


class AccessDeniedView extends StatelessWidget {
  final String featureName;
  const AccessDeniedView({super.key, required this.featureName});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 18, color: cs.onSurface),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline_rounded, size: 56,
                color: isDark ? Colors.white24 : Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('Akses Terbatas',
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700,
                    fontSize: 18, color: cs.onSurface)),
            const SizedBox(height: 8),
            Text('$featureName cuma bisa diakses oleh admin.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Inter', fontSize: 13,
                    color: isDark ? Colors.white54 : Colors.grey.shade600)),
          ]),
        ),
      ),
    );
  }
}