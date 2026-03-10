// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {EscrowFreelanceFactory} from "../src/EscrowFreelanceFactory.sol";

contract DeployEscrowFactory is Script {
    function run() external returns (EscrowFreelanceFactory) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        EscrowFreelanceFactory factory = new EscrowFreelanceFactory();
        vm.stopBroadcast();
        return factory;
    }
}
