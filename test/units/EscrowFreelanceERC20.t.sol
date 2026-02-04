// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {EscrowFreelance} from "../../src/EscrowFreelance.sol";
import {DeployEscrow} from "../../script/DeployEscrow.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Errors} from "../../src/libraries/Errors.sol";

contract EscrowFreelanceTest is Test {
    EscrowFreelance escrowWithToken;
    MockERC20 token;
    uint256 sendValue = 1 ether;

    function setUp() public {
        // Deploy escrow with ERC20 token via your script
        escrowWithToken = new DeployEscrow().runWithTokenAddressAnvil();

        // STEP 2: Cast the token address from escrow to MockERC20
        token = MockERC20(escrowWithToken.getTokenAddress());

        // Mint tokens to client for testing
        address client = escrowWithToken.getClientAdress();
        token.mint(client, 1_000_000e18);
    }

    // ---------------------------
    // Funding Tests
    // ---------------------------

    function testERC20FundingSuccess() public {
        address client = escrowWithToken.getClientAdress();
        uint256 amount = 1000e18;

        vm.prank(client);
        token.approve(address(escrowWithToken), amount);

        vm.prank(client);
        escrowWithToken.fund(amount);

        assertEq(token.balanceOf(address(escrowWithToken)), amount);
        assertEq(token.balanceOf(client), 1_000_000e18 - amount);
        assertEq(escrowWithToken.getAmountToRelease(), amount);
    }

    function testERC20FundingWithoutApproveReverts() public {
        address client = escrowWithToken.getClientAdress();
        uint256 amount = 1000e18;

        vm.prank(client);
        vm.expectRevert();
        escrowWithToken.fund(amount);
    }

    function testERC20FundingBelowMinimumReverts() public {
        uint256 usdAmount = 2000e18;
        address freelancer = escrowWithToken.getFreelancerAdress();

        vm.prank(freelancer);
        escrowWithToken.setMinimumPriceUSD(usdAmount);

        address client = escrowWithToken.getClientAdress();
        uint256 amountTooLow = escrowWithToken.convertAmountFromUSDtoETH(
            usdAmount
        ) - 1;

        vm.prank(client);
        token.approve(address(escrowWithToken), amountTooLow);

        vm.prank(client);
        vm.expectRevert(Errors.AmountIsInferiorToMinimumUSD.selector);
        escrowWithToken.fund(amountTooLow);
    }

    // ---------------------------
    // Release Tests
    // ---------------------------

    function testERC20PerformUpkeepReleaseFunds() public {
        address client = escrowWithToken.getClientAdress();
        address freelancer = escrowWithToken.getFreelancerAdress();
        uint256 amount = 1000e18;

        vm.prank(client);
        token.approve(address(escrowWithToken), amount);

        vm.prank(client);
        escrowWithToken.fund(amount);

        vm.prank(freelancer);
        escrowWithToken.markDelivered();

        vm.prank(client);
        escrowWithToken.confirmDelivery();

        (bool upkeepNeeded, bytes memory performData) = escrowWithToken
            .checkUpkeep("");
        assertTrue(upkeepNeeded, "Upkeep should be needed");

        uint256 freelancerBalanceBefore = token.balanceOf(freelancer);
        vm.prank(address(this));
        escrowWithToken.performUpkeep(performData);
        uint256 freelancerBalanceAfter = token.balanceOf(freelancer);

        assertEq(freelancerBalanceAfter - freelancerBalanceBefore, amount);
        assertEq(escrowWithToken.getAmountToRelease(), 0);
    }

    function testERC20ReleaseWithoutConfirmationReverts() public {
        address client = escrowWithToken.getClientAdress();
        address freelancer = escrowWithToken.getFreelancerAdress();
        uint256 amount = 1000e18;

        vm.prank(client);
        token.approve(address(escrowWithToken), amount);

        vm.prank(client);
        escrowWithToken.fund(amount);

        vm.prank(freelancer);
        escrowWithToken.markDelivered();

        //do not confirm delivery

        vm.prank(address(this));
        vm.expectRevert(Errors.DeliverNotConfirmed.selector);
        escrowWithToken.performUpkeep(abi.encode(uint8(2)));
    }

    // ---------------------------
    // Refund Tests
    // ---------------------------

    function testERC20RefundClientAfterDeadline() public {
        address client = escrowWithToken.getClientAdress();
        uint256 amount = 1000e18;

        vm.prank(client);
        token.approve(address(escrowWithToken), amount);

        vm.prank(client);
        escrowWithToken.fund(amount);

        // Move forward past deadline
        vm.warp(block.timestamp + 8 days);

        (bool upkeepNeeded, bytes memory performData) = escrowWithToken
            .checkUpkeep("");
        assertTrue(upkeepNeeded, "Upkeep should be needed for refund");

        uint256 clientBalanceBefore = token.balanceOf(client);
        vm.prank(address(this));
        escrowWithToken.performUpkeep(performData);
        uint256 clientBalanceAfter = token.balanceOf(client);

        assertEq(clientBalanceAfter - clientBalanceBefore, amount);
        assertEq(escrowWithToken.getAmountToRelease(), 0);
    }

    // ---------------------------
    // Edge Cases
    // ---------------------------

    function testERC20FundingETHReverts() public {
        address client = escrowWithToken.getClientAdress();
        uint256 amount = 1 ether;

        vm.prank(client);
        vm.expectRevert(Errors.TokenAddressIsNotETH.selector);
        escrowWithToken.fund{value: amount}(amount);
    }

    function testERC20DoubleFundingAfterReleasedReverts() public {
        address client = escrowWithToken.getClientAdress();
        uint256 amount = 1000e18;

        vm.prank(client);
        token.approve(address(escrowWithToken), amount);

        vm.prank(client);
        escrowWithToken.fund(amount);

        // mark delivered and confirm delivery to release
        vm.prank(escrowWithToken.getFreelancerAdress());
        escrowWithToken.markDelivered();

        vm.prank(client);
        escrowWithToken.confirmDelivery();

        (bool upkeepNeeded, bytes memory performData) = escrowWithToken
            .checkUpkeep("");
        vm.prank(address(this));
        escrowWithToken.performUpkeep(performData);

        // Try funding again after RELEASED
        vm.prank(client);
        token.approve(address(escrowWithToken), amount);

        vm.prank(client);
        vm.expectRevert(
            Errors.ContractHasBeenAlreadyReleasedOrRefunded.selector
        );
        escrowWithToken.fund(amount);
    }
}
