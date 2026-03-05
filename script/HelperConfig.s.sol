// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockPriceFeed.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address priceFeed;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_ANSWER = 2000e8;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else if (block.chainid == 84531) {
            activeNetworkConfig = getBasetestconfig();
        } else if (block.chainid == 421614) {
            activeNetworkConfig = getArbitrumSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getSepoliaConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory sepoliaConfig = NetworkConfig({priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306});

        return sepoliaConfig;
    }

    function getBasetestconfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory baseTestnetConfig = NetworkConfig({priceFeed: 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1});

        return baseTestnetConfig;
    }

    function getArbitrumSepoliaConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory arbitrumSepoliaConfig =
            NetworkConfig({priceFeed: 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165});

        return arbitrumSepoliaConfig;
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.priceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator mockPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_ANSWER);
        vm.stopBroadcast();

        NetworkConfig memory anvilConfig = NetworkConfig({priceFeed: address(mockPriceFeed)});

        return anvilConfig;
    }
}
