/// Kumpulan string Bahasa Indonesia untuk seluruh aplikasi.
///
/// Aturan: tidak ada teks user-facing yang di-hardcode di widget;
/// semua lewat class ini agar konsisten dan mudah diaudit.
abstract final class AppStrings {
  static const appName = 'WorthBang';
  static const appTagline = 'Cek harga, sebelum bayar.';

  // Tab navigasi bawah.
  static const tabHome = 'Beranda';
  static const tabSearch = 'Cari';
  static const tabHistory = 'Riwayat';
  static const tabProfile = 'Profil';

  // Placeholder tiap tab (diganti screen asli di tiket berikutnya).
  static const homeTitle = 'Beranda';
  static const homeGreeting = 'Mau cek harga apa hari ini?';
  static const homeExploreTitle = 'Jelajahi fitur';
  static const homePriceCheckSubtitle =
      'Bandingkan harga sebelum memutuskan membeli.';
  static const homeBuilderSubtitle = 'Buat rekomendasi rakitan PC.';
  static const homeSearchSubtitle = 'Temukan produk dan bandingkan listing.';
  static const homeTrendsSubtitle = 'Lihat ringkasan tren harga.';
  static const homeStoresSubtitle = 'Cari toko komputer di sekitar.';
  static const homeToolsSubtitle = 'Konversi mata uang dan zona waktu.';
  static const homeWishlistSubtitle = 'Simpan produk dan pantau target.';
  static const homeGameSubtitle = 'Tebak harga komponen PC.';
  static const homeChatSubtitle = 'Tanya seputar PC dan laptop.';
  static const searchTitle = 'Cari';
  static const searchPlaceholder =
      'Filter & sortir hasil akan hadir di sini (T4: Search).';
  static const historyTitle = 'Riwayat';
  static const historyPlaceholder =
      'Daftar riwayat analisis akan hadir di sini (T5: History).';
  static const profileTitle = 'Profil';
  static const profilePlaceholder =
      'Pengaturan profil akan hadir di sini (T6: Profile).';

  // Label verdict — SELALU tampil bersama warna (jangan hanya warna).
  static const verdictWorthIt = 'Worth It';
  static const verdictFair = 'Wajar';
  static const verdictOverpriced = 'Kemahalan';

  // Auth (T2).
  static const loginTitle = 'Masuk';
  static const registerTitle = 'Daftar Akun';
  static const nameLabel = 'Nama';
  static const nameRequired = 'Nama wajib diisi';
  static const emailLabel = 'Email';
  static const emailInvalid = 'Format email tidak valid';
  static const passwordLabel = 'Kata sandi';
  static const passwordMin = 'Minimal 8 karakter';
  static const loginButton = 'Masuk';
  static const registerButton = 'Daftar';
  static const goToRegister = 'Belum punya akun? Daftar di sini';
  static const goToLogin = 'Sudah punya akun? Masuk di sini';
  static const biometricButton = 'Masuk dengan sidik jari';

  // Price check (T3).
  static const priceCheckTitle = 'Cek Harga';
  static const queryLabel = 'Nama produk';
  static const queryHint = 'cth: RTX 4060';
  static const queryMin = 'Minimal 2 karakter';
  static const priceLabel = 'Harga yang ditawarkan';
  static const priceInvalid = 'Masukkan harga yang valid';
  static const conditionLabel = 'Kondisi';
  static const checkButton = 'Cek Kelayakan';
  static const doneButton = 'Selesai';

  // Bundle (T4).
  static const bundleTitle = 'Cek Bundle';
  static const bundleModeButton = 'Mode Bundle (multi-komponen)';
  static const bundleAddItem = 'Tambah komponen';
  static const bundleItemLabel = 'Komponen';
  static const bundlePriceLabel = 'Harga paket yang ditawarkan';

  // Search filter & sort (T5).
  static const searchScreenTitle = 'Cari Produk';
  static const searchButton = 'Cari';
  static const searchPriceOptionalLabel = 'Harga (opsional)';
  static const maxPriceLabel = 'Harga maks';
  static const sortLabel = 'Urutkan';
  static const searchEmpty = 'Tidak ada listing yang cocok dengan filter.';

  // History & verify (T6).
  static const historyScreenTitle = 'Riwayat Analisis';
  static const historyEmpty =
      'Belum ada riwayat. Lakukan cek harga dulu di Beranda.';
  static const verifyChainButton = 'Verifikasi rantai';
  static const syncButton = 'Sinkron ke server';
  static const verifyTitle = 'Verifikasi Hash Chain';
  static const verifyEmpty = 'Belum ada blok untuk diverifikasi.';
  static String verifyOk(int n) => 'Rantai valid: $n blok terverifikasi.';
  static const verifyFailed =
      'Rantai RUSAK: ada blok yang datanya diubah!';
  static const tamperSelfTest = 'Self-test: simulasi tampering (debug)';
  static const tamperDemoNote =
      'Mode demo: satu blok diubah di memori (database asli tidak disentuh).';

  // Tren harga (T7).
  static const trendTitle = 'Tren Harga';
  static const viewTrendButton = 'Lihat tren harga';

  // Random builder (T8).
  static const builderTitle = 'Rakit PC Acak';
  static const budgetLabel = 'Budget';
  static const randomBuildButton = 'Acak Rakit';
  static const shakeHint = 'Goyangkan HP untuk mengacak ulang';
  static const shakeDetected = 'Shake terdeteksi — merakit ulang…';
  static const totalLabel = 'Total';

  // Toko terdekat (T9).
  static const storesTitle = 'Toko Terdekat';
  static const refreshLabel = 'Muat';
  static const storesEmpty = 'Tidak ada toko di sekitar.';
  static const searchStoreLabel = 'Cari nama toko';
  static const searchStoreHint = 'cth: Computa, ELS Computer...';
  static const cheapestLabel = 'TERMURAH';
  static const demoLocationNote =
      'Izin lokasi tidak diberikan — memakai lokasi demo Jakarta.';

  // Konverter (T10).
  static const toolsTitle = 'Konverter';
  static const currencySection = 'Mata Uang';
  static const timezoneSection = 'Zona Waktu';
  static const amountLabel = 'Nominal (IDR)';
  static const toLabel = 'Ke';
  static const fromLabel = 'Dari';

  // Wishlist & alert (T11).
  static const wishlistTitle = 'Wishlist & Alert';
  static const wishlistTab = 'Wishlist';
  static const alertsTab = 'Alert Harga';
  static const wishlistEmpty =
      'Wishlist kosong. Simpan dari hasil cek harga.';
  static const alertsEmpty =
      'Belum ada alert. Buat dari hasil cek harga.';
  static const addWishlist = 'Simpan ke wishlist';
  static const wishlistAdded = 'Tersimpan ke wishlist.';
  static const addAlert = 'Buat alert harga';
  static const alertAdded = 'Alert harga dibuat. Kami cek tiap 15 menit.';
  static const targetPriceLabel = 'Target harga';
  static const cancelButton = 'Batal';
  static const saveButton = 'Simpan';
  static const checkAlertsNow = 'Cek alert sekarang';
  static const alertCheckNone =
      'Tidak ada alert yang terpicu saat ini.';

  // Game Tebak Harga (T12).
  static const gameTitle = 'Tebak Harga';
  static const guessLabel = 'Tebakan harga';
  static const submitGuessButton = 'Kirim Tebakan';
  static const nextRoundButton = 'Ronde Berikutnya';
  static const finishButton = 'Lihat Hasil';
  static const retryButton = 'Coba Lagi';
  static const gameFinished = 'Permainan Selesai!';
  static const newRecord = '🏆 Rekor baru!';
  static const playAgainButton = 'Main Lagi';
  static const moreFeatures = 'Fitur lainnya';

  // Chatbot Dodo (T13).
  static const chatTitle = 'Tanya Dodo';
  static const chatHint = 'Tanya soal komponen PC/laptop…';
  static const chatWelcome =
      'Halo! Aku Dodo 🤖. Tanya soal harga komponen, minta rakitan PC, atau tanya fitur aplikasi ini.';
  static const chatError = 'Gagal menghubungi Dodo';
  static const buildCardTitle = 'Rakitan rekomendasi';

  // Profil (T14).
  static const profileScreenTitle = 'Profil';
  static const settingsSection = 'Pengaturan';
  static const biometricSetting = 'Biometric unlock';
  static const biometricSubtitle = 'Buka sesi dengan sidik jari/wajah';
  static const tiltSetting = 'Efek 3D kartu (gyroscope)';
  static const tiltSubtitle = 'Kartu miring mengikuti gerakan HP';
  static const themeSetting = 'Tema';
  static const feedbackSection = 'Kirim Feedback';
  static const kesanLabel = 'Kesan';
  static const saranLabel = 'Saran';
  static const sendFeedbackButton = 'Kirim Feedback';
  static const feedbackSent = 'Terima kasih atas feedback-nya!';
  static const photoUpdated = 'Foto profil diperbarui.';
  static const editNameTitle = 'Ubah Nama';
  static const logoutTitle = 'Keluar';
  static const logoutConfirm = 'Yakin ingin keluar dari akun?';
  static const logoutButton = 'Keluar';

  // Offline & sinkronisasi (T15).
  static const offlineBanner =
      'Offline — data tersimpan lokal, mutasi dikirim saat online.';
  static const queuedForSync =
      'Offline — disimpan, otomatis dikirim saat online.';
  static const pendingSync = 'Menunggu sinkron';
  static const syncNowButton = 'Sinkronkan';
  static const syncDone = 'Sinkron selesai. Sisa antrian';
  static String syncHistoryDone(int sent, int rest) =>
      'Terkirim $sent riwayat ke server • sisa antrian $rest';
  static const neverSynced = 'Belum pernah disinkronkan';
  static String lastUpdated(String when) => 'Terakhir diperbarui $when';
}
