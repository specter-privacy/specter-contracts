// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import {ISPECTERAnnouncer} from "./interfaces/ISPECTERAnnouncer.sol";

/**
 * @title  SPECTERAnnouncer
 * @author SpecterPQ : Pranshu Rastogi
 * @notice On-chain announcement registry for SpecterPQ stealth payments on Monad.
 *
 * @dev    ARCHITECTURE
 *         ─────────────────────────────────────────────────────────────────────
 *         SPECTERAnnouncer is a stateless, permissionless event emitter for the
 *         SpecterPQ post-quantum stealth address scheme. It has no storage, no
 *         owner, no admin keys, and is not upgradeable. Every call resolves to a
 *         single LOG3 opcode plus input validation. There are no SSTORE operations.
 *
 *         EPHEMERAL KEY DESIGN
 *         ─────────────────────────────────────────────────────────────────────
 *         ML-KEM-768 produces a 1,088-byte ciphertext. Emitting it in the event
 *         log would add over 1 KB to every announcement. Instead:
 *
 *           - Only keccak256(ephemeralPubKey) is stored in the event log (32 bytes).
 *           - The full ciphertext is passed as calldata, permanently archived
 *             on-chain and retrievable via eth_getTransactionByHash.
 *           - Scanners fetch the ciphertext only for the ~1/256 events that pass
 *             the view_tag filter, making the extra RPC call negligible.
 *
 *         Log data is therefore 109 bytes per announcement (32-byte hash +
 *         77-byte metadata) regardless of ciphertext size.
 *
 *         SCANNING PROTOCOL
 *         ─────────────────────────────────────────────────────────────────────
 *         1. eth_getLogs(address=SPECTERAnnouncer, fromBlock=deployBlock)
 *         2. For each Announcement event:
 *              a. Read metadata[0] (view_tag). Discard if no match (~255/256 filtered).
 *              b. On match: eth_getTransactionByHash → ABI-decode calldata.
 *              c. Assert keccak256(ciphertext) == ephemeralKeyHash (integrity check).
 *              d. ML-KEM.Decaps(recipientSecretKey, ciphertext) → sharedSecret.
 *              e. Derive stealth private key from sharedSecret.
 *
 *         SCHEME IDENTIFIER
 *         ─────────────────────────────────────────────────────────────────────
 *         SCHEME_ID = 1000 is the provisional SpecterPQ scheme identifier.
 *         schemeId is emitted as a non-indexed field — this contract's address
 *         is the unique filter for all SCHEME_ID = 1000 announcements.
 *
 *         METADATA LAYOUT
 *         ─────────────────────────────────────────────────────────────────────
 *         Raw-packed, no ABI encoding. Multi-byte fields are big-endian.
 *         Absent optional fields MUST be zero-padded.
 *
 *           Offset   Field        Type      Notes
 *           ──────   ──────────   ───────   ────────────────────────────────
 *           [0]      view_tag     uint8     Required. 1-byte scan filter.
 *           [1..32]  tx_hash      bytes32   Optional. Source-chain tx hash.
 *           [33..64] amount       uint256   Optional. Transfer value in wei.
 *           [65..76] channel_id   bytes12   Optional. Application channel.
 *
 *         Minimum valid metadata: 1 byte (view_tag only).
 *         Maximum defined layout: 77 bytes.
 *
 *         DEPLOYMENT
 *         ─────────────────────────────────────────────────────────────────────
 *         Deployed deterministically via CREATE2 using Nick's factory
 *         (0x4e59b44847b379578588920cA78FbF26c0B4956C).
 *         Salt: keccak256("specterpq.announcer.v1")
 *         Same address on every EVM chain where the factory is present.
 */
contract SPECTERAnnouncer is ISPECTERAnnouncer {

    // ─── Constants ────────────────────────────────────────────────────────────────

    /// @inheritdoc ISPECTERAnnouncer
    uint256 public constant SCHEME_ID = 1000;

    /// @inheritdoc ISPECTERAnnouncer
    uint256 public constant EPHEMERAL_KEY_LENGTH = 1088;

    /// @inheritdoc ISPECTERAnnouncer
    uint256 public constant MAX_BATCH = 50;

    // ─── Immutables ───────────────────────────────────────────────────────────────

    /// @inheritdoc ISPECTERAnnouncer
    uint256 public immutable deployBlock;

    // ─── Constructor ──────────────────────────────────────────────────────────────

    constructor() {
        deployBlock = block.number;
    }

    // ─── External ─────────────────────────────────────────────────────────────────

    /// @inheritdoc ISPECTERAnnouncer
    function announce(
        address        stealthAddress,
        bytes calldata ephemeralPubKey,
        bytes calldata metadata
    ) external {
        _announce(stealthAddress, ephemeralPubKey, metadata);
    }

    /// @inheritdoc ISPECTERAnnouncer
    /// @dev Reverts with SchemeMismatch if schemeId != SCHEME_ID.
    function announce(
        uint256        schemeId,
        address        stealthAddress,
        bytes calldata ephemeralPubKey,
        bytes calldata metadata
    ) external {
        if (schemeId != SCHEME_ID) revert SchemeMismatch(schemeId, SCHEME_ID);
        _announce(stealthAddress, ephemeralPubKey, metadata);
    }

    /// @inheritdoc ISPECTERAnnouncer
    /// @dev Recommended batch size: 10–50. A validation failure on any element
    ///      reverts the entire transaction.
    function announceMany(
        address[]  calldata stealthAddresses,
        bytes[]    calldata ephemeralPubKeys,
        bytes[]    calldata metadatas
    ) external {
        uint256 n = stealthAddresses.length;
        if (n == 0) revert BatchEmpty();
        if (n > MAX_BATCH) revert BatchTooLarge(n, MAX_BATCH);
        if (ephemeralPubKeys.length != n || metadatas.length != n)
            revert BatchLengthMismatch();

        for (uint256 i; i < n;) {
            _announce(stealthAddresses[i], ephemeralPubKeys[i], metadatas[i]);
            unchecked { ++i; }
        }
    }

    // ─── Internal ─────────────────────────────────────────────────────────────────

    /// @dev Shared validation and emission path for all announce entry points.
    function _announce(
        address        stealthAddress,
        bytes calldata ephemeralPubKey,
        bytes calldata metadata
    ) internal {
        if (stealthAddress == address(0))
            revert ZeroStealthAddress();
        if (ephemeralPubKey.length != EPHEMERAL_KEY_LENGTH)
            revert EphemeralKeyLength(ephemeralPubKey.length, EPHEMERAL_KEY_LENGTH);
        if (metadata.length == 0)
            revert MetadataRequired();

        emit Announcement(
            SCHEME_ID,
            stealthAddress,
            msg.sender,
            keccak256(ephemeralPubKey),
            metadata
        );
    }
}
