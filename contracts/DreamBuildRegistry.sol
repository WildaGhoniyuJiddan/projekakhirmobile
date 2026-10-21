// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// Registry penjangkaran hash Kartu Rakitan Impian (WorthBang).
///
/// Yang disimpan on-chain HANYA sidik jari (SHA-256) isi kartu + pemilik
/// penerbit + versi + waktu. Isi kartu sendiri tetap di database
/// aplikasi (Supabase) — verifikasi publik menghitung ulang hash dari
/// isi yang tampil dan mencocokkannya dengan catatan di sini.
///
/// cardId (bytes32) = SHA-256 dari string uuid kartu.
contract DreamBuildRegistry {
    struct Record {
        bytes32 contentHash;
        address publisher;
        uint256 version;
        uint256 timestamp;
    }

    /// Catatan penerbitan terakhir per kartu.
    mapping(bytes32 => Record) public latest;

    /// Seluruh riwayat penerbitan per kartu (versi lama tidak tertimpa).
    mapping(bytes32 => Record[]) internal _history;

    event Published(
        bytes32 indexed cardId,
        uint256 version,
        bytes32 contentHash,
        address publisher,
        uint256 timestamp
    );

    /// Catat penerbitan satu versi kartu. Dipanggil wallet proyek lewat
    /// Edge Function `publish-build` (user aplikasi tidak pegang wallet).
    function publish(
        bytes32 cardId,
        bytes32 contentHash,
        uint256 version
    ) external {
        Record memory rec = Record({
            contentHash: contentHash,
            publisher: msg.sender,
            version: version,
            timestamp: block.timestamp
        });
        _history[cardId].push(rec);
        latest[cardId] = rec;
        emit Published(cardId, version, contentHash, msg.sender, block.timestamp);
    }

    function historyLength(bytes32 cardId) external view returns (uint256) {
        return _history[cardId].length;
    }

    function historyAt(bytes32 cardId, uint256 index)
        external
        view
        returns (Record memory)
    {
        return _history[cardId][index];
    }
}
