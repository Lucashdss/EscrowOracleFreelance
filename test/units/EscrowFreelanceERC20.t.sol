// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {EscrowFreelance} from "../../src/EscrowFreelance.sol";
import {EscrowFreelanceFactory} from "../../src/EscrowFreelanceFactory.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Errors} from "../../src/libraries/Errors.sol";

contract EscrowFreelanceTest is Test {
    EscrowFreelance escrowWithToken;
    EscrowFreelanceFactory factory;
    HelperConfig helperConfig;
    MockERC20 token;
    address client;
    address freelancer;
    address admin;
    uint256 sendValue = 1 ether;
    event ContractFunded(address indexed client, uint256 amount, address indexed token, bool isETH);

    function setUp() public {
        client = makeAddr("client");
        freelancer = makeAddr("freelancer");
        admin = makeAddr("admin");
        helperConfig = new HelperConfig();
        factory = new EscrowFreelanceFactory();
        token = new MockERC20("Test Token", "TST", 18);
        address priceFeed = helperConfig.activeNetworkConfig();

        vm.prank(client);
        address escrowAddress = factory.createEscrow(freelancer, 7 days, priceFeed, address(token), admin, 0);
        escrowWithToken = EscrowFreelance(payable(escrowAddress));

        // Mint tokens to client for testing
        token.mint(client, 1_000_000e18);
    }

    // ---------------------------
    // Funding Tests
    // ---------------------------

    function testERC20FundingSuccess() public {
        address client = escrowWithToken.getClientAddress();
        uint256 amount = 1000e18;

        vm.prank(client);
        token.approve(address(escrowWithToken), amount);

        vm.expectEmit(false, false, false, true, address(escrowWithToken));
        emit ContractFunded(client, amount, address(token), false);
        vm.prank(client);
        escrowWithToken.fund(amount);

        assertEq(token.balanceOf(address(escrowWithToken)), amount);
        assertEq(token.balanceOf(client), 1_000_000e18 - amount);
        assertEq(escrowWithToken.getAmountToRelease(), amount);
    }

    function testERC20FundingWithoutApproveReverts() public {
        address client = escrowWithToken.getClientAddress();
        uint256 amount = 1000e18;

        vm.prank(client);
        vm.expectRevert(Errors.InsufficientAllowance.selector);
        escrowWithToken.fund(amount);
    }

    function testERC20FundingWithPartialAllowanceReverts() public {
        address fundedClient = escrowWithToken.getClientAddress();
        uint256 amount = 1000e18;

        vm.prank(fundedClient);
        token.approve(address(escrowWithToken), amount - 1);

        vm.prank(fundedClient);
        vm.expectRevert(Errors.InsufficientAllowance.selector);
        escrowWithToken.fund(amount);
    }

    function testERC20FundingWithInsufficientBalanceReverts() public {
        uint256 amount = 1_000_000e18 + 1;

        vm.prank(client);
        token.approve(address(escrowWithToken), amount);

        vm.prank(client);
        vm.expectRevert(Errors.InsufficientTokenBalance.selector);
        escrowWithToken.fund(amount);
    }

    function testERC20FundingBelowMinimumReverts() public {
        uint256 usdAmount = 2000e18;
        address freelancer = escrowWithToken.getFreelancerAddress();

        vm.prank(freelancer);
        escrowWithToken.setMinimumPriceUSD(usdAmount);

        address client = escrowWithToken.getClientAddress();
        uint256 amountTooLow = escrowWithToken.convertAmountFromUSDtoETH(usdAmount) - 1;

        vm.prank(client);
        token.approve(address(escrowWithToken), amountTooLow);

        vm.prank(client);
        vm.expectRevert(Errors.AmountIsInferiorToMinimumUSD.selector);
        escrowWithToken.fund(amountTooLow);
    }

    // ---------------------------
    // Release Tests
    // ---------------------------

    function testERC20ConfirmDeliveryReleasesFundsImmediately() public {
        uint256 amount = 1000e18;
        uint256 feeAmount = amount / 100;
        uint256 releaseAmount = amount - feeAmount;

        vm.prank(client);
        token.approve(address(escrowWithToken), amount);

        vm.prank(client);
        escrowWithToken.fund(amount);

        vm.prank(freelancer);
        escrowWithToken.markWorkSubmitted();

        uint256 freelancerBalanceBefore = token.balanceOf(freelancer);
        uint256 adminBalanceBefore = token.balanceOf(admin);
        vm.prank(client);
        escrowWithToken.confirmDelivery();
        uint256 freelancerBalanceAfter = token.balanceOf(freelancer);

        assertEq(freelancerBalanceAfter - freelancerBalanceBefore, releaseAmount);
        assertEq(token.balanceOf(admin) - adminBalanceBefore, feeAmount);
        assertEq(uint256(escrowWithToken.getEscrowState()), uint256(EscrowFreelance.EscrowState.RELEASED));
        assertEq(escrowWithToken.getAmountToRelease(), 0);
        assertEq(factory.getActiveEscrowCount(), 0);
    }

    function testResolveConflictBeforeDisputeReverts() public {
        address client = escrowWithToken.getClientAddress();
        address freelancer = escrowWithToken.getFreelancerAddress();
        uint256 amount = 1000e18;

        vm.prank(client);
        token.approve(address(escrowWithToken), amount);

        vm.prank(client);
        escrowWithToken.fund(amount);

        vm.prank(freelancer);
        escrowWithToken.markWorkSubmitted();

        vm.expectRevert(Errors.InvalidState.selector);
        vm.prank(admin);
        escrowWithToken.resolveConflict(freelancer);
    }

    function testERC20FundingWhenDisputeReverts() public {
        uint256 amount = 1000e18;

        vm.prank(client);
        token.approve(address(escrowWithToken), amount);

        vm.prank(client);
        escrowWithToken.fund(amount);

        vm.prank(freelancer);
        escrowWithToken.markWorkSubmitted();

        vm.prank(client);
        escrowWithToken.initiateDispute();

        vm.prank(client);
        vm.expectRevert(Errors.ContractInDispute.selector);
        escrowWithToken.fund(amount);
    }

    function testRequestModificationUpdatesDeadlineAndState() public {
        address client = escrowWithToken.getClientAddress();
        address freelancer = escrowWithToken.getFreelancerAddress();
        uint256 amount = 1000e18;

        vm.prank(client);
        token.approve(address(escrowWithToken), amount);

        vm.prank(client);
        escrowWithToken.fund(amount);

        vm.prank(freelancer);
        escrowWithToken.markWorkSubmitted();

        uint256 initialDeadline = escrowWithToken.getDeadline();
        uint256 extension = 2 days;

        vm.prank(client);
        escrowWithToken.requestModificationAndUpdateDeadline(extension);

        assertEq(escrowWithToken.getModificationsRequested(), 1);
        assertEq(escrowWithToken.getDeadline(), initialDeadline + extension);
        assertEq(uint256(escrowWithToken.getEscrowState()), uint256(EscrowFreelance.EscrowState.PENDING_MODIFICATION));
    }

    function testRequestModificationOnlyClientCanCall() public {
        address client = escrowWithToken.getClientAddress();
        address freelancer = escrowWithToken.getFreelancerAddress();
        uint256 amount = 1000e18;

        vm.prank(client);
        token.approve(address(escrowWithToken), amount);

        vm.prank(client);
        escrowWithToken.fund(amount);

        vm.prank(freelancer);
        escrowWithToken.markWorkSubmitted();

        vm.prank(freelancer);
        vm.expectRevert(Errors.OnlyClient.selector);
        escrowWithToken.requestModificationAndUpdateDeadline(1 days);
    }

    function testRequestModificationRevertsAfterTwoRequests() public {
        address client = escrowWithToken.getClientAddress();
        address freelancer = escrowWithToken.getFreelancerAddress();
        uint256 amount = 1000e18;

        vm.prank(client);
        token.approve(address(escrowWithToken), amount);

        vm.prank(client);
        escrowWithToken.fund(amount);

        vm.prank(freelancer);
        escrowWithToken.markWorkSubmitted();

        vm.prank(client);
        escrowWithToken.requestModificationAndUpdateDeadline(1 days);

        vm.prank(client);
        escrowWithToken.requestModificationAndUpdateDeadline(1 days);

        assertEq(escrowWithToken.getModificationsRequested(), 2);

        vm.prank(client);
        vm.expectRevert(Errors.MaxModificationsReached.selector);
        escrowWithToken.requestModificationAndUpdateDeadline(1 days);
    }

    // ---------------------------
    // Refund Tests
    // ---------------------------

    function testERC20RefundClientAfterDeadline() public {
        address client = escrowWithToken.getClientAddress();
        uint256 amount = 1000e18;
        uint256 feeAmount = amount / 100;
        uint256 refundAmount = amount - feeAmount;

        vm.prank(client);
        token.approve(address(escrowWithToken), amount);

        vm.prank(client);
        escrowWithToken.fund(amount);

        // Move forward past deadline
        vm.warp(block.timestamp + 8 days);

        uint256 clientBalanceBefore = token.balanceOf(client);
        uint256 adminBalanceBefore = token.balanceOf(admin);
        factory.processExpiredEscrows();
        uint256 clientBalanceAfter = token.balanceOf(client);

        assertEq(clientBalanceAfter - clientBalanceBefore, refundAmount);
        assertEq(token.balanceOf(admin) - adminBalanceBefore, feeAmount);
        assertEq(escrowWithToken.getAmountToRelease(), 0);
        assertEq(factory.getActiveEscrowCount(), 0);
    }

    // ---------------------------
    // Edge Cases
    // ---------------------------

    function testERC20FundingETHReverts() public {
        address client = escrowWithToken.getClientAddress();
        uint256 amount = 1 ether;

        vm.deal(client, amount);
        vm.prank(client);
        (bool success,) =
            address(escrowWithToken).call{value: amount}(abi.encodeWithSelector(EscrowFreelance.fund.selector, amount));

        assertFalse(success, "ERC20 escrows must reject ETH funding");
    }

    function testERC20DoubleFundingAfterReleasedReverts() public {
        address client = escrowWithToken.getClientAddress();
        uint256 amount = 1000e18;
        uint256 feeAmount = amount / 100;
        uint256 releaseAmount = amount - feeAmount;

        vm.prank(client);
        token.approve(address(escrowWithToken), amount);

        vm.prank(client);
        escrowWithToken.fund(amount);

        uint256 freelancerBalanceBefore = token.balanceOf(freelancer);

        vm.prank(escrowWithToken.getFreelancerAddress());
        escrowWithToken.markWorkSubmitted();

        vm.prank(client);
        escrowWithToken.confirmDelivery();

        assertEq(token.balanceOf(freelancer) - freelancerBalanceBefore, releaseAmount);
        assertEq(token.balanceOf(admin), feeAmount);
        assertEq(factory.getActiveEscrowCount(), 0);

        // Try funding again after RELEASED
        vm.prank(client);
        token.approve(address(escrowWithToken), amount);

        vm.prank(client);
        vm.expectRevert(Errors.ContractHasBeenAlreadyReleasedOrRefunded.selector);
        escrowWithToken.fund(amount);
    }
}
