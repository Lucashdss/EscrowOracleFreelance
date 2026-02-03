// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {EscrowFreelance} from "../src/EscrowFreelance.sol";
import {DeployEscrow} from "../script/DeployEscrow.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract EscrowFreelanceTest is Test {
    EscrowFreelance escrow;
    EscrowFreelance escrowWithToken;
    uint256 sendValue = 1 ether;

    function setUp() public {
        escrow = new DeployEscrow().runWithETH();
        escrowWithToken = new DeployEscrow().runWithTokenAddressAnvil();
    }

    function testContractBalanceFunded() public {
        address client = escrow.getClientAdress();
        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: 1 ether}(1 ether);
        uint256 escrowBalance = address(escrow).balance;
        assertApproxEqAbs(escrowBalance, 1 ether, 1e14);
    }

    function testFundMoreEther() public {
        address client = escrow.getClientAdress();
        uint256 escrowInitialBalance = escrow.getAmountToRelease();
        uint256 clientInitialBalance = client.balance;

        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);

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

    function testClientMarkDeliverConfirmed() public {
        address freelancer = escrow.getFreelancerAdress();
        address client = escrow.getClientAdress();

        console.log(client);

        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);
        vm.prank(freelancer);
        escrow.markDelivered();
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
        address client = escrow.getClientAdress();

        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);
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
        address client = escrow.getClientAdress();

        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);
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
        escrow.fund(sendValue);
    }

    function testCheckUpkeepDeadlinePassed() public {
        // Fast forward time to exceed the deadline
        vm.warp(block.timestamp + 8 days);

        // Ensure the contract is in the FUNDED state
        vm.prank(escrow.getClientAdress());
        escrow.fund{value: 1 ether}(1 ether);

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

    function testPerformUpkeepReleaseFunds() public {
        // Set up the contract in a DELIVERED state with delivery confirmed
        address freelancer = escrow.getFreelancerAdress();
        address client = escrow.getClientAdress();

        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);

        vm.prank(freelancer);
        escrow.markDelivered();

        vm.prank(client);
        escrow.confirmDelivery();

        // Call checkUpkeep to get the performData
        (bool upkeepNeeded, bytes memory performData) = escrow.checkUpkeep("");
        assertTrue(upkeepNeeded, "Upkeep should be needed for releasing funds");

        // Perform upkeep and verify the funds are released
        uint256 freelancerInitialBalance = freelancer.balance;
        vm.prank(address(this));
        escrow.performUpkeep(performData);
        uint256 freelancerFinalBalance = freelancer.balance;

        assertEq(
            freelancerFinalBalance,
            freelancerInitialBalance + 1 ether,
            "Freelancer should receive the correct amount"
        );
    }

    function testCheckUpkeepDeliveryConfirmed() public {
        // Set up the contract in a DELIVERED state with delivery confirmed
        address freelancer = escrow.getFreelancerAdress();
        address client = escrow.getClientAdress();

        vm.prank(client);
        escrow.fund{value: 1 ether}(1 ether);
        vm.prank(freelancer);
        escrow.markDelivered();
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

    function testCheckUpkeepNoUpkeepNeeded() public view {
        // Ensure the contract is in a state where no upkeep is needed
        EscrowFreelance.EscrowState state = escrow.getScrowState();
        assertEq(
            uint256(state),
            uint256(EscrowFreelance.EscrowState.CREATED), //check but it should be created, change main contract
            "Initial state should be CREATED"
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

    function testContractDeploymentSendEther() public view {
        EscrowFreelance.EscrowState state = escrow.getScrowState();

        assertEq(
            uint256(state),
            uint256(EscrowFreelance.EscrowState.CREATED), //check but it should be created, change main contract
            "Initial state should be CREATED"
        );
    }

    function testDeadlineCorrectSet() public view {
        uint256 deliveryPeriod = 7 days;
        uint256 contractDeploymentTime = block.timestamp;
        uint256 expectedDeadline = contractDeploymentTime + deliveryPeriod;

        uint256 actualDeadline = escrow.getDeadline();

        assertEq(
            actualDeadline,
            expectedDeadline,
            "Deadline is not set correctly"
        );
    }

    function testDataFeedAddressCorrect() public {
        HelperConfig helper = new HelperConfig();
        address dataFeedAddressFromHelper = helper.activeNetworkConfig();

        address dataFeedAddressFromContract = escrow.getDataFeedAddress();

        assertEq(
            dataFeedAddressFromContract,
            dataFeedAddressFromHelper,
            "Data feed address is not set correctly"
        );
    }

    function testFundContractWithNoFundsIs0() public view {
        uint256 escrowBalance = address(escrow).balance;

        assertEq(escrowBalance, 0, "Escrow balance should be zero");
    }

    function testFundingContractWithNoFunds() public {
        address client = escrow.getClientAdress();

        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);
        uint256 escrowBalance = address(escrow).balance;

        assertEq(escrowBalance, 1 ether, "Escrow balance should be one ether");
    }

    function testSetMininumUSD() public {
        address freelancer = escrow.getFreelancerAdress();
        uint256 newMinimumUSD = 200;

        vm.prank(freelancer);
        escrow.setMinimumPriceUSD(newMinimumUSD);

        assertEq(
            escrow.getMinimumPriceUSD(),
            escrow.convertAmountFromUSDtoETH(newMinimumUSD),
            "Minimum price in USD not set correctly"
        );
    }

    function testFundLessThanMininumUSD() public {
        address freelancer = escrow.getFreelancerAdress();
        address client = escrow.getClientAdress();
        uint256 newMinimumUSD = 200;
        uint256 fundAmount = escrow.convertAmountFromUSDtoETH(newMinimumUSD) -
            1;

        vm.prank(freelancer);
        escrow.setMinimumPriceUSD(newMinimumUSD);
        console.log("Minimum price in ether:", escrow.getMinimumPriceUSD());
        vm.deal(client, 5 ether);
        vm.prank(client);
        vm.expectRevert();
        escrow.fund{value: fundAmount}(fundAmount);
    }
}
