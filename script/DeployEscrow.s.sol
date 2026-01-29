//SPDX-license-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {EscrowFreelance} from "../src/EscrowFreelance.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployEscrow is Script {
    function run() external returns (EscrowFreelance) {
        address freelancer = makeAddr("freelancer");
        uint256 deliveryPeriod = 7 days;
        uint256 sendValue = 1 ether;
        HelperConfig helperConfig = new HelperConfig();

        vm.startBroadcast();
        EscrowFreelance escrow = new EscrowFreelance{value: sendValue}(
            freelancer,
            deliveryPeriod,
            helperConfig.activeNetworkConfig()
        );
        vm.stopBroadcast();
        return escrow;
    }

    function runWithoutValue() external returns (EscrowFreelance) {
        address freelancer = makeAddr("freelancer");
        uint256 deliveryPeriod = 7 days;
        HelperConfig helperConfig = new HelperConfig();

        vm.startBroadcast();
        EscrowFreelance escrow = new EscrowFreelance(
            freelancer,
            deliveryPeriod,
            helperConfig.activeNetworkConfig()
        );
        vm.stopBroadcast();
        return escrow;
    }
}
