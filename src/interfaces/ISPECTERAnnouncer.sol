// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

/// @title  ISPECTERAnnouncer
/// @author SpecterPQ : Pranshu Rastogi
/// @notice Interface for the SpecterPQ on-chain stealth payment announcer.
interface ISPECTERAnnouncer {

    // ─── Errors ───────────────────────────────────────────────────────────────────

    error ZeroStealthAddress();
    error EphemeralKeyLength(uint256 actual, uint256 expected);
    error MetadataRequired();
    error SchemeMismatch(uint256 given, uint256 expected);
    error BatchEmpty();
    error BatchTooLarge(uint256 length, uint256 max);
    error BatchLengthMismatch();

    // ─── Events ───────────────────────────────────────────────────────────────────

    /// @notice Emitted once per announced stealth payment.
    /// @param schemeId         SpecterPQ scheme identifier (SCHEME_ID = 1000). Not indexed.
    /// @param stealthAddress   One-time recipient address.
    /// @param caller           Transaction sender or relayer.
    /// @param ephemeralKeyHash keccak256 of the ML-KEM-768 ciphertext. Recover the full
    ///                         ciphertext via eth_getTransactionByHash on the emitting tx.
    /// @param metadata         Raw-packed payload; byte[0] is the view_tag.
    event Announcement(
        uint256         schemeId,
        address indexed stealthAddress,
        address indexed caller,
        bytes32         ephemeralKeyHash,
        bytes           metadata
    );

    // ─── View ─────────────────────────────────────────────────────────────────────

    function SCHEME_ID() external view returns (uint256);
    function EPHEMERAL_KEY_LENGTH() external view returns (uint256);
    function MAX_BATCH() external view returns (uint256);
    function deployBlock() external view returns (uint256);

    // ─── Write ────────────────────────────────────────────────────────────────────

    function announce(
        address        stealthAddress,
        bytes calldata ephemeralPubKey,
        bytes calldata metadata
    ) external;

    function announce(
        uint256        schemeId,
        address        stealthAddress,
        bytes calldata ephemeralPubKey,
        bytes calldata metadata
    ) external;

    function announceMany(
        address[]  calldata stealthAddresses,
        bytes[]    calldata ephemeralPubKeys,
        bytes[]    calldata metadatas
    ) external;
}
