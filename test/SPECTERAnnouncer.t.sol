// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SPECTERAnnouncer} from "../src/SPECTERAnnouncer.sol";
import {ISPECTERAnnouncer} from "../src/interfaces/ISPECTERAnnouncer.sol";

contract SPECTERAnnouncerTest is Test {

    SPECTERAnnouncer public announcer;

    address constant STEALTH = address(0xBEEF);

    event Announcement(
        uint256         schemeId,
        address indexed stealthAddress,
        address indexed caller,
        bytes32         ephemeralKeyHash,
        bytes           metadata
    );

    // ─── Setup ────────────────────────────────────────────────────────────────────

    function setUp() public {
        announcer = new SPECTERAnnouncer();
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────────

    /// @dev Produces a deterministic 1088-byte ciphertext (non-zero bytes).
    function _makeKey() internal pure returns (bytes memory key) {
        key = new bytes(1088);
        for (uint256 i; i < 1088;) {
            key[i] = bytes1(uint8((i * 137 + 42) % 256 | 1)); // always nonzero
            unchecked { ++i; }
        }
    }

    /// @dev Varies key content by nonce so each call produces a distinct ciphertext.
    function _makeKey(uint256 nonce) internal pure returns (bytes memory key) {
        key = _makeKey();
        bytes32 seed = keccak256(abi.encode(nonce));
        assembly { mstore(add(key, 32), seed) }
    }

    function _meta(uint8 viewTag) internal pure returns (bytes memory) {
        return abi.encodePacked(viewTag);
    }

    function _fullMeta(uint8 viewTag) internal pure returns (bytes memory meta) {
        meta = new bytes(77);
        meta[0] = bytes1(viewTag);
    }

    // ─── Constants ────────────────────────────────────────────────────────────────

    function test_SchemeId() public view {
        assertEq(announcer.SCHEME_ID(), 1000);
    }

    function test_EphemeralKeyLength() public view {
        assertEq(announcer.EPHEMERAL_KEY_LENGTH(), 1088);
    }

    function test_MaxBatch() public view {
        assertEq(announcer.MAX_BATCH(), 50);
    }

    function test_DeployBlock() public view {
        assertEq(announcer.deployBlock(), block.number);
    }

    // ─── announce (3-arg) ─────────────────────────────────────────────────────────

    function test_Announce_EmitsCorrectEvent() public {
        bytes memory key  = _makeKey();
        bytes memory meta = _fullMeta(0xAB);
        bytes32 expectedHash = keccak256(key);

        vm.expectEmit(true, true, false, true, address(announcer));
        emit Announcement(1000, STEALTH, address(this), expectedHash, meta);

        announcer.announce(STEALTH, key, meta);
    }

    function test_Announce_MinimalMetadata() public {
        bytes memory key  = _makeKey();
        bytes memory meta = _meta(0xFF);

        vm.expectEmit(true, true, false, true, address(announcer));
        emit Announcement(1000, STEALTH, address(this), keccak256(key), meta);

        announcer.announce(STEALTH, key, meta);
    }

    function test_Announce_CallerIndexed() public {
        bytes memory key    = _makeKey();
        bytes memory meta   = _meta(0x01);
        address caller      = address(0xCAFE);

        vm.prank(caller);
        vm.expectEmit(true, true, false, true, address(announcer));
        emit Announcement(1000, STEALTH, caller, keccak256(key), meta);

        announcer.announce(STEALTH, key, meta);
    }

    function test_Announce_HashMatchesKeccak() public {
        bytes memory key  = _makeKey();
        bytes memory meta = _meta(0x42);

        vm.recordLogs();
        announcer.announce(STEALTH, key, meta);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);

        // Non-indexed data: abi.encode(schemeId, ephemeralKeyHash, metadata)
        (uint256 schemeId, bytes32 emittedHash, bytes memory emittedMeta) =
            abi.decode(logs[0].data, (uint256, bytes32, bytes));

        assertEq(schemeId,     1000);
        assertEq(emittedHash,  keccak256(key));
        assertEq(emittedMeta,  meta);

        // Indexed topics: [eventSig, stealthAddress, caller]
        assertEq(address(uint160(uint256(logs[0].topics[1]))), STEALTH);
        assertEq(address(uint160(uint256(logs[0].topics[2]))), address(this));
    }

    function test_Announce_DifferentKeysDifferentHashes() public {
        bytes memory keyA = _makeKey(0);
        bytes memory keyB = _makeKey(1);
        bytes memory meta = _meta(0x01);

        vm.recordLogs();
        announcer.announce(STEALTH, keyA, meta);
        announcer.announce(STEALTH, keyB, meta);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        (, bytes32 hashA,) = abi.decode(logs[0].data, (uint256, bytes32, bytes));
        (, bytes32 hashB,) = abi.decode(logs[1].data, (uint256, bytes32, bytes));

        assertTrue(hashA != hashB);
    }

    // ─── announce (3-arg) reverts ─────────────────────────────────────────────────

    function test_Announce_Revert_ZeroAddress() public {
        vm.expectRevert(ISPECTERAnnouncer.ZeroStealthAddress.selector);
        announcer.announce(address(0), _makeKey(), _meta(0x01));
    }

    function test_Announce_Revert_KeyTooShort() public {
        vm.expectRevert(
            abi.encodeWithSelector(ISPECTERAnnouncer.EphemeralKeyLength.selector, 1087, 1088)
        );
        announcer.announce(STEALTH, new bytes(1087), _meta(0x01));
    }

    function test_Announce_Revert_KeyTooLong() public {
        vm.expectRevert(
            abi.encodeWithSelector(ISPECTERAnnouncer.EphemeralKeyLength.selector, 1089, 1088)
        );
        announcer.announce(STEALTH, new bytes(1089), _meta(0x01));
    }

    function test_Announce_Revert_KeyEmpty() public {
        vm.expectRevert(
            abi.encodeWithSelector(ISPECTERAnnouncer.EphemeralKeyLength.selector, 0, 1088)
        );
        announcer.announce(STEALTH, new bytes(0), _meta(0x01));
    }

    function test_Announce_Revert_EmptyMetadata() public {
        vm.expectRevert(ISPECTERAnnouncer.MetadataRequired.selector);
        announcer.announce(STEALTH, _makeKey(), new bytes(0));
    }

    // ─── announce (4-arg ERC-5564 overload) ──────────────────────────────────────

    function test_Announce4Arg_HappyPath() public {
        bytes memory key  = _makeKey();
        bytes memory meta = _meta(0x01);

        vm.expectEmit(true, true, false, true, address(announcer));
        emit Announcement(1000, STEALTH, address(this), keccak256(key), meta);

        announcer.announce(uint256(1000), STEALTH, key, meta);
    }

    function test_Announce4Arg_Revert_WrongScheme() public {
        vm.expectRevert(
            abi.encodeWithSelector(ISPECTERAnnouncer.SchemeMismatch.selector, 1, 1000)
        );
        announcer.announce(uint256(1), STEALTH, _makeKey(), _meta(0x01));
    }

    function test_Announce4Arg_Revert_SchemeZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(ISPECTERAnnouncer.SchemeMismatch.selector, 0, 1000)
        );
        announcer.announce(uint256(0), STEALTH, _makeKey(), _meta(0x01));
    }

    function test_Announce4Arg_Revert_ZeroAddress() public {
        vm.expectRevert(ISPECTERAnnouncer.ZeroStealthAddress.selector);
        announcer.announce(uint256(1000), address(0), _makeKey(), _meta(0x01));
    }

    function test_Announce4Arg_Revert_BadKeyLength() public {
        vm.expectRevert(
            abi.encodeWithSelector(ISPECTERAnnouncer.EphemeralKeyLength.selector, 64, 1088)
        );
        announcer.announce(uint256(1000), STEALTH, new bytes(64), _meta(0x01));
    }

    // ─── announceMany ─────────────────────────────────────────────────────────────

    function test_AnnounceMany_EmitsAllEvents() public {
        uint256 n = 5;
        (address[] memory stealths, bytes[] memory keys, bytes[] memory metas) = _makeBatch(n);

        vm.recordLogs();
        announcer.announceMany(stealths, keys, metas);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, n);

        for (uint256 i; i < n; ++i) {
            address emittedStealth = address(uint160(uint256(logs[i].topics[1])));
            assertEq(emittedStealth, stealths[i]);

            (, bytes32 emittedHash,) = abi.decode(logs[i].data, (uint256, bytes32, bytes));
            assertEq(emittedHash, keccak256(keys[i]));
        }
    }

    function test_AnnounceMany_MaxBatch() public {
        (address[] memory stealths, bytes[] memory keys, bytes[] memory metas) = _makeBatch(50);
        announcer.announceMany(stealths, keys, metas);
    }

    function test_AnnounceMany_SingleItem() public {
        (address[] memory stealths, bytes[] memory keys, bytes[] memory metas) = _makeBatch(1);

        vm.expectEmit(true, true, false, true, address(announcer));
        emit Announcement(1000, stealths[0], address(this), keccak256(keys[0]), metas[0]);

        announcer.announceMany(stealths, keys, metas);
    }

    function test_AnnounceMany_Revert_Empty() public {
        vm.expectRevert(ISPECTERAnnouncer.BatchEmpty.selector);
        announcer.announceMany(new address[](0), new bytes[](0), new bytes[](0));
    }

    function test_AnnounceMany_Revert_TooLarge() public {
        vm.expectRevert(
            abi.encodeWithSelector(ISPECTERAnnouncer.BatchTooLarge.selector, 51, 50)
        );
        announcer.announceMany(new address[](51), new bytes[](51), new bytes[](51));
    }

    function test_AnnounceMany_Revert_KeysMismatch() public {
        address[] memory stealths = new address[](2);
        bytes[]   memory keys     = new bytes[](1);   // wrong
        bytes[]   memory metas    = new bytes[](2);
        stealths[0] = STEALTH; stealths[1] = address(0xBEEF2);
        keys[0]     = _makeKey();
        metas[0]    = _meta(0x01); metas[1] = _meta(0x02);

        vm.expectRevert(ISPECTERAnnouncer.BatchLengthMismatch.selector);
        announcer.announceMany(stealths, keys, metas);
    }

    function test_AnnounceMany_Revert_MetasMismatch() public {
        address[] memory stealths = new address[](2);
        bytes[]   memory keys     = new bytes[](2);
        bytes[]   memory metas    = new bytes[](1);   // wrong
        stealths[0] = STEALTH; stealths[1] = address(0xBEEF2);
        keys[0]     = _makeKey(0); keys[1] = _makeKey(1);
        metas[0]    = _meta(0x01);

        vm.expectRevert(ISPECTERAnnouncer.BatchLengthMismatch.selector);
        announcer.announceMany(stealths, keys, metas);
    }

    function test_AnnounceMany_Revert_ZeroAddressInBatch() public {
        address[] memory stealths = new address[](2);
        bytes[]   memory keys     = new bytes[](2);
        bytes[]   memory metas    = new bytes[](2);
        stealths[0] = STEALTH; stealths[1] = address(0); // zero in slot 1
        keys[0]     = _makeKey(0); keys[1] = _makeKey(1);
        metas[0]    = _meta(0x01); metas[1] = _meta(0x02);

        vm.expectRevert(ISPECTERAnnouncer.ZeroStealthAddress.selector);
        announcer.announceMany(stealths, keys, metas);
    }

    function test_AnnounceMany_Revert_BadKeyInBatch() public {
        address[] memory stealths = new address[](2);
        bytes[]   memory keys     = new bytes[](2);
        bytes[]   memory metas    = new bytes[](2);
        stealths[0] = STEALTH; stealths[1] = address(0xBEEF2);
        keys[0]     = _makeKey(); keys[1] = new bytes(64); // wrong length
        metas[0]    = _meta(0x01); metas[1] = _meta(0x02);

        vm.expectRevert(
            abi.encodeWithSelector(ISPECTERAnnouncer.EphemeralKeyLength.selector, 64, 1088)
        );
        announcer.announceMany(stealths, keys, metas);
    }

    // ─── Gas snapshots ────────────────────────────────────────────────────────────

    function test_Gas_SingleAnnounce() public {
        bytes memory key  = _makeKey();
        bytes memory meta = _fullMeta(0xAB);

        uint256 before = gasleft();
        announcer.announce(STEALTH, key, meta);
        uint256 used = before - gasleft();

        console2.log("Gas (single announce, function-only):", used);
        assertLt(used, 50_000);
    }

    function test_Gas_BatchAnnounce10() public {
        (address[] memory stealths, bytes[] memory keys, bytes[] memory metas) = _makeBatch(10);

        uint256 before = gasleft();
        announcer.announceMany(stealths, keys, metas);
        uint256 used = before - gasleft();

        console2.log("Gas (batch 10, function-only):", used);
        console2.log("Gas per announcement (batch 10):", used / 10);
    }

    function test_Gas_BatchAnnounce50() public {
        (address[] memory stealths, bytes[] memory keys, bytes[] memory metas) = _makeBatch(50);

        uint256 before = gasleft();
        announcer.announceMany(stealths, keys, metas);
        uint256 used = before - gasleft();

        console2.log("Gas (batch 50, function-only):", used);
        console2.log("Gas per announcement (batch 50):", used / 50);
    }

    // ─── Fuzz ─────────────────────────────────────────────────────────────────────

    function testFuzz_Announce(address stealthAddress, uint8 viewTag, uint256 keyNonce) public {
        vm.assume(stealthAddress != address(0));
        bytes memory key  = _makeKey(keyNonce);
        bytes memory meta = _meta(viewTag);

        vm.recordLogs();
        announcer.announce(stealthAddress, key, meta);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);

        (, bytes32 emittedHash,) = abi.decode(logs[0].data, (uint256, bytes32, bytes));
        assertEq(emittedHash, keccak256(key));
        assertEq(address(uint160(uint256(logs[0].topics[1]))), stealthAddress);
    }

    function testFuzz_AnnounceMany(uint8 rawSize) public {
        uint256 n = bound(uint256(rawSize), 1, 50);
        (address[] memory stealths, bytes[] memory keys, bytes[] memory metas) = _makeBatch(n);

        vm.recordLogs();
        announcer.announceMany(stealths, keys, metas);

        assertEq(vm.getRecordedLogs().length, n);
    }

    function testFuzz_Announce4Arg_SchemeMismatch(uint256 badScheme) public {
        vm.assume(badScheme != 1000);
        vm.expectRevert(
            abi.encodeWithSelector(ISPECTERAnnouncer.SchemeMismatch.selector, badScheme, 1000)
        );
        announcer.announce(badScheme, STEALTH, _makeKey(), _meta(0x01));
    }

    // ─── Internal batch helper ────────────────────────────────────────────────────

    function _makeBatch(uint256 n)
        internal
        pure
        returns (
            address[] memory stealths,
            bytes[]   memory keys,
            bytes[]   memory metas
        )
    {
        stealths = new address[](n);
        keys     = new bytes[](n);
        metas    = new bytes[](n);

        for (uint256 i; i < n; ++i) {
            stealths[i] = address(uint160(0x10000 + i));
            keys[i]     = _makeKey(i);
            metas[i]    = abi.encodePacked(uint8((i + 1) % 256));
        }
    }
}
