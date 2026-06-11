// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {SPECTERAnnouncer} from "../src/SPECTERAnnouncer.sol";

/**
 * @notice Live smoke-test script for SPECTERAnnouncer on Monad testnet.
 *
 * Sends three transactions:
 *   TX 1 — announce() 3-arg  (single, minimal metadata)
 *   TX 2 — announce() 4-arg  (single, full 77-byte metadata, ERC-5564 overload)
 *   TX 3 — announceMany()    (batch of 5)
 *
 * Run:
 *   source .env
 *   forge script script/testAnnounce.s.sol --rpc-url $MONAD_TESTNET_RPC --broadcast -vvv
 */
contract TestAnnounce is Script {

    // Deployed SPECTERAnnouncer on Monad testnet
    SPECTERAnnouncer constant ANNOUNCER =
        SPECTERAnnouncer(0x7a687B5a7c98c880f23F00003A820e7E2fF7fDaC);

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        console2.log("=== SPECTERAnnouncer Smoke Test ===");
        console2.log("Contract  :", address(ANNOUNCER));
        console2.log("Caller    :", deployer);
        console2.log("deployBlock:", ANNOUNCER.deployBlock());
        console2.log("SCHEME_ID  :", ANNOUNCER.SCHEME_ID());
        console2.log("");

        // ── TX 1: announce() 3-arg, minimal metadata ──────────────────────────
        bytes memory key1   = _mockCiphertext(1);
        bytes memory meta1  = abi.encodePacked(uint8(0xAB)); // view_tag only

        console2.log("TX 1: announce() 3-arg");
        console2.log("  stealthAddress :", address(0xDEAD1));
        console2.log("  ephemeralKeyHash:", _toHex(keccak256(key1)));
        console2.log("  view_tag        : 0xAB");

        vm.startBroadcast(deployerKey);
        ANNOUNCER.announce(address(0xDEAD1), key1, meta1);
        vm.stopBroadcast();

        console2.log("  => sent");
        console2.log("");

        // ── TX 2: announce() 4-arg, full 77-byte metadata ─────────────────────
        bytes memory key2  = _mockCiphertext(2);
        bytes memory meta2 = _fullMetadata(
            0xCD,                                                   // view_tag
            bytes32(uint256(0xBEEF)),                               // tx_hash (mock)
            1_000_000 gwei,                                         // amount
            bytes12(bytes4(0xCAFEBABE))                             // channel_id
        );

        console2.log("TX 2: announce() 4-arg (schemeId overload)");
        console2.log("  stealthAddress :", address(0xDEAD2));
        console2.log("  ephemeralKeyHash:", _toHex(keccak256(key2)));
        console2.log("  view_tag        : 0xCD");
        console2.log("  amount          : 1,000,000 gwei");

        vm.startBroadcast(deployerKey);
        ANNOUNCER.announce(uint256(1000), address(0xDEAD2), key2, meta2);
        vm.stopBroadcast();

        console2.log("  => sent");
        console2.log("");

        // ── TX 3: announceMany() batch of 5 ───────────────────────────────────
        uint256 n = 5;
        address[] memory stealths = new address[](n);
        bytes[]   memory keys     = new bytes[](n);
        bytes[]   memory metas    = new bytes[](n);

        for (uint256 i; i < n; ++i) {
            stealths[i] = address(uint160(0xBEEF0000 + i));
            keys[i]     = _mockCiphertext(10 + i);
            metas[i]    = abi.encodePacked(uint8(i + 1)); // view_tag = 1..5
        }

        console2.log("TX 3: announceMany() batch of 5");
        for (uint256 i; i < n; ++i) {
            console2.log("  [", i, "] stealthAddress:", stealths[i]);
            console2.log("       view_tag      :", uint256(uint8(i + 1)));
        }

        vm.startBroadcast(deployerKey);
        ANNOUNCER.announceMany(stealths, keys, metas);
        vm.stopBroadcast();

        console2.log("  => sent (5 Announcement events in one tx)");
        console2.log("");
        console2.log("=== All smoke tests passed ===");
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /// @dev Produces a deterministic 1088-byte mock ML-KEM ciphertext keyed by `seed`.
    function _mockCiphertext(uint256 seed) internal pure returns (bytes memory ct) {
        ct = new bytes(1088);
        bytes32 h = keccak256(abi.encode("specter.mock.ciphertext", seed));
        // Fill 32 bytes at a time via assembly for gas efficiency in the script
        uint256 chunks = 1088 / 32; // 34 full chunks
        for (uint256 i; i < chunks; ++i) {
            h = keccak256(abi.encode(h, i));
            assembly {
                mstore(add(add(ct, 32), mul(i, 32)), h)
            }
        }
        // Fill remaining 0 bytes (1088 % 32 = 0 — exactly 34 chunks, no remainder)
    }

    /// @dev Packs the full 77-byte metadata layout.
    function _fullMetadata(
        uint8   viewTag,
        bytes32 txHash,
        uint256 amount,
        bytes12 channelId
    ) internal pure returns (bytes memory meta) {
        meta = new bytes(77);
        meta[0] = bytes1(viewTag);
        // bytes [1..32]: tx_hash
        for (uint256 i; i < 32; ++i) {
            meta[1 + i] = txHash[i];
        }
        // bytes [33..64]: amount (big-endian uint256)
        bytes32 amountBytes = bytes32(amount);
        for (uint256 i; i < 32; ++i) {
            meta[33 + i] = amountBytes[i];
        }
        // bytes [65..76]: channel_id
        for (uint256 i; i < 12; ++i) {
            meta[65 + i] = channelId[i];
        }
    }

    /// @dev Returns a human-readable hex string for a bytes32 value.
    function _toHex(bytes32 b) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(66);
        result[0] = "0";
        result[1] = "x";
        for (uint256 i; i < 32; ++i) {
            result[2 + i * 2]     = hexChars[uint8(b[i]) >> 4];
            result[2 + i * 2 + 1] = hexChars[uint8(b[i]) & 0xf];
        }
        return string(result);
    }
}
