// Deploy DreamBuildRegistry ke Polygon Amoy (testnet).
//
// Prasyarat:
//   npm i ethers solc        (atau pakai Hardhat/Remix — file .sol sama)
//   wallet proyek terisi MATIC testnet dari faucet Amoy.
//
// Env (JANGAN hardcode / commit):
//   RPC_URL      default: https://rpc-amoy.polygon.technology
//   PRIVATE_KEY  private key wallet proyek (0x...)
//
// Pakai:
//   RPC_URL=... PRIVATE_KEY=0x... node deploy.mjs
// Output: alamat kontrak -> pasang sebagai secret CHAIN_CONTRACT_ADDRESS
// di Supabase (lihat README.md).

import { readFileSync } from "node:fs";
import { ethers } from "ethers";
import solc from "solc";

const rpcUrl = process.env.RPC_URL ?? "https://rpc-amoy.polygon.technology";
const privateKey = process.env.PRIVATE_KEY;
if (!privateKey) {
  console.error("PRIVATE_KEY belum di-set di env");
  process.exit(1);
}

// Kompilasi kontrak dari sumber (tanpa dependensi eksternal).
const source = readFileSync(new URL("./DreamBuildRegistry.sol", import.meta.url), "utf8");
const input = {
  language: "Solidity",
  sources: { "DreamBuildRegistry.sol": { content: source } },
  settings: { outputSelection: { "*": { "*": ["abi", "evm.bytecode"] } } },
};
const output = JSON.parse(solc.compile(JSON.stringify(input)));
if (output.errors?.some((e) => e.severity === "error")) {
  console.error(output.errors);
  process.exit(1);
}
const { abi, evm } = output.contracts["DreamBuildRegistry.sol"].DreamBuildRegistry;

const provider = new ethers.JsonRpcProvider(rpcUrl);
const wallet = new ethers.Wallet(privateKey, provider);
console.log("Deployer:", wallet.address);

const factory = new ethers.ContractFactory(abi, evm.bytecode.object, wallet);
const contract = await factory.deploy();
await contract.waitForDeployment();
console.log("DreamBuildRegistry ter-deploy di:", await contract.getAddress());
