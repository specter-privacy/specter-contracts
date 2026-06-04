// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.23;

/**
 * @title  SPECTERAnnouncer
 * @notice ERC-5564-compatible announcer for SpecterPQ's ML-KEM-768 stealth address scheme.
 *
 * @dev    Emits ERC-5564 `Announcement` events with a SpecterPQ-specific schemeId.
 *         This contract has NO state, NO admin keys, and is NOT upgradeable.
 *         It is a pure event emitter — one LOG4 per call.
 *
 * Deployment:
 *   Deployed via CREATE2 using the deterministic deployer at
 *   0x4e59b44847b379578588920cA78FbF26c0B4956C (Nick's factory) on both
 *   Monad testnet (chainId 10143) and Monad mainnet (chainId 143).
 *   Salt: keccak256("specterpq.announcer.v1")
 *
 * Scheme ID:
 *   SCHEME_ID = 1000 (provisional; update to the registered value when
 *   ERC-XXXX: Post-Quantum Stealth Addresses is accepted)
 *
 * EphemeralPubKey:
 *   The ML-KEM-768 ciphertext — exactly 1,088 bytes.
 *   (NIST FIPS 203: ML-KEM-768 ciphertext is 1,088 bytes)
 *
 * Metadata byte layout (all fields packed, no ABI encoding):
 *   [0]        view_tag     uint8   required  — 1-byte scan filter
 *   [1..32]    tx_hash      bytes32 optional  — 0x00..00 = absent
 *   [33..64]   amount       uint256 optional  — big-endian wei; 0 = absent
 *   [65..76]   channel_id   bytes12 optional  — Yellow channel; 0x00..00 = absent
 *   Total: 77 bytes (fixed-length; pad with zeros for absent fields)
 *
 * Minimum valid metadata: 1 byte (view_tag only). Scanner handles short payloads.
 */

contract SPECTERAnnouncer {

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice Provisional scheme ID for SpecterPQ's ML-KEM-768 stealth address scheme.
    ///         Update to the registered ERC value when ERC-XXXX is accepted.
    uint256 public constant SCHEME_ID = 1000;

    /// @notice Expected byte length of an ML-KEM-768 ciphertext (ephemeralPubKey).
    uint256 public constant EPHEMERAL_KEY_LENGTH = 1088;

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @notice Block number at which this contract was deployed.
    ///         Scanners use this as the fromBlock for eth_getLogs calls.
    uint256 public immutable deployBlock;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /**
     * @dev ERC-5564 Announcement event.
     *      Three indexed topics: schemeId, stealthAddress, caller.
     *      Non-indexed: ephemeralPubKey (1088-byte ML-KEM ciphertext), metadata.
     *
     *      Indexed schemeId allows scanners to filter exclusively for SCHEME_ID=1000
     *      without touching secp256k1 (schemeId=1) announcements.
     */
    event Announcement(
        uint256 indexed schemeId,
        address indexed stealthAddress,
        address indexed caller,
        bytes ephemeralPubKey,
        bytes metadata
    );

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor() {
        deployBlock = block.number;
    }

    // -------------------------------------------------------------------------
    // External functions
    // -------------------------------------------------------------------------

    /**
     * @notice Announce a SpecterPQ stealth payment.
     *
     * @param stealthAddress  Derived stealth address that received the funds.
     * @param ephemeralPubKey ML-KEM-768 ciphertext; MUST be exactly 1088 bytes.
     * @param metadata        Packed metadata; byte[0] MUST be the view_tag.
     *                        Full layout in contract header.
     *
     * @dev   Gas profile (estimated):
     *          Base tx:          21,000
     *          LOG4 base:         1,500
     *          LOG4 per topic:    1,500 × 3 = 4,500
     *          Calldata (1165B):  ~4,660   (4 gas/zero byte, 16/nonzero)
     *          LOG data (1165B):  8 × 1165 = 9,320
     *          Total est.:       ~41,000 gas
     *
     *        On Monad, gas is charged on gas_limit (not gas_used).
     *        Set gasLimit = 60,000 in the frontend to give 46% headroom.
     */
    function announce(
        address stealthAddress,
        bytes calldata ephemeralPubKey,
        bytes calldata metadata
    ) external {
        require(
            ephemeralPubKey.length == EPHEMERAL_KEY_LENGTH,
            "SPECTERAnnouncer: ephemeralPubKey must be 1088 bytes (ML-KEM-768 ciphertext)"
        );
        require(
            metadata.length >= 1,
            "SPECTERAnnouncer: metadata must contain at least the view_tag (1 byte)"
        );
        require(
            stealthAddress != address(0),
            "SPECTERAnnouncer: stealthAddress cannot be zero"
        );

        emit Announcement(
            SCHEME_ID,
            stealthAddress,
            msg.sender,
            ephemeralPubKey,
            metadata
        );
    }

    /**
     * @notice ERC-5564-compatible overload that accepts schemeId as a parameter.
     *         Callers that build transactions using the canonical IERC5564Announcer ABI
     *         can use this overload. Reverts if schemeId != SCHEME_ID.
     *
     * @dev    Having both overloads avoids ABI-compatibility issues with tooling that
     *         hardcodes the 4-argument announce() signature from ERC-5564.
     */
    function announce(
        uint256 schemeId,
        address stealthAddress,
        bytes calldata ephemeralPubKey,
        bytes calldata metadata
    ) external {
        require(
            schemeId == SCHEME_ID,
            "SPECTERAnnouncer: schemeId must equal SCHEME_ID"
        );
        require(
            ephemeralPubKey.length == EPHEMERAL_KEY_LENGTH,
            "SPECTERAnnouncer: ephemeralPubKey must be 1088 bytes (ML-KEM-768 ciphertext)"
        );
        require(
            metadata.length >= 1,
            "SPECTERAnnouncer: metadata must contain at least the view_tag (1 byte)"
        );
        require(
            stealthAddress != address(0),
            "SPECTERAnnouncer: stealthAddress cannot be zero"
        );

        emit Announcement(
            SCHEME_ID,
            stealthAddress,
            msg.sender,
            ephemeralPubKey,
            metadata
        );
    }
}
