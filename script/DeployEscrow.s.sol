// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {EscrowFreelance} from "../src/EscrowFreelance.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

contract DeployEscrow is Script {
    function runWithETH() external returns (EscrowFreelance) {
        address freelancer = makeAddr("freelancer");
        address admin = makeAddr("admin");
        uint256 deliveryPeriod = 7 days;
        HelperConfig helperConfig = new HelperConfig();

        vm.startBroadcast();
        EscrowFreelance escrow = new EscrowFreelance(
            msg.sender,
            freelancer,
            deliveryPeriod,
            helperConfig.activeNetworkConfig(),
            address(0), // ETH
            admin,
            0
        );
        vm.stopBroadcast();
        return escrow;
    }

    function runWithETHandBPS() external returns (EscrowFreelance) {
        address freelancer = makeAddr("freelancer");
        address admin = makeAddr("admin");
        uint256 deliveryPeriod = 7 days;
        uint256 bps = 1000; // 10%
        HelperConfig helperConfig = new HelperConfig();

        vm.startBroadcast();
        EscrowFreelance escrow = new EscrowFreelance(
            msg.sender,
            freelancer,
            deliveryPeriod,
            helperConfig.activeNetworkConfig(),
            address(0), // ETH
            admin,
            bps
        );
        vm.stopBroadcast();
        return escrow;
    }

    function runWithTokenAddressAnvil() external returns (EscrowFreelance) {
        address freelancer = makeAddr("freelancer");
        address admin = msg.sender;
        uint256 deliveryPeriod = 7 days;
        HelperConfig helperConfig = new HelperConfig();

        // Deploy mock token
        MockERC20 token = new MockERC20("Test Token", "TST", 18);

        vm.startBroadcast();
        EscrowFreelance escrow = new EscrowFreelance(
            msg.sender,
            freelancer,
            deliveryPeriod,
            helperConfig.activeNetworkConfig(),
            address(token), // Use ERC20 instead of ETH
            admin,
            0
        );
        vm.stopBroadcast();
        return escrow;
    }
}
