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
import { readFile, writeFile, mkdir, readdir } from 'node:fs/promises';
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
  { id: 'intel285k', dir: 'buildcores-build-2026-intel-285k-sfs52_vuJ-glb' },
];

// README category -> role used by the app.
const CATEGORY_ROLE = {
  Motherboard: 'mobo',
  GPU: 'gpu',
  RAM: 'ram',
  PSU: 'psu',
  CPUCooler: 'cpu',
  PCCase: 'case',
  CaseFan: 'fan',
};

// Variants per role, triangle budget, longest-edge size in millimetres, the
// part's slot in the assembled scene, and its Monex-tinted base colour.
const ROLES = {
  mobo: { count: 3, budget: 6000, sizeMm: 300, slot: [0, 0, 0], color: '#2E3440' },
  gpu: { count: 3, budget: 6000, sizeMm: 270, slot: [-10, 96, 62], color: '#4B5563' },
  ram: { count: 2, budget: 1500, sizeMm: 130, slot: [96, 34, -46], color: '#5C4033' },
  cpu: { count: 2, budget: 3000, sizeMm: 110, slot: [-22, 42, -22], color: '#374151' },
  psu: { count: 2, budget: 2200, sizeMm: 150, slot: [172, 44, 92], color: '#1F2937' },
  fan: { count: 2, budget: 900, sizeMm: 120, slot: [-124, 66, 26], color: '#3F3F46' },
  case: { count: 2, budget: 3500, sizeMm: 440, slot: [0, 0, 0], color: '#202634' },
};

const io = new NodeIO()
  .registerExtensions(ALL_EXTENSIONS)
  .registerDependencies({
    'draco3d.decoder': await draco3d.createDecoderModule(),
    'draco3d.encoder': await draco3d.createEncoderModule(),
  });

/// "- file.glb | Category | Name" rows from a set's README.txt.
async function readManifest(setDir) {
  const rows = [];
  for (const entry of await readdir(setDir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const readme = path.join(setDir, entry.name, 'README.txt');
    if (!existsSync(readme)) continue;
    const text = await readFile(readme, 'utf-8');
    for (const line of text.split(/\r?\n/)) {
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
  return rows;
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
  for (const mesh of d.getRoot().listMeshes()) {
    for (const prim of mesh.listPrimitives()) {
      const pos = prim.getAttribute('POSITION');
      if (!pos) continue;
      const arr = pos.getArray();
      for (let i = 0; i < arr.length; i++) positions.push(arr[i]);
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

/// Rotates so the thinnest axis points up, scales the longest edge to sizeMm
/// and moves the part into its slot.
function placePart(positions, normals, sizeMm, slot) {
  const min = [Infinity, Infinity, Infinity];
  const max = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < positions.length; i += 3) {
    for (let c = 0; c < 3; c++) {
      const v = positions[i + c];
      if (v < min[c]) min[c] = v;
      if (v > max[c]) max[c] = v;
    }
  }
  const size = [max[0] - min[0], max[1] - min[1], max[2] - min[2]];
  let thin = 0;
  if (size[1] < size[thin]) thin = 1;
  if (size[2] < size[thin]) thin = 2;
  const rest = [0, 1, 2].filter((c) => c !== thin);
  const scale = sizeMm / Math.max(size[rest[0]], size[rest[1]]);
  const map = [rest[0], thin, rest[1]];
  const centre = [0, 1, 2].map((c) => (min[c] + max[c]) / 2);

  const out = new Float32Array(positions.length);
  const outN = new Float32Array(normals.length);
  for (let i = 0; i < positions.length; i += 3) {
    const rel = [
      positions[i] - centre[0],
      positions[i + 1] - centre[1],
      positions[i + 2] - centre[2],
    ];
    for (let c = 0; c < 3; c++) {
      out[i + c] = rel[map[c]] * scale + slot[c];
      outN[i + c] = normals[i + map[c]];
    }
  }
  return { positions: out, normals: outN };
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

  const candidates = new Map();
  for (const set of SETS) {
    const setDir = path.join(RAW_ROOT, set.dir);
    if (!existsSync(setDir)) continue;
    for (const row of await readManifest(setDir)) {
      const role = CATEGORY_ROLE[row.category];
      if (!role || !ROLES[role]) continue;
      if (!existsSync(row.path)) continue;
      if (!candidates.has(role)) candidates.set(role, []);
      candidates.get(role).push({ ...row, set: set.id });
    }
  }

  const catalog = { version: 1, roles: {} };

  for (const [role, cfg] of Object.entries(ROLES)) {
    const pool = candidates.get(role) ?? [];
    if (!pool.length) {
      console.warn('no candidates for role', role);
      continue;
    }
    pool.sort((a, b) => a.file.length - b.file.length);
    const variants = [];
    for (const cand of pool) {
      if (variants.length >= cfg.count) break;
      const geo = await loadGeometry(cand.path);
      if (!geo.positions.length) continue;
      if (geo.indices.length / 3 > cfg.budget) {
        const ratio = cfg.budget / (geo.indices.length / 3);
        const target = Math.floor(geo.indices.length / 3 * ratio) * 3;
        const [dst] = MeshoptSimplifier.simplify(
          geo.indices, geo.positions, 3, target, 0.02, [],
        );
        geo.indices = dst;
      }
      const packed0 = compact(geo.positions, geo.indices);
      geo.positions = packed0.positions;
      geo.indices = packed0.indices;
      const normals = computeNormals(geo.positions, geo.indices);
      const placed = placePart(geo.positions, normals, cfg.sizeMm, cfg.slot);
      const packed = packPart({
        positions: placed.positions,
        normals: placed.normals,
        indices: geo.indices,
      });
      const id = `${role}_${variants.length}`;
      await writeFile(path.join(OUT, `${id}.wglb`), packed);
      variants.push({
        id,
        role,
        set: cand.set,
        name: cand.name,
        category: cand.category,
        file: `assets/3d/prepared/${id}.wglb`,
        bytes: packed.byteLength,
        tris: geo.indices.length / 3,
        verts: geo.positions.length / 3,
        color: cfg.color,
      });
      console.log(
        `${id.padEnd(8)} ${String(geo.indices.length / 3).padStart(6)} tris ` +
          `${String(geo.positions.length / 3).padStart(6)} verts ` +
          `${String(packed.byteLength).padStart(7)} B  ${cand.name.slice(0, 40)}`,
      );
    }
    catalog.roles[role] = variants;
  }

  await writeFile(path.join(OUT, 'catalog.json'), JSON.stringify(catalog, null, 2));
  const all = Object.values(catalog.roles).flat();
  console.log(
    `total: ${all.reduce((s, p) => s + p.tris, 0)} tris, ` +
      `${(all.reduce((s, p) => s + p.bytes, 0) / 1e6).toFixed(2)} MB`,
  );
}

await main();
