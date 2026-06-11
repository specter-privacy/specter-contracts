// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {SPECTERAnnouncer} from "../src/SPECTERAnnouncer.sol";

contract DeploySPECTERAnnouncer is Script {

    // CREATE2_FACTORY (0x4e59b44847b379578588920cA78FbF26c0B4956C) is inherited from forge-std/Base.sol
    // via Script → Base. No redeclaration needed.

    // Deterministic salt — produces the same contract address on every EVM chain
    // where Nick's CREATE2 factory is deployed.
    bytes32 constant SALT = keccak256("specterpq.announcer.v1");

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        bytes memory initCode = type(SPECTERAnnouncer).creationCode;
        bytes32 initCodeHash  = keccak256(initCode);
        address expected      = vm.computeCreate2Address(SALT, initCodeHash, CREATE2_FACTORY);

        console2.log("Deployer:        ", deployer);
        console2.log("Expected address:", expected);

        if (expected.code.length > 0) {
            console2.log("Already deployed - skipping.");
            return;
        }

        vm.startBroadcast(deployerKey);

        (bool ok,) = CREATE2_FACTORY.call(abi.encodePacked(SALT, initCode));
        require(ok, "CREATE2 deployment failed");

        // We computed `expected` deterministically before the call.
        // Verify code landed there rather than trying to decode the factory's return format.
        require(expected.code.length > 0, "No code at expected address after deployment");
        address deployed = expected;
        console2.log("Deployed at:     ", deployed);

        SPECTERAnnouncer ann = SPECTERAnnouncer(deployed);
        console2.log("deployBlock:     ", ann.deployBlock());
        console2.log("SCHEME_ID:       ", ann.SCHEME_ID());

        vm.stopBroadcast();
    }
}
