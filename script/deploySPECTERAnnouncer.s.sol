// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.23;

import {Script, console2} from "forge-std/Script.sol";
import {SPECTERAnnouncer} from "../src/SPECTERAnnouncer.sol";

contract deploySPECTERAnnouncer is Script {
    // Nick's deterministic deployer — confirmed present on Monad
    address constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // Salt: keccak256("specterpq.announcer.v1")
    // This produces the same address on testnet and mainnet.
    bytes32 constant SALT = keccak256("specterpq.announcer.v1");

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        // Compute the expected CREATE2 address before deploying
        bytes memory initCode = type(SPECTERAnnouncer).creationCode;
        address expected = computeCreate2Address(SALT, keccak256(initCode), CREATE2_FACTORY);
        console2.log("Expected address:", expected);

        // Deploy via Nick's factory
        // The factory accepts: abi.encodePacked(bytes32 salt, bytes initCode)
        (bool ok, bytes memory ret) = CREATE2_FACTORY.call(
            abi.encodePacked(SALT, initCode)
        );
        require(ok, "CREATE2 deployment failed");

        address deployed = address(uint160(bytes20(ret)));
        console2.log("Deployed SPECTERAnnouncer at:", deployed);
        console2.log("Deploy block recorded in contract immutable: deployBlock");
        require(deployed == expected, "Address mismatch — salt collision?");

        vm.stopBroadcast();
    }
}
