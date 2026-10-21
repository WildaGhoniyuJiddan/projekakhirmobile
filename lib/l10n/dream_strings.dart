/// String UI khusus fitur Rakitan Impian (dream builds).
///
/// Sengaja terpisah dari `strings.dart` (AppStrings) agar fitur ini bisa
/// dikembangkan tanpa menyentuh file string global.
abstract final class DreamStrings {
  static const title = 'Rakitan Impian';
  static const homeSubtitle = 'Susun kartu rakitan & terbitkan ke blockchain.';
  static const empty =
      'Belum ada kartu Rakitan Impian. Buat kartu pertama untuk menyusun '
      'rakitan impianmu dan menerbitkannya ke blockchain.';
  static const newBuild = 'Buat Kartu Baru';
  static const nameLabel = 'Nama kartu';
  static const nameHint = 'mis. Rakitan Gaming 2026';
  static const create = 'Buat';
  static const cancel = 'Batal';
  static const saveDraft = 'Simpan Draft';
  static const delete = 'Hapus Kartu';
  static const publish = 'Terbitkan ke Blockchain';
  static const publishing = 'Menerbitkan...';
  static const statusDraft = 'Draft';
  static const statusPublished = 'Terbit';
  static const versionLabel = 'Versi';
  static const totalLabel = 'Total';
  static const emptySlot = 'Kosong — ketuk untuk memilih part';
  static const pickPart = 'Pilih Part';
  static const searchPartHint = 'Cari part...';
  static const clearSlot = 'Kosongkan slot';
  static const addFromResult = 'Rakitan Impian';
  static const addFromResultTitle = 'Tambah ke Rakitan Impian';
  static const addFromResultNew = 'Buat kartu baru...';
  static const addedToast = 'Ditambahkan ke Rakitan Impian.';
  static const savedToast = 'Draft tersimpan.';
  static const publishedToast = 'Kartu diterbitkan ke blockchain.';
  static const txHashLabel = 'Tx Hash';
  static const contentHashLabel = 'Hash Konten (SHA-256)';
  static const verifyQrLabel = 'Pindai untuk verifikasi publik';
  static const pickBuildFirst = 'Pilih kartu tujuan dulu';
}
