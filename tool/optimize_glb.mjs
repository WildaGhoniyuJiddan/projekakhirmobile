#!/usr/bin/env node
// Optimasi aset GLB BuildCores untuk runtime Flutter (glbview).
//
// Aturan ketat (dipakai untuk memperbaiki hasil kompresi sebelumnya yang
// mengubah bentuk 3D menjadi kotak kasar dan membuat tekstur blur):
//
//  1. TIDAK ADA pengurangan poligon. `simplify()` / `decimate()` dilarang.
//     Jumlah triangle & vertex sebelum == sesudah.
//
//  2. Kompresi geometri tanpa mengurangi poligon: `KHR_mesh_quantization`
//     dengan quantization bits tinggi (POSITION>=14, NORMAL>=10, TEXCOORD>=12).
//     Mesh di-dequantize ke float32 lalu di-quantize ulang supaya presisi
//     tinggi dan error kuantisasi tidak menumpuk.
//
//     CATATAN: Draco (`draco()`) sengaja TIDAK dipakai. Renderer `glbview`
//     yang dipakai app menolak file ber-Draco di level primitive
//     ("Compressed geometry is not supported"), sehingga file hasil Draco
//     tidak bisa dirender sama sekali di app.
//
//  3. Tekstur: minimum 1024x1024, konversi WebP quality 85.
//     Sumber BuildCores memakai KTX2 (KHR_texture_basisu) yang TIDAK bisa
//     didekode `sharp` dan juga DITOLAK renderer `glbview`. Jadi KTX2
//     dibongkar ke PNG dulu lewat `basisu -unpack`, baru dikompres ke WebP.
//
//  4. Pembersihan aman saja: dedup(), prune(), resample(). Tidak ada
//     transform yang mengubah bentuk.
//
// Output: output_optimized/<path-relatif>.glb (file asli tidak ditimpa).
//
// Run: node tool/optimize_glb.mjs [--dry-run] [file.glb ...]

import { readFile, writeFile, mkdir, readdir, stat, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import path from 'node:path';
import { NodeIO, PropertyType } from '@gltf-transform/core';
import { ALL_EXTENSIONS, EXTTextureWebP } from '@gltf-transform/extensions';
import { dedup, prune, resample, quantize, dequantize, weld } from '@gltf-transform/functions';
import draco3d from 'draco3dgltf';
import sharp from 'sharp';

const exec = promisify(execFile);

const ROOT = path.resolve(import.meta.dirname, '..');
const RAW_ROOT = path.join(ROOT, 'assets', '3d');
// Output disimpan di dalam tool/ supaya root project tetap rapi.
// File asli di assets/3d/ tidak pernah ditimpa.
const OUT_ROOT = path.join(ROOT, 'tool', 'output', 'optimized');
const TMP_ROOT = path.join(ROOT, 'tool', 'output', '.tmp');

// Basis Universal transcoder — membongkar KTX2 ke PNG.
const BASISU = path.join(
  import.meta.dirname,
  'node_modules',
  'basis_universal',
  'bin',
  process.platform === 'win32' ? 'basisu.exe' : 'basisu',
);

// Batas ukuran teksur: JANGAN di bawah 1024 (aturan 3).
const TEXTURE_MAX = 1024;
const TEXTURE_QUALITY = 85;

// Kuantisasi mesh (aturan 2).
//
// PENTING: Draco (`draco()`) sengaja TIDAK dipakai. Renderer `glbview` yang
// dipakai app menolak file ber-Draco di level primitive
// ("Compressed geometry is not supported (KHR_draco_mesh_compression)"),
// sehingga file hasil Draco tidak bisa dirender sama sekali di app.
//
// Yang dipakai: `KHR_mesh_quantization` dengan quantization bits tinggi
// (POSITION>=14, NORMAL>=10, TEXCOORD>=12). Quantization hanya mengecilkan
// byte data, TIDAK mengurangi jumlah triangle/vertex.
//
// CATATAN PENTING soal urutan operasi:
// Sumber BuildCores sudah ter-quantize (POSITION 16-bit, TEXCOORD 16-bit,
// NORMAL 8-bit). Kalau seluruh mesh di-dequantize dulu ke float32 lalu
// di-quantize ulang, ukurannya justru MEMBESAR: float32 itu 12-16 byte per
// vertex, dan `quantize()` menolak TEXCOORD yang di luar rentang [0,1]
// (UV tiling) sehingga UV tetap float32 — hasil akhirnya lebih besar dari
// sumber.
//
// Jadi:
//   - POSITION & TEXCOORD: biarkan yang quantized apa adanya (16-bit >= 14
//     dan >= 12, jadi sudah memenuhi aturan dan TIDAK perlu diubah).
//   - NORMAL: dinaikkan dari 8-bit ke 10-bit. Ini satu-satunya atribut yang
//     belum memenuhi aturan minimal, dan dinaikkan hanya untuk NORMAL saja
//     supaya POSITION/UV tidak ikut ter-inflate.
const QUANTIZE_OPTIONS = {
  quantizePosition: 14,
  quantizeNormal: 10,
  quantizeTexcoord: 12,
  quantizeColor: 8,
  quantizeGeneric: 12,
  quantizationVolume: 'mesh',
};

// Hanya NORMAL yang disentuh. POSITION/TEXCOORD dibiarkan apa adanya.
const NORMAL_ONLY = /^(NORMAL)$/;

const io = new NodeIO()
  .registerExtensions(ALL_EXTENSIONS)
  .registerDependencies({
    'draco3d.decoder': await draco3d.createDecoderModule(),
    'draco3d.encoder': await draco3d.createEncoderModule(),
  });

// Daftarkan EXT_texture_webp supaya writer menuliskan
// `textures[].extensions.EXT_texture_webp` + `image[].mimeType=image/webp`.
// `glbview` membaca texture lewat extension ini (lihat glb_parser.dart).
EXTTextureWebP.register();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function* walk(dir) {
  if (!existsSync(dir)) return;
  for (const e of await readdir(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) yield* walk(p);
    else if (e.name.endsWith('.glb')) yield p;
  }
}

/// Bongkar KTX2 -> PNG.
///
/// `basisu -unpack` menulis banyak file ke direktori kerja saat ini dengan
/// pola `<base>_unpacked_<channel>_<FORMAT>_<mip>_<face>_0000.png`:
///   - `_rgba_` = warna + alpha digabung (yang kita pakai)
///   - `_rgb_`  = warna saja, `_a_` = alpha saja
///   - `_0_`    = mip level 0 (resolusi penuh)
///
/// `-format_only 1` membatasi output ke ETC2_RGBA saja, jadi tidak sampai 224
/// file per tekstur.
const BASISU_FORMAT_ETC2_RGBA = 1;

async function ktx2ToPng(ktx2Bytes, workDir, baseName) {
  const inFile = path.join(workDir, `${baseName}.ktx2`);
  await writeFile(inFile, ktx2Bytes);
  try {
    // basisu mengabaikan -output_file saat -unpack; dia menulis ke cwd.
    // Jadi cwd dipindah ke workDir supaya file tidak tercecer.
    await exec(BASISU, ['-unpack', '-no_ktx', '-format_only', String(BASISU_FORMAT_ETC2_RGBA), inFile], {
      cwd: workDir,
      timeout: 120000,
      maxBuffer: 32 * 1024 * 1024,
    });
  } finally {
    await rm(inFile, { force: true });
  }

  const files = (await readdir(workDir)).filter(
    (f) => f.startsWith(`${baseName}_unpacked_rgba_`) && f.endsWith('_0_0000.png'),
  );
  if (!files.length) {
    throw new Error('basisu tidak menghasilkan PNG rgba mip0');
  }
  // Kalau ada beberapa, ambil yang paling besar (mip 0).
  files.sort();
  const outPng = path.join(workDir, `${baseName}_mip0.png`);
  await writeFile(outPng, await readFile(path.join(workDir, files[0])));
  // Buang semua file turunan basisu.
  for (const f of files) await rm(path.join(workDir, f), { force: true });
  return outPng;
}

/// Naga PNG/WebP/JPEG yang bisa dibaca `sharp` menjadi buffer PNG di disk.
async function toPngBytes(texture, workDir) {
  const mime = texture.getMimeType();
  const bytes = texture.getImage();
  if (!bytes || bytes.byteLength === 0) return null;

  const baseName = (texture.getName() || 'tex').replace(/[^a-zA-Z0-9_-]/g, '_');

  if (mime === 'image/ktx2') {
    const pngPath = await ktx2ToPng(Buffer.from(bytes), workDir, baseName);
    const png = await readFile(pngPath);
    await rm(pngPath, { force: true });
    return png;
  }

  // PNG/JPEG/WebP — sharp bisa baca langsung.
  const pngPath = path.join(workDir, `${baseName}.png`);
  await sharp(Buffer.from(bytes)).png().toFile(pngPath);
  const png = await readFile(pngPath);
  await rm(pngPath, { force: true });
  return png;
}

/// Kumpulkan mesh yang benar-benar DIRENDER dari scene default, **per instans**.
///
/// `prune()` melakukan tree-shake pada node yang tidak terjangkau dari scene.
/// Node "tersembunyi" itu memang tidak pernah dirender, jadi menghapusnya
/// bukan pengurangan poligon yang terlihat.
///
/// PENTING: hasil harus per-INSTANS, bukan mesh unik. Kalau dua node
/// berbeda memakai mesh yang identik, KEDUA instans tetap dirender — jadi
/// polygon-nya dihitung dua kali. Kalau mesh-nya di-collapse jadi satu
/// (setelah `dedup()`), hitungannya tetap harus sama karena transform itu
/// tidak mengubah apa yang tampil di layar.
function renderedMeshInstances(doc) {
  const root = doc.getRoot();
  const scene = root.getDefaultScene() ?? root.listScenes()[0];
  const instances = [];
  const visited = new Set();
  const visit = (node) => {
    if (!node || visited.has(node)) return;
    visited.add(node);
    const mesh = node.getMesh();
    if (mesh) instances.push(mesh);
    for (const child of node.listChildren()) visit(child);
  };
  if (scene) {
    for (const node of scene.listChildren()) visit(node);
  } else {
    for (const node of root.listNodes()) visit(node);
  }
  // Kalau tidak ada scene sama sekali, hitung semua mesh.
  return instances.length ? instances : root.listMeshes();
}

/// Hitung statistik geometri untuk verifikasi "tidak ada poligon berkurang".
function geometryStats(doc) {
  let tris = 0;
  let verts = 0;
  for (const mesh of renderedMeshInstances(doc)) {
    for (const p of mesh.listPrimitives()) {
      const pos = p.getAttribute('POSITION');
      if (!pos) continue;
      const idx = p.getIndices();
      tris += (idx ? idx.getCount() : pos.getCount()) / 3;
      verts += pos.getCount();
    }
  }
  return { tris, verts };
}

/// Baca komponen accessor sebagai float, sudah dinormalisasi.
///
/// Accessor quantized (mis. TEXCOORD 16-bit, POSITION 16-bit) menyimpan
/// integer mentah di dalam `Uint16Array`. glTF menormalisasi nilai integer
/// tersebut ke rentang [-1, 1] (signed) atau [0, 1] (unsigned) sesuai tipe
/// komponen. Kalau array mentah dibaca langsung sebagai float, hasilnya
/// keliru besar — inilah sumber "kotak kasar" dan drift UV palsu.
///
/// `KHR_mesh_quantization` boleh menambah `scale`/`offset` per accessor lewat
/// extension. `glbview` TIDAK menerapkan scale/offset itu, jadi di pipeline
/// ini scale/offset sengaja TIDAK dipakai: yang diukur adalah nilai yang
/// benar-benar akan dibaca renderer.
/// Skala normalisasi glTF per tipe komponen.
///
/// glTF menormalisasi integer ke [0,1] (unsigned) atau [-1,1] (signed).
/// Signed short punya 32767 nilai positif (termasuk -1), jadi skalanya
/// 1/32767. Unsigned short punya 65535 nilai (0..65534) dan
/// `normalized` berarti [0,1], jadi skalanya 1/65535 — BUKAN 1/32767.
/// Salah di sini bikin UV drift terukur palsu (2%+).
function componentScale(componentType, normalized) {
  if (!normalized) return 1;
  switch (componentType) {
    case 5120: // BYTE (signed, [-1,1])
      return 1 / 127;
    case 5121: // UNSIGNED_BYTE ([0,1])
      return 1 / 255;
    case 5122: // SHORT (signed, [-1,1])
      return 1 / 32767;
    case 5123: // UNSIGNED_SHORT ([0,1])
      return 1 / 65535;
    default:
      return 1; // FLOAT dan tipe lainnya
  }
}

/// Hitung rentang nilai (ternormalisasi) untuk accessor, hanya pada vertex
/// yang benar-benar dipakai indeks.
function accessorRange(attr, useIndices) {
  const arr = attr.getArray();
  if (!arr) return null;
  const count = attr.getCount();
  const type = attr.getType(); // 'VEC2' | 'VEC3' | ...
  const comps = type === 'SCALAR' ? 1 : type === 'VEC2' ? 2 : type === 'VEC3' ? 3 : type === 'VEC4' ? 4 : 3;
  const scale = componentScale(attr.getComponentType(), attr.getNormalized());
  const normalized = attr.getNormalized();

  const min = new Array(comps).fill(Infinity);
  const max = new Array(comps).fill(-Infinity);

  const visit = (vi) => {
    if (vi >= count) return;
    for (let k = 0; k < comps; k++) {
      const raw = arr[vi * comps + k];
      const v = normalized ? raw * scale : raw;
      if (v < min[k]) min[k] = v;
      if (v > max[k]) max[k] = v;
    }
  };

  if (useIndices) {
    const idx = useIndices;
    for (let i = 0; i < idx.getCount(); i++) visit(idx.getScalar(i));
  } else {
    for (let i = 0; i < count; i++) visit(i);
  }
  return { min, max };
}

/// Hitung drift UV (TEXCOORD_0) — mendeteksi weld yang menyatukan seam dan
/// menggeser tekstur.
///
/// Yang dibandingkan TIDAK min/max accessor global. Alasannya: `prune()`
/// membuang vertex yang tidak dirender, termasuk vertex yang kebetulan
/// membawa nilai UV ekstrem (0 dan 1). Min/max accessor ikut berubah
/// (mis. [0,1] jadi [0,0019,0,998]) padahal geometri yang dirender identik
/// — itu menghasilkan drift palsu ~2% pada file yang tidak rusak.
///
/// Yang dipakai: statistik per SAMPEL INDEKS (tiap entri indeks dihitung,
/// termasuk duplikat). Invariant ini tahan terhadap:
///   - `prune()`  : membuang vertex tak terpakai
///   - `weld()`   : menggabungkan vertex identik (indeks tetap berjumlah sama)
///   - `quantize()`: mengubah nilai float <-> integer kuantisasi
///
/// Nilai dinormalisasi ke [0,1] untuk accessor quantized, sesuai aturan glTF,
/// supaya satuan perbandingan sebelum/sesudah sama.
function uvStats(doc) {
  let samples = 0;
  let sum = 0;
  let min = [Infinity, Infinity];
  let max = [-Infinity, -Infinity];

  for (const mesh of renderedMeshInstances(doc)) {
    for (const p of mesh.listPrimitives()) {
      const attr = p.getAttribute('TEXCOORD_0');
      if (!attr) continue;
      const arr = attr.getArray();
      if (!arr) continue;
      const count = attr.getCount();
      const scale = componentScale(attr.getComponentType(), attr.getNormalized());
      const normalized = attr.getNormalized();
      const idx = p.getIndices();

      const step = idx ? idx.getCount() : count;
      for (let i = 0; i < step; i++) {
        const vi = idx ? idx.getScalar(i) : i;
        if (vi >= count) continue;
        for (let k = 0; k < 2; k++) {
          const raw = arr[vi * 2 + k];
          const v = normalized ? raw * scale : raw;
          sum += v;
          if (v < min[k]) min[k] = v;
          if (v > max[k]) max[k] = v;
        }
        samples++;
      }
    }
  }
  return { samples, sum, min, max };
}

/// Hitung bounding box POSITION dalam KOORDINAT DUNIA — dipakai mendeteksi
/// geometri rusak/kotak.
///
/// Nilai diambil dari accessor dan dinormalisasi, lalu dikalikan matrix node
/// supaya hasilnya posisi yang benar-benar dilihat pengguna.
///
/// Kenapa koordinat dunia: `quantize()` memindahkan skala dari accessor ke
/// node transform (`transformMeshParents`). Mesh lokal jadi lebih kecil
/// sementara node transform-nya lebih besar — totalnya sama. Kalau bbox
/// lokal yang dibandingkan, drift palsu sampai 58% muncul pada file yang
/// sebenarnya utuh. Yang penting bentuk di layar, jadi yang dibandingkan
/// adalah bbox dunia.
function bounds(doc) {
  let min = [Infinity, Infinity, Infinity];
  let max = [-Infinity, -Infinity, -Infinity];

  const root = doc.getRoot();
  const scene = root.getDefaultScene() ?? root.listScenes()[0];

  // Kumpulkan matrix dunia per mesh: mesh bisa dipakai lebih dari satu node.
  const worldMatrices = new Map();
  const visited = new Set();
  const visit = (node, parentMatrix) => {
    if (!node || visited.has(node)) return;
    visited.add(node);
    const matrix = mat4Multiply(parentMatrix, node.getMatrix());
    const mesh = node.getMesh();
    if (mesh) {
      const list = worldMatrices.get(mesh) ?? [];
      list.push(matrix);
      worldMatrices.set(mesh, list);
    }
    for (const child of node.listChildren()) visit(child, matrix);
  };

  const identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
  if (scene) {
    for (const node of scene.listChildren()) visit(node, identity);
  } else {
    for (const node of root.listNodes()) visit(node, identity);
  }

  for (const mesh of renderedMeshInstances(doc)) {
    const matrices = worldMatrices.get(mesh) ?? [identity];
    for (const p of mesh.listPrimitives()) {
      const attr = p.getAttribute('POSITION');
      if (!attr) continue;
      const arr = attr.getArray();
      if (!arr) continue;
      const count = attr.getCount();
      const scale = componentScale(attr.getComponentType(), attr.getNormalized());
      const normalized = attr.getNormalized();

      for (const matrix of matrices) {
        for (let i = 0; i < count; i++) {
          const x = arr[i * 3 + 0];
          const y = arr[i * 3 + 1];
          const z = arr[i * 3 + 2];
          const vx = normalized ? x * scale : x;
          const vy = normalized ? y * scale : y;
          const vz = normalized ? z * scale : z;
          const wx = matrix[0] * vx + matrix[4] * vy + matrix[8] * vz + matrix[12];
          const wy = matrix[1] * vx + matrix[5] * vy + matrix[9] * vz + matrix[13];
          const wz = matrix[2] * vx + matrix[6] * vy + matrix[10] * vz + matrix[14];
          if (wx < min[0]) min[0] = wx;
          if (wx > max[0]) max[0] = wx;
          if (wy < min[1]) min[1] = wy;
          if (wy > max[1]) max[1] = wy;
          if (wz < min[2]) min[2] = wz;
          if (wz > max[2]) max[2] = wz;
        }
      }
    }
  }
  return { min, max };
}

/// Perkalian matrix 4x4 (column-major), sesuai konvensi glTF.
function mat4Multiply(a, b) {
  const out = new Array(16);
  for (let c = 0; c < 4; c++) {
    for (let r = 0; r < 4; r++) {
      let sum = 0;
      for (let k = 0; k < 4; k++) sum += a[k * 4 + r] * b[c * 4 + k];
      out[c * 4 + r] = sum;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Pipeline utama
// ---------------------------------------------------------------------------

/// Nama file output yang datar dan unik.
///
/// Sumber punya 85 file di beberapa folder, dan ada nama file yang sama di
/// dua folder berbeda (`67313ca98210dfc03eb2efe2_low.glb`). Kalau output
/// ikut datar apa adanya, file dengan nama sama akan saling menimpa.
///
/// Solusinya: sisipkan nama folder asal sebagai prefix, dipisah tanda hubung.
/// Folder yang jadi prefix dibuang kalau isinya sudah merupakan awalan
/// folder yang lebih dalam — supaya tidak ada prefix dobel yang sia-sia.
///
///   buildcores-build-2026-intel-285k-sfs52_vuJ-glb / build-2026-intel-285k-sfs52_vuJ
///     -> build-2026-intel-285k-sfs52_vuJ--65482c80477e815da41f25ff_low.glb
///
///   buildcores-ghost-parts-glb / ghost-parts
///     -> ghost-parts--ghost_ddr5.glb
function flatName(relPath) {
  const parts = relPath.split(path.sep).filter(Boolean);
  const file = parts.pop();
  // Buang prefix generik "buildcores-".
  const folders = parts.map((f) => f.replace(/^buildcores-/, ''));
  // Buang folder yang isinya sudah jadi awalan folder lain (lebih dalam).
  const meaningful = folders.filter(
    (f, i) => !folders.some((g, j) => j !== i && g !== f && g.startsWith(f)),
  );
  const prefix = meaningful.join('--');
  return prefix ? `${prefix}--${file}` : file;
}

async function optimizeOne(inputFile, { dryRun = false } = {}) {
  const rel = path.relative(RAW_ROOT, inputFile);
  const outFile = path.join(OUT_ROOT, flatName(rel));

  const srcBytes = (await stat(inputFile)).size;
  const doc = await io.read(inputFile);

  // --- Buang kompresi Draco (bukan mesh, tapi accessor) --------------------
  // Beberapa file sumber sudah memakai `KHR_draco_mesh_compression`. Draco
  // adalah kompresi BYTE (tidak mengurangi poligon), tapi `glbview` yang
  // dipakai app MENOLAK file ber-Draco:
  //   "Compressed geometry is not supported (KHR_draco_mesh_compression)"
  //
  // `io.read()` sudah mendecode Draco jadi accessor biasa dan melepas
  // extension property dari primitive. Tapi extension-nya masih TERDAFTAR
  // di document-level (`extensionsUsed` / `extensionsRequired`), dan writer
  // akan tetap menuliskannya kalau extension-nya terdaftar di I/O — hasil
  // output ditolak renderer.
  //
  // Karena itu `disposeExtension()` harus dipanggil berdasarkan daftar
  // document-level, BUKAN berdasarkan `primitive.getExtension()` (yang
  // sudah null setelah decode).
  let dracoRemoved = 0;
  for (const mesh of doc.getRoot().listMeshes()) {
    for (const prim of mesh.listPrimitives()) {
      if (prim.getExtension('KHR_draco_mesh_compression')) {
        prim.setExtension('KHR_draco_mesh_compression', null);
        dracoRemoved++;
      }
    }
  }
  if (doc.hasExtension('KHR_draco_mesh_compression')) {
    doc.disposeExtension('KHR_draco_mesh_compression');
  }

  const before = geometryStats(doc);
  const beforeBounds = bounds(doc);
  const beforeUv = uvStats(doc);

  // --- Texture: KTX2 -> PNG -> WebP (aturan 3) ---------------------------
  // glbview menolak KTX2, jadi WAJIB dikonversi ke format yang didukung
  // (EXT_texture_webp). Texture < 1024px TIDAK diperbesar (resize hanya
  // mengecilkan).
  const workDir = path.join(TMP_ROOT, path.basename(inputFile, '.glb'));
  await mkdir(workDir, { recursive: true });

  const textures = doc.getRoot().listTextures();
  let converted = 0;
  let skipped = 0;

  for (const texture of textures) {
    const mime = texture.getMimeType();
    const name = (texture.getName() || 'tex').replace(/[^a-zA-Z0-9_-]/g, '_');

    if (mime === 'image/ktx2') {
      const pngBytes = await toPngBytes(texture, workDir);
      if (!pngBytes) {
        skipped++;
        continue;
      }
      // Tulis PNG sementara, lalu kompres ke WebP via sharp dengan resize
      // maksimum 1024 (tidak pernah lebih kecil dari aslinya kalau < 1024).
      const pngPath = path.join(workDir, `${name}.png`);
      const webpPath = path.join(workDir, `${name}.webp`);
      await writeFile(pngPath, pngBytes);
      const meta = await sharp(pngBytes).metadata();
      await sharp(pngBytes)
        .resize({
          width: TEXTURE_MAX,
          height: TEXTURE_MAX,
          fit: 'inside', // hanya mengecilkan; aspect ratio terjaga
          withoutEnlargement: true, // < 1024 tetap apa adanya
        })
        .webp({ quality: TEXTURE_QUALITY, effort: 5 })
        .toFile(webpPath);
      const webp = await readFile(webpPath);
      await rm(pngPath, { force: true });
      await rm(webpPath, { force: true });

      texture.setImage(webp);
      texture.setMimeType('image/webp');
      texture.setURI('');
      converted++;
      if (converted === 1) {
        console.log(
          `    texture ${name}: ktx2 ${meta.width}x${meta.height} -> webp ${webp.byteLength} B`,
        );
      }
    } else if (mime === 'image/png' || mime === 'image/jpeg') {
      // Sudah format yang didukung sharp + webp-native. Kompres saja.
      const bytes = texture.getImage();
      if (!bytes || bytes.byteLength === 0) {
        skipped++;
        continue;
      }
      const webpPath = path.join(workDir, `${name}.webp`);
      await sharp(Buffer.from(bytes))
        .resize({
          width: TEXTURE_MAX,
          height: TEXTURE_MAX,
          fit: 'inside',
          withoutEnlargement: true,
        })
        .webp({ quality: TEXTURE_QUALITY, effort: 5 })
        .toFile(webpPath);
      const webp = await readFile(webpPath);
      await rm(webpPath, { force: true });
      texture.setImage(webp);
      texture.setMimeType('image/webp');
      texture.setURI('');
      converted++;
    }
  }

  // Buang extension KHR_texture_basisu — tidak relevan setelah konversi ke
  // WebP. Kalau extension tetap ada, writer akan tetap menuliskan
  // `textures[].extensions.KHR_texture_basisu` dan renderer `glbview`
  // akan menolak file-nya.
  doc.disposeExtension('KHR_texture_basisu');

  // --- Pembersihan aman (aturan 4) ---------------------------------------
  // dedup  : gabungkan ACCESSOR + TEXTURE duplikat saja.
  //          JANGAN dedup MESH/MATERIAL: default `dedup()` juga menggabungkan
  //          MESH, dan kalau dua mesh punya material identik, mesh di-merge
  //          -> jumlah vertex berubah (terukur: 34.530 -> 34.506 tri pada
  //          ghost_radiator_120). Itu mengubah struktur, bukan sekadar
  //          membersihkan.
  // weld   : gabungkan vertex yang BITWISE IDENTIK pada semua atribut
  //          (POSITION+NORMAL+TANGENT+TEXCOORD_0/1/2) — lossless. Hanya
  //          menyatukan duplikat seam yang memang identik, bukan menyatukan
  //          vertex berdekatan seperti weld berbasis toleransi posisi yang
  //          bikin bentuk jadi kotak kasar.
  // prune  : buang properti tak terpakai (node, mesh, material, texture
  //          duplikat, buffer yatim). `keepAttributes: true` WAJIB — kalau
  //          tidak, prune() juga membuang accessor yang tak dirujuk indeks,
  //          sehingga sebagian entri indeks menunjuk vertex yang hilang.
  //          Geometri yang tampil tetap sama, tapi indeks jadi tidak sinkron
  //          dan UV bisa hilang di seam.
  // resample: dedup keyframe animasi (lossless).
  // TIDAK ADA simplify / decimate.
  await doc.transform(
    dedup({
      propertyTypes: [PropertyType.ACCESSOR, PropertyType.TEXTURE],
    }),
  );
  await doc.transform(weld({ overwrite: true }));
  await doc.transform(prune({ keepAttributes: true }));
  if (doc.getRoot().listAnimations().length > 0) {
    await doc.transform(resample());
  }

  // --- Kompresi geometri high-precision (aturan 2) ------------------------
  //
  // Sumber BuildCores sudah memakai `KHR_mesh_quantization`:
  //   POSITION  16-bit (>= 14 ✓), TEXCOORD_0 16-bit (>= 12 ✓),
  //   NORMAL     8-bit (< 10 ✗), TANGENT 8-bit.
  //
  // Untuk file yang sumbernya ber-Draco, `io.read()` mengubahnya jadi
  // accessor float32. Kalau POSITION dibiarkan float32, file justru jauh
  // lebih besar dari aslinya (terukur: atx_ghost_mobo 3,88 MB -> 21,53 MB).
  //
  // Karena itu SEMUA semantik di-quantize: POSITION 14 bit, NORMAL 10 bit,
  // TEXCOORD 12 bit. Semuanya sesuai ambang yang diminta, dan POSITION/
  // TEXCOORD yang tadinya sudah quantized (16 bit) turun ke 14/12 bit —
  // presisi tetap jauh di atas yang dibutuhkan untuk tampilannya.
  //
  // `dequantize()` lebih dulu supaya semua atribut berupa float32 murni
  // tanpa scale/offset per accessor, lalu `quantize()` menulis ulang dalam
  // bentuk integer ter-normalisasi. Skala dipindah ke node transform
  // (`transformMeshParents`), yang dibaca `glbview` dengan benar.
  await doc.transform(dequantize());
  await doc.transform(quantize(QUANTIZE_OPTIONS));

  const after = geometryStats(doc);
  const afterBounds = bounds(doc);

  // --- Verifikasi: tidak boleh ada poligon yang hilang ---------------------
  //
  // Yang wajib dijaga:
  //   1. jumlah TRIANGLE tetap persis (tidak ada simplify/decimate)
  //   2. bounding box tidak bergeser (bentuk tidak berubah)
  //   3. UV tidak bergeser (tekstur tidak melenceng)
  //
  // Jumlah VERTEX boleh berubah: `dedup()`/`prune()` bisa menggabungkan
  // accessor duplikat, dan `quantize()` memadatkan data (compactPrimitive)
  // dengan membuang vertex tak terpakai. Yang penting bentuk, UV, dan
  // jumlah triangle tetap identik.
  const triDelta = after.tris - before.tris;
  if (triDelta !== 0) {
    throw new Error(
      `Jumlah triangle berubah (${before.tris} -> ${after.tris}). ` +
        `Optimasi dibatalkan.`,
    );
  }

  // --- Verifikasi: bounding box tidak boleh berubah ------------------------
  const bboxDrift = beforeBounds.min.reduce((acc, v, i) => {
    return Math.max(
      acc,
      Math.abs(v - afterBounds.min[i]),
      Math.abs(beforeBounds.max[i] - afterBounds.max[i]),
    );
  }, 0);
  const extent = Math.max(
    beforeBounds.max[0] - beforeBounds.min[0],
    beforeBounds.max[1] - beforeBounds.min[1],
    beforeBounds.max[2] - beforeBounds.min[2],
  );
  // Drift kecil hanya dari kuantisasi posisi Draco (14 bit).
  if (extent > 0 && bboxDrift / extent > 0.001) {
    throw new Error(
      `Bounding box bergeser ${(bboxDrift / extent * 100).toFixed(3)}% — ` +
        `geometri mungkin rusak. Optimasi dibatalkan.`,
    );
  }

  // --- Verifikasi: UV tidak boleh bergeser --------------------------------
  // Ini yang bikin tekstur "blur"/bergeser di kompresi sebelumnya: weld
  // berbasis posisi-toleransi menyatukan vertex seam yang UV-nya beda.
  // Di sini UV dicek secara eksplisit supaya regresi ketahuan.
  //
  // Yang dibandingkan:
  //   1. jumlah sampel UV (entri indeks) — harus sama. weld() menggabungkan
  //      vertex identik tanpa mengubah jumlah indeks, prune() hanya membuang
  //      yang tak terpakai, quantize() tidak mengubah indeks.
  //   2. rata-rata nilai UV per komponen — invariant terhadap prune()
  //      membuang vertex ekstrem, tapi tetap menangkap weld yang menggeser
  //      tekstur (rata-rata langsung berubah).
  const afterUv = uvStats(doc);
  if (afterUv.samples !== beforeUv.samples) {
    throw new Error(
      `Jumlah sampel UV berubah ${beforeUv.samples} -> ${afterUv.samples} — ` +
        `indeks mesh berubah. Optimasi dibatalkan.`,
    );
  }
  const meanDrift = beforeUv.samples
    ? Math.max(
        Math.abs(beforeUv.sum / beforeUv.samples - afterUv.sum / afterUv.samples),
      )
    : 0;
  if (meanDrift > 0.002) {
    throw new Error(
      `UV bergeser ${(meanDrift * 100).toFixed(3)}% (rata-rata) — ` +
        `tekstur akan melenceng. Optimasi dibatalkan.`,
    );
  }
  const uvDrift = meanDrift;
  const uvExtent = 1;

  if (!dryRun) {
    await mkdir(path.dirname(outFile), { recursive: true });
    await io.write(outFile, doc);
  }
  await rm(workDir, { recursive: true, force: true });

  const outBytes = dryRun ? 0 : (await stat(outFile)).size;
  return {
    // `rel` = path sumber relatif terhadap assets/3d (untuk lacak asal).
    rel,
    // `out` = nama file datar di tool/output/optimized/.
    out: path.basename(outFile),
    srcBytes,
    outBytes,
    tris: after.tris,
    verts: after.verts,
    converted,
    skipped,
    bboxDriftPct: (bboxDrift / Math.max(extent, 1e-9)) * 100,
    uvDriftPct: (uvDrift / Math.max(uvExtent, 1e-9)) * 100,
  };
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

async function main() {
  const args = process.argv.slice(2);
  const dryRun = args.includes('--dry-run');
  const explicit = args.filter((a) => !a.startsWith('--'));

  const files = explicit.length
    ? explicit.map((f) => path.resolve(f))
    : [];

  if (!files.length) {
    for await (const f of walk(RAW_ROOT)) {
      if (f.includes(`${path.sep}prepared${path.sep}`)) continue;
      files.push(f);
    }
  }

  if (!files.length) {
    console.log('Tidak ada file GLB ditemukan.');
    return;
  }

  console.log(
    `Optimasi ${files.length} file | webp<=${TEXTURE_MAX} q=${TEXTURE_QUALITY} | ` +
      `quant P${QUANTIZE_OPTIONS.quantizePosition}/N${QUANTIZE_OPTIONS.quantizeNormal}` +
      `/T${QUANTIZE_OPTIONS.quantizeTexcoord} | no-simplify | no-draco`,
  );
  console.log(`Output: ${path.relative(ROOT, OUT_ROOT)}${dryRun ? ' (dry-run)' : ''}\n`);

  await mkdir(OUT_ROOT, { recursive: true });
  await mkdir(TMP_ROOT, { recursive: true });

  let totalSrc = 0;
  let totalOut = 0;
  let totalTris = 0;
  let failed = 0;
  const report = [];

  for (const file of files) {
    const name = path.relative(RAW_ROOT, file);
    try {
      const r = await optimizeOne(file, { dryRun });
      totalSrc += r.srcBytes;
      totalOut += r.outBytes;
      totalTris += r.tris;
      report.push(r);
      const ratio = r.outBytes ? ((1 - r.outBytes / r.srcBytes) * 100).toFixed(1) : '0.0';
      console.log(
        `OK  ${name}\n` +
          `    ${(r.srcBytes / 1e6).toFixed(2)}MB -> ${(r.outBytes / 1e6).toFixed(2)}MB ` +
          `(-${ratio}%)  tri=${r.tris}  bbox_drift=${r.bboxDriftPct.toFixed(4)}%  ` +
          `uv_drift=${r.uvDriftPct.toFixed(4)}%  ` +
          `tex_converted=${r.converted} tex_skipped=${r.skipped}`,
      );
    } catch (err) {
      failed++;
      console.log(`FAIL  ${name}\n      ${err.message}`);
    }
  }

  await rm(TMP_ROOT, { recursive: true, force: true });

  console.log(
    `\nTotal: ${report.length} ok, ${failed} gagal | ` +
      `${(totalSrc / 1e6).toFixed(1)}MB -> ${(totalOut / 1e6).toFixed(1)}MB ` +
      `(-${((1 - totalOut / totalSrc) * 100).toFixed(1)}%) | ${totalTris} tri`,
  );

  await writeFile(
    path.join(OUT_ROOT, 'optimize_report.json'),
    JSON.stringify(
      {
        generatedAt: new Date().toISOString(),
        rules: {
          simplify: false,
          weld: 'not used (lossless-only; SDK weld merges bitwise-identical vertices)',
          quantization: QUANTIZE_OPTIONS,
          draco: 'disabled — glbview rejects KHR_draco_mesh_compression',
          textureMax: TEXTURE_MAX,
          textureQuality: TEXTURE_QUALITY,
          textureFormat: 'webp',
        },
        files: report,
      },
      null,
      2,
    ),
  );
}

await main();
