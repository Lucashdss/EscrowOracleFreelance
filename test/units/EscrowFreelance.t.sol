// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {EscrowFreelance} from "../../src/EscrowFreelance.sol";
import {EscrowFreelanceFactory} from "../../src/EscrowFreelanceFactory.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Errors} from "../../src/libraries/Errors.sol";

contract EscrowFreelanceTest is Test {
    EscrowFreelance escrow;
    EscrowFreelanceFactory factory;
    HelperConfig helperConfig;
    address client;
    address freelancer;
    address admin;
    uint256 sendValue = 1 ether;
    event StateChanged(EscrowFreelance.EscrowState newState);
    event ContractFunded(address indexed client, uint256 amount, address indexed token, bool isETH);
    event FeeCharged(address indexed admin, uint256 feeAmount, address indexed token, bool isETH);
    event DisputeInitiated(address initiator);
    event ConflictResolved(address resolver, address winner);

    function setUp() public {
        client = makeAddr("client");
        freelancer = makeAddr("freelancer");
        admin = makeAddr("admin");
        helperConfig = new HelperConfig();
        factory = new EscrowFreelanceFactory();
        vm.deal(client, 100 ether);
        address priceFeed = helperConfig.activeNetworkConfig();

        vm.prank(client);
        address escrowAddress = factory.createEscrow(freelancer, 7 days, priceFeed, address(0), admin, 0);
        escrow = EscrowFreelance(payable(escrowAddress));
    }

    receive() external payable {}

    function testContractBalanceFunded() public {
        address client = escrow.getClientAddress();
        uint256 usdAmount = 2000e18;
        uint256 expectedEth = escrow.convertAmountFromUSDtoETH(usdAmount);
        uint256 balanceBefore = address(escrow).balance;

        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: expectedEth}(expectedEth);

        uint256 escrowBalance = address(escrow).balance;

        assertApproxEqAbs(
            escrowBalance - balanceBefore,
            expectedEth,
            1e14 // rounding tolerance
        );
    }

    function testFundMoreEther() public {
        address client = escrow.getClientAddress();
        uint256 escrowInitialBalance = escrow.getAmountToRelease();
        uint256 clientInitialBalance = client.balance;

        vm.expectEmit(false, false, false, true, address(escrow));
        emit ContractFunded(client, sendValue, address(0), true);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);

        uint256 escrowFinalBalance = escrow.getAmountToRelease();

        assertEq(escrowFinalBalance, escrowInitialBalance + sendValue, "Escrow balance did not increase correctly");

        assertEq(client.balance, clientInitialBalance - sendValue, "Client balance did not decrease correctly");
    }

    function testFirstFundingEmitsFundedState() public {
        vm.expectEmit(false, false, false, true, address(escrow));
        emit StateChanged(EscrowFreelance.EscrowState.FUNDED);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);
    }

    function testClientMarkDeliverConfirmed() public {
        console.log(client);

        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);
        vm.prank(freelancer);
        escrow.markWorkSubmitted();
        vm.prank(client);
        escrow.confirmDelivery();
        bool deliveryConfirmed = escrow.getDeliveryConfirmedState();

        assertEq(deliveryConfirmed, true, "Delivery confirmed state did not update to true");
    }

    function testFreelancertmarkWorkSubmitted() public {
        address freelancer = escrow.getFreelancerAddress();
        address client = escrow.getClientAddress();

        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);
        vm.prank(freelancer);
        escrow.markWorkSubmitted();

        EscrowFreelance.EscrowState state = escrow.getEscrowState();

        assertEq(
            uint256(state),
            uint256(EscrowFreelance.EscrowState.WORK_SUBMITTED),
            "Escrow state did not update to WORK_SUBMITTED"
        );
    }

    function testFreelancerTryMarkAsDeliverConfirmed() public {
        address freelancer = escrow.getFreelancerAddress();
        address client = escrow.getClientAddress();

        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);
        vm.prank(freelancer);
        escrow.markWorkSubmitted();

        vm.prank(freelancer);
        vm.expectRevert();
        escrow.confirmDelivery();
    }

    function testFreelanceFundMoreEther() public {
        address freelancer = escrow.getFreelancerAddress();
        vm.prank(freelancer);
        vm.deal(freelancer, 5 ether);
        vm.expectRevert();
        escrow.fund(sendValue);
    }

    function testProcessExpiredEscrowsRefundsExpiredEscrow() public {
        uint256 feeAmount = 1 ether / 100;
        uint256 refundAmount = 1 ether - feeAmount;
        uint256 adminBalanceBefore = admin.balance;

        vm.prank(escrow.getClientAddress());
        escrow.fund{value: 1 ether}(1 ether);

        vm.warp(block.timestamp + 8 days);

        uint256 clientBalanceBefore = escrow.getClientAddress().balance;
        factory.processExpiredEscrows();

        assertEq(uint256(escrow.getEscrowState()), uint256(EscrowFreelance.EscrowState.REFUNDED));
        assertEq(escrow.getClientAddress().balance, clientBalanceBefore + refundAmount);
        assertEq(admin.balance, adminBalanceBefore + feeAmount);
        assertEq(factory.getActiveEscrowCount(), 0);
    }

    function testProcessExpiredEscrowsProcessesUpToDefaultBatchSize() public {
        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);

        address secondClient = makeAddr("second-client");
        vm.deal(secondClient, 5 ether);
        address priceFeed = helperConfig.activeNetworkConfig();
        vm.prank(secondClient);
        address secondEscrowAddress = factory.createEscrow(freelancer, 7 days, priceFeed, address(0), admin, 0);
        EscrowFreelance secondEscrow = EscrowFreelance(payable(secondEscrowAddress));

        vm.prank(secondClient);
        secondEscrow.fund{value: sendValue}(sendValue);

        vm.warp(block.timestamp + 8 days);
        factory.processExpiredEscrows();

        assertEq(factory.getActiveEscrowCount(), 0, "Both expired escrows should be processed within the default batch");
        assertEq(factory.getScanCursor(), 0, "Cursor should reset after all active escrows are removed");
        assertEq(uint256(escrow.getEscrowState()), uint256(EscrowFreelance.EscrowState.REFUNDED));
        assertEq(uint256(secondEscrow.getEscrowState()), uint256(EscrowFreelance.EscrowState.REFUNDED));
    }

    function testProcessExpiredEscrowsRefundsExpiredEscrowAndRemovesItFromRegistry() public {
        uint256 feeAmount = sendValue / 100;
        uint256 refundAmount = sendValue - feeAmount;
        uint256 adminBalanceBefore = admin.balance;

        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);

        vm.warp(block.timestamp + 8 days);

        uint256 clientBalanceBefore = client.balance;
        factory.processExpiredEscrows();

        assertEq(uint256(escrow.getEscrowState()), uint256(EscrowFreelance.EscrowState.REFUNDED));
        assertEq(client.balance, clientBalanceBefore + refundAmount);
        assertEq(admin.balance, adminBalanceBefore + feeAmount);
        assertEq(factory.getActiveEscrowCount(), 0);
    }

    function testProcessExpiredEscrowsRefundsPendingModificationEscrow() public {
        uint256 feeAmount = sendValue / 100;
        uint256 refundAmount = sendValue - feeAmount;
        uint256 adminBalanceBefore = admin.balance;

        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);
        vm.prank(freelancer);
        escrow.markWorkSubmitted();
        vm.prank(client);
        escrow.requestModificationAndUpdateDeadline(1 days);

        vm.warp(block.timestamp + 9 days);

        uint256 clientBalanceBefore = client.balance;
        factory.processExpiredEscrows();

        assertEq(uint256(escrow.getEscrowState()), uint256(EscrowFreelance.EscrowState.REFUNDED));
        assertEq(client.balance, clientBalanceBefore + refundAmount);
        assertEq(admin.balance, adminBalanceBefore + feeAmount);
        assertEq(factory.getActiveEscrowCount(), 0);
    }

    function testProcessExpiredEscrowsNoopsBeforeDeadline() public {
        assertEq(factory.getActiveEscrowCount(), 1, "Factory should track the new escrow as active");
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);

        factory.processExpiredEscrows();

        assertEq(uint256(escrow.getEscrowState()), uint256(EscrowFreelance.EscrowState.FUNDED));
        assertEq(factory.getActiveEscrowCount(), 1);
    }

    function testConfirmDeliveryReleasesFundsAndRemovesEscrowFromActiveList() public {
        uint256 feeAmount = 1 ether / 100;
        uint256 releaseAmount = 1 ether - feeAmount;

        vm.prank(client);
        escrow.fund{value: 1 ether}(1 ether);
        vm.prank(freelancer);
        escrow.markWorkSubmitted();

        uint256 freelancerBalanceBefore = freelancer.balance;
        uint256 adminBalanceBefore = admin.balance;
        vm.prank(client);
        escrow.confirmDelivery();

        assertEq(uint256(escrow.getEscrowState()), uint256(EscrowFreelance.EscrowState.RELEASED));
        assertEq(freelancer.balance, freelancerBalanceBefore + releaseAmount);
        assertEq(admin.balance, adminBalanceBefore + feeAmount);
        assertEq(factory.getActiveEscrowCount(), 0);
    }

    function testConfirmDeliveryWithAmountBelow100ChargesZeroFee() public {
        uint256 amount = 99;

        vm.deal(client, 1 ether);
        vm.prank(client);
        escrow.fund{value: amount}(amount);
        vm.prank(freelancer);
        escrow.markWorkSubmitted();

        uint256 freelancerBalanceBefore = freelancer.balance;
        uint256 adminBalanceBefore = admin.balance;

        vm.expectEmit(false, false, false, true, address(escrow));
        emit FeeCharged(admin, 0, address(0), true);
        vm.prank(client);
        escrow.confirmDelivery();

        assertEq(freelancer.balance - freelancerBalanceBefore, amount);
        assertEq(admin.balance, adminBalanceBefore);
        assertEq(escrow.getAmountToRelease(), 0);
    }

    function testGetVersion() public view {
        uint256 version = escrow.getVersion();
        assertEq(version, 4, "Price feed version should be 4");
    }

    function testConvertAmountFromUSDtoETH() public view {
        uint256 usdAmount = 1000e18;

        // Read oracle price directly
        AggregatorV3Interface feed = AggregatorV3Interface(escrow.getDataFeedAddress());

        (, int256 price,,,) = feed.latestRoundData();
        require(price > 0, "Invalid oracle price");

        // Chainlink ETH/USD has 8 decimals → scale to 18
        uint256 adjustedPrice = uint256(price) * 1e10;

        // Same formula used in the contract (ceil division)
        uint256 expectedEth = (usdAmount * 1e18 + adjustedPrice - 1) / adjustedPrice;

        uint256 ethAmount = escrow.convertAmountFromUSDtoETH(usdAmount);

        assertEq(ethAmount, expectedEth);
    }

    function testContractDeploymentSendEther() public view {
        EscrowFreelance.EscrowState state = escrow.getEscrowState();

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

        assertEq(actualDeadline, expectedDeadline, "Deadline is not set correctly");
    }

    function testDataFeedAddressCorrect() public view {
        assertEq(
            escrow.getDataFeedAddress(), helperConfig.activeNetworkConfig(), "Data feed address is not set correctly"
        );
    }

    // this test is only meaningful on anvil local blockchain
    function testFundContractWithNoFundsIs0() public view {
        if (block.chainid != 31337) return;

        assertEq(address(escrow).balance, 0);
    }

    function testFundingContractWithNoFunds() public {
        address client = escrow.getClientAddress();
        uint256 balanceBefore = address(escrow).balance;
        uint256 usdAmount = 2000e18; // example
        uint256 valueToSend = escrow.convertAmountFromUSDtoETH(usdAmount);

        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: valueToSend}(valueToSend);
        uint256 escrowBalance = address(escrow).balance;

        assertEq(escrowBalance - balanceBefore, valueToSend, "Escrow balance should be one ether");
    }

    function testSetMininumUSD() public {
        address freelancer = escrow.getFreelancerAddress();
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
        address freelancer = escrow.getFreelancerAddress();
        address client = escrow.getClientAddress();
        uint256 newMinimumUSD = 200;
        uint256 fundAmount = escrow.convertAmountFromUSDtoETH(newMinimumUSD) - 1;

        vm.prank(freelancer);
        escrow.setMinimumPriceUSD(newMinimumUSD);
        console.log("Minimum price in ether:", escrow.getMinimumPriceUSD());
        vm.deal(client, 5 ether);
        vm.prank(client);
        vm.expectRevert();
        escrow.fund{value: fundAmount}(fundAmount);
    }

    function testInitiateDisputeByClientFromWorkSubmitted() public {
        address client = escrow.getClientAddress();
        address freelancer = escrow.getFreelancerAddress();

        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);

        vm.prank(freelancer);
        escrow.markWorkSubmitted();

        vm.expectEmit(false, false, false, true, address(escrow));
        emit StateChanged(EscrowFreelance.EscrowState.DISPUTE);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit DisputeInitiated(client);

        vm.prank(client);
        escrow.initiateDispute();

        assertEq(uint256(escrow.getEscrowState()), uint256(EscrowFreelance.EscrowState.DISPUTE));
        assertEq(factory.getActiveEscrowCount(), 0, "Disputed escrows should be removed from the active registry");
    }

    function testInitiateDisputeByFreelancerFromPendingModification() public {
        address client = escrow.getClientAddress();
        address freelancer = escrow.getFreelancerAddress();

        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);

        vm.prank(freelancer);
        escrow.markWorkSubmitted();

        vm.prank(client);
        escrow.requestModificationAndUpdateDeadline(1 days);

        vm.prank(freelancer);
        escrow.initiateDispute();

        assertEq(uint256(escrow.getEscrowState()), uint256(EscrowFreelance.EscrowState.DISPUTE));
        assertEq(factory.getActiveEscrowCount(), 0, "Disputed escrows should be removed from the active registry");
    }

    function testInitiateDisputeRevertsForUnauthorizedCaller() public {
        address outsider = makeAddr("outsider");

        vm.prank(outsider);
        vm.expectRevert(Errors.OnlyClientOrFreelancer.selector);
        escrow.initiateDispute();
    }

    function testInitiateDisputeRevertsWhenStateIsInvalid() public {
        address client = escrow.getClientAddress();

        vm.prank(client);
        vm.expectRevert(Errors.InvalidState.selector);
        escrow.initiateDispute();
    }

    function testResolveConflictRevertsWhenCallerIsNotAdmin() public {
        address client = escrow.getClientAddress();
        address freelancer = escrow.getFreelancerAddress();

        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);
        vm.prank(freelancer);
        escrow.markWorkSubmitted();
        vm.prank(client);
        escrow.initiateDispute();

        vm.prank(client);
        vm.expectRevert(Errors.OnlyAdmin.selector);
        escrow.resolveConflict(client);
    }

    function testResolveConflictRevertsWhenStateIsNotDispute() public {
        address admin = escrow.getAdminAddress();
        address client = escrow.getClientAddress();

        vm.prank(admin);
        vm.expectRevert(Errors.InvalidState.selector);
        escrow.resolveConflict(client);
    }

    function testResolveConflictRevertsForInvalidWinnerAddress() public {
        address admin = escrow.getAdminAddress();
        address client = escrow.getClientAddress();
        address freelancer = escrow.getFreelancerAddress();
        address outsider = makeAddr("outsider-winner");

        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);
        vm.prank(freelancer);
        escrow.markWorkSubmitted();
        vm.prank(client);
        escrow.initiateDispute();

        vm.prank(admin);
        vm.expectRevert(Errors.InvalidConflictWinner.selector);
        escrow.resolveConflict(outsider);
    }

    function testCancelEscrowOnlyClientCanCall() public {
        vm.prank(freelancer);
        vm.expectRevert(Errors.OnlyClient.selector);
        escrow.cancelEscrow();
    }

    function testCancelEscrowSetsCanceledStateAndRemovesEscrow() public {
        vm.expectEmit(false, false, false, true, address(escrow));
        emit StateChanged(EscrowFreelance.EscrowState.CANCELED);

        vm.prank(client);
        escrow.cancelEscrow();

        assertEq(uint256(escrow.getEscrowState()), uint256(EscrowFreelance.EscrowState.CANCELED));
        assertEq(factory.getActiveEscrowCount(), 0);
    }

    function testFundingAfterCancelEscrowReverts() public {
        vm.prank(client);
        escrow.cancelEscrow();

        vm.prank(client);
        vm.expectRevert(Errors.ContractCanceled.selector);
        escrow.fund{value: sendValue}(sendValue);
    }

    function testCancelEscrowAfterFundingReverts() public {
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);

        vm.prank(client);
        vm.expectRevert(Errors.InvalidState.selector);
        escrow.cancelEscrow();
    }

    function testFundRevertsWhenEscrowIsInDispute() public {
        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);
        vm.prank(freelancer);
        escrow.markWorkSubmitted();
        vm.prank(client);
        escrow.initiateDispute();

        vm.prank(client);
        vm.expectRevert(Errors.ContractInDispute.selector);
        escrow.fund{value: sendValue}(sendValue);
    }

    function testConstructorRevertsWhenBpsIsAbove100Percent() public {
        address priceFeed = helperConfig.activeNetworkConfig();

        vm.expectRevert(Errors.InvalidBps.selector);
        new EscrowFreelance(client, freelancer, 7 days, priceFeed, address(0), address(factory), admin, 10001);
    }

    function testResolveConflictRefundsClientWhenWinnerIsClient() public {
        address admin = escrow.getAdminAddress();
        address client = escrow.getClientAddress();
        address freelancer = escrow.getFreelancerAddress();
        uint256 feeAmount = sendValue / 100;
        uint256 refundAmount = sendValue - feeAmount;

        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);
        vm.prank(freelancer);
        escrow.markWorkSubmitted();
        vm.prank(client);
        escrow.initiateDispute();

        uint256 clientBalanceBefore = client.balance;
        uint256 adminBalanceBefore = admin.balance;

        vm.expectEmit(false, false, false, true, address(escrow));
        emit StateChanged(EscrowFreelance.EscrowState.REFUNDED);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit ConflictResolved(admin, client);

        vm.prank(admin);
        escrow.resolveConflict(client);

        assertEq(uint256(escrow.getEscrowState()), uint256(EscrowFreelance.EscrowState.REFUNDED));
        assertEq(client.balance, clientBalanceBefore + refundAmount);
        assertEq(admin.balance, adminBalanceBefore + feeAmount);
        assertEq(escrow.getAmountToRelease(), 0);
    }

    function testResolveConflictReleasesFreelancerWhenWinnerIsFreelancer() public {
        address admin = escrow.getAdminAddress();
        address client = escrow.getClientAddress();
        address freelancer = escrow.getFreelancerAddress();
        uint256 feeAmount = sendValue / 100;
        uint256 releaseAmount = sendValue - feeAmount;

        vm.deal(client, 5 ether);
        vm.prank(client);
        escrow.fund{value: sendValue}(sendValue);
        vm.prank(freelancer);
        escrow.markWorkSubmitted();
        vm.prank(client);
        escrow.initiateDispute();

        uint256 freelancerBalanceBefore = freelancer.balance;
        uint256 adminBalanceBefore = admin.balance;

        vm.expectEmit(false, false, false, true, address(escrow));
        emit StateChanged(EscrowFreelance.EscrowState.RELEASED);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit ConflictResolved(admin, freelancer);

        vm.prank(admin);
        escrow.resolveConflict(freelancer);

        assertEq(uint256(escrow.getEscrowState()), uint256(EscrowFreelance.EscrowState.RELEASED));
        assertEq(freelancer.balance, freelancerBalanceBefore + releaseAmount);
        assertEq(admin.balance, adminBalanceBefore + feeAmount);
        assertEq(escrow.getAmountToRelease(), 0);
    }
}
