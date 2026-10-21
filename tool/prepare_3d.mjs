// Offline 3D asset pipeline for WorthBang.
//
// The runtime viewer (glbview) parses GLB in Dart and rejects Draco-compressed
// geometry, so shipped assets must be Draco-free and inside a triangle budget.
// This script turns the raw BuildCores GLBs into a compact custom part format
// that the Dart side can merge at runtime without a GLB parser:
//
//   assets/3d/prepared/<id>.wglb   'WGLB' header + f32 positions/normals + u32 indices
//   assets/3d/prepared/catalog.json  role -> variants, names, colours
//
// Notes on why the pipeline looks the way it does:
//  - gltf-transform's weld() merges vertices per attribute set, so seam
//    vertices that share a position but differ in NORMAL survive and block
//    the simplifier (it collapses 176k tris to only 158k). Welding by exact
//    position instead takes the same mesh to 10k tris.
//  - Normals are recomputed here from the welded mesh, so they are correct
//    for the merged surface.
//
// Run: node tool/prepare_3d.mjs
import { readFile, writeFile, mkdir, readdir, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { dedup, dequantize } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import draco3d from 'draco3dgltf';

await MeshoptSimplifier.ready;

const ROOT = path.resolve(import.meta.dirname, '..');
const RAW_ROOT = path.join(ROOT, 'assets', '3d');
const OUT = path.join(ROOT, 'assets', '3d', 'prepared');

const SETS = [
  { id: 'tron', dir: 'buildcores-build-tron-pc-reNa0UbbC-glb' },
  { id: 'msi', dir: 'buildcores-build-msi-meg-golden-dragon-glb' },
  { id: 'white', dir: 'buildcores-build-white-tear-ran-down-my-leg-ahh-build-bOq5BJCQk-glb' },
  { id: 'piets', dir: 'buildcores-build-piets-pc-9J3EfSt9Y-glb' },
  { id: 'firstpc', dir: 'buildcores-build-first-pc-oSA2Nlo7e-glb' },
  // 'intel285k' SENGAJA tidak dipakai: build-nya tidak punya
  // Motherboard/PSU/CPUCooler (cuma case+GPU+RAM+fan + setup meja),
  // jadi sebagai set PC ia tidak lengkap.
];

// KEPUTUSAN PRODUK (Dan, 2026-10-21): aset dipakai sebagai SATU SET PC
// utuh per build BuildCores. Yang diacak di app = set-nya, bukan part.
// Model 3D murni hiasan — TIDAK mewakili komponen hasil acakan build.
// Konsekuensinya: part-part satu set TIDAK dipindah/dirotasi sendiri-
// sendiri; mereka sudah saling pas di frame dunia build asalnya. Seluruh
// set hanya diberi SATU transform bersama (pusat bbox -> origin, skala
// seragam) supaya relatifnya persis seperti build aslinya.

// README category -> gaya tampilan: role (nama material), warna flat
// Monex, dan budget triangle per file part.
const CATEGORY_STYLE = {
  Motherboard: { role: 'mobo', color: '#2E3440', budget: 6000 },
  GPU: { role: 'gpu', color: '#4B5563', budget: 6000 },
  RAM: { role: 'ram', color: '#5C4033', budget: 2000 },
  PSU: { role: 'psu', color: '#1F2937', budget: 2500 },
  CPUCooler: { role: 'cpu', color: '#374151', budget: 3500 },
  // Case kaca lengkung (MAESTRO 900R): simplify error tinggi membuat
  // chord panjang melintasi lengkungan = segitiga duri. Budget besar +
  // error dikunci rendah khusus case.
  PCCase: { role: 'case', color: '#202634', budget: 14000, maxErr: 0.08 },
  CaseFan: { role: 'fan', color: '#3F3F46', budget: 1200 },
};
// Sisi terpanjang satu set utuh dinormalkan ke ukuran ini (mm).
const SET_SIZE_MM = 440;

const io = new NodeIO()
  .registerExtensions(ALL_EXTENSIONS)
  .registerDependencies({
    'draco3d.decoder': await draco3d.createDecoderModule(),
    'draco3d.encoder': await draco3d.createEncoderModule(),
  });

/// "- file.glb | Category | Name" rows from a set's README.txt, plus
/// the build's display name from the README header ("# Tron PC — ...").
async function readManifest(setDir) {
  const rows = [];
  let setName = null;
  for (const entry of await readdir(setDir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const readme = path.join(setDir, entry.name, 'README.txt');
    if (!existsSync(readme)) continue;
    const text = await readFile(readme, 'utf-8');
    for (const line of text.split(/\r?\n/)) {
      if (!setName && line.startsWith('#')) {
        // Dua format header BuildCores:
        // "# Tron PC — share ..." dan "# BuildCores — GLB build 'MSI MEG ...'".
        const quoted = line.match(/'([^']+)'/);
        const plain = line.match(/^#\s*(.+?)\s*(?:—|--|\()/);
        if (quoted) setName = quoted[1].trim();
        else if (plain) setName = plain[1].trim();
      }
      const m = line.match(/^-\s*(\S+\.glb)\s*\|\s*([^|]+)\|(.*)$/);
      if (m) {
        // Field ketiga bisa punya ekor "| tri_count=162429" — buang agar
        // nama produk tetap bersih.
        const name = m[3].split('|')[0].trim();
        if (!name) continue;
        rows.push({
          file: m[1],
          category: m[2].trim(),
          name,
          path: path.join(path.dirname(readme), m[1]),
        });
      }
    }
  }
  return { setName, rows };
}

/// Merges vertices that share an exact position, dropping degenerates.
function weldByPosition(positions, indices) {
  const map = new Map();
  const remap = new Uint32Array(positions.length / 3);
  const out = [];
  for (let v = 0; v < positions.length / 3; v++) {
    const key = `${positions[v * 3]},${positions[v * 3 + 1]},${positions[v * 3 + 2]}`;
    let id = map.get(key);
    if (id === undefined) {
      id = out.length / 3;
      map.set(key, id);
      out.push(positions[v * 3], positions[v * 3 + 1], positions[v * 3 + 2]);
    }
    remap[v] = id;
  }
  const tris = [];
  for (let t = 0; t < indices.length; t += 3) {
    const a = remap[indices[t]], b = remap[indices[t + 1]], c = remap[indices[t + 2]];
    if (a !== b && b !== c && a !== c) tris.push(a, b, c);
  }
  return { positions: new Float32Array(out), indices: new Uint32Array(tris) };
}

/// Decodes and welds one source GLB into flat arrays.
///
/// Node world transforms WAJIB diterapkan: GLB BuildCores menaruh
/// geometri di matriks node (case NV5: 31/32 node ber-transform).
/// Membaca POSITION mentah tanpa transform membuat semua panel
/// menumpuk dalam kubus 2x2x2 di origin (render jadi slab rusak).
async function loadGeometry(file) {
  let d = await io.read(file);
  d = await d.transform(dedup(), dequantize());
  d = await d.transform((doc) => {
    for (const mesh of doc.getRoot().listMeshes()) {
      for (const prim of mesh.listPrimitives()) {
        prim.setAttribute('NORMAL', null);
        prim.setAttribute('TEXCOORD_0', null);
        prim.setAttribute('COLOR_0', null);
      }
    }
  });

  const positions = [];
  const indices = [];
  let base = 0;
  const visit = (node, parent) => {
    const local = node.getMatrix();
    const world = new Array(16);
    for (let r = 0; r < 4; r++) {
      for (let c = 0; c < 4; c++) {
        world[c * 4 + r] =
          parent[r] * local[c * 4] +
          parent[4 + r] * local[c * 4 + 1] +
          parent[8 + r] * local[c * 4 + 2] +
          parent[12 + r] * local[c * 4 + 3];
      }
    }
    const mesh = node.getMesh();
    if (mesh) {
      for (const prim of mesh.listPrimitives()) {
        const pos = prim.getAttribute('POSITION');
        if (!pos) continue;
        const arr = pos.getArray();
        for (let i = 0; i < arr.length; i += 3) {
          const x = arr[i], y = arr[i + 1], z = arr[i + 2];
          positions.push(
            world[0] * x + world[4] * y + world[8] * z + world[12],
            world[1] * x + world[5] * y + world[9] * z + world[13],
            world[2] * x + world[6] * y + world[10] * z + world[14],
          );
        }
        const count = pos.getCount();
        const idx = prim.getIndices();
        if (idx) {
          const ia = idx.getArray();
          for (let i = 0; i < ia.length; i++) indices.push(ia[i] + base);
        } else {
          for (let i = 0; i < count; i++) indices.push(i + base);
        }
        base += count;
      }
    }
    for (const child of node.listChildren()) visit(child, world);
  };
  const identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
  for (const scene of d.getRoot().listScenes()) {
    for (const child of scene.listChildren()) visit(child, identity);
  }
  return weldByPosition(new Float32Array(positions), new Uint32Array(indices));
}

/// Drops vertices no triangle references and renumbers the indices.
function compact(positions, indices) {
  const referenced = new Uint8Array(positions.length / 3);
  for (let i = 0; i < indices.length; i++) referenced[indices[i]] = 1;
  const out = [];
  const remap = new Int32Array(positions.length / 3).fill(-1);
  for (let v = 0; v < referenced.length; v++) {
    if (!referenced[v]) continue;
    remap[v] = out.length / 3;
    out.push(positions[v * 3], positions[v * 3 + 1], positions[v * 3 + 2]);
  }
  const idx = new Uint32Array(indices.length);
  for (let i = 0; i < indices.length; i++) idx[i] = remap[indices[i]];
  return { positions: new Float32Array(out), indices: idx };
}

/// Buang komponen terhubung (shell) yang diagonal bbox-nya di bawah
/// [minDiag] meter (satuan mentah GLB). Motherboard dsb. terdiri dari
/// ratusan shell kecil (sekrup, kapasitor) yang masing-masing punya
/// lantai topologi — simplifier tidak bisa menembusnya, total tri
/// mentok puluhan ribu. Pada skala panggung 440mm shell < 12mm tidak
/// terlihat, jadi buang saja sebelum simplify.
function dropSmallComponents(positions, indices, minDiag = 0.012) {
  const parent = new Int32Array(positions.length / 3);
  for (let i = 0; i < parent.length; i++) parent[i] = i;
  const find = (x) => {
    while (parent[x] !== x) { parent[x] = parent[parent[x]]; x = parent[x]; }
    return x;
  };
  for (let t = 0; t < indices.length; t += 3) {
    const a = find(indices[t]);
    const b = find(indices[t + 1]);
    const c = find(indices[t + 2]);
    if (a !== b) parent[a] = b;
    if (b !== c) parent[b] = c;
  }
  const compMin = new Map(), compMax = new Map();
  for (let v = 0; v < parent.length; v++) {
    const r = find(v);
    if (!compMin.has(r)) {
      compMin.set(r, [Infinity, Infinity, Infinity]);
      compMax.set(r, [-Infinity, -Infinity, -Infinity]);
    }
    const mn = compMin.get(r), mx = compMax.get(r);
    for (let c = 0; c < 3; c++) {
      const val = positions[v * 3 + c];
      if (val < mn[c]) mn[c] = val;
      if (val > mx[c]) mx[c] = val;
    }
  }
  const keep = new Set();
  for (const [r, mn] of compMin) {
    const mx = compMax.get(r);
    const diag = Math.hypot(mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2]);
    if (diag >= minDiag) keep.add(r);
  }
  const out = [];
  for (let t = 0; t < indices.length; t += 3) {
    if (keep.has(find(indices[t]))) out.push(indices[t], indices[t + 1], indices[t + 2]);
  }
  return new Uint32Array(out);
}

/// Area-weighted vertex normals from the welded mesh.
function computeNormals(positions, indices) {
  const normals = new Float32Array(positions.length);
  for (let t = 0; t < indices.length; t += 3) {
    const a = indices[t] * 3, b = indices[t + 1] * 3, c = indices[t + 2] * 3;
    const ux = positions[b] - positions[a], uy = positions[b + 1] - positions[a + 1], uz = positions[b + 2] - positions[a + 2];
    const vx = positions[c] - positions[a], vy = positions[c + 1] - positions[a + 1], vz = positions[c + 2] - positions[a + 2];
    const nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    for (const o of [a, b, c]) {
      normals[o] += nx;
      normals[o + 1] += ny;
      normals[o + 2] += nz;
    }
  }
  for (let i = 0; i < normals.length; i += 3) {
    const len = Math.hypot(normals[i], normals[i + 1], normals[i + 2]);
    if (len > 1e-8) {
      normals[i] /= len; normals[i + 1] /= len; normals[i + 2] /= len;
    } else {
      normals[i + 1] = 1;
    }
  }
  return normals;
}

/// Satu transform bersama untuk SELURUH set: geser pusat bbox set ke
/// origin dan skala seragam (sisi terpanjang -> SET_SIZE_MM). Relatif
/// antar-part tidak berubah sama sekali — tidak ada rotasi, tidak ada
/// permutasi sumbu, tidak ada slot per part.
function setTransform(geos) {
  const min = [Infinity, Infinity, Infinity];
  const max = [-Infinity, -Infinity, -Infinity];
  for (const g of geos) {
    for (let i = 0; i < g.positions.length; i += 3) {
      for (let c = 0; c < 3; c++) {
        const v = g.positions[i + c];
        if (v < min[c]) min[c] = v;
        if (v > max[c]) max[c] = v;
      }
    }
  }
  const size = [max[0] - min[0], max[1] - min[1], max[2] - min[2]];
  const scale = SET_SIZE_MM / Math.max(size[0], size[1], size[2]);
  const centre = [0, 1, 2].map((c) => (min[c] + max[c]) / 2);
  return { centre, scale };
}

function applyTransform(positions, centre, scale) {
  const out = new Float32Array(positions.length);
  for (let i = 0; i < positions.length; i += 3) {
    for (let c = 0; c < 3; c++) {
      out[i + c] = (positions[i + c] - centre[c]) * scale;
    }
  }
  return out;
}

/// Simplify adaptif: longgarkan error bertahap dari geometri asli
/// sampai budget tercapai atau error menyentuh [maxErr]. Mesh tertentu
/// (kaca lengkung case) rusak bentuknya di error tinggi — untuk itu
/// maxErr dikunci rendah dan sisa tri di atas budget diterima.
function simplifyTo(geo, budget, maxErr = 0.5) {
  if (geo.indices.length / 3 <= budget) return geo.indices;
  const target = budget * 3;
  let err = 0.02;
  let dst = geo.indices;
  while (err <= maxErr) {
    [dst] = MeshoptSimplifier.simplify(
      geo.indices, geo.positions, 3, target, err, [],
    );
    if (dst.length / 3 <= budget * 1.05) break;
    err *= 2.5;
  }
  return dst;
}

/// 'WGLB' | version | vertexCount | indexCount | positions | normals | indices
function packPart(part) {
  const header = new ArrayBuffer(16);
  const dv = new DataView(header);
  dv.setUint8(0, 0x57); // W
  dv.setUint8(1, 0x47); // G
  dv.setUint8(2, 0x4c); // L
  dv.setUint8(3, 0x42); // B
  dv.setUint32(4, 1, true);
  dv.setUint32(8, part.positions.length / 3, true);
  dv.setUint32(12, part.indices.length, true);
  const bytes = new Uint8Array(
    16 + part.positions.byteLength + part.normals.byteLength + part.indices.byteLength,
  );
  bytes.set(new Uint8Array(header), 0);
  let off = 16;
  bytes.set(new Uint8Array(part.positions.buffer), off);
  off += part.positions.byteLength;
  bytes.set(new Uint8Array(part.normals.buffer), off);
  off += part.normals.byteLength;
  bytes.set(new Uint8Array(part.indices.buffer), off);
  return bytes;
}

async function main() {
  await mkdir(OUT, { recursive: true });
  // Bersihkan output lama: nama file v2 berbeda (per set).
  for (const f of await readdir(OUT)) {
    if (f.endsWith('.wglb')) await rm(path.join(OUT, f));
  }

  const catalog = { version: 2, sets: [] };

  for (const set of SETS) {
    const setDir = path.join(RAW_ROOT, set.dir);
    if (!existsSync(setDir)) continue;
    const { setName, rows } = await readManifest(setDir);
    if (!rows.length) continue;

    // Proses semua part set ini di frame dunia build asalnya.
    const parts = [];
    for (const row of rows) {
      if (!existsSync(row.path)) continue;
      // Whitelist kategori komponen PC internal saja. Build BuildCores
      // bisa berisi setup meja utuh (Chair, Desk, Monitor, Keyboard,
      // Speaker, ...) — itu bukan bagian PC dan frame dunianya skala
      // ruangan, jadi selalu dibuang.
      const style = CATEGORY_STYLE[row.category];
      if (!style) {
        console.log(`skip kategori ${row.category}: ${row.name.slice(0, 40)}`);
        continue;
      }
      let geo = await loadGeometry(row.path);
      if (!geo.positions.length) continue;
      geo.indices = dropSmallComponents(geo.positions, geo.indices);
      if (!geo.indices.length) continue;
      geo.indices = simplifyTo(geo, style.budget, style.maxErr);
      const packed0 = compact(geo.positions, geo.indices);
      geo = { positions: packed0.positions, indices: packed0.indices };
      parts.push({
        row,
        style,
        positions: geo.positions,
        indices: geo.indices,
        normals: computeNormals(geo.positions, geo.indices),
      });
    }
    if (!parts.length) continue;

    // SATU transform bersama untuk seluruh set.
    const { centre, scale } = setTransform(parts);
    const outParts = [];
    for (let i = 0; i < parts.length; i++) {
      const p = parts[i];
      const id = `${set.id}_${i}`;
      const packed = packPart({
        positions: applyTransform(p.positions, centre, scale),
        normals: p.normals,
        indices: p.indices,
      });
      await writeFile(path.join(OUT, `${id}.wglb`), packed);
      outParts.push({
        id,
        role: p.style.role,
        name: p.row.name,
        category: p.row.category,
        file: `assets/3d/prepared/${id}.wglb`,
        bytes: packed.byteLength,
        tris: p.indices.length / 3,
        verts: p.positions.length / 3,
        color: p.style.color,
      });
      console.log(
        `${id.padEnd(12)} ${String(p.indices.length / 3).padStart(6)} tris ` +
          `${String(packed.byteLength).padStart(7)} B  ${p.row.name.slice(0, 42)}`,
      );
    }
    catalog.sets.push({
      id: set.id,
      name: setName ?? set.id,
      parts: outParts,
    });
  }

  await writeFile(path.join(OUT, 'catalog.json'), JSON.stringify(catalog, null, 2));
  const all = catalog.sets.flatMap((s) => s.parts);
  console.log(
    `sets: ${catalog.sets.length}, parts: ${all.length}, ` +
      `total: ${all.reduce((s, p) => s + p.tris, 0)} tris, ` +
      `${(all.reduce((s, p) => s + p.bytes, 0) / 1e6).toFixed(2)} MB`,
  );
}

await main();
