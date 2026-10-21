// verify-build — Edge Function Supabase (Deno/TypeScript), PUBLIK.
//
// Halaman verifikasi Kartu Rakitan Impian: GET ?id=<uuid kartu>.
// - Data kartu dibaca via PostgREST dengan anon key; RLS hanya membuka
//   kartu berstatus 'published' (draft -> halaman "belum diterbitkan").
// - Hash dihitung ULANG di server dari data yang ditampilkan.
// - Bila CHAIN_RPC_URL & CHAIN_CONTRACT_ADDRESS terpasang, hash
//   on-chain dibaca dari DreamBuildRegistry (eth_call latest(bytes32))
//   dan dibandingkan. Hasil: COCOK / TIDAK COCOK / belum-aktif.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { ethers } from "https://esm.sh/ethers@6";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const CHAIN_RPC_URL = Deno.env.get("CHAIN_RPC_URL") ?? "";
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

type BuildItem = {
  slot: string;
  part_name: string;
  price: number;
  sort: number;
};

type Build = {
  id: string;
  owner_id: string;
  name: string;
  version: number;
  published_version: number | null;
  content_hash: string | null;
  tx_hash: string | null;
  dream_build_items: BuildItem[];
};

function esc(s: unknown): string {
  return String(s ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function rupiah(n: number): string {
  return "Rp" + n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
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

function sortedItems(build: Build): BuildItem[] {
  const slotIdx = (s: string) => {
    const i = SLOT_ORDER.indexOf(s);
    return i < 0 ? SLOT_ORDER.length : i;
  };
  return [...(build.dream_build_items ?? [])].sort(
    (a, b) => slotIdx(a.slot) - slotIdx(b.slot) || a.sort - b.sort,
  );
}

/// Teks kanonik WB-DREAM-v1 — sama dengan dream_build_api.dart &
/// publish-build (test vector di contracts/README.md).
function canonicalText(build: Build, items: BuildItem[]): string {
  const total = items.reduce((sum, it) => sum + it.price, 0);
  const lines = [
    "WB-DREAM-v1",
    `card:${build.id}`,
    `owner:${build.owner_id}`,
    `version:${build.published_version ?? build.version}`,
    ...items.map(
      (it) => `slot=${it.slot};name=${it.part_name};price=${it.price}`,
    ),
    `total=${total}`,
  ];
  return lines.join("\n");
}

/// Baca latest(bytes32) dari kontrak via JSON-RPC eth_call.
/// Return data 4 word x 32 byte didekode manual:
/// [0]=contentHash [1]=publisher [2]=version [3]=timestamp.
async function readOnChain(
  cardIdHex: string,
): Promise<{ hash: string; version: number; timestamp: number } | null> {
  const iface = new ethers.Interface([
    "function latest(bytes32) view returns (bytes32,address,uint256,uint256)",
  ]);
  const data = iface.encodeFunctionData("latest", [`0x${cardIdHex}`]);
  const resp = await fetch(CHAIN_RPC_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "eth_call",
      params: [{ to: CHAIN_CONTRACT_ADDRESS, data }, "latest"],
    }),
  });
  const out = (await resp.json()) as { result?: string };
  const result = out.result ?? "";
  // 0x + 4 word * 64 hex char.
  if (!result.startsWith("0x") || result.length < 2 + 256) return null;
  const word = (i: number) => result.slice(2 + i * 64, 2 + (i + 1) * 64);
  const hash = word(0).toLowerCase();
  if (/^0+$/.test(hash)) return null; // belum pernah diterbitkan on-chain
  return {
    hash,
    version: Number(BigInt(`0x${word(2)}`)),
    timestamp: Number(BigInt(`0x${word(3)}`)),
  };
}

function page(title: string, body: string): Response {
  const html = `<!doctype html>
<html lang="id"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<style>
  body { font-family: system-ui, sans-serif; margin: 24px auto; max-width: 720px; padding: 0 16px; color: #141b24; }
  table { border-collapse: collapse; width: 100%; margin: 12px 0; }
  td, th { border: 1px solid #ddd; padding: 8px; text-align: left; }
  .hash { font-family: monospace; font-size: 12px; word-break: break-all; }
  .ok { color: #1a7f37; font-weight: 700; }
  .bad { color: #b42318; font-weight: 700; }
  .muted { color: #667085; }
</style></head><body>${body}</body></html>`;
  return new Response(html, {
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}

serve(async (req: Request) => {
  const id = new URL(req.url).searchParams.get("id") ?? "";
  if (!id || !SUPABASE_URL || !SUPABASE_ANON_KEY) {
    return page("Verifikasi Rakitan Impian", "<h1>Parameter tidak valid</h1>");
  }

  const resp = await fetch(
    `${SUPABASE_URL}/rest/v1/dream_builds?id=eq.${id}` +
      `&select=*,dream_build_items(*)`,
    {
      headers: {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": `Bearer ${SUPABASE_ANON_KEY}`,
      },
    },
  );
  const builds = (await resp.json()) as Build[];
  if (!Array.isArray(builds) || builds.length === 0) {
    return page(
      "Verifikasi Rakitan Impian",
      "<h1>Kartu belum diterbitkan</h1>" +
        '<p class="muted">Kartu ini masih draft atau tidak ditemukan, ' +
        "sehingga belum ada catatan publik untuk diverifikasi.</p>",
    );
  }
  const build = builds[0];
  const items = sortedItems(build);
  const total = items.reduce((sum, it) => sum + it.price, 0);

  const recomputed = await sha256Hex(canonicalText(build, items));
  const cardIdHex = await sha256Hex(build.id);

  let onChain: Awaited<ReturnType<typeof readOnChain>> = null;
  if (CHAIN_RPC_URL && CHAIN_CONTRACT_ADDRESS) {
    try {
      onChain = await readOnChain(cardIdHex);
    } catch {
      onChain = null;
    }
  }

  let statusHtml: string;
  if (onChain) {
    statusHtml = onChain.hash === recomputed.toLowerCase()
      ? '<span class="ok">COCOK — isi kartu sama persis dengan catatan on-chain.</span>'
      : '<span class="bad">TIDAK COCOK — isi kartu berbeda dari catatan on-chain.</span>';
  } else {
    statusHtml =
      '<span class="muted">belum-aktif — pemeriksaan on-chain belum tersedia.</span>';
  }

  const rows = items
    .map(
      (it) =>
        `<tr><td>${esc(it.slot)}</td><td>${esc(it.part_name)}</td>` +
        `<td>${esc(rupiah(it.price))}</td></tr>`,
    )
    .join("");

  const body = `
<h1>${esc(build.name)}</h1>
<p class="muted">Kartu Rakitan Impian — versi ${esc(build.published_version ?? build.version)}</p>
<table><tr><th>Slot</th><th>Part</th><th>Harga</th></tr>${rows}
<tr><td colspan="2"><strong>Total</strong></td><td><strong>${esc(rupiah(total))}</strong></td></tr></table>
<p>Status verifikasi: ${statusHtml}</p>
<p>Hash hitung ulang dari isi di atas:<br><span class="hash">${esc(recomputed)}</span></p>
<p>Hash tercatat di aplikasi:<br><span class="hash">${esc(build.content_hash ?? "-")}</span></p>
<p>Hash on-chain (Polygon Amoy):<br><span class="hash">${esc(onChain?.hash ?? "-")}</span></p>
${
    build.tx_hash
      ? `<p><a href="https://amoy.polygonscan.com/tx/${esc(build.tx_hash)}">Lihat transaksi di Amoy Polygonscan</a></p>`
      : ""
  }`;
  return page(`Verifikasi — ${build.name}`, body);
});
