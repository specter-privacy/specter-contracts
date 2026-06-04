// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.23;

contract SPECTERAnnouncer {

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
}
