import 'package:flutter/material.dart';
class _LC {
  static const orange     = Color(0xFFFFA500);
  static const background  = Color(0xFFF5F5F7);
  static const white       = Colors.white;
  static const textPrimary = Color(0xFF18181B);
  static const textMuted   = Color(0xFF71717A);
  static const textLight   = Color(0xFF9E9E9E);
  static const divider     = Color(0xFFEEEEEE);

  static const darkBg      = Color(0xFF18181B);
  static const darkSurface = Color(0xFF27272A);
  static const darkBorder  = Color(0xFF3F3F46);
  static const darkText    = Colors.white;
  static const darkMuted   = Color(0xFFFFFFFF); // will use opacity

  static List<BoxShadow> cardShadow(bool isDark) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
  ];

  static TextStyle h1(bool isDark) => TextStyle(
    fontFamily: 'Inter', fontWeight: FontWeight.w700,
    fontSize: 22, height: 1.3,
    color: isDark ? Colors.white : textPrimary,
  );
  static TextStyle h2(bool isDark) => TextStyle(
    fontFamily: 'Inter', fontWeight: FontWeight.w600,
    fontSize: 15, height: 1.4,
    color: isDark ? Colors.white : textPrimary,
  );
  static TextStyle body(bool isDark) => TextStyle(
    fontFamily: 'Inter', fontWeight: FontWeight.w400,
    fontSize: 14, height: 1.65,
    color: isDark ? Colors.white70 : textMuted,
  );
  static TextStyle caption(bool isDark) => TextStyle(
    fontFamily: 'Inter', fontSize: 12, height: 1.5,
    color: isDark ? Colors.white38 : textLight,
  );
  static TextStyle appBarTitle(bool isDark) => TextStyle(
    fontFamily: 'Inter', fontWeight: FontWeight.w600,
    fontSize: 17,
    color: isDark ? Colors.white : textPrimary,
  );
}

class _LegalHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String lastUpdated;

  const _LegalHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.lastUpdated,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: BoxDecoration(
        color: isDark ? _LC.darkSurface : _LC.white,
        boxShadow: _LC.cardShadow(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: _LC.orange.withValues(alpha: isDark ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: _LC.orange, size: 24),
          ),
          const SizedBox(height: 16),
          Text(title, style: _LC.h1(isDark)),
          const SizedBox(height: 6),
          Text(subtitle, style: _LC.body(isDark)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isDark ? _LC.darkBg : _LC.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Terakhir diperbarui: $lastUpdated',
              style: _LC.caption(isDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalSection extends StatelessWidget {
  final String number;
  final String title;
  final String content;
  final bool isLast;

  const _LegalSection({
    required this.number,
    required this.title,
    required this.content,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: _LC.orange.withValues(alpha: isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    number,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: _LC.orange,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: _LC.h2(isDark)),
                    const SizedBox(height: 8),
                    Text(content, style: _LC.body(isDark)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast) ...[
          const SizedBox(height: 20),
          Divider(
            height: 1,
            thickness: 1,
            color: isDark ? _LC.darkBorder : _LC.divider,
            indent: 20,
            endIndent: 20,
          ),
        ],
      ],
    );
  }
}

class _HighlightBox extends StatelessWidget {
  final String text;
  final IconData icon;

  const _HighlightBox({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _LC.orange.withValues(alpha: isDark ? 0.1 : 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: _LC.orange.withValues(alpha: isDark ? 0.3 : 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _LC.orange, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: _LC.body(isDark).copyWith(
                color: isDark ? Colors.white : _LC.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark ? _LC.darkBg : _LC.background,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Terms of Service', style: _LC.appBarTitle(isDark)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
              height: 1,
              color: isDark ? _LC.darkBorder : _LC.divider),
        ),
      ),
      body: ListView(
        children: [
          _LegalHeader(
            icon: Icons.gavel_rounded,
            title: 'Terms of Service',
            subtitle:
                'Syarat dan ketentuan penggunaan aplikasi Philoin Smart Home.',
            lastUpdated: '1 Juni 2025',
          ),

          const SizedBox(height: 12),

          const _HighlightBox(
            icon: Icons.info_outline_rounded,
            text:
                'Dengan menggunakan aplikasi Philoin, Anda menyatakan telah membaca, memahami, '
                'dan menyetujui seluruh syarat dan ketentuan berikut.',
          ),

          Container(
            margin: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            decoration: BoxDecoration(
              color: isDark ? _LC.darkSurface : _LC.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: _LC.cardShadow(isDark),
            ),
            child: const Column(
              children: [
                _LegalSection(
                  number: '1',
                  title: 'Penerimaan Syarat',
                  content:
                      'Dengan mengakses atau menggunakan layanan Philoin, Anda setuju untuk terikat '
                      'dengan syarat ini. Jika Anda tidak menyetujui syarat ini, harap hentikan '
                      'penggunaan aplikasi.',
                ),
                _LegalSection(
                  number: '2',
                  title: 'Penggunaan Layanan',
                  content:
                      'Anda boleh menggunakan aplikasi ini hanya untuk keperluan yang sah dan sesuai '
                      'dengan hukum yang berlaku. Anda dilarang menggunakan layanan untuk tujuan ilegal, '
                      'menyebabkan gangguan, atau membahayakan pengguna lain maupun infrastruktur sistem.',
                ),
                _LegalSection(
                  number: '3',
                  title: 'Akun Pengguna',
                  content:
                      'Anda bertanggung jawab menjaga kerahasiaan kredensial akun Anda. Philoin tidak '
                      'bertanggung jawab atas kerugian yang disebabkan oleh akses tidak sah akibat '
                      'kelalaian pengguna dalam menjaga keamanan akun.',
                ),
                _LegalSection(
                  number: '4',
                  title: 'Perangkat & Integrasi openHAB',
                  content:
                      'Koneksi ke server openHAB adalah tanggung jawab pengguna sepenuhnya. Philoin '
                      'hanya menyediakan antarmuka dan tidak bertanggung jawab atas kerusakan perangkat '
                      'akibat kesalahan konfigurasi atau penggunaan rule otomasi.',
                ),
                _LegalSection(
                  number: '5',
                  title: 'Batasan Tanggung Jawab',
                  content:
                      'Philoin disediakan "sebagaimana adanya" tanpa jaminan apapun. Kami tidak '
                      'menjamin ketersediaan layanan 100% dan tidak bertanggung jawab atas kerugian '
                      'tidak langsung yang timbul dari penggunaan atau ketidakmampuan menggunakan layanan.',
                ),
                _LegalSection(
                  number: '6',
                  title: 'Perubahan Syarat',
                  content:
                      'Kami berhak memperbarui syarat ini sewaktu-waktu. Perubahan akan diberitahukan '
                      'melalui aplikasi. Penggunaan berkelanjutan setelah pemberitahuan berarti Anda '
                      'menerima syarat yang diperbarui.',
                ),
                _LegalSection(
                  number: '7',
                  title: 'Hukum yang Berlaku',
                  content:
                      'Syarat ini diatur oleh hukum Republik Indonesia. Setiap sengketa diselesaikan '
                      'melalui musyawarah mufakat terlebih dahulu, dan jika tidak tercapai, melalui '
                      'pengadilan yang berwenang di Indonesia.',
                  isLast: true,
                ),
              ],
            ),
          ),
          _ContactCard(
            isDark: isDark,
            title: 'Ada pertanyaan?',
            email: 'support@philoin.app',
          ),
        ],
      ),
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark ? _LC.darkBg : _LC.background,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Privacy Policy', style: _LC.appBarTitle(isDark)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
              height: 1,
              color: isDark ? _LC.darkBorder : _LC.divider),
        ),
      ),
      body: ListView(
        children: [
          _LegalHeader(
            icon: Icons.shield_outlined,
            title: 'Privacy Policy',
            subtitle:
                'Bagaimana Philoin mengumpulkan, menggunakan, dan melindungi data Anda.',
            lastUpdated: '1 Juni 2025',
          ),

          const SizedBox(height: 12),

          const _HighlightBox(
            icon: Icons.lock_outline_rounded,
            text:
                'Privasi Anda adalah prioritas kami. Kami berkomitmen untuk melindungi '
                'informasi pribadi Anda dan tidak akan pernah menjualnya kepada pihak ketiga.',
          ),

          Container(
            margin: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            decoration: BoxDecoration(
              color: isDark ? _LC.darkSurface : _LC.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: _LC.cardShadow(isDark),
            ),
            child: const Column(
              children: [
                _LegalSection(
                  number: '1',
                  title: 'Data yang Kami Kumpulkan',
                  content:
                      'Kami mengumpulkan: (a) Informasi akun seperti nama, email, dan foto profil '
                      'yang Anda berikan saat registrasi; (b) Data konfigurasi server openHAB seperti '
                      'URL server dan token API yang disimpan secara lokal di perangkat Anda; '
                      '(c) Data penggunaan aplikasi secara anonim untuk peningkatan layanan.',
                ),
                _LegalSection(
                  number: '2',
                  title: 'Cara Kami Menggunakan Data',
                  content:
                      'Data Anda digunakan untuk: mengautentikasi akun, menyediakan fungsionalitas '
                      'kontrol perangkat smart home, mempersonalisasi pengalaman aplikasi, '
                      'dan mengirimkan notifikasi yang relevan. Kami tidak menggunakan data '
                      'Anda untuk iklan.',
                ),
                _LegalSection(
                  number: '3',
                  title: 'Penyimpanan Data',
                  content:
                      'Kredensial Firebase (email & password) disimpan dengan enkripsi oleh Firebase Authentication. '
                      'Konfigurasi server openHAB (URL, token, username, password) disimpan secara lokal '
                      'di perangkat Anda menggunakan Flutter Secure Storage dan tidak dikirim ke server kami.',
                ),
                _LegalSection(
                  number: '4',
                  title: 'Berbagi Data dengan Pihak Ketiga',
                  content:
                      'Kami menggunakan layanan Firebase (Google) untuk autentikasi. Data yang dibagikan '
                      'hanya email dan nama akun sesuai kebijakan Firebase. Kami tidak membagikan, '
                      'menjual, atau menyewakan data pribadi Anda kepada pihak lain manapun.',
                ),
                _LegalSection(
                  number: '5',
                  title: 'Keamanan Data',
                  content:
                      'Kami menerapkan langkah-langkah keamanan teknis yang wajar, termasuk enkripsi '
                      'data sensitif dan koneksi HTTPS. Namun, tidak ada sistem yang 100% aman — '
                      'kami mendorong Anda untuk menggunakan password yang kuat dan unik.',
                ),
                _LegalSection(
                  number: '6',
                  title: 'Hak Anda',
                  content:
                      'Anda berhak untuk: mengakses data pribadi Anda, meminta koreksi data yang '
                      'tidak akurat, menghapus akun beserta data Anda, dan menarik persetujuan '
                      'kapan saja. Hubungi kami melalui email di bawah untuk mengajukan permintaan.',
                ),
                _LegalSection(
                  number: '7',
                  title: 'Cookie & Pelacakan',
                  content:
                      'Aplikasi mobile Philoin tidak menggunakan cookie. Kami mungkin menggunakan '
                      'analytics anonim (tanpa informasi identitas) untuk memahami pola penggunaan '
                      'dan meningkatkan performa aplikasi.',
                ),
                _LegalSection(
                  number: '8',
                  title: 'Perubahan Kebijakan',
                  content:
                      'Kami dapat memperbarui kebijakan privasi ini dari waktu ke waktu. '
                      'Perubahan signifikan akan diberitahukan melalui notifikasi aplikasi atau email. '
                      'Tanggal "terakhir diperbarui" di atas selalu mencerminkan versi terkini.',
                  isLast: true,
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? _LC.darkSurface : _LC.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: _LC.cardShadow(isDark),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ringkasan Data',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.white : _LC.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _DataPoint(
                  icon: Icons.check_circle_outline_rounded,
                  color: const Color(0xFF34C759),
                  text: 'Data disimpan terenkripsi',
                  isDark: isDark,
                ),
                _DataPoint(
                  icon: Icons.check_circle_outline_rounded,
                  color: const Color(0xFF34C759),
                  text: 'Tidak dijual ke pihak ketiga',
                  isDark: isDark,
                ),
                _DataPoint(
                  icon: Icons.check_circle_outline_rounded,
                  color: const Color(0xFF34C759),
                  text: 'Konfigurasi server hanya di perangkat lokal',
                  isDark: isDark,
                ),
                _DataPoint(
                  icon: Icons.check_circle_outline_rounded,
                  color: const Color(0xFF34C759),
                  text: 'Akun dapat dihapus kapan saja',
                  isDark: isDark,
                ),
              ],
            ),
          ),
          _ContactCard(
            isDark: isDark,
            title: 'Data Requests & Pertanyaan',
            email: 'privacy@philoin.app',
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final bool isDark;
  final String title;
  final String email;

  const _ContactCard({
    required this.isDark,
    required this.title,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? _LC.darkSurface : _LC.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _LC.cardShadow(isDark),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: _LC.orange.withValues(alpha: isDark ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.mail_outline_rounded,
                color: _LC.orange, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.white : _LC.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: _LC.orange,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DataPoint extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final bool isDark;

  const _DataPoint({
    required this.icon,
    required this.color,
    required this.text,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: isDark ? Colors.white60 : _LC.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}