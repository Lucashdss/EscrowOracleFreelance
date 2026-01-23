//SPDX-license-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {EscrowFreelance} from "../src/EscrowFreelance.sol";

contract DeployEscrow is Script {
    function run() external returns (EscrowFreelance) {
        address freelancer = makeAddr("freelancer");
        uint256 deliveryPeriod = 7 days;
        uint256 sendValue = 1 ether;

        vm.startBroadcast();
        EscrowFreelance escrow = new EscrowFreelance{value: sendValue}(
            freelancer,
            deliveryPeriod
        );
        vm.stopBroadcast();
        return escrow;
    }
}
