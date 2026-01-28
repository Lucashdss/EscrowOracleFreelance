// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {EscrowFreelance} from "../src/EscrowFreelance.sol";
import {DeployEscrow} from "../script/DeployEscrow.s.sol";

contract EscrowFreelanceTest is Test {
    EscrowFreelance escrow;
    uint256 sendValue = 1 ether;

    function setUp() public {
        escrow = new DeployEscrow().run();
    }

    function testContractBalanceFunded() public view {
        uint256 escrowBalance = address(escrow).balance;
        assertEq(escrowBalance, 1 ether);
    }

    function testFundMoreEther() public {
        address client = escrow.getClientAdress();
        uint256 escrowInitialBalance = escrow.getAmountToRelease();
        uint256 clientInitialBalance = client.balance;

        vm.prank(client);
        escrow.fundEther{value: sendValue}();

        uint256 escrowFinalBalance = escrow.getAmountToRelease();

        assertEq(
            escrowFinalBalance,
            escrowInitialBalance + sendValue,
            "Escrow balance did not increase correctly"
        );

        assertEq(
            client.balance,
            clientInitialBalance - sendValue,
            "Client balance did not decrease correctly"
        );
    }

    function testCLientMarkDeliverConfirmed() public {
        address freelancer = escrow.getFreelancerAdress();
        vm.prank(freelancer);
        escrow.markDelivered();
        address client = escrow.getClientAdress();

        vm.prank(client);
        escrow.confirmDelivery();
        bool deliveryConfirmed = escrow.getDeliveryConfirmedState();

        assertEq(
            deliveryConfirmed,
            true,
            "Delivery confirmed state did not update to true"
        );
    }

    function testFreelancertMarkDelivered() public {
        address freelancer = escrow.getFreelancerAdress();
        vm.prank(freelancer);
        escrow.markDelivered();

        EscrowFreelance.EscrowState state = escrow.getScrowState();

        assertEq(
            uint256(state),
            uint256(EscrowFreelance.EscrowState.DELIVERED),
            "Escrow state did not update to DELIVERED"
        );
    }

    function testFreelancerTryMarkAsDeliverConfirmed() public {
        address freelancer = escrow.getFreelancerAdress();
        vm.prank(freelancer);
        escrow.markDelivered();

        vm.prank(freelancer);
        vm.expectRevert();
        escrow.confirmDelivery();
    }

    function testFreelanceFundMoreEther() public {
        address freelancer = escrow.getFreelancerAdress();
        vm.prank(freelancer);
        vm.deal(freelancer, 5 ether);
        vm.expectRevert();
        escrow.fundEther{value: sendValue}();
    }

    function testCheckUpkeepDeadlinePassed() public {
        // Fast forward time to exceed the deadline
        vm.warp(block.timestamp + 8 days);

        // Call checkUpkeep and verify the result
        (bool upkeepNeeded, bytes memory performData) = escrow.checkUpkeep("");
        uint8 action = abi.decode(performData, (uint8));

        assertEq(
            upkeepNeeded,
            true,
            "Upkeep should be needed when deadline has passed and state is FUNDED"
        );
        assertEq(action, 1, "PerformData should be empty for this upkeep");
    }

    function testCheckUpkeepDeliveryConfirmed() public {
        // Set up the contract in a DELIVERED state with delivery confirmed
        address freelancer = escrow.getFreelancerAdress();
        vm.prank(freelancer);
        escrow.markDelivered();

        address client = escrow.getClientAdress();
        vm.prank(client);
        escrow.confirmDelivery();

        // Call checkUpkeep and verify the result
        (bool upkeepNeeded, bytes memory performData) = escrow.checkUpkeep("");
        uint8 action = abi.decode(performData, (uint8));

        assertEq(
            upkeepNeeded,
            true,
            "Upkeep should be needed when state is DELIVERED and delivery is confirmed"
        );
        assertEq(action, 2, "PerformData should be empty for this upkeep");
    }

    function testCheckUpkeepNoUpkeepNeeded() public {
        // Ensure the contract is in a state where no upkeep is needed
        EscrowFreelance.EscrowState state = escrow.getScrowState();
        assertEq(
            uint256(state),
            uint256(EscrowFreelance.EscrowState.FUNDED), //check but it should be created, change main contract
            "Initial state should be FUNDED"
        );

        // Call checkUpkeep and verify the result
        (bool upkeepNeeded, bytes memory performData) = escrow.checkUpkeep("");

        assertEq(
            upkeepNeeded,
            false,
            "Upkeep should not be needed in the CREATED state"
        );
        assertEq(
            performData.length,
            0,
            "PerformData should be empty when no upkeep is needed"
        );
    }

    function testGetVersion() public view {
        uint256 version = escrow.getVersion();
        assertEq(version, 4, "Price feed version should be 4");
    }

    function testConvertAmountFromUSDtoETH() public view {
        uint256 usdAmount = 1000 * 1e18; // $1000 in 18 decimals
        uint256 expectedEthAmount = (usdAmount * 1e18) / (2000 * 1e18); // $2000 price in ETH

        uint256 ethAmount = escrow.convertAmountFromUSDtoETH(usdAmount);

        assertEq(
            ethAmount,
            expectedEthAmount,
            "ETH amount conversion is incorrect"
        );
    }
}
