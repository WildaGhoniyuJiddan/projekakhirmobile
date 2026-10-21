// publish-build — Edge Function Supabase (Deno/TypeScript).
//
// Menerbitkan Kartu Rakitan Impian ke blockchain Polygon Amoy:
//   1. Verifikasi JWT user (endpoint Auth proyek).
//   2. Baca kartu + item dari PostgREST memakai JWT user — RLS
//      menjamin hanya kartu miliknya yang terbaca (orang lain -> 404).
//   3. Susun teks kanonik WB-DREAM-v1 & hitung SHA-256 DI SERVER
//      (tidak percaya hash kiriman aplikasi).
//   4. Kirim transaksi publish(cardId, contentHash, version) ke
//      DreamBuildRegistry memakai wallet proyek (secret server).
//   5. Update baris kartu (status published + tx_hash dsb.) tetap
//      memakai JWT user (RLS pemilik mengizinkan).
//
// Secret yang dibutuhkan (JANGAN masuk APK/repo):
//   CHAIN_RPC_URL, CHAIN_PRIVATE_KEY, CHAIN_CONTRACT_ADDRESS
// Belum terpasang -> 503 { error: 'chain belum dikonfigurasi' }.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { ethers } from "https://esm.sh/ethers@6";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const CHAIN_RPC_URL = Deno.env.get("CHAIN_RPC_URL") ?? "";
const CHAIN_PRIVATE_KEY = Deno.env.get("CHAIN_PRIVATE_KEY") ?? "";
const CHAIN_CONTRACT_ADDRESS = Deno.env.get("CHAIN_CONTRACT_ADDRESS") ?? "";

const SLOT_ORDER = [
  "CPU",
  "Motherboard",
  "GPU",
  "RAM",
  "Storage",
  "PSU",
  "Casing",
  "Cooler",
  "Monitor",
  "Lainnya",
];

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

type BuildItem = {
  slot: string;
  part_name: string;
  price: number;
  sort: number;
};

type Build = {
  id: string;
  owner_id: string;
  version: number;
  dream_build_items: BuildItem[];
};

/// Teks kanonik WB-DREAM-v1 — kontrak bersama dengan Dart
/// (dream_build_api.dart) & contracts/README.md (ada test vector).
function canonicalText(build: Build): string {
  const slotIdx = (s: string) => {
    const i = SLOT_ORDER.indexOf(s);
    return i < 0 ? SLOT_ORDER.length : i;
  };
  const items = [...(build.dream_build_items ?? [])].sort(
    (a, b) => slotIdx(a.slot) - slotIdx(b.slot) || a.sort - b.sort,
  );
  const total = items.reduce((sum, it) => sum + it.price, 0);
  const lines = [
    "WB-DREAM-v1",
    `card:${build.id}`,
    `owner:${build.owner_id}`,
    `version:${build.version}`,
    ...items.map(
      (it) => `slot=${it.slot};name=${it.part_name};price=${it.price}`,
    ),
    `total=${total}`,
  ];
  return lines.join("\n");
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ") || !SUPABASE_URL || !SUPABASE_ANON_KEY) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }
  const jwt = auth.slice("Bearer ".length);

  // 1. User dari JWT.
  const userResp = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { "Authorization": auth, "apikey": SUPABASE_ANON_KEY },
  });
  if (userResp.status !== 200) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  let payload: { build_id?: unknown };
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: "Body harus JSON valid" }, 400);
  }
  const buildId = typeof payload.build_id === "string" ? payload.build_id : "";
  if (!buildId) {
    return jsonResponse({ error: "build_id wajib" }, 400);
  }

  const restHeaders = {
    "apikey": SUPABASE_ANON_KEY,
    "Authorization": auth,
  };

  // 2. Kartu + item (RLS: bukan milik user -> kosong -> 404).
  const buildResp = await fetch(
    `${SUPABASE_URL}/rest/v1/dream_builds?id=eq.${buildId}` +
      `&select=*,dream_build_items(*)`,
    { headers: restHeaders },
  );
  const builds = (await buildResp.json()) as Build[];
  if (!Array.isArray(builds) || builds.length === 0) {
    return jsonResponse({ error: "Kartu tidak ditemukan" }, 404);
  }
  const build = builds[0];

  // 3. Hash di server.
  const contentHash = await sha256Hex(canonicalText(build));
  const cardId = await sha256Hex(build.id);

  // 4. Chain (bila belum dikonfigurasi, berhenti sopan di sini).
  if (!CHAIN_RPC_URL || !CHAIN_PRIVATE_KEY || !CHAIN_CONTRACT_ADDRESS) {
    return jsonResponse({ error: "chain belum dikonfigurasi" }, 503);
  }
  let txHash: string;
  try {
    const provider = new ethers.JsonRpcProvider(CHAIN_RPC_URL);
    const wallet = new ethers.Wallet(CHAIN_PRIVATE_KEY, provider);
    const contract = new ethers.Contract(
      CHAIN_CONTRACT_ADDRESS,
      ["function publish(bytes32,bytes32,uint256)"],
      wallet,
    );
    const tx = await contract.publish(
      `0x${cardId}`,
      `0x${contentHash}`,
      build.version,
    );
    const receipt = await tx.wait();
    txHash = receipt.hash as string;
  } catch (e) {
    return jsonResponse({ error: `Transaksi chain gagal: ${e}` }, 502);
  }

  // 5. Catat hasil penerbitan ke baris kartu (JWT user, RLS pemilik).
  const nowIso = new Date().toISOString();
  const upd = await fetch(
    `${SUPABASE_URL}/rest/v1/dream_builds?id=eq.${buildId}`,
    {
      method: "PATCH",
      headers: {
        ...restHeaders,
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
      },
      body: JSON.stringify({
        status: "published",
        content_hash: contentHash,
        tx_hash: txHash,
        published_version: build.version,
        published_at: nowIso,
        updated_at: nowIso,
      }),
    },
  );
  if (!upd.ok) {
    return jsonResponse(
      { error: `Gagal update kartu (HTTP ${upd.status})`, tx_hash: txHash },
      500,
    );
  }

  return jsonResponse({
    tx_hash: txHash,
    content_hash: contentHash,
    version: build.version,
  });
});
