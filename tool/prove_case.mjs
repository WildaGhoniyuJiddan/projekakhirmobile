// Bukti skill glb-asset-pipeline Target A pada 1 case asli BuildCores:
// proses DUA cara — (1) persis loadGeometry prepare_3d.mjs saat ini
// (abaikan transform node), (2) dengan transform node diterapkan —
// lalu bandingkan bbox & statistik .wglb yang dihasilkan.
import { readFile, writeFile } from 'node:fs/promises';
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { dedup, dequantize } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import draco3d from 'draco3dgltf';
import { vec3, mat4 } from 'gl-matrix';

await MeshoptSimplifier.ready;
const FILE = process.argv[2];
const BUDGET = 3500; // budget role case

const io = new NodeIO()
  .registerExtensions(ALL_EXTENSIONS)
  .registerDependencies({
    'draco3d.decoder': await draco3d.createDecoderModule(),
    'draco3d.encoder': await draco3d.createEncoderModule(),
  });

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

async function loadGeometry(file, applyNodeTransforms) {
  let d = await io.read(file);
  d = await d.transform(dedup(), dequantize());
  const positions = [];
  const indices = [];
  let base = 0;
  const scene = d.getRoot().listScenes()[0];
  const visit = (node, parentMatrix) => {
    let world = parentMatrix;
    if (applyNodeTransforms) {
      const local = mat4.fromValues(...node.getMatrix());
      world = mat4.create();
      mat4.multiply(world, parentMatrix, local);
    }
    const mesh = node.getMesh();
    if (mesh) {
      for (const prim of mesh.listPrimitives()) {
        const pos = prim.getAttribute('POSITION');
        if (!pos) continue;
        const arr = pos.getArray();
        const v = vec3.create();
        for (let i = 0; i < arr.length; i += 3) {
          if (applyNodeTransforms) {
            vec3.set(v, arr[i], arr[i + 1], arr[i + 2]);
            vec3.transformMat4(v, v, world);
            positions.push(v[0], v[1], v[2]);
          } else {
            positions.push(arr[i], arr[i + 1], arr[i + 2]);
          }
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
  for (const child of scene.listChildren()) visit(child, mat4.create());
  return weldByPosition(new Float32Array(positions), new Uint32Array(indices));
}

function bbox(positions) {
  const min = [Infinity, Infinity, Infinity];
  const max = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < positions.length; i += 3) {
    for (let c = 0; c < 3; c++) {
      const v = positions[i + c];
      if (v < min[c]) min[c] = v;
      if (v > max[c]) max[c] = v;
    }
  }
  return [0, 1, 2].map((c) => +(max[c] - min[c]).toFixed(3));
}

function finish(geo, label) {
  let tris = geo.indices.length / 3;
  if (tris > BUDGET) {
    const target = BUDGET * 3;
    const [dst] = MeshoptSimplifier.simplify(geo.indices, geo.positions, 3, target, 0.02, []);
    geo.indices = dst;
    tris = geo.indices.length / 3;
  }
  console.log(
    `${label}: verts=${geo.positions.length / 3} tris=${tris} bbox=${JSON.stringify(bbox(geo.positions))}`,
  );
  return geo;
}

const rawInfo = await io.read(FILE);
const root = rawInfo.getRoot();
console.log(
  `sumber: meshes=${root.listMeshes().length} nodes=${root.listNodes().length} ` +
    `nodesWithTransform=${root.listNodes().filter((n) => !n.getMatrix().every((v, i) => v === [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1][i])).length}`,
);
const srcBytes = (await readFile(FILE)).length;
console.log(`ukuran sumber: ${(srcBytes / 1e6).toFixed(2)} MB`);
finish(await loadGeometry(FILE, false), 'TANPA transform node (pipeline lama)');
finish(await loadGeometry(FILE, true), 'DENGAN transform node (skill v2)');
