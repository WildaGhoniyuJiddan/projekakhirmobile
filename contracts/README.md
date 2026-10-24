# DreamBuildRegistry — Penjangkaran Blockchain Rakitan Impian

Smart contract minimal di **Polygon Amoy testnet** untuk mencatat sidik
jari (hash SHA-256) Kartu Rakitan Impian yang diterbitkan dari aplikasi
WorthBang. Isi kartu tetap di Supabase; yang on-chain hanya hash +
penerbit + versi + waktu, agar siapa pun bisa membuktikan isi kartu
tidak berubah sejak diterbitkan.

- Kontrak: `DreamBuildRegistry.sol` (Solidity ^0.8.20, tanpa dependensi)
- Deploy: `deploy.mjs` (ethers v6, baca env — tidak ada key ter-hardcode)
- Verifikasi publik: QR di aplikasi langsung membuka transaksi di Polygonscan Amoy
  (`https://amoy.polygonscan.com/tx/<tx_hash>`)

## Spek kanonik WB-DREAM-v1 (kontrak bersama Dart / TypeScript / chain)

Teks kanonik kartu = baris-baris berikut digabung `"\n"`, **tanpa**
newline di akhir, di-encode UTF-8:

```
WB-DREAM-v1
card:<uuid kartu>
owner:<uuid pemilik>
version:<int>
slot=<SLOT>;name=<nama part>;price=<int rupiah>
total=<int jumlah harga>
```

- Satu baris `slot=...` per slot terisi, urutan slot tetap:
  CPU, Motherboard, GPU, RAM, Storage, PSU, Casing, Cooler, Monitor,
  Lainnya.
- `total` = jumlah semua `price`.
- **contentHash** = SHA-256 hex lowercase dari teks kanonik.
- **cardId on-chain (bytes32)** = SHA-256 dari string uuid kartu.

### Test vector (WAJIB sama di Dart, TS, dan hitungan manual)

Kartu contoh:

- card: `11111111-2222-3333-4444-555555555555`
- owner: `aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee`
- version: `1`
- part:
  - CPU — AMD Ryzen 5 7600 — 3050000
  - Motherboard — MSI B650M Mortar WiFi — 2899000
  - GPU — ASRock Radeon RX 9070 XT Challenger 16GB — 14590000
  - RAM — ADATA XPG Lancer DDR5 32GB (2x16GB) 6000MHz — 2850000
  - Storage — ADATA Legend 850 Lite 1TB NVMe Gen4 — 1299000

Teks kanoniknya persis:

```
WB-DREAM-v1
card:11111111-2222-3333-4444-555555555555
owner:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
version:1
slot=CPU;name=AMD Ryzen 5 7600;price=3050000
slot=Motherboard;name=MSI B650M Mortar WiFi;price=2899000
slot=GPU;name=ASRock Radeon RX 9070 XT Challenger 16GB;price=14590000
slot=RAM;name=ADATA XPG Lancer DDR5 32GB (2x16GB) 6000MHz;price=2850000
slot=Storage;name=ADATA Legend 850 Lite 1TB NVMe Gen4;price=1299000
total=24688000
```

Hasil (dihitung dengan Node `crypto.createHash('sha256')`):

- contentHash: `32c2e8b8a0bf7f5e5aebec07ca2fbd8b56cca62f0ce12b8902c70f14ac902ffa`
- cardId bytes32: `666ff6ccaa5b3c07feaa3a95d3a4bd2c46ac9e9abdb09ca9133528d3dc1e8952`

Test Dart yang membuktikan nilai yang sama:
`test/dream_build/canonical_hash_test.dart`.

## Langkah deploy (SEKALI, oleh pemilik proyek)

1. **Buat wallet proyek** (MetaMask) — khusus proyek ini, bukan wallet
   pribadi. Simpan seed phrase di luar repo.
2. **Isi faucet Amoy**: ambil MATIC testnet gratis dari faucet Polygon
   (https://faucet.polygon.technology — pilih jaringan Amoy) ke alamat
   wallet proyek. Testnet = tidak ada nilai uang.
3. **Jalankan migration** `supabase/migrations/20261021000001_dream_builds.sql`
   di proyek Supabase (SQL editor / CLI).
4. **Deploy kontrak**:
   ```
   cd contracts
   npm i ethers solc
   RPC_URL=https://rpc-amoy.polygon.technology PRIVATE_KEY=0x... node deploy.mjs
   ```
   Catat alamat kontrak dari output.
5. **Pasang secret Supabase** (Edge Function `publish-build`) — JANGAN pernah commit nilai ini / masukkan ke APK:
   - `CHAIN_RPC_URL` = `https://rpc-amoy.polygon.technology`
   - `CHAIN_PRIVATE_KEY` = private key wallet proyek (**hanya**
     `publish-build`)
   - `CHAIN_CONTRACT_ADDRESS` = alamat kontrak hasil langkah 4
6. **Deploy Edge Function** (`publish-build` dengan `verify_jwt`
   aktif) lewat jalur deploy Supabase yang biasa dipakai proyek ini.

Tanpa langkah 5, `publish-build` menjawab `503 chain belum
dikonfigurasi` dan aplikasi tetap bisa menyimpan draft seperti biasa.

## Verifikasi manual di Amoy Polygonscan

1. Terbitkan kartu dari aplikasi → dapat **tx hash**.
2. Buka `https://amoy.polygonscan.com/tx/<tx_hash>` — terlihat transaksi
   ke alamat kontrak, fungsi `publish`, dan event `Published`.
3. Di tab kontrak (Read Contract), panggil `latest` dengan cardId
   bytes32 kartu → bandingkan `contentHash` dengan hash di halaman
   verifikasi (`verify-build`) dan di aplikasi.
4. `historyLength(cardId)` menunjukkan jumlah versi yang pernah
   diterbitkan; `historyAt(cardId, i)` membaca versi ke-i — versi lama
   tidak pernah tertimpa penerbitan baru.
